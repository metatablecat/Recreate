-- Done to cleanup some require bloat

local Recreate = require(script.Recreate)
local Relayer = require(script.Renderer)
local Signals = require(script.Signals)

-- type exports: Recreate
export type Ref = Recreate.Ref
export type RefDyna = Recreate.RefDyna
export type HydrationDyna = Recreate.HydrationDyna
export type HydrateEffectConsumer<T = unknown> = Recreate.HydrateEffectConsumer<T>
export type RefConsumer = Recreate.RefConsumer
export type BuiltInDyna = Recreate.BuiltInDyna

-- type exports: Relayer
export type EventDyna = Relayer.DynaEvent
export type ChangeSignalDyna = Relayer.DynaChangeSignal
export type ChildrenDyna = Relayer.DynaChildren
export type TagsDyna = Relayer.DynaTags
export type SenderParams = Relayer.SenderParams
export type IDyna = Relayer.IDyna
export type IVirtual = Relayer.IVirtual

-- type exports: Signals
export type getter<T> = Signals.getter<T>
export type setter<T> = Signals.setter<T>
export type update<T> = Signals.update<T>
export type equals<T> = Signals.equals<T>
export type dispose = Signals.dispose
export type scope = Signals.scope

return {
	Recreate = Recreate,
	Relayer = Relayer,
	Signals = Signals
}