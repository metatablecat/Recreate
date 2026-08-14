const Types = require("./Types")
const Common = require("./Common")

return function<T>(componentName: string, init: (T) -> Types.MakeDescription): Types.Component<T>
	if type(componentName) ~= "string" then error("Component name must be a string") end
	if type(init) ~= "function" then error("Component initialiser must be a function") end

	return function(capture: T)
		local comCapture = {
			name = componentName,
			build = init,
			capture = capture
		}
		table.freeze(comCapture)
		return {[Common.KEY_Factory] = comCapture}
	end
end