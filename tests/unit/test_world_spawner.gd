# res://tests/unit/test_world_spawner.gd
extends GutTest

## Unit-Tests für WorldSpawner.
##
## Strategie: WorldSpawner extends RefCounted — direkt instanziierbar.
## EntityOrchestrator und WorldData als einfache Doubles/Stubs.
## Kein SceneTree-Overhead.
##
## Abgedeckt:
##   P1 — Typisiertes Spawning: willow_tree / maple_tree / copper_ore werden gespawnt
##   P1 — Harvest-Filter: geerntete typed Positions werden nicht gespawnt
##   P1 — Seed-Konsistenz: _generate_positions() nutzt world_seed aus WorldData

# ─────────────────────────────────────────────
# Stubs
# ─────────────────────────────────────────────

## Minimaler EntityOrchestrator-Stub: zeichnet alle spawn_entity()-Aufrufe auf.
class StubOrchestrator extends EntityOrchestrator:
	var spawned: Array = []
	var spawned_nodes: Array[Node3D] = []

	func spawn_entity(type_id: String, pos: Vector3, _cfg: Dictionary = {}, _pid: int = 1) -> Node3D:
		spawned.append({"type_id": type_id, "position": pos})
		var n := Node3D.new()
		spawned_nodes.append(n)
		return n

	func get_entity_count() -> int:
		return spawned.size()

## Minimal-Stub für TerrainField — get_height_at() gibt 0 zurück.
class StubTerrain extends TerrainField:
	func get_height_at(_x: float, _z: float) -> float:
		return 0.0

# ─────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────

var _orchestrator: StubOrchestrator
var _data:         WorldData
var _terrain:      StubTerrain

func before_each() -> void:
	_orchestrator = add_child_autofree(StubOrchestrator.new()) as StubOrchestrator
	_data         = WorldData.new()
	_terrain      = StubTerrain.new()

func after_each() -> void:
	for n in _orchestrator.spawned_nodes:
		if is_instance_valid(n):
			n.free()

# ─────────────────────────────────────────────
# Typisiertes Spawning (P1)
# ─────────────────────────────────────────────

func test_typed_trees_all_spawned() -> void:
	## Wenn typed_tree_positions befüllt ist, müssen alle Typen spawnen.
	_data.add_typed_tree("willow_tree", Vector3(1, 0, 1))
	_data.add_typed_tree("maple_tree",  Vector3(2, 0, 2))
	_data.add_typed_tree("oak_tree",    Vector3(3, 0, 3))

	var spawner := _make_spawner()
	spawner.spawn_all(autofree(Node3D.new()))

	var type_ids := _orchestrator.spawned.map(func(e): return e["type_id"])
	assert_true("willow_tree" in type_ids, "willow_tree muss gespawnt werden")
	assert_true("maple_tree"  in type_ids, "maple_tree muss gespawnt werden")
	assert_true("oak_tree"    in type_ids, "oak_tree muss gespawnt werden")

func test_typed_ores_all_spawned() -> void:
	_data.add_typed_ore("iron_ore",   Vector3(-4, 0, 6))
	_data.add_typed_ore("copper_ore", Vector3(6,  0, -8))

	var spawner := _make_spawner()
	spawner.spawn_all(autofree(Node3D.new()))

	var type_ids := _orchestrator.spawned.map(func(e): return e["type_id"])
	assert_true("iron_ore"   in type_ids, "iron_ore muss gespawnt werden")
	assert_true("copper_ore" in type_ids, "copper_ore muss gespawnt werden")

# ─────────────────────────────────────────────
# Harvest-Filter (P0/P1)
# ─────────────────────────────────────────────

func test_harvested_typed_tree_not_spawned() -> void:
	## Geerntete Position (via make_key) darf nicht respawnt werden.
	var pos := Vector3(5, 0, 5)
	_data.add_typed_tree("oak_tree", pos)
	_data.mark_harvested(WorldData.make_key("oak_tree", pos))

	var spawner := _make_spawner()
	spawner.spawn_all(autofree(Node3D.new()))

	var tree_spawns := _orchestrator.spawned.filter(
		func(e): return e["type_id"] == "oak_tree" and e["position"].is_equal_approx(pos)
	)
	assert_eq(tree_spawns.size(), 0,
		"Geerntete oak_tree-Position darf nicht gespawnt werden")

func test_harvested_typed_ore_not_spawned() -> void:
	var pos := Vector3(-4, 0, 6)
	_data.add_typed_ore("copper_ore", pos)
	_data.mark_harvested(WorldData.make_key("copper_ore", pos))

	var spawner := _make_spawner()
	spawner.spawn_all(autofree(Node3D.new()))

	var ore_spawns := _orchestrator.spawned.filter(
		func(e): return e["type_id"] == "copper_ore" and e["position"].is_equal_approx(pos)
	)
	assert_eq(ore_spawns.size(), 0,
		"Geerntete copper_ore-Position darf nicht gespawnt werden")

func test_unharvested_type_at_same_position_still_spawns() -> void:
	## Nur der geerntete Typ wird gefiltert — andere Typen an selber Position spawnen.
	var pos := Vector3(5, 0, 5)
	_data.add_typed_tree("oak_tree",    pos)
	_data.add_typed_tree("willow_tree", pos)
	_data.mark_harvested(WorldData.make_key("oak_tree", pos))

	var spawner := _make_spawner()
	spawner.spawn_all(autofree(Node3D.new()))

	var willow_spawns := _orchestrator.spawned.filter(
		func(e): return e["type_id"] == "willow_tree" and e["position"].is_equal_approx(pos)
	)
	assert_eq(willow_spawns.size(), 1,
		"Willow an selber Position wie geerntete Eiche muss trotzdem spawnen")

