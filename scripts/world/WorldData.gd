class_name WorldData
extends RefCounted

## WorldData — Reines Daten-Objekt für den Weltzustand.
## Kein Node-Overhead — reine Datenhaltung (RefCounted).

var tree_positions: Array[Vector3] = []
var ore_positions: Array[Vector3] = []
var player_position: Vector3 = Vector3.ZERO
var harvested_objects: Dictionary = {}  # { "object_uuid": true }


func add_tree(pos: Vector3) -> void:
	tree_positions.append(pos)


func add_ore(pos: Vector3) -> void:
	ore_positions.append(pos)


func mark_harvested(uuid: String) -> void:
	harvested_objects[uuid] = true


func is_harvested(uuid: String) -> bool:
	return harvested_objects.has(uuid)


func get_tree_count() -> int:
	return tree_positions.size()
