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

export type BuiltInDyna = RefDyna | HydrationDyna

type Props = {
	[string | BuiltInDyna | IDyna]: any
}

type HydrationEffects = {
	[Signals.setter<boolean>]: boolean
}
type RefQueue = {
	[Ref]: {[IVirtual]: {[string|IDyna]: (Ref) -> unknown}}
}

const function setPropertyDynamic(virt: IVirtual, propName: string | IDyna, propVal: any)
	if type(propVal) == "table" and propVal.__rctag == "hydrationeffect" then
			Recreate.setEffect(virt::IVirtual, propName, propVal.getter)
	else
		RendererRCI.setValue(virt::IVirtual, propName, propVal)
	end
end

const function hydrate(virt: IVirtual?, props: Props, objectName: string?, hydrationEffects: HydrationEffects, rq: RefQueue): IVirtual
	local hydrator = props[Recreate.hydrated]
	if hydrator then
		if not hydrationEffects[hydrator] then
			hydrationEffects[hydrator] = true
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
	
	for childIndex, childProps in RendererRCI.children(props::any) do
		local child, name = RendererRCI.findCreatedVirt(childIndex, virt::IVirtual)
		local obj = hydrate(child, childProps, name, hydrationEffects, rq)
		RendererRCI.setParent(obj, virt::IVirtual)
	end

	for propName: IDyna|string, propVal in props do
		if type(propVal) == "table" and propVal.__rctag == "refconsumer" then
			local aref: Ref = propVal.ref
			local refslot = rq[aref]

			if not refslot then
				refslot = {}
				rq[aref] = refslot
			end

			local objslot = refslot[virt::IVirtual]
			if not objslot then
				objslot = {}
				refslot[virt::IVirtual] = objslot
			end

			objslot[propName] = propVal.fn
		else
			setPropertyDynamic(virt::IVirtual, propName, propVal)
		end
	end
	
	return virt::IVirtual
end

const function doHydration(obj: IVirtual?, props): IVirtual
	local hydrationEffects: HydrationEffects = {}
	local refQueue: RefQueue = {}
	obj = hydrate(obj, props, nil, hydrationEffects, refQueue)

	for ref, state in refQueue do
		if not ref.value then continue end -- never allocated
		for virt, objstate in state do
			for propName, resolver in objstate do
				setPropertyDynamic(virt, propName, resolver(ref))
			end
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
		RendererRCI.setValue(virt, prop, getter(scope))
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
