## tests/unit/test_structure_use_and_build_mode.gd
## Strukturnutzung (StructureUse, Brunnen), Eimer-Animation und Bau-Modus-Zustand.
extends GutTest

const PLAYER := "p1"

class StubInventory extends InventorySystem:
	var stock: Dictionary = {}
	var reject_adding: Array[String] = []
	func give(item_id: String, qty: int) -> void:
		stock[item_id] = int(stock.get(item_id, 0)) + qty
	func has_item(item_id: String, _player_id: String, quantity: int = 1) -> bool:
		return int(stock.get(item_id, 0)) >= quantity
	func remove_item(item_id: String, _player_id: String, quantity: int = 1) -> bool:
		if int(stock.get(item_id, 0)) < quantity:
			return false
		stock[item_id] = int(stock[item_id]) - quantity
		return true
	func request_add_item(item_id: String, _player_id: String, quantity: int = 1) -> bool:
		if reject_adding.has(item_id):
			return false
		give(item_id, quantity)
		return true

var _inv: StubInventory
var _well: BuildPieceDefinition

func before_each() -> void:
	BuildModeState.reset()
	_inv = StubInventory.new()
	_well = load("res://data/building/Well.tres") as BuildPieceDefinition

func after_each() -> void:
	BuildModeState.reset()

# ── StructureUse ─────────────────────────────────────────────────────────────

func test_well_data_has_use_and_animation() -> void:
	assert_true(_well.has_use())
	assert_true(_well.has_well_bucket_animation())
	assert_eq(_well.use_consumes, {"bucket": 1})
	assert_eq(_well.use_gives, {"water_bucket": 1})

func test_items_exist_in_manifest() -> void:
	assert_true(DataManifest.ITEMS.has("res://data/items/Bucket.tres"))
	assert_true(DataManifest.ITEMS.has("res://data/items/WaterBucket.tres"))
	assert_not_null(load("res://data/items/Bucket.tres"))

func test_use_swaps_empty_for_full_bucket() -> void:
	_inv.give("bucket", 1)
	assert_eq(StructureUse.use(_well, PLAYER, _inv, 0, 10000), "")
	assert_eq(int(_inv.stock["bucket"]), 0)
	assert_eq(int(_inv.stock["water_bucket"]), 1)

func test_use_without_bucket_is_refused() -> void:
	assert_eq(StructureUse.use(_well, PLAYER, _inv, 0, 10000), StructureUse.FAIL_MISSING)
	assert_false(_inv.stock.has("water_bucket"))

func test_use_respects_cooldown() -> void:
	_inv.give("bucket", 2)
	assert_eq(StructureUse.use(_well, PLAYER, _inv, 9500, 10000), StructureUse.FAIL_COOLDOWN)
	assert_eq(int(_inv.stock["bucket"]), 2)
	assert_eq(StructureUse.use(_well, PLAYER, _inv, 5000, 10000), "")

func test_full_inventory_refunds_ingredients() -> void:
	_inv.give("bucket", 1)
	_inv.reject_adding = ["water_bucket"]
	assert_eq(StructureUse.use(_well, PLAYER, _inv, 0, 10000), StructureUse.FAIL_INVENTORY_FULL)
	assert_eq(int(_inv.stock["bucket"]), 1)

func test_piece_without_use_is_refused() -> void:
	var plain := BuildPieceDefinition.new()
	assert_eq(StructureUse.check(plain, PLAYER, _inv), StructureUse.FAIL_NO_USE)

func test_empty_player_is_refused() -> void:
	_inv.give("bucket", 1)
	assert_eq(StructureUse.check(_well, "", _inv), StructureUse.FAIL_INVALID_PLAYER)

# ── Brunnen-Mesh / Animation ─────────────────────────────────────────────────

