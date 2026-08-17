--[[
	A `Dyna` which can be used to bind events to an `Instance`.
]]--
export type DynaEvent = {
	read dynatag: "event",
	read eventName: string,
}

--[[
	A `Dyna` which can be used to bind `GetPropertyChangedSignal` events to an `Instance`.
]]--
export type DynaChangeSignal = {
	read dynatag: "changesignal",
	read propertyName: string,
}

--[[
	A `Dyna` which directs Relayer to handle children of an `Instance`.
]]--
export type DynaChildren = {
	read dynatag: "children",
}

--[[
	A `Dyna` which directs Relayer to handle tags of an `Instance`.
]]--
export type DynaTags = {
	read dynatag: "tags"
}

--[[
	Holds information about a bound `Connection`
]]--
export type SenderParams = {
	read Sender: Instance,
	read Connection: RBXScriptConnection
}

const Signals = require(script.Parent.Signals)

export type IDyna = DynaEvent | DynaChangeSignal | DynaChildren | DynaTags
export type IVirtual = Instance

const Relayer = {}
const RCI = {}
const mallocstate: {
	[Instance]: {
		weak_storage: {
			events: {[string]: RBXScriptConnection},
			change: {[string]: RBXScriptConnection},
		},
		effects: {[()->()]: true}
	}
} = {}
const dynamutables = {
	event = setmetatable({}, {__mode = "v"}),
	change = setmetatable({}, {__mode = "v"}),
}

--[[
	A `Dyna` which directs Relayer to handle children of an `Instance`.
]]--
Relayer.Children = {dynatag = "children"}::DynaChildren; table.freeze(Relayer.Children)
--[[
	A `Dyna` which directs Relayer to handle tags of an `Instance`.
]]--
Relayer.Tags = {dynatag = "tags"}::DynaTags; table.freeze(Relayer.Tags)

--[[
	Generates a `DynaEvent` with the given `eventName`

	Params:

	* `eventName` - The event name to target

	Returns:

	* `DynaEvent` - the `DynaEvent` with the given event name
]]--
function Relayer.Event(eventName: string): DynaEvent
	local dyna = dynamutables.event[eventName]
	if not dyna then
		dyna = {
			dynatag = "event",
			eventName = eventName
		}
	end

	return dyna
end

--[[
	Generates a `DynaChangeSignal` with the given property to listen to

	Params:

	* `propName` - The property name to target

	Returns:

	* `DynaChangeSignal` - the `DynaChangeSignal` with the given property name
]]--
function Relayer.Change(propName: string): DynaChangeSignal
	local dyna = dynamutables.change[propName]
	if not dyna then
		dyna = {
			dynatag = "changesignal",
			propertyName = propName
		}
	end

	return dyna
end

const function statemalloc(item: Instance)
	local state = mallocstate[item]
	if not state then
		state = {
			weak_storage = {
				events = setmetatable({}, {__mode = "v"}),
				change = setmetatable({}, {__mode = "v"}),
			},
			effects = {}
		}
		mallocstate[item] = state
	end
	return state
end

const function statefree(item: Instance)
	local state = mallocstate[item]
	if not state then return end
	mallocstate[item] = nil
	
	for _, connection in state.weak_storage.events do
		connection:Disconnect()
	end
	for _, connection in state.weak_storage.change do
		connection:Disconnect()
	end
	for dispose in state.effects do
		dispose()
	end
end

type MallocCategory = "event"|"change"|"effect"
const function setalloc(item: Instance, category: MallocCategory, key: any, value: any)
	local state = statemalloc(item)
	
	if category == "event" then
		state.weak_storage.events[key] = value
	elseif category == "change" then
		state.weak_storage.change[key] = value
	elseif category == "effect" then
		state.effects[key] = value
	end
end

function RCI.createVirtual(props): Instance
	local cname = props.ClassName
	if not cname then error("Failed to get prop 'ClassName'") end
	props.ClassName = nil
	local obj = Instance.new(cname)
	
	statemalloc(obj)
	
	local c; c = obj.AncestryChanged:Connect(function(_, p)
		if p == nil then
			c:Disconnect()
			statefree(obj)
		end
	end)
	
	return obj
end

function RCI.children(props): {[string|IVirtual]: {[any]: any}}
	local children = props[Relayer.Children]
	if children then
		props[Relayer.Children] = nil
		return children
	end
	return {}
end

function RCI.findCreatedVirt(childIndex: IVirtual|string, parent: IVirtual): (IVirtual?, string)
	if typeof(childIndex) == "Instance" then
		if childIndex.Parent == parent then
			return childIndex, childIndex.Name
		end
	else
		return parent:FindFirstChild(childIndex), childIndex
	end
	
	return nil, childIndex
end

function RCI.setParent(child: IVirtual, parent: IVirtual)
	child.Parent = parent
end

const function compare<T>(values: {T}, changed: {[T]: any}): ({T}, {T})
	changed = table.clone(changed)
	
	local added, removed = {}, {}
	
	for _, value in values do
		if changed[value] then
			changed[value] = nil
		else
			table.insert(removed, value)
		end
	end
	
	for changed in changed do
		table.insert(added, changed)
	end
	
	return added, removed
end

const function dynaSet(virt: IVirtual, prop: IDyna, value: any)
	if prop.dynatag == "event" then
		if value == nil then
			setalloc(virt, "event", prop.eventName, nil)
		else
			local event = virt[prop.eventName]
			if typeof(event) ~= "RBXScriptSignal" then error(`{prop.eventName} is not a bindable signal on {virt.ClassName}`) end

			local sp = {
				Sender = virt
			}
			sp.Connection = event:Connect(function(...)
				value(sp, ...)
			end)
			table.freeze(sp)

			setalloc(virt, "event", prop.eventName, sp.Connection)
		end
	elseif prop.dynatag == "changesignal" then
		if value == nil then
			setalloc(virt, "change", prop.propertyName, nil)
		else
			local propName = prop.propertyName
			local event = virt:GetPropertyChangedSignal(propName)
			local sp = {
				Sender = virt
			}
			sp.Connection = event:Connect(function(...)
				value(sp, propName, ...)
			end)
			table.freeze(sp)

			setalloc(virt, "change", propName, sp.Connection)
		end
	elseif prop.dynatag == "tags" then
		if type(value) ~= "table" then error("Invalid tags type") end
		
		local add, remove = compare(virt:GetTags(), value)
		
		for _, tag in remove do
			virt:RemoveTag(tag)
		end
		for _, tag in add do
			virt:AddTag(tag)
		end
	elseif prop.dynatag == "children" then
		if type(value) ~= "table" then error("Invalid children type") end
		
		local add, remove = compare(virt:GetChildren(), value)
		
		for _, child in remove do
			child:Destroy()
		end
		for _, child in add do
			child.Parent = virt
		end
	else
		error(`Unknown Dyna type {prop.key or prop}`)
	end
end

function RCI.setValue(virt: IVirtual, prop: string|IDyna, value: any)
	if type(prop) == "table" then
		dynaSet(virt, prop, value)
	else
		virt[prop] = value
	end	
end

function RCI.effectAllocate(virt: IVirtual, dispose: Signals.dispose)
	setalloc(virt, "effect", dispose, true)
	return function()
		setalloc(virt, "effect", dispose, nil)
		dispose()
	end
end

Relayer.__RCImplementor = RCI
return Relayer