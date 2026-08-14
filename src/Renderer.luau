const Common = require("./Common")
const Types = require("./Types")
const Renderer = {}

local PIPELINE

function Renderer.send(op: keyof<Types.Pipeline>, ...)
	if not PIPELINE then return end
	local f = PIPELINE[op]
	if not f then return end
	f(...)
end

function Renderer.set(renderPipeline: Types.Pipeline)
	if PIPELINE then error("A rendering pipeline is already set") end
	PIPELINE = renderPipeline

	renderPipeline.init(Common.RefStorage)
end

return Renderer