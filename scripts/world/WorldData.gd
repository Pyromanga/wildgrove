class_name WorldData
extends RefCounted

## WorldData — Reines Daten-Objekt für den Weltzustand.
##
## KEIN Node-Overhead — extends RefCounted (kein SceneTree nötig).
##
## BUG-FIX (Session 4): Fragile positions-derived String-Keys ersetzt.
##   VORHER: "tree_" + str(pos) → str(Vector3(5,0,5)) ist plattformabhängig
##           (Locale, Float-Präzision). Zwei Bäume die denselben String erzeugen
##           → silent Data-Loss im Save.
##   NACHHER: "tree_%d_%d_%d" % [int(x), int(y), int(z)] — deterministisch,
##            locale-unabhängig, int-gecasted (ganzzahlige Grid-Koordinaten).
##
## Langfristig: Entity-UUIDs statt positions-derived Keys (ChunkService-Scope).

var tree_positions:    Array[Vector3] = []
var ore_positions:     Array[Vector3] = []
var player_position:   Vector3 = Vector3.ZERO
## Format: { "tree_5_0_5": true, "ore_-3_0_2": true }
var harvested_objects: Dictionary = {}


func add_tree(pos: Vector3) -> void:
	if not pos in tree_positions:
		tree_positions.append(pos)


func add_ore(pos: Vector3) -> void:
	if not pos in ore_positions:
		ore_positions.append(pos)


func mark_harvested(key: String) -> void:
	harvested_objects[key] = true
	Logger.log_debug("Als geerntet markiert: '%s'." % key, "WorldData")


func mark_tree_harvested(pos: Vector3) -> void:
	mark_harvested(_tree_key(pos))


func mark_ore_harvested(pos: Vector3) -> void:
	mark_harvested(_ore_key(pos))


func is_tree_harvested(pos: Vector3) -> bool:
	return harvested_objects.has(_tree_key(pos))


func is_ore_harvested(pos: Vector3) -> bool:
	return harvested_objects.has(_ore_key(pos))


## Legacy-Kompatibilität: generischer Key-Check (für externe Aufrufer die
## noch einen String übergeben — bis zur vollständigen Migration).
func is_harvested(key: String) -> bool:
	return harvested_objects.has(key)


func get_tree_count() -> int:
	return tree_positions.size()


func get_ore_count() -> int:
	return ore_positions.size()


# ─────────────────────────────────────────────
# Intern — deterministische Key-Generierung
# ─────────────────────────────────────────────


## Deterministischer Key: Locale-unabhängig, int-gecasted für ganzzahlige Grids.
static func _tree_key(pos: Vector3) -> String:
	return "tree_%d_%d_%d" % [int(pos.x), int(pos.y), int(pos.z)]


static func _ore_key(pos: Vector3) -> String:
	return "ore_%d_%d_%d" % [int(pos.x), int(pos.y), int(pos.z)]
