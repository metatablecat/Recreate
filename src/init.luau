-- RECREATE 2.0
-- APACHE 2.0 LICENSE
-- metatablecat games 2023-2026

const Common = require("@self/Common")
const Types = require("@self/Types")

export type Node = Types.NodeRef
export type SpecialKey<T> = Types.SpecialKey<T>
export type Watchable = Types.Watchable
export type Component<T> = Types.Component<T>
export type RendererNode = Types.Node

local RC_LIB = {
	_VERSION = Common.LIB_VER,

	Ref = Common.KEY_Ref,
	OnInit = Common.KEY_OnInit,
	Children = Common.KEY_Children,
	isSpecialKey = Common.isLikelySpecialKey,

	create = require("@self/NodeBuilder"),
	component = require("@self/Component"),

	Node = require("@self/Nodelib"),
	setRenderer = require("@self/Renderer").set,
	
	NULL = Common.NULL
}

function RC_LIB.RENDERER_getInternalNode(node): Types.Node
	-- copypaste: NodeLib.resolvePublic
	local inode = Common.RefStorage[node.ID]
	if not inode then error(`Node {node.ID} is destroyed`) end
	if inode.Destroyed then error(`Node {node.ID} is destroyed`) end
	if inode.Ref ~= node then error(`Node {node.ID} is destroyed`) end
	return inode
end

setmetatable(RC_LIB, {
	__tostring = function() return `Recreate v{Common.LIB_VER} - metatablecat games` end
})
table.freeze(RC_LIB)
return RC_LIB