const Types = require("./Types")
const Common = require("./Common")
local buildStep, makeDescriptionBlob

type InitStep = {
	f: (Types.NodeRef) -> (),
	ref: Types.NodeRef
}

type BuildProgressItem = {
	Ok: boolean,
	Node: Types.Node,
	Ref: Types.NodeRef?,
	BoundWatchables: boolean,
	Error: ConstructionError?,
	SentToRender: boolean
}

type ConstructionError = {
	message: string,
	nodeDepth: {number},
	callerCallstack: string?,
	componentStack: {string}?
}

const function constructionError(
	message: string,
	nodeDepth: {number},
	callerCallstack: string?,
	componentStack: {string}?
): ConstructionError
	return {
		message = message,
		nodeDepth = nodeDepth,
		callerCallstack = callerCallstack,
		componentStack = componentStack
	}
end

function buildStep(
	description: Types.MakeDescription,
	initStack: {InitStep},
	nodeDepthStack: {number},
	resultInfo: {BuildProgressItem}
): (boolean, Types.Node | ConstructionError)
	local ok, node, ref, boundWatchable, err = makeDescriptionBlob(description, initStack, nodeDepthStack, resultInfo)

	table.insert(resultInfo, {
		Ok = ok,
		Node = node,
		Ref = ref,
		BoundWatchables = boundWatchable,
		Error = err
	})

	if ok then return true, node end -- all good! we dont need to try to cleanup this node
	return false, err or constructionError("Inner call error returned no message", nodeDepthStack)
end

const function createRef(
	node: Types.Node,
	description: Types.MakeDescription,
	nodeDepthStack: {number}
): (Types.NodeRef?, ConstructionError?)
	local ref = description[Common.KEY_Ref]
	local slot = #Common.RefStorage + 1

	if ref then
		description[Common.KEY_Ref] = nil

		if type(ref) ~= "table" or not ref.ID then return nil, constructionError("Passed Ref is not valid", nodeDepthStack) end
		if ref.ID >= 0 then return nil, constructionError("Passed ref is already allocated", nodeDepthStack) end
		if table.isfrozen(ref) then return nil, constructionError("Ref is readonly", nodeDepthStack) end
	else
		ref = {}
	end

	node.ID = slot
	ref.ID = slot
	table.freeze(ref)
	node.Ref = ref
	Common.RefStorage[slot] = node

	return ref
end

const function reconcileDescriptionFromFactories(
	node: Types.Node,
	description: Types.MakeDescription,
	initStack: {InitStep},
	nodeDepthStack: {number}
): (Types.MakeDescription, ConstructionError?)
	local factory: Types.ComponentCapture<any>? 
	local componentStack = {}

	while true do
		factory = description[Common.KEY_Factory]
		if not factory then break end

		if type(factory) == "function" then return nil, constructionError("Components must be called to capture parameters to build", nodeDepthStack, nil, componentStack) end
		if type(factory) ~= "table" then return nil, constructionError("Component is not a table", nodeDepthStack, nil, componentStack) end

		local name = factory.name or "unknown"
		table.insert(componentStack, name)

		local capture = factory.capture
		local build = factory.build
		if type(build) ~= "function" then return nil, constructionError(`Component {name} cannot build as build is not a function`, nodeDepthStack, nil, componentStack) end

		local ok, nextDescription = xpcall(build, function(err)
			return constructionError(`Component {name} build function errored: {err}`, nodeDepthStack, debug.traceback(), componentStack)
		end, capture)
		if not ok then return nil, nextDescription end

		local init = nextDescription[Common.KEY_OnInit]
		if init then
			table.insert(initStack, {
				f = init,
				ref = node.Ref
			})
		end

		description = nextDescription
	end

	return description
end

const function isWatchable(
	obj: Types.Watchable
): boolean
	return type(obj) == "table" and type(obj.__RCImplementor) == "table"
end

const function bindWatchableConstruction(
	node: Types.Node,
	state: Types.MapIndex<Types.Watchable, string|Types.SpecialKey>,
	watchable: Types.Watchable,
	key: string | Types.SpecialKey,
	nodeDepthStack: {number}
): (boolean, unknown|ConstructionError)
	-- it should be asserted that this is indeed a watchable
	local watch = watchable.__RCImplementor.watch
	if not watch then return false, constructionError(`Watchable {watchable} is missing implementation for operation WATCH`, nodeDepthStack) end

	local ok, ce = xpcall(watch, function(err)
		return constructionError(`Watchable failed to watch due to error: {err}`, nodeDepthStack, debug.traceback())
	end, watchable, node.Ref, key)
	if not ok then return false, ce end

	Common.DictionaryIndexerSet(state, watchable, key, true)
	return true, ce
end

