class_name VillageNames
extends RefCounted

## VillageNames — deterministische deutsche Ortsnamen ("Eichenfurt", "Birkenau", …).
## Reine Funktion von einem Integer-Hash; keine Marken-/Franchise-Namen (siehe AGENT.md).

const PREFIXES: Array[String] = [
	"Eichen", "Birken", "Stein", "Mühl", "Wald", "Bach", "Linden", "Hain", "Rosen", "Fuchs",
	"Raben", "Nebel", "Wiesen", "Kiesel", "Weiden", "Tannen", "Buchen", "Hirsch", "Salz", "Klee",
	"Erlen", "Ahorn", "Moos", "Kranich", "Hasel", "Wolfs", "Distel", "Amsel",
]
const SUFFIXES: Array[String] = [
	"dorf", "bach", "furt", "au", "stedt", "hagen", "brunn", "heim", "feld", "rode", "thal", "kamp",
]

## `kind_id`: Dorf-Art; deren name_suffixes() ersetzen die Standard-Endungen ("Birkenwipfel" statt "Birkenfeld").
static func name_for(hash_value: int, kind_id: String = VillageKinds.KIND_GROUND) -> String:
	var h: int = absi(hash_value)
	var suffixes: Array[String] = VillageKinds.get_kind(kind_id).name_suffixes()
	if suffixes.is_empty():
		suffixes = SUFFIXES
	var prefix: String = PREFIXES[h % PREFIXES.size()]
	var suffix: String = suffixes[(h >> 5) % suffixes.size()]
	return prefix + suffix
