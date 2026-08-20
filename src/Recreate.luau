-- A simpler Recreate
--!strict
--!optimize 2

const USE_TEST_RENDERING = _G.USE_TEST_RENDERING or false

const Renderer = require(script.Renderer)
const RendererRCI = Renderer.__RCImplementor
if not RendererRCI then
	error("Recreate is not linked to a renderer")
end

const Signals = require(script.Signals)

export type IVirtual = Renderer.IVirtual
export type IDyna = Renderer.IDyna

export type Ref = {
	value: IVirtual
}

export type RefDyna = {
	read k: "ref"
}
export type HydrationDyna = {
	read k: "hydrated"
}
export type SupressedDyna = {
	read k: "supressed"
}

export type HydrateEffectConsumer<T> = {
	__rctag: "hydrationeffect",
	getter: Signals.getter<T>
}

export type RefConsumer = {
	__rctag: "refconsumer",
	ref: Ref,
	fn: (Ref) -> unknown
}

const Recreate = {}

Recreate.ref = {k = "ref"}::RefDyna; table.freeze(Recreate.ref)
Recreate.hydrated = {k = "hydrated"}::HydrationDyna; table.freeze(Recreate.hydrated)
Recreate.supressed = {k = "supressed"}::SupressedDyna; table.freeze(Recreate.supressed)

export type BuiltInDyna = RefDyna | HydrationDyna | SupressedDyna

type Props = {
	[string | BuiltInDyna | IDyna]: any
}

type HydrationEffects = {
	[Signals.setter<boolean>]: boolean
}
type RefQueue = {
	[Ref]: {[IVirtual]: {[string|IDyna]: (Ref) -> unknown}}
}
type LateResolutionQueue = {
	[IVirtual]: {
		[IDyna|string]: unknown
	}
}
type QueueCtx = {
	hydration: HydrationEffects,
	refs: RefQueue,
	lateResolution: LateResolutionQueue
}

const function setPropertyDynamic(virt: IVirtual, propName: string | IDyna, propVal: any, supressed: boolean)
	if type(propVal) == "table" and propVal.__rctag == "hydrationeffect" then
		if supressed then return end
		Recreate.setEffect(virt::IVirtual, propName, propVal.getter)
	else
		RendererRCI.setValue(virt::IVirtual, propName, propVal, supressed)
	end
end

const function allocLateKey(virt: IVirtual, prop: IDyna|string, val: any, queue: LateResolutionQueue)
	local lateallocslot = queue[virt]
		if not lateallocslot then
			lateallocslot = {}
			queue[virt] = lateallocslot
		end

		lateallocslot[prop] = val
end

const function hydrateStep(virt: IVirtual, props: Props, queue: QueueCtx, supressed: boolean)
	for propName: IDyna|string, propVal in props do
		if type(propVal) == "table" and propVal.__rctag == "refconsumer" then
			if supressed then return end
			local aref: Ref = propVal.ref
			local refslot = queue.refs[aref]

			if not refslot then
				refslot = {}
				queue.refs[aref] = refslot
			end

			local objslot = refslot[virt::IVirtual]
			if not objslot then
				objslot = {}
				refslot[virt::IVirtual] = objslot
			end

			objslot[propName] = propVal.fn
		elseif RendererRCI.isLateAllocatedKey(propName) then
			allocLateKey(virt, propName, propVal, queue.lateResolution)
		else
			setPropertyDynamic(virt::IVirtual, propName, propVal, supressed)
		end
	end
end

const function hydrate(
	virt: IVirtual?,
	props: Props,
	objectName: string?,
	hydrationEffects: HydrationEffects,
	queue: QueueCtx,
	supression: boolean
): IVirtual
	if not supression then
		-- should we start supressing now?
		local flag = props[Recreate.supressed]
		if flag then
			supression = true
		end
	end
	props[Recreate.supressed] = nil

	if not supression then
		local hydrator = props[Recreate.hydrated]
		if hydrator then
			if not hydrationEffects[hydrator] then
				hydrationEffects[hydrator] = true
			end
		end
	end
	
	if not virt then
		virt = RendererRCI.createVirtual(props)
	end
	
	local ref: Ref? = props[Recreate.ref]
	if ref then
		props[Recreate.ref] = nil
		ref.value = virt::IVirtual
	end

	local children: {[any]: any} = props[RendererRCI.childrenDyna]
	if children then
		props[RendererRCI.childrenDyna] = nil

		if type(children) == "table" then
			if children.__rctag == "hydrationeffect" then
				if not supression then
					Recreate.setEffect(virt::Instance, RendererRCI.childrenDyna, children.getter)
				end
			elseif children.__rctag == "refconsumer" then
				error("Children key cannot be connected to useRef.")
			else
				for childIndex, childProps in children do
					local child, name = RendererRCI.findCreatedVirt(childIndex, virt::IVirtual)
					local obj = hydrate(child, childProps, name, hydrationEffects, queue, supression)
					RendererRCI.setParent(obj, virt::IVirtual)
				end
			end
		else
			error("Invalid type for Children, should be a table")
		end
	end

	hydrateStep(virt::IVirtual, props, queue, supression)
	return virt::IVirtual
