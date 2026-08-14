-- Relayer - Recreate rendering piepline for Roblox
-- metatablecatgames 2026

local Recreate = require(script.Parent.Recreate)

type SenderParams = {
	Sender: Instance,
	Connection: RBXScriptConnection
}

local PIPELINE_QUEUE = {
	destroy = {}::{[RenderObject]: true},
	create = {}::{[RenderObject]: true},
	specialkeysteps = {
		classes = {}::{[RenderObject]: {
			add: {[string]: true},
			remove: {[string]: true},
		}},
		events = {}::{[RenderObject]: {
			set: (Recreate.Node, SenderParams, ...any) -> ()
		}},
		change = {}::{[RenderObject]: {
			set: (Recreate.Node, SenderParams, key: string, value: any) -> ()
		}}
	},
	setprops = {}::{[RenderObject]: {[string]: any}},
	setparent = {}::{[RenderObject]: RenderObject|Instance},
	
	work = false
}
local PIPELINE = {}
const Relayer = {}

type RenderObject = {
	class: string,
	instance: Instance,
	props: { [string]: any },
	
	eventConnections: { [string]: RBXScriptConnection },
	changeConnections: { [string]: RBXScriptConnection },
	
	tags: { [string]: boolean },
	node: Recreate.RendererNode,
	
	children: {[RenderObject]: true},
	parent: RenderObject|Instance?,
}

const keyMemoization = {
	change = setmetatable({}, {__mode = "v"}),
	event = setmetatable({}, {__mode = "v"}),
}

Relayer.ClassName = {key = "Relayer.ClassName"} :: Recreate.SpecialKey<"Relayer.ClassName">; table.freeze(Relayer.ClassName)
Relayer.Classes = {key = "Relayer.Classes"} :: Recreate.SpecialKey<"Relayer.Classes">; table.freeze(Relayer.Classes)
Relayer.Event = function(eventName: string): Recreate.SpecialKey<"Relayer.Event">
	local ekey = keyMemoization.event[eventName]
	if not ekey then
		ekey = {
			key = "Relayer.Event",
			eventName = eventName,
		}
		table.freeze(ekey)
		keyMemoization.event[eventName] = ekey
	end

	return ekey
end
Relayer.Change = function(propName: string): Recreate.SpecialKey<"Relayer.Change">
	local ckey = keyMemoization.change[propName]
	if not ckey then
		ckey = {
			key = "Relayer.Change",
			propName = propName,
		}
		table.freeze(ckey)
		keyMemoization.change[propName] = ckey
	end
	return ckey
end

local RENDER_STATE: {[Recreate.RendererNode]: RenderObject} = {}

const function destroyNodeItem(state: RenderObject, node: Recreate.RendererNode)
	for child in state.children do
		destroyNodeItem(child)
	end

	if RENDER_STATE[node] == state then
		RENDER_STATE[node] = nil
	end
	
	PIPELINE_QUEUE.destroy[state] = true
	PIPELINE_QUEUE.work = true
end

