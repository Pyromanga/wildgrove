# res://tests/unit/test_world_service_terrain_plane.gd
extends GutTest

## Tests für WorldService.request_terrain_plane / preview_terrain_plane — Material-Verrechnung
## beim Ebnen. Terrain, Inventar und Bauhandler sind Fakes; kein SceneTree-Aufbau der Welt.

const PLAYER := "p1"
const HIGH := Vector3(0, 0, 0)

class FlatTerrain extends TerrainField:
	var base: float = 0.0
	func get_height_at(x: float, z: float) -> float:
		var layer := get_edit_layer()
		return base + (layer.get_delta_at(x, z) if layer != null else 0.0)
	func get_material_at(_x: float, _z: float) -> String:
		return "dirt"

class StubInventory extends InventorySystem:
	var items: Dictionary = {}
	var free_slots: int = 10
	func has_item(item_id: String, _player_id: String, quantity: int = 1) -> bool:
		return int(items.get(item_id, 0)) >= quantity
	func remove_item(item_id: String, _player_id: String, quantity: int = 1) -> bool:
		if int(items.get(item_id, 0)) < quantity:
			return false
		items[item_id] = int(items[item_id]) - quantity
		return true
	func request_add_item(item_id: String, _player_id: String, quantity: int = 1) -> bool:
		items[item_id] = int(items.get(item_id, 0)) + quantity
		return true
	func get_free_slots(_player_id: String) -> int:
		return free_slots

var _svc: WorldService
var _terrain: FlatTerrain
var _layer: TerrainEditLayer
var _inv: StubInventory
var _refreshed: int = 0

func before_each() -> void:
	_svc = WorldService.new()
	add_child_autofree(_svc)
	_svc.configure(ServiceDeps.from_dict({}))
	_layer = TerrainEditLayer.new()
	_terrain = FlatTerrain.new()
	_terrain.set_edit_layer(_layer)
	_refreshed = 0
	var registry := BuildRegistry.new()
	var editor := WorldTerrainEditor.new(_layer, registry, func(_p: Array) -> void: _refreshed += 1)
	editor.set_height_fn(_terrain.get_height_at)
	_svc._terrain = _terrain
	_svc._terrain_editor = editor
	_svc._build_handler = WorldBuildHandler.new(registry, editor, Callable(), _terrain.get_height_at,
		Callable(), Callable(), 64.0)
	_svc._edits_active = true
	_inv = StubInventory.new()
	add_child_autofree(_inv)
	_svc._ent_inventory = _inv

func _edit(plane_y: float, direction: String = TerrainPlanePlanner.DIR_BOTH) -> Dictionary:
	return _svc.request_terrain_plane(PLAYER, HIGH, plane_y, direction)

func test_cutting_high_ground_yields_one_item_per_full_unit() -> void:
	_terrain.base = 2.0
	var result := _edit(0.0)
	assert_true(result["ok"])
	assert_eq(int(_inv.items.get("dirt", 0)), 1, "Ein voller Zug abtragen = 1 Erde, wie eine Grabaktion.")
	assert_lt(_layer.get_delta_lattice(0, 0), 0.0)
	assert_eq(_refreshed, 1)

func test_filling_low_ground_consumes_one_item() -> void:
	_terrain.base = -2.0
	_inv.items = {"dirt": 3}
	var result := _edit(0.0)
	assert_true(result["ok"])
	assert_eq(int(_inv.items["dirt"]), 2)
	assert_gt(_layer.get_delta_lattice(0, 0), 0.0)

func test_filling_without_material_fails_and_changes_nothing() -> void:
	_terrain.base = -2.0
	var result := _edit(0.0)
	assert_false(result["ok"])
	assert_eq(result["reason"], "no_material")
	assert_true(_layer.is_empty())

func test_fill_prefers_sand_over_dirt_like_normal_fill() -> void:
	_terrain.base = -2.0
	_inv.items = {"dirt": 2, "sand": 2}
	_edit(0.0)
	assert_eq(int(_inv.items["sand"]), 1)
	assert_eq(int(_inv.items["dirt"]), 2)

func test_cutting_with_full_inventory_fails() -> void:
	_terrain.base = 2.0
	_inv.free_slots = 0
	var result := _edit(0.0)
	assert_false(result["ok"])
	assert_eq(result["reason"], "inventory_full")
	assert_true(_layer.is_empty())

func test_partial_cut_goes_to_credit_not_items() -> void:
	_terrain.base = 0.1     # nur 10 cm über der Ebene → deutlich weniger als eine Einheit
	var result := _edit(0.0)
	assert_true(result["ok"])
	assert_eq(int(_inv.items.get("dirt", 0)), 0)
	var credit := float(_svc._plane_credit.get(PLAYER, 0.0))
	assert_gt(credit, 0.0)
	assert_lt(credit, 1.0)

func test_credit_accumulates_to_an_item() -> void:
	# Mehrere kleine Abträge summieren sich zu einem ganzen Item.
	var got := 0
	for i in 12:
		_layer.clear()   # Gelände je Zug wieder auf 10 cm über der Ebene zurücksetzen
		_terrain.base = 0.1
		_edit(0.0)
		got = int(_inv.items.get("dirt", 0))
		if got > 0:
			break
	assert_gt(got, 0, "Bruchteile gehen nicht verloren.")

func test_direction_down_does_not_consume_material() -> void:
	_terrain.base = 0.0
	_layer.set_delta(Vector2i(0, 0), -1.0)   # Mulde, Rest liegt auf der Ebene
	var result := _edit(0.0, TerrainPlanePlanner.DIR_DOWN)
	assert_false(result["ok"])
	assert_eq(result["reason"], "nothing_to_cut")
	assert_true(_inv.items.is_empty())

func test_nan_plane_is_rejected() -> void:
	var result := _edit(NAN)
	assert_false(result["ok"])
	assert_eq(result["reason"], "no_plane")

func test_not_active_in_coop() -> void:
	_svc._edits_active = false
	_terrain.base = 2.0
	var result := _edit(0.0)
	assert_false(result["ok"])
	assert_eq(result["reason"], "coop_unsupported")
	assert_true(_layer.is_empty())

func test_preview_plane_reports_state() -> void:
	_terrain.base = 2.0
	assert_true(_svc.preview_terrain_plane(PLAYER, HIGH, 0.0)["ok"])
	_terrain.base = 0.0
	assert_eq(_svc.preview_terrain_plane(PLAYER, HIGH, 0.0)["reason"], "already_level")
	_svc._edits_active = false
	assert_eq(_svc.preview_terrain_plane(PLAYER, HIGH, 0.0)["reason"], "coop_unsupported")

func test_event_routes_to_service() -> void:
	var bus := MockEventBus.new()
	_svc._bus = bus
	_svc.on_ready()
	_terrain.base = 2.0
	bus.world().emit_terrain_plane_requested(PLAYER, HIGH, 0.0, TerrainPlanePlanner.DIR_BOTH)
	assert_lt(_layer.get_delta_lattice(0, 0), 0.0)
	_svc.on_cleanup()
	assert_false(bus.world().terrain_plane_requested.is_connected(_svc._on_terrain_plane_requested))