end

const function doHydration(obj: IVirtual?, props: Props): IVirtual
	local hydrationEffects: HydrationEffects = {}
	local refQueue: RefQueue = {}
	local lateAllocQueue: LateResolutionQueue = {}
	local queue: QueueCtx = {
		hydration = hydrationEffects,
		refs = refQueue,
		lateResolution = lateAllocQueue
	}

	local supressionMode = props[Recreate.supressed] == true
	obj = hydrate(obj, props, nil, hydrationEffects, queue, supressionMode)

	for ref, state in refQueue do
		if not ref.value then continue end -- never allocated
		for virt, objstate in state do
			for propName, resolver in objstate do
				if RendererRCI.isLateAllocatedKey(propName) then
					allocLateKey(virt, propName, resolver(ref), lateAllocQueue)
				else
					setPropertyDynamic(virt, propName, resolver(ref), supressionMode)
				end
			end
		end
	end

	for virt, state in lateAllocQueue do
		for idyna, propVal in state do
			setPropertyDynamic(virt, idyna, propVal, supressionMode)
		end
	end

	for setter in hydrationEffects do setter(true) end
	return obj
end

--[[
	Creates a new `IVirtual` from the given `props` table.

	Refer to documentation on the layout of the `props` table
]]--
function Recreate.create(props): IVirtual
	-- make an empty object then hydrate as normal
	return doHydration(nil, props)
end

--[[
	Connects a `getter` from `Roblox/Signals` to a property through an `effect`

	Params:
	* `virt: IVirtual` - the `IVirtual` to connect to
	* `prop: string | IDyna` - the property or `Dyna` to bind to
	* `getter: Signals.getter<T>` - the `getter` function

	Returns:
	* `Signals.dispose` - A callback to dispose the effect
]]--
function Recreate.setEffect<T>(virt: IVirtual, prop: string|IDyna, getter: Signals.getter<T>): Signals.dispose
	local dispose = Signals.createEffect(function(scope)
		RendererRCI.setValue(virt, prop, getter(scope), false)
	end)
	return RendererRCI.effectAllocate(virt, dispose)
end

--[[
	Returns a table for binding an `getter` during hydration. This exists to allow renderers to
	descriminate between effects and functions.

	Params:
	* `getter: Signals.getter<T>` - The getter to listen to

	Returns:
	* `HydrateEffectConsumer` - an effect consumer for `Hydrate` to use
]]--
function Recreate.useEffect<T>(getter: Signals.getter<T>): HydrateEffectConsumer<T>
	return {
		__rctag = "hydrationeffect",
		getter = getter
	}
end

--[[
	Adds a callback that fires when a Ref is resolved. You can return a value
	or a `HydrationEffectConsumer` returned by `useEffect`.

	Params:
	* `ref`: Ref` - The Ref to connect to
	* `fn`: (Ref) -> unknown` - The callback that should return a new value

	Returns:
	* `RefConsumer` - a Ref consumer for `Hydrate` to use
]]--
function Recreate.useRef(ref: Ref, fn: (Ref) -> unknown): RefConsumer
	return {
		__rctag = "refconsumer",
		ref = ref,
		fn = fn
	}
end

--[[
	Hydrates an existing `IVirtual` from the given `props` table.

	Refer to documentation on the layout of the `props` table
]]--
function Recreate.hydrate(virt: IVirtual, props: Props)
	doHydration(virt, props)
end

--[[
	Sets a value for the given property name or `Dyna`.

	Refer to renderer impl for layout of this call
]]--
Recreate.setValue = RendererRCI.setValue
Recreate.renderer = Renderer
Recreate.signals = Signals

table.freeze(Recreate)
return Recreate