const function update(dt: number)
	if not PIPELINE_QUEUE.work then return end
	
	-- applies changes to instance state
	-- destroy
	-- create
	-- updateSpecialKeys (usk)
	-- setProps
	-- setParent
	
	for state in PIPELINE_QUEUE.destroy do
		if state.instance then
			state.instance:Destroy()
			state.instance = nil
		end
		
		for key, connection in state.eventConnections do
			connection:Disconnect()
		end

		for _, connection in state.changeConnections do
			connection:Disconnect()
		end
		state.eventConnections = {}
		state.changeConnections = {}
	end
	
	for state in PIPELINE_QUEUE.create do
		if PIPELINE_QUEUE.destroy[state] then continue end
		
		local instanceobj = Instance.new(state.class)
		for propName, propVal in state.props do
			if propName == "Parent" then continue end
			instanceobj[propName] = propVal
		end
		
		instanceobj.AncestryChanged:Connect(function(_, p)
			if not p then
				Recreate.Node.destroy(state.node.Ref) -- CAVEAT: we want this case to cleanup the entire Recreate state, not just Relayer
			end
		end)
		
		state.instance = instanceobj
	end
	PIPELINE_QUEUE.create = {}
	
	for state, classes in PIPELINE_QUEUE.specialkeysteps.classes do
		if PIPELINE_QUEUE.destroy[state] then continue end
		if not state.instance then continue end
		
		for add in classes.add do
			state.instance:AddTag(add)
			state.tags[add] = true
		end
		
		for remove in classes.remove do
			state.instance:RemoveTag(remove)
			state.tags[remove] = nil
		end
	end
	PIPELINE_QUEUE.specialkeysteps.classes = {}
	
	for state, events in PIPELINE_QUEUE.specialkeysteps.events do
		if PIPELINE_QUEUE.destroy[state] then continue end
		if not state.instance then continue end
		
		for eventName, eventState in events do
			if state.eventConnections[eventName] then
				state.eventConnections[eventName]:Disconnect()
			end
			
			if not eventState.set then
				state.eventConnections[eventName] = nil
			else
				local senderParams = {
					Sender = state.instance,
				}
				local setfn = eventState.set
				senderParams.Connection = state.instance[eventName]:Connect(function(...)
					setfn(state.node.Ref, senderParams, ...)
				end)
				state.eventConnections[eventName] = senderParams.Connection
			end
		end
	end
	PIPELINE_QUEUE.specialkeysteps.events = {}
	
	for state, events in PIPELINE_QUEUE.specialkeysteps.change do
		if PIPELINE_QUEUE.destroy[state] then continue end
		if not state.instance then continue end
		
		for propName, eventState in events do
			if state.changeConnections[propName] then
				state.changeConnections[propName]:Disconnect()
			end
			if not eventState.set then
				state.changeConnections[propName] = nil
			else
				local senderParams = {
					Sender = state.instance,
				}
				local setfn = eventState.set
				state.changeConnections[propName] = state.instance:GetPropertyChangedSignal(propName):Connect(function(...)
					local v = state.instance[propName]
					setfn(state.node.Ref, senderParams, propName, v)
				end)
				state.eventConnections[propName] = senderParams.Connection
			end
		end
	end
	PIPELINE_QUEUE.specialkeysteps.classes = {}
	
	for state, props in PIPELINE_QUEUE.setprops do
		for propName, propVal in props do
			if not state.instance then continue end
			state.instance[propName] = propVal
			state.props[propName] = propVal
		end
	end
	
	for child, parent in PIPELINE_QUEUE.setparent do
		if PIPELINE_QUEUE.destroy[child] then continue end
		
		child.Parent = parent
		if typeof(parent) == "Instance" then
			child.instance.Parent = parent
		else
			child.instance.Parent = parent.instance
		end
	end
	PIPELINE_QUEUE.setparent = {}
	PIPELINE_QUEUE.destroy = {}
	PIPELINE_QUEUE.work = false
end

const function createstate(node: Recreate.RendererNode): RenderObject
	local renderState = {}
	renderState.instance = nil
	renderState.props = table.clone(node.Props)
	renderState.tags = {}
	renderState.eventConnections = setmetatable({}, {__mode = "v"})
	renderState.changeConnections = setmetatable({}, {__mode = "v"})
	renderState.node = node
	
	local className = node.SpecialKeys[Relayer.ClassName]
	if not className then warn("no class name") return end
	
	renderState.class = className
	
	local children = {}
	renderState.children = children
	for child in node.Children do
		local childState = createstate(child)
		children[childState] = true
		childState.parent = renderState
		PIPELINE_QUEUE.setparent[childState] = renderState
	end
	
	local eventSignal, changeSignal = {}, {}
	PIPELINE_QUEUE.specialkeysteps.events[renderState] = eventSignal
	PIPELINE_QUEUE.specialkeysteps.change[renderState] = changeSignal
	
	for key, state in node.SpecialKeys do
		if key.key == "Relayer.Event" then
			eventSignal[key.eventName] = {set = state}
		elseif key.key == "Relayer.Change" then
			changeSignal[key.propName] = {set = state}
		elseif key == Relayer.Classes then
			if PIPELINE_QUEUE.specialkeysteps.classes[renderState] then continue end
			local write = {}
			for key in state do
				write[key] = true
			end
			PIPELINE_QUEUE.specialkeysteps.classes[renderState] = {add = write, remove = {}}
		end
	end
	
	PIPELINE_QUEUE.create[renderState] = true
	PIPELINE_QUEUE.work = true
	RENDER_STATE[node] = renderState
	
	return renderState
