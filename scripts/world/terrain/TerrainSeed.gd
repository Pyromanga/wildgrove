class_name TerrainSeed
extends RefCounted

## TerrainSeed — leitet aus dem world_seed stabile Teil-Seeds ab (FNV-1a über "seed|salt").
##
## WARUM NICHT String.hash(): Der Wert von String.hash() ist nicht über Engine-Versionen
## garantiert. Ändert er sich, sähe jede bestehende Welt nach einem Engine-Update anders
## aus. FNV-1a ist festgeschrieben — dieselbe (world_seed, salt) ergibt für immer dieselbe
## Zahl, auf jedem Gerät und in jeder Godot-Version.
##
## Jede Noise-Quelle bekommt einen eigenen Salt ("terrain.continent", "climate.temp", ...):
## Änderungen an einer Quelle verschieben die anderen nicht, und keine zwei Quellen
## teilen sich versehentlich denselben Seed (was sie korrelieren würde).

const FNV_OFFSET: int = 2166136261
const FNV_PRIME: int = 16777619

## Gibt eine nicht-negative 31-Bit-Zahl zurück (passend für FastNoiseLite.seed).
static func derive(world_seed: int, salt: String) -> int:
	var h: int = FNV_OFFSET
	for b in ("%d|%s" % [world_seed, salt]).to_utf8_buffer():
		h = ((h ^ int(b)) * FNV_PRIME) & 0xFFFFFFFF
	return h & 0x7FFFFFFF
