# res://tests/unit/test_chunk_entity_lifecycle.gd
extends GutTest

## Lebenszyklus der Chunk-Entities: was ein Chunk spawnt, muss beim Entladen wieder verschwinden
## (sonst schweben Bäume/Tiere ohne Boden in der Luft und entstehen beim Zurückkehren doppelt),
## Abgeerntetes darf nicht neu entstehen, doppeltes Laden darf nichts verdoppeln.

class FlatField extends TerrainField:
	func get_height_at(_x: float, _z: float) -> float:
		return 5.0

var _field: FlatField
var _spawner: ChunkEntitySpawner
var _spawned_nodes: Array[Node3D] = []
var _spawned_types: Array[String] = []
var _unloaded: Array[Node3D] = []
var _harvested_types: Dictionary = {}

func before_each() -> void:
	_field = FlatField.new()
	_spawned_nodes = []
	_spawned_types = []
	_unloaded = []
	_harvested_types = {}
	_spawner = ChunkEntitySpawner.new(64.0, 4242, _spawn_cb)

func _spawn_cb(type_id: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	autofree(n)
	_spawned_nodes.append(n)
	_spawned_types.append(type_id)
	return n

func _unload_cb(node: Node3D) -> void:
	_unloaded.append(node)

func _is_harvested_cb(type_id: String, _pos: Vector3) -> bool:
	return _harvested_types.has(type_id)

## Erster Chunk (ab (0,0) spiralförmig) in dem tatsächlich etwas spawnt.
func _find_spawning_chunk(spawner: ChunkEntitySpawner, skip: Array[Vector2i] = []) -> Vector2i:
	for i in 60:
		var coord := Vector2i(i % 8, i / 8)
		if skip.has(coord):
			continue
		spawner.spawn_for_chunk(coord, Vector2(coord.x * 64.0, coord.y * 64.0), _field)
		if spawner.get_spawned_count(coord) > 0:
			return coord
	return Vector2i(-999, -999)

# ── Buchführung ─────────────────────────────────

func test_spawner_tracks_what_it_spawned() -> void:
	var coord := _find_spawning_chunk(_spawner)
	assert_ne(coord, Vector2i(-999, -999), "Testaufbau: irgendein Chunk muss etwas spawnen.")
	# Vorherige (leere) Chunks haben nichts beigetragen → alles Gespawnte gehört zu `coord`.
	assert_eq(_spawner.get_spawned_count(coord), _spawned_nodes.size())

func test_despawn_releases_exactly_the_spawned_entities() -> void:
	var coord := _find_spawning_chunk(_spawner)
	var count := _spawner.get_spawned_count(coord)
	_spawner.despawn_for_chunk(coord, _unload_cb)
	assert_eq(_unloaded.size(), count)
	assert_eq(_spawner.get_spawned_count(coord), 0)

func test_despawn_unknown_chunk_is_a_noop() -> void:
	_spawner.despawn_for_chunk(Vector2i(500, 500), _unload_cb)
	assert_eq(_unloaded.size(), 0)

func test_despawn_only_touches_its_own_chunk() -> void:
	var a := _find_spawning_chunk(_spawner)
	var b := _find_spawning_chunk(_spawner, [a])
	assert_ne(a, b)
	var count_b := _spawner.get_spawned_count(b)
	_spawner.despawn_for_chunk(a, _unload_cb)
	assert_eq(_spawner.get_spawned_count(b), count_b, "Anderer Chunk bleibt unberührt.")

func test_already_freed_entities_are_skipped() -> void:
	var coord := _find_spawning_chunk(_spawner)
	var count := _spawner.get_spawned_count(coord)
	_spawned_nodes[0].free()   # z.B. Baum wurde gefällt und freigegeben
	_spawner.despawn_for_chunk(coord, _unload_cb)
	assert_eq(_unloaded.size(), count - 1)

# ── Doppeltes Laden / Neu-Laden ─────────────────

func test_loading_same_chunk_twice_does_not_duplicate() -> void:
	var coord := _find_spawning_chunk(_spawner)
	var before := _spawned_nodes.size()
	_spawner.spawn_for_chunk(coord, Vector2(coord.x * 64.0, coord.y * 64.0), _field)
	assert_eq(_spawned_nodes.size(), before)

func test_reload_after_unload_recreates_the_same_entities() -> void:
	var coord := _find_spawning_chunk(_spawner)
	var first_count := _spawner.get_spawned_count(coord)
	var first_types := _spawned_types.duplicate()
	_spawner.despawn_for_chunk(coord, _unload_cb)
	_spawned_types.clear()
	_spawner.spawn_for_chunk(coord, Vector2(coord.x * 64.0, coord.y * 64.0), _field)
	assert_eq(_spawner.get_spawned_count(coord), first_count, "Deterministisch: dieselben Entities wie beim ersten Mal.")
	# Die zuletzt gespawnten Typen entsprechen denen des Chunks (Reihenfolge deterministisch).
	assert_eq(_spawned_types.slice(_spawned_types.size() - first_count), first_types.slice(first_types.size() - first_count))

# ── Abgeerntetes ────────────────────────────────

func test_harvested_types_are_not_respawned() -> void:
	var coord := _find_spawning_chunk(_spawner)
	var seen: Dictionary = {}
	for t in _spawned_types:
		seen[t] = true
	# Neuer Spawner, dem ALLE bisher gesehenen Typen als abgeerntet gelten.
	_harvested_types = seen
	var filtered := ChunkEntitySpawner.new(64.0, 4242, _spawn_cb, _is_harvested_cb)
	var before := _spawned_nodes.size()
	filtered.spawn_for_chunk(coord, Vector2(coord.x * 64.0, coord.y * 64.0), _field)
	assert_eq(_spawned_nodes.size(), before, "Abgeerntetes darf nicht neu entstehen.")
	assert_eq(filtered.get_spawned_count(coord), 0)

func test_harvest_filter_does_not_change_rng_sequence_for_the_rest() -> void:
	# Ohne Filter: N Entities. Filter, der nichts sperrt → gleich viele (der Filter greift erst NACH
	# dem Würfeln, verschiebt also keine Zufallsfolge).
	var coord := _find_spawning_chunk(_spawner)
	var baseline := _spawner.get_spawned_count(coord)
	var passthrough := ChunkEntitySpawner.new(64.0, 4242, _spawn_cb, _is_harvested_cb)
	passthrough.spawn_for_chunk(coord, Vector2(coord.x * 64.0, coord.y * 64.0), _field)
	assert_eq(passthrough.get_spawned_count(coord), baseline)

# ── Callback-Robustheit ─────────────────────────

func test_spawn_callback_returning_null_is_not_tracked() -> void:
	var null_spawner := ChunkEntitySpawner.new(64.0, 4242, _null_spawn_cb)
	var coord := _find_spawning_chunk(null_spawner)
	assert_eq(coord, Vector2i(-999, -999), "Nichts wurde erzeugt → nichts zu verfolgen.")

func _null_spawn_cb(_type_id: String, _pos: Vector3) -> Node3D:
	return null

func test_invalid_unload_callback_does_not_crash() -> void:
	var coord := _find_spawning_chunk(_spawner)
	_spawner.despawn_for_chunk(coord, Callable())
	assert_eq(_spawner.get_spawned_count(coord), 0, "Buchführung wird trotzdem bereinigt.")
