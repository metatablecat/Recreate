-- utility types
export type Dictionary<K, V> = {[K]: V}
export type Map<T> = {[T]: boolean}
export type DictionaryIndex<T, U, V> = Dictionary<T, Dictionary<U, V>>
export type MapIndex<T, U> = Dictionary<T, Map<U>>

-- lib types

export type SpecialKey<T = any> = {
	key: T,
	[any]: any
} 

export type NodeRef = {
	read ID: number
}

export type RCImplementor = {
	watch: (Watchable, NodeRef, string|SpecialKey) -> unknown,
	unwatch: (Watchable, NodeRef, (string|SpecialKey)?) -> (),
}

export type Watchable = {
	__RCImplementor: RCImplementor,
	[any]:any
}

export type Node = {
	ID: number,
	Ref: NodeRef,
	Destroyed: boolean,
	
	Props: Dictionary<string, unknown>,
	SpecialKeys: Dictionary<SpecialKey, unknown>,
	WatchableState: MapIndex<Watchable, string>,

	BoundToSource: boolean,
	Children: Map<Node>,
	Parent: Node?
}

export type MakeDescription = {
	[SpecialKey|string]: unknown
}

export type Component<T> = (T) -> ComponentCapture<T>
export type ComponentCapture<T> = {
	read name: string,
	read capture: T,
	read build: (T) -> MakeDescription
}

export type Pipeline = {
	init: (initialState: {Node}) -> (), -- REQUIRED FOR FIRST INIT

	setParent: (node: Node, parent: Node?, oldParent: Node?) -> ()?,
	setChildrenBatch: (node: Node, newChildren: {Node}, removedChildren: {Node}) -> ()?,
	destroy: (node: Node) -> ()?,
	setProperty: (node: Node, prop: string, val: any, oldVal: any) -> ()?,

	-- specialkey logic
	specialKeySet: (node: Node, sk: SpecialKey, val: any, oldval: any) -> ()?,

	-- list/dict
	specialKeySetIndex: (node: Node, sk: SpecialKey, index: any, val: any, oldval: any) -> ()?,
	specialKeyBatchSetIndex: (node: Node, sk: SpecialKey, pairs: {[any]: any}, oldpairs: {[any]: any}) -> ()?,
	specialKeyBatchRemove: (node: Node, sk: SpecialKey, keys: {any}, oldpairs: {[any]: any}) -> ()?
}

return nil