end

const function setparent(state: RenderObject, parent: RenderObject | Instance )
	if state.parent == parent then return end
	
	local oldParent = state.parent
	if oldParent and type(oldParent) == "table" then
		oldParent.children[state] = nil
	end
	
	state.parent = parent
	if typeof(parent) == "table" then
		parent.children[state] = true
	end
	PIPELINE_QUEUE.setparent[state] = parent
	PIPELINE_QUEUE.work = true
end

const function setparentexternalnodes(child: Recreate.RendererNode, parent: Recreate.RendererNode)
	local renderState = RENDER_STATE[child]
	local parentState = RENDER_STATE[parent]

	if parentState then
		if not renderState then
			renderState = createstate(child)
		end

		setparent(renderState, parentState)
		return	
	end

	destroyNodeItem(renderState, child)
end

function PIPELINE.init(initialState: {Recreate.RendererNode})
end

function PIPELINE.setParent(node: Recreate.RendererNode, parent: Recreate.RendererNode)
	setparentexternalnodes(node, parent)
end

function PIPELINE.setChildrenBatch(node: Recreate.RendererNode, newChildren: {Recreate.RendererNode}, removedChildren: {Recreate.RendererNode})
	local renderstate = RENDER_STATE[node]
	if not renderstate then return end
	
	for _, child in newChildren do
		setparentexternalnodes(child, node)
	end
	
	for _, removed in removedChildren do
		local rmstate = RENDER_STATE[removed]
		if rmstate then destroyNodeItem(rmstate, removed) end
	end
end

function PIPELINE.destroy(node: Recreate.RendererNode)
	local renderstate = RENDER_STATE[node]
	if not renderstate then return end
	destroyNodeItem(renderstate, node)
end

function PIPELINE.setProperty(node: Recreate.RendererNode, prop: string, val: any, oldVal: any, resync: boolean)
	local renderstate = RENDER_STATE[node]
	if not renderstate then return end
	
	local isChanged = renderstate.props[prop] ~= val
	local map = PIPELINE_QUEUE.setprops[renderstate]
	if not map then
		if not isChanged then return end
		map = {}
		PIPELINE_QUEUE.setprops[renderstate] = map
	end
	
	if isChanged then
		map[prop] = val
	else
		map[prop] = nil
		if not next(map) then
			PIPELINE_QUEUE.setprops[renderstate] = nil
		end 
	end
	PIPELINE_QUEUE.work = true -- naive! we dont know what else may be trying to work here
end

function PIPELINE.specialKeySet(node: Recreate.RendererNode, sk: Recreate.SpecialKey<unknown>, val: any, oldVal: any)
	local state = RENDER_STATE[node]
	if not state then return end
	
	if sk.key == "Relayer.Event" then
		local eName = sk.eventName
		local hasConnection = state.eventConnections[eName]
		if not hasConnection and not val then return end
		
		local slot = PIPELINE_QUEUE.specialkeysteps.events[state]
		if not slot then
			slot = {}
			PIPELINE_QUEUE.specialkeysteps.events[state] = slot
		end
		
		slot[eName] = {set = val}
	elseif sk.key == "Relayer.Change" then
		local pName = sk.propName
		local hasConnection = state.changeConnections[pName]
		if not hasConnection and not val then return end

		local slot = PIPELINE_QUEUE.specialkeysteps.change[state]
		if not slot then
			slot = {}
			PIPELINE_QUEUE.specialkeysteps.change[state] = slot
		end

		slot[pName] = {set = val}
	elseif sk.key == "Relayer.Classes" then
		local adding, removing, tags = {}, {}, {}
		
		for tag in val do
			if state.tags[tag] then continue end
			adding[tag] = true
			tags[tag] = true
		end
		
		for tag in state.tags do
			if not val[tag] then
				removing[tag] = true
			else
				tags[tag] = true
			end
		end
		
		state.tags = tags
		PIPELINE_QUEUE.specialkeysteps.classes[state] = {add = adding, remove = removing}
	else
		error(`Operation not supported for specialkey {sk.key}`)
	end
	
	PIPELINE_QUEUE.work = true
