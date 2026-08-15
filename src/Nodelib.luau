const Common = require("./Common")
const Renderer = require("./Renderer")
const Types = require("./Types")
const NodeLib = {}

const function resolve(node: Types.NodeRef): Types.Node?
	local inode = Common.RefStorage[node.ID]
	if not inode then return nil end
	if inode.Destroyed then return nil end
	if inode.Ref ~= node then return nil end
	return inode
end

const function resolvePublic(node: Types.NodeRef): Types.Node
	local inode = resolve(node)
	if not inode then error(`Node {node.ID} is destroyed`) end
	return inode
end

function NodeLib.destroy(node: Types.NodeRef)
	local inode = resolve(node)
	if not inode then return end

	inode.Destroyed = true
	Common.RefStorage[node.ID] = nil

	local parent = inode.Parent
	if parent then
		inode.Parent = nil
		parent.Children[inode] = nil
	end

	for _, child in inode.Children do
		NodeLib.destroy(child)
	end
	inode.Children = {}

	for watchable in inode.WatchableState do
		local rci = watchable.__RCImplementor
		if not rci then continue end
		local uw = rci.unwatch
		if not uw then continue end
		pcall(uw, watchable, inode)
	end
	inode.WatchableState = {}

	Renderer.send("destroy", inode)
end

function NodeLib.RENDERER_markSourceBound(node: Types.NodeRef, bound: boolean)
	local inode = resolvePublic(node)
	if inode.Parent then error("Node is parented to another node and cannot be bound") end
	inode.BoundToSource = bound
end

const function circularDependency(n: Types.Node, parent: Types.Node)
	repeat
		parent = parent.Parent
		if parent == n then return true end
	until not parent
	return false
end

const function circularDependencyWarn(n: Types.Node, parent: Types.Node): boolean
	if circularDependency(n, parent) then
		warn(`Moving node {n.ID} into node {parent.ID} would cause a circular dependency`)
		return true
	end
	return false
end

function NodeLib.setParent(node: Types.NodeRef, parent: Types.NodeRef?)
	local in1 = resolvePublic(node)
	local in2 = if parent then resolvePublic(parent) else nil
	local oldParent = in1.Parent

	if in2 == oldParent then return end
	if in1.BoundToSource then error("Node is bound to an external source and cannot be moved") end

	if oldParent then
		in1.Parent = nil
		oldParent.Children[in1] = nil
	end

	if in2 then
		if circularDependency(in1, in2) then error(`Moving node {node.ID} into node {parent.ID} would cause a circular dependency`) end
		in1.Parent = in2
		in2.Children[in1] = true
	end

	Renderer.send("setParent", in1, in2, oldParent)
end

const function batchIterateChildren(node: Types.Node, add: {Types.Node}?, remove: {Types.Node}?)
	-- this doesn't call SetParent for performance
	if add then
		for _, child in add do
			if child.Parent == node then continue end
			if circularDependencyWarn(child, node) then continue end
			if child.BoundToSource then
				warn(`Node {node.ID} is bound to an external renderer`)
				continue
			end

			child.Parent = node
			node.Children[child] = true
		end
	end

	if remove then
		for _, child in remove do
			if child.Parent ~= node then continue end
			
			child.Parent = nil
			node.Children[child] = nil
		end
	end

	Renderer.send("setChildrenBatch", node, add or {}, remove or {})
end

function NodeLib.specialKeySet(node: Types.NodeRef, sk: Types.SpecialKey, val: any)
	local inode = resolvePublic(node)
	if sk == Common.KEY_Children then
		-- in new table: add
		-- not in new table: remove

		local add, remove = {}, {}

		for node in val do
			local child = resolve(node)
			if not child then
				warn(`Ref {node.ID} is destroyed or invalid`)
				continue
			end
			if inode.Children[child] then continue end
			table.insert(add, child)
		end

		for node in inode.Children do
			if not val[node] then table.insert(remove, node) end
		end

		batchIterateChildren(inode, add, remove)
	else
		local ov = inode.SpecialKeys[sk]
		if ov == val then return end
		inode.SpecialKeys[sk] = val

		Renderer.send("specialKeySet", inode, sk, val, ov)
	end
end

function NodeLib.specialKeySetIndex(node: Types.NodeRef, sk: Types.SpecialKey, index: any, val: any)
	if sk == Common.KEY_Children then
		local parent = if val == nil then nil else node
		NodeLib.setParent(index, parent)
	else
		local inode = resolvePublic(node)
		local tab = inode.SpecialKeys[sk] or {}
		if type(tab) ~= "table" then error(`SpecialKey {sk} is not a table`) end
		local ov = tab[index]
		if ov == val then return end
		tab[index] = val

		Renderer.send("specialKeySetIndex", inode, sk, index, val, ov)
	end
end

function NodeLib.specialKeyBatchSetIndex(node: Types.NodeRef, sk: Types.SpecialKey, pairs: {[any]: any})
	local inode = resolvePublic(node)
	if sk == Common.KEY_Children then
		local add = {}
		for ref in pairs do
			local child = resolve(ref)
			if not child then
				warn(`Ref {node.ID} is destroyed or invalid`)
				continue
			end

			table.insert(add, child)
		end

		batchIterateChildren(inode, add)
	else
		local tab = inode.SpecialKeys[sk] or {}
		if type(tab) ~= "table" then error(`SpecialKey {sk} is not a table`) end
		local oldValues = {}
		local changes = {}

		for k, v in pairs do
			if v == Common.NULL then v = nil end
			local ov = tab[k]
			oldValues[k] = ov
			tab[k] = v
			changes[k] = Common.NULL
		end

		Renderer.send("specialKeyBatchSetIndex", inode, sk, changes, oldValues)
	end
end

function NodeLib.specialKeyBatchRemove(node: Types.NodeRef, sk: Types.SpecialKey, keys: {any})
	local inode = resolvePublic(node)
	if sk == Common.KEY_Children then
		local remove = {}
		for _, ref in keys do
			local child = resolve(ref)
			if not child then
				warn(`Ref {node.ID} is destroyed or invalid`)
				continue
			end

			table.insert(remove, child)
		end

		batchIterateChildren(inode, nil, remove)
	else
		local tab = inode.SpecialKeys[sk] or {}
		if type(tab) ~= "table" then error(`SpecialKey {sk} is not a table`) end
		local oldValues = {}
		
		for _, key in keys do
			local ov = tab[key]
			if ov == nil then continue end

			oldValues[key] = ov
			tab[key] = nil
		end

		Renderer.send("specialKeyBatchRemove", inode, sk, keys, oldValues)
	end
end

return NodeLib