const function handleChildren(
	node: Types.Node,
	description: Types.MakeDescription,
	initStack: {InitStep},
	watchableState: Types.MapIndex<Types.Watchable, string|Types.SpecialKey>,
	nodeDepthStack: {number},
	resultInfo: {BuildProgressItem}
): ConstructionError?
	local children = description[Common.KEY_Children]
	local childTable = {}
	node.Children = childTable

	if not children then return nil end
	description[Common.KEY_Children] = nil

	-- if its watchable then we'll bind to that
	if isWatchable(children) then
		local didBind, err = bindWatchableConstruction(node, watchableState, children, Common.KEY_Children, nodeDepthStack)
		if not didBind then return err end
		children = err
	end

	if type(children) ~= "table" then return constructionError("Recreate.Children must be a table", nodeDepthStack) end

	for idx, child: Types.MakeDescription in children do
		local ok, ce
		if type(child) ~= "table" then return constructionError("Children must be tables", nodeDepthStack) end

		if child.ID and Common.RefStorage[child.ID] and Common.RefStorage[child.ID].Ref == child then
			return constructionError(`Node {node.ID} cannot be parented this way, use SetParent instead`, nodeDepthStack)
		else
			table.insert(nodeDepthStack, idx)
			ok, ce = buildStep(child, initStack, nodeDepthStack, resultInfo)
			table.remove(nodeDepthStack, #nodeDepthStack)

			if not ok then return ce end
			ce.Parent = node
			childTable[ce] = true
		end
	end

	return nil
end

const function handleExternal(
	node: Types.Node,
	description: Types.MakeDescription,
	watchableState: Types.MapIndex<Types.Watchable, string>,
	nodeDepthStack: {number}
): ConstructionError?
	local props: {[string]: unknown}, sks: {[Types.SpecialKey]: unknown} = {}, {}
	node.Props = props
	node.SpecialKeys = sks

	for key, value in description do
		if key == Common.KEY_Children then continue end

		if type(key) == "table" then
			if not Common.isLikelySpecialKey(key) then return constructionError("Table keys must be SpecialKey with a defined key value", nodeDepthStack) end

			if isWatchable(value) then
				local didBind, err = bindWatchableConstruction(node, watchableState, value, key, nodeDepthStack)
				if not didBind then return err end
				value = err
			end

			sks[key] = value

		elseif type(key) == "string" then
			if isWatchable(value) then
				local didBind, err = bindWatchableConstruction(node, watchableState, value, key, nodeDepthStack)
				if not didBind then return err end
				value = err
			end

			props[key] = value

		else
			return constructionError(`Key value {key} is invalid, must be string or SpecialKey`, nodeDepthStack)
		end
	end

	return nil
end

function makeDescriptionBlob(
	description: Types.MakeDescription,
	initStack: {InitStep},
	nodeDepthStack: {number},
	resultInfo: {BuildProgressItem}
): (
	boolean, -- ok
	Types.Node, -- built object
	Types.NodeRef?, -- bound ref
	boolean, -- bound watchables,
	ConstructionError? -- construction error,
)
	local node = {}::Types.Node -- required to marshal the node out in the typechecks
	node.BoundToSource = false
	if type(description) ~= "table" then return false, node, nil, false, constructionError("MakeDescription is not a table", nodeDepthStack) end

	local ce: ConstructionError, ref: Types.NodeRef
	ref, ce = createRef(node, description, nodeDepthStack)
	if ce then return false, node, nil, false, ce end

	description, ce = reconcileDescriptionFromFactories(node, description, initStack, nodeDepthStack)
	if ce then return false, node, ref, false, ce end

	local watchableState = {}
	node.WatchableState = watchableState

	ce = handleChildren(node, description, initStack, watchableState, nodeDepthStack, resultInfo)
	if ce then return false, node, ref, true, ce end

	ce = handleExternal(node, description, watchableState, nodeDepthStack)
	if ce then return false, node, ref, true, ce end

	return true, node, ref, true, nil
end


const function throwConstructionError(e: ConstructionError)
	error(e.message)

end

const function cleanup(item: BuildProgressItem)
	local ref = item.Ref
	local node = item.Node

	if ref and Common.RefStorage[ref.ID] == node.Ref then Common.RefStorage[ref.ID] = nil end
	if item.BoundWatchables then
		-- try to cleanup watchables, we dont care if it errors or not
		-- these dont invoke the watchable API because we are assuming watchable is what it says it is
		for watchable in node.WatchableState do
			local rci = watchable.__RCImplementor
			local unwatch = rci.unwatch
			if unwatch then
				local wok, werr = xpcall(unwatch, debug.traceback::(string)->string, watchable, ref)
				if not wok then warn(`Error when unwatching {watchable} while cleaning up a failed make task: {werr}`) end
			end
		end
		node.WatchableState = {}
	end
end

return function(description: Types.MakeDescription): Types.NodeRef
	local init: {InitStep}, errors: {BuildProgressItem} = {}, {}
	local ok, err = buildStep(description, init, {1}, errors)
	if not ok then
		for _, errorItem in errors do cleanup(errorItem) end
		throwConstructionError(err)
	end

	-- TODO: task is a roblox specific impl, we need to find a cross platform way of deferring task logic
	for _, step in init do task.defer(step.f, step.ref) end
	return err.Ref
end