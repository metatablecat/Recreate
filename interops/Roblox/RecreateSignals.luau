--!strict
const Recreate = require(script.Parent.Recreate)
const Signals = require(script.Parent.Signals)

export type WatchableEffect<T> = {
	__RCImplementor: {
		watch: (WatchableEffect<T>, Recreate.Node, string|Recreate.SpecialKey<unknown>) -> unknown,
		unwatch: (WatchableEffect<T>, Recreate.Node, (string|Recreate.SpecialKey<unknown>)?) -> (),
	},
	bindings: {[Recreate.Node]: {[string|Recreate.SpecialKey<unknown>]: true}},
	getter: Signals.getter<T>,
	dispose: Signals.dispose
}

const RCI = {
	watch = function<T>(self: WatchableEffect<T>, node: Recreate.Node, key: string|Recreate.SpecialKey<unknown>): unknown
		local binding = self.bindings[node]
		if not binding then
			binding = {}
			self.bindings[node] = binding
		end

		binding[key] = true
		return self.getter()
	end,
	
	unwatch = function<T>(self: WatchableEffect<T>, node: Recreate.Node, key: string|Recreate.SpecialKey<unknown>?)
		if not key then
			self.bindings[node] = nil
		else
			local binding = self.bindings[node]
			if not binding then return end
			binding[key] = nil
			if not next(binding) then
				self.bindings[node] = nil
			end
		end
	end,
}

return function<T>(getter: Signals.getter<T>): WatchableEffect<T>
	local effect = {}::WatchableEffect<T>
	local bindings = {}
	effect.__RCImplementor = RCI
	effect.bindings = bindings
	effect.getter = getter
	
	effect.dispose = Signals.createEffect(function(scope)
		local value = getter(scope)
		for node, binding in bindings do
			for key in binding do
				if Recreate.isSpecialKey(key) then
					Recreate.Node.specialKeySet(node, key::Recreate.SpecialKey<unknown>, value)
					-- we dont have mutable behaviour in Signals, so we need this despite it being more expensive
					-- either way, polyfilling would be expensive in either Signals OR Recreate so
					-- its not a big deal
					
					-- there are other primitive Watchables that can provide mutable table behaviour if it is needed
				else
					Recreate.Node.setProperty(node, key::string, value)
				end
			end
		end
	end)
	
	return effect
end
