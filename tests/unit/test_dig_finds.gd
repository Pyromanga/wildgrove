# res://tests/unit/test_dig_finds.gd
extends GutTest

## Tests für DigFindTable, DigFindRegistry und WorldDigHandler (Funde/Leitern) — ohne SceneTree.

var _ladders: LadderRegistry
var _finds: DigFindRegistry
var _handler: WorldDigHandler
var _spawned: Array = []
var _height: float = 0.0

func before_each() -> void:
	_ladders = LadderRegistry.new()
	_finds = DigFindRegistry.new()
	_spawned = []
	_height = 0.0
	_handler = WorldDigHandler.new(_ladders, _finds, _flat_ground, _spawn_stub, _despawn_stub, 64.0)
	_handler.seed_rng(12345)

func _flat_ground(_x: float, _z: float) -> float:
	return _height

func _spawn_stub(type_id: String, pos: Vector3, cfg: Dictionary) -> Node3D:
	_spawned.append({"type": type_id, "pos": pos, "cfg": cfg})
	return null

func _despawn_stub(_node: Node3D) -> void:
	pass

func test_chance_grows_with_depth_and_is_capped() -> void:
	assert_eq(DigFindTable.find_chance(0.0), DigFindTable.CHANCE_BASE)
	assert_gt(DigFindTable.find_chance(10.0), DigFindTable.find_chance(1.0))
	assert_eq(DigFindTable.find_chance(1000.0), DigFindTable.CHANCE_MAX)

func test_rare_finds_need_depth() -> void:
	assert_false("gem_diamond" in DigFindTable.kinds_at_depth(5.0))
	assert_false("gold_ore" in DigFindTable.kinds_at_depth(5.0))
	assert_true("gem_diamond" in DigFindTable.kinds_at_depth(25.0))
	assert_eq(DigFindTable.kinds_at_depth(0.0), ["copper_ore"] as Array[String])

func test_every_kind_has_manifest_item_and_loot() -> void:
	for kind: String in DigFindTable.KINDS.keys():
		var item_id: String = String(DigFindTable.get_def(kind)["item"])
		assert_true(_manifest_has_item(item_id), "Item fehlt im Manifest: %s" % item_id)
		assert_eq(DigFindTable.build_loot(kind).roll().keys(), [item_id])

func _manifest_has_item(item_id: String) -> bool:
	for path in DataManifest.ITEMS:
		var res: Resource = load(path)
		if res != null and res.get("id") == item_id:
			return true
	return false

func test_roll_statistics_are_sane() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hits: int = 0
	for i in 2000:
		if not DigFindTable.roll(10.0, rng).is_empty():
			hits += 1
	var rate: float = float(hits) / 2000.0
	assert_between(rate, 0.08, 0.20, "~12 %% bei 10 m")

func test_registry_roundtrip_and_near() -> void:
	assert_true(_finds.add({"key": "F_1", "kind": "gold_ore", "x": 3.0, "y": 1.0, "z": 4.0}))
	assert_false(_finds.add({"key": "F_2", "kind": "gibt_es_nicht", "x": 0.0, "y": 0.0, "z": 0.0}))
	assert_eq(_finds.near(3.0, 4.0, 0.5).size(), 1)
	var copy := DigFindRegistry.new()
	copy.load_save(_finds.to_save())
	assert_eq(copy.count(), 1)

func test_after_dig_spawns_and_persists_find() -> void:
	var found: int = 0
	for i in 200:
		_finds.clear()
		_spawned = []
		if not String(_handler.after_dig(Vector2(20, 20), 10.0)["found"]).is_empty():
			found += 1
			assert_eq(_finds.count(), 1)
			assert_eq(_spawned[0]["type"], WorldDigHandler.ENTITY_FIND)
			assert_almost_eq((_spawned[0]["pos"] as Vector3).y, WorldDigHandler.FIND_LIFT, 0.001)
	assert_gt(found, 0)

func test_finds_follow_the_ground() -> void:
	_finds.add({"key": "F_a", "kind": "copper_ore", "x": 20.0, "y": 0.15, "z": 20.0})
	_height = -3.0
	_handler.reseat_finds(Vector2(20, 20))
	assert_almost_eq(float(_finds.get_record("F_a")["y"]), -3.0 + WorldDigHandler.FIND_LIFT, 0.001)

func test_no_second_find_next_to_existing() -> void:
	_finds.add({"key": "F_a", "kind": "copper_ore", "x": 20.0, "y": 0.15, "z": 20.0})
	for i in 100:
		assert_eq(_handler.after_dig(Vector2(20.5, 20), 10.0)["found"], "")

func test_chunk_load_spawns_views() -> void:
	_finds.add({"key": "F_a", "kind": "copper_ore", "x": 10.0, "y": 0.0, "z": 10.0})
	_handler.on_chunk_loaded(Vector2i(0, 0))
	assert_eq(_spawned.size(), 1)
	_spawned = []
	_handler.on_chunk_loaded(Vector2i(5, 5))
	assert_eq(_spawned.size(), 0)

var _bag: int = 0
var _pit: TerrainEditLayer

func _pit_ground(x: float, z: float) -> float:
	return 2.4 + _pit.get_delta_at(x, z)

func _can_afford(_p: String, cost: Dictionary) -> bool:
	return _bag >= int(cost["ladder"])

func _pay(_p: String, cost: Dictionary) -> bool:
	_bag -= int(cost["ladder"])
	return true

func _refund(_p: String, items: Dictionary) -> void:
	_bag += int(items["ladder"])

func test_ladder_costs_and_refund() -> void:
	_pit = TerrainEditLayer.new()
	for i in 40:
		_pit.apply_brush(0.0, 0.0, WorldTerrainEditor.BRUSH_RADIUS, WorldTerrainEditor.DIG_STEP, WorldTerrainEditor.CORE_RADIUS)
	var h := WorldDigHandler.new(_ladders, _finds, _pit_ground, _spawn_stub, _despawn_stub, 64.0)
	h.set_inventory_ops(_can_afford, _pay, _refund)
	var bottom := Vector3(0, _pit_ground(0.0, 0.0), 0)
	_bag = 1
	var res := h.place_ladder("p1", bottom, Vector3(1, 0, 0))
	assert_eq(res["reason"], "no_materials", "Eine Leiter reicht für 20 m nicht.")
	_bag = 20
	res = h.place_ladder("p1", bottom, Vector3(1, 0, 0))
	assert_true(res["ok"])
	assert_lt(_bag, 20)
	assert_true(h.remove_ladder("p1", String(res["key"]), bottom)["ok"])
	assert_eq(_bag, 20, "Abbauen erstattet alles.")