end

const function mutateTag(state: RenderObject, tag: string, set: boolean)	
	local slot = PIPELINE_QUEUE.specialkeysteps.classes[state]
	if not slot then
		slot = {add = {}, remove = {}}
		PIPELINE_QUEUE.specialkeysteps.classes[state] = slot -- NAIVE!
	end
	
	local isDefinedOnNode = state.tags[tag] ~= nil
	local isTryingToAddToInstance = slot.add[tag] ~= nil
	local isTryingToRemoveFromInstance = slot.remove[tag] ~= nil
	
	if set then
		if isDefinedOnNode then
			if isTryingToRemoveFromInstance then
				slot.remove[tag] = nil
				return false
			end
		else
			if isTryingToAddToInstance then return false end
			slot.add[tag] = true
		end
	else
		if isDefinedOnNode then
			if isTryingToRemoveFromInstance then return false end
			slot.remove[tag] = true
			return true
		else
			if isTryingToAddToInstance then
				slot.add[tag] = nil
				return false
			end
		end
	end
end

function PIPELINE.specialKeySetIndex(node: Recreate.RendererNode, sk: Recreate.SpecialKey<unknown>, index: any, val: any, oldVal: any)
	if sk ~= Relayer.Classes then
		error(`Operation not supported for specialkey {sk.key}`)
	end
	
	local state = RENDER_STATE[node]
	if not state then return end
	local didMutate = mutateTag(state, index, val == true)
	if didMutate then PIPELINE_QUEUE.work = true end
end

function PIPELINE.specialKeyBatchSetIndex(node: Recreate.RendererNode, sk: Recreate.SpecialKey<unknown>, pairs: {[any]: any}, oldpairs: {[any]: any})
	if sk ~= Relayer.Classes then
		error(`Operation not supported for specialkey {sk.key}`)
	end
	
	local state = RENDER_STATE[node]
	if not state then return end
	
	local anythingMutated = false
	for key, set in pairs do
		local didMutate = mutateTag(state, key, set == true)
		if didMutate then
			anythingMutated = true
		end
	end
	
	if anythingMutated then PIPELINE_QUEUE.work = true end
end

function PIPELINE.specialKeyBatchRemove(node: Recreate.RendererNode, sk: Recreate.SpecialKey<unknown>, keys: {any}, oldpairs: {[any]: any})
	if sk ~= Relayer.Classes then
		error(`Operation not supported for specialkey {sk.key}`)
	end
	
	local state = RENDER_STATE[node]
	if not state then return end
	
	local tags = state.tags
	local anythingMutated = false
	
	for _, key in keys do
		local didMutate = mutateTag(state, key, false)
		if didMutate then
			anythingMutated = true
		end
	end
	
	if anythingMutated then PIPELINE_QUEUE.work = true end
end

-- PUBLIC FACE
function Relayer.mount(node: Recreate.Node, parent: LayerCollector)
	local inode = Recreate.RENDERER_getInternalNode(node)
	if inode.Parent or inode.BoundToSource then error("Node is either mounted or has a parent") end
	inode.BoundToSource = true
	
	setparent(createstate(inode), parent)
end

function Relayer.isRendered(node: Recreate.Node)
	local inode = Recreate.RENDERER_getInternalNode(node)
	return RENDER_STATE[inode] ~= nil
end

function Relayer.isMounted(node: Recreate.Node)
	local inode = Recreate.RENDERER_getInternalNode(node)
	return inode.BoundToSource and RENDER_STATE[inode] ~= nil
end

function Relayer.unmount(node: Recreate.Node)
	local inode = Recreate.RENDERER_getInternalNode(node)
	if not inode.BoundToSource then error("Node is not mounted") end
	local state = RENDER_STATE[inode]
	if not state then error("Node is not mounted") end
	
	inode.BoundToSource = false
	destroyNodeItem(state, inode)
end

function Relayer.updatePassthrough(dt: number)
	update(dt)
end

Recreate.setRenderer(PIPELINE)
return Relayer