# ─────────────────────────────────────────────
# Seed-Konsistenz (P1)
# ─────────────────────────────────────────────

func test_generate_positions_uses_world_seed() -> void:
	## _generate_positions() ohne WorldGenerationService → Hardcode-Defaults.
	## world_seed muss in _data gesetzt werden wenn er 0 war.
	_data.world_seed = 42
	var spawner := _make_spawner_no_worldgen()
	spawner._generate_positions()
	## Nach _generate_positions(): typed_tree_positions muss befüllt sein.
	assert_false(_data.typed_tree_positions.is_empty(),
		"_generate_positions() muss typed_tree_positions befüllen")
	## Seed-Konsistenz: world_seed darf nicht von 42 abweichen
	assert_eq(_data.world_seed, 42,
		"world_seed darf durch _generate_positions() nicht überschrieben werden wenn bereits gesetzt")

func test_generate_positions_sets_seed_if_zero() -> void:
	_data.world_seed = 0
	var spawner := _make_spawner_no_worldgen()
	spawner._generate_positions()
	assert_ne(_data.world_seed, 0,
		"world_seed muss gesetzt werden wenn er 0 war")

# ─────────────────────────────────────────────
# ADR-010 Round 55: Tier 3 — spawn_local_player=false
# ─────────────────────────────────────────────

func test_spawn_local_player_true_by_default_spawns_player() -> void:
	## Tier 1/2 unverändert: Default-Parameter muss weiterhin ein Player-Entity spawnen.
	var spawner := _make_spawner()
	spawner.spawn_all(autofree(Node3D.new()))
	var type_ids := _orchestrator.spawned.map(func(e): return e["type_id"])
	assert_true("player" in type_ids,
		"Ohne spawn_local_player-Parameter muss weiterhin ein Player-Entity gespawnt werden (Tier 1/2).")

func test_spawn_local_player_false_skips_player_spawn() -> void:
	## Tier 3: der Host-Prozess spielt nicht mit — kein Player-Entity für ihn.
	var spawner := _make_spawner()
	spawner.spawn_all(autofree(Node3D.new()), 1, false)
	var type_ids := _orchestrator.spawned.map(func(e): return e["type_id"])
	assert_false("player" in type_ids,
		"Mit spawn_local_player=false darf KEIN Player-Entity für den Host gespawnt werden (Tier 3).")

func test_spawn_local_player_false_still_spawns_world_content() -> void:
	## Tier 3: die Welt existiert unabhängig davon, ob der Host mitspielt —
	## nur das Player-Entity entfällt, alles andere bleibt unverändert.
	_data.add_typed_tree("oak_tree", Vector3(5, 0, 5))
	var spawner := _make_spawner()
	spawner.spawn_all(autofree(Node3D.new()), 1, false)
	var type_ids := _orchestrator.spawned.map(func(e): return e["type_id"])
	assert_true("oak_tree" in type_ids,
		"spawn_local_player=false darf das Spawnen der übrigen Welt (Bäume/Erze/NPCs/Tiere) nicht beeinflussen.")
	assert_true("woodcutter_npc" in type_ids,
		"spawn_local_player=false darf den Quest-NPC-Spawn nicht beeinflussen.")
	assert_true("tutorial_guide_npc" in type_ids,
		"spawn_local_player=false darf den Tutorial-Guide-NPC-Spawn nicht beeinflussen (ADR-048 Round 106).")

func test_spawn_all_spawns_all_four_stationary_npcs() -> void:
	## ADR-048 Round 106: Tutorial-Guide-NPC ist der fünfte stationäre NPC
	## neben Quest/Shop/Bank/Auktionshaus — hier einmal gebündelt geprüft,
	## dass keiner davon beim normalen (Tier 1/2) Spawn-Pfad fehlt.
	var spawner := _make_spawner()
	spawner.spawn_all(autofree(Node3D.new()))
	var type_ids := _orchestrator.spawned.map(func(e): return e["type_id"])
	for expected in ["woodcutter_npc", "shop_npc", "bank_npc", "auction_house_npc", "tutorial_guide_npc"]:
		assert_true(expected in type_ids, "%s muss beim normalen Spawn-Pfad gespawnt werden." % expected)

# ─────────────────────────────────────────────
# Hilfsfunktionen
# ─────────────────────────────────────────────

## WorldSpawner ohne WorldGenerationService (für die Seed-Tests, die _generate_positions()
## ohne echte Terrain-Generierung ausüben).
## spawn_player_cb ist seit dem ChunkManager-Fix (kein stiller Fallback mehr,
## siehe WorldSpawner._init()) Pflicht-Dep — hier auf denselben Stub-Orchestrator
## geroutet wie die übrigen Spawns, analog zu WorldService.spawn_entity() in Produktion.
func _make_spawner_no_worldgen() -> WorldSpawner:
	return WorldSpawner.new(
		_orchestrator as EntityOrchestrator, _terrain as TerrainField, null, _data,
		func(pos: Vector3, pid: int) -> Node3D:
			return _orchestrator.spawn_entity("player", pos, {spawn_position = pos}, pid)
	)

## WorldSpawner mit Stub-Terrain aber ohne WorldGenerationService.
func _make_spawner() -> WorldSpawner:
	return _make_spawner_no_worldgen()