func test_animated_well_mesh_is_smaller_than_static() -> void:
	var with_bucket := BuildPieceDefinition.build_well_mesh(1.9, true)
	var without := BuildPieceDefinition.build_well_mesh(1.9, false)
	var count_with := (with_bucket.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var count_without := (without.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_lt(count_without, count_with)

func test_bucket_geometry_is_consistent() -> void:
	var geo := BuildPieceDefinition.well_bucket_geometry(1.9)
	assert_gt(float(geo["anchor_y"]), float(geo["rest_y"]))
	assert_almost_eq(float(geo["rope_len"]), float(geo["anchor_y"]) - float(geo["rest_y"]), 0.0001)
	# Eimer taucht nicht unter den Boden.
	assert_lt(float(geo["drop"]), float(geo["rest_y"]))

func test_bucket_drop_curve() -> void:
	assert_almost_eq(BuildPiece.bucket_drop_fraction(0.0), 0.0, 0.0001)
	assert_almost_eq(BuildPiece.bucket_drop_fraction(0.45), 1.0, 0.0001)
	assert_almost_eq(BuildPiece.bucket_drop_fraction(1.0), 0.0, 0.0001)
	assert_gt(BuildPiece.bucket_drop_fraction(0.2), 0.0)
	assert_lt(BuildPiece.bucket_drop_fraction(0.2), 1.0)

# ── Bau-Modus ────────────────────────────────────────────────────────────────

func test_build_mode_has_multiple_sources() -> void:
	assert_false(BuildModeState.is_active())
	BuildModeState.set_source(BuildModeState.SOURCE_PANEL, true)
	BuildModeState.set_source(BuildModeState.SOURCE_PLACING, true)
	BuildModeState.set_source(BuildModeState.SOURCE_PANEL, false)
	assert_true(BuildModeState.is_active())
	BuildModeState.set_source(BuildModeState.SOURCE_PLACING, false)
	assert_false(BuildModeState.is_active())

func test_build_mode_signal_fires_only_on_change() -> void:
	var bus := MockEventBus.new()
	var seen: Array = []
	bus.ui().build_mode_changed.connect(func(a: bool) -> void: seen.append(a))
	BuildModeState.set_source(BuildModeState.SOURCE_PANEL, true, bus)
	BuildModeState.set_source(BuildModeState.SOURCE_PLACING, true, bus)   # keine Änderung
	BuildModeState.set_source(BuildModeState.SOURCE_PANEL, false, bus)    # keine Änderung
	BuildModeState.set_source(BuildModeState.SOURCE_PLACING, false, bus)
	assert_eq(seen, [true, false])

func test_dismantle_only_enabled_in_build_mode() -> void:
	var piece := BuildPiece.new()
	add_child_autofree(piece)
	assert_false(piece._interactable_comp.enabled)
	assert_false(piece.is_in_group("interactable"))
	assert_true(piece._interactable_comp.get_actions().is_empty())
	piece._apply_build_mode(true)
	assert_true(piece._interactable_comp.enabled)
	assert_true(piece.is_in_group("interactable"))
	assert_false(piece._interactable_comp.get_actions().is_empty())
	piece._apply_build_mode(false)
	assert_false(piece.is_in_group("interactable"))

func test_component_disabled_has_no_actions() -> void:
	var comp := InteractableComponent.new()
	comp.data = InteractableData.new()
	add_child_autofree(comp)
	assert_false(comp.get_actions().is_empty())
	comp.set_enabled(false)
	assert_true(comp.get_actions().is_empty())

# ── BuildPiece mit echtem Brunnen (on_spawn) ─────────────────────────────────

class StubData extends DataService:
	var piece: BuildPieceDefinition
	func get_build_piece(_id: String) -> BuildPieceDefinition:
		return piece

class StubCtx extends IEntityContext:
	var data: DataService
	var bus: IEventBus
	func get_data() -> DataService:
		return data
	func get_event_bus() -> IEventBus:
		return bus

func _spawn_well() -> BuildPiece:
	var data := StubData.new()
	data.piece = _well
	var ctx := StubCtx.new()
	ctx.data = data
	ctx.bus = MockEventBus.new()
	var piece := BuildPiece.new()
	add_child_autofree(piece)
	piece.on_spawn({"key": "k1", "piece_id": "well", "yaw": 0.0}, ctx)
	return piece

func test_spawned_well_has_use_component_and_moving_parts() -> void:
	var piece := _spawn_well()
	assert_not_null(piece._use_comp)
	assert_not_null(piece._bucket_node)
	assert_not_null(piece._rope_node)
	assert_eq(piece._use_comp.data.label, "Wasser schöpfen")
	# Nutzaktion ist immer aktiv → Brunnen bleibt auch außerhalb des Bau-Modus interagierbar.
	assert_true(piece.is_in_group("interactable"))
	assert_false(piece._interactable_comp.enabled)

func test_well_animation_moves_bucket_and_stretches_rope() -> void:
	var piece := _spawn_well()
	var rest_y: float = piece._bucket_node.position.y
	piece.play_well_bucket_animation(0.5)
	await get_tree().create_timer(0.25).timeout   # ~t=0.5 → Eimer unten
	assert_lt(piece._bucket_node.position.y, rest_y)
	assert_gt(piece._rope_node.scale.y, 1.0)
	await get_tree().create_timer(0.5).timeout    # fertig → zurück in Ruhe
	assert_almost_eq(piece._bucket_node.position.y, rest_y, 0.001)
	assert_almost_eq(piece._rope_node.scale.y, 1.0, 0.001)

func test_respawn_does_not_duplicate_use_component() -> void:
	var piece := _spawn_well()
	var first := piece._use_comp
	piece.on_spawn({"key": "k1", "piece_id": "well", "yaw": 0.0}, piece._ctx)
	assert_eq(piece._use_comp, first)
