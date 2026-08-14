const Types = require("./Types")
const Common = {}
Common.LIB_VER = "2.0.0_alpha"
Common.RefStorage = {} :: {[number]: Types.Node}

const function specialKey<T>(key: T, value: any): Types.SpecialKey<T>
	local keypair = {
		key = key,
		value = value
	}
	table.freeze(keypair)

	return keypair
end

function Common.isLikelySpecialKey(sk: unknown): boolean
	return type(sk) == "table" and sk.key -- value of sk.value is unknown and is usually not consumed anyway outside of impl-specific usecases
end

function Common.DictionaryIndexerSet<T, U, V>(tab: Types.DictionaryIndex<T, U, V>, indexer: T, innerIndexer: U, innerValue: V): Types.Dictionary<U, V>
	local object = tab[indexer]

	if not object then
		object = {}
		tab[indexer] = object
	end

	object[innerIndexer] = innerValue
	return object
end

function Common.DictionaryIndexerRemove<T, U>(tab: Types.DictionaryIndex<T, U, unknown>, indexer: T, innerValue: U)
	local object = tab[indexer]
	if not object then return end

	object[innerValue] = nil
	if not next(object) then
		tab[indexer] = nil
	end
end

Common.KEY_Children = specialKey("Recreate.Children") :: Types.SpecialKey<"Recreate.Children">
Common.KEY_Factory = specialKey("Recreate.Factory") :: Types.SpecialKey<"Recreate.Factory">
Common.KEY_OnInit = specialKey("Recreate.OnInit") :: Types.SpecialKey<"Recreate.OnInit">
Common.KEY_Ref = specialKey("Recreate.Ref") :: Types.SpecialKey<"Recreate.Ref">
Common.MakeSpecialKey = specialKey
Common.NULL = {}; table.freeze(Common.NULL)

return Common