# res://tests/unit/test_spawn_safe_zone_placer.gd
extends GutTest

## Unit-Tests für SpawnSafeZonePlacer.place() (statische Factory, analog zu
## test_enemy_attack.gd — echte Kind-Objekte
## inspizieren statt Rückgabewerte raten).
##
## ZoneService/NetworkBridge/SessionManager echt instanziiert (etabliertes
## Muster aus test_pvp_service.gd) — genau die Verdrahtung zwischen diesen
## drei ist Teil dessen, was place() leisten soll.
##
## Abgedeckt:
##   - Ohne TerrainField (null): y-Höhe bleibt 0.0 -> Position exakt
##     ZONE_HEIGHT*0.5 über dem Ursprung
##   - Mit TerrainField: Position übernimmt dessen Höhe bei (0,0)
##   - zone_config: zone_id, tags exakt wie im Code hart codiert
##   - CollisionShape3D-Kind mit CylinderShape3D (Radius/Höhe exakt)
##   - trigger wird tatsächlich Kind von world_root, UND ist der Rückgabewert
##   - ZoneService kennt die Zone danach wirklich (get_zone_config(), nicht
##     nur "wurde aufgerufen")
##   - inject_network_bridge() wird durchgereicht (kein Crash bei null)

var _world_root: Node3D
var _zone_service: ZoneService
var _bus: MockEventBus


class StubTerrainField extends TerrainField:
	var fixed_height: float = 3.0
	func get_height_at(_x: float, _z: float) -> float:
		return fixed_height


func before_each() -> void:
	_world_root = Node3D.new()
	add_child_autofree(_world_root)
	_bus = MockEventBus.new()
	_zone_service = ZoneService.new()
	_zone_service.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	_zone_service.on_ready()


func after_each() -> void:
	_zone_service.on_cleanup()
	_world_root = null
	_zone_service = null
	_bus = null


func _find_collision_shape(trigger: ZoneTriggerVolume) -> CollisionShape3D:
	for child in trigger.get_children():
		if child is CollisionShape3D:
			return child
	return null


# ─────────────────────────────────────────────
# Position / Höhe
# ─────────────────────────────────────────────

func test_position_without_terrain_uses_zero_height() -> void:
	var trigger := SpawnSafeZonePlacer.place(_world_root, null, _zone_service, null)
	assert_almost_eq(trigger.position.y, SpawnSafeZonePlacer.ZONE_HEIGHT * 0.5, 0.0001)
	assert_almost_eq(trigger.position.x, 0.0, 0.0001)
	assert_almost_eq(trigger.position.z, 0.0, 0.0001)

func test_position_with_terrain_uses_terrain_height_at_origin() -> void:
	var gen := StubTerrainField.new()
	gen.fixed_height = 3.0
	var trigger := SpawnSafeZonePlacer.place(_world_root, gen, _zone_service, null)
	assert_almost_eq(trigger.position.y, 3.0 + SpawnSafeZonePlacer.ZONE_HEIGHT * 0.5, 0.0001)


# ─────────────────────────────────────────────
# zone_config / Shape
# ─────────────────────────────────────────────

func test_zone_config_id_and_tags() -> void:
	var trigger := SpawnSafeZonePlacer.place(_world_root, null, _zone_service, null)
	assert_eq(trigger.zone_config.zone_id, SpawnSafeZonePlacer.ZONE_ID)
	assert_eq(trigger.zone_config.tags, [&"safe"])

func test_trigger_name_is_spawn_safe_zone() -> void:
	var trigger := SpawnSafeZonePlacer.place(_world_root, null, _zone_service, null)
	assert_eq(trigger.name, "SpawnSafeZone")

func test_collision_shape_is_cylinder_with_configured_dimensions() -> void:
	var trigger := SpawnSafeZonePlacer.place(_world_root, null, _zone_service, null)
	var col := _find_collision_shape(trigger)
	assert_not_null(col)
	assert_true(col.shape is CylinderShape3D)
	var cyl: CylinderShape3D = col.shape
	assert_almost_eq(cyl.radius, SpawnSafeZonePlacer.ZONE_RADIUS, 0.0001)
	assert_almost_eq(cyl.height, SpawnSafeZonePlacer.ZONE_HEIGHT, 0.0001)


# ─────────────────────────────────────────────
# Verdrahtung
# ─────────────────────────────────────────────

func test_trigger_is_added_as_child_of_world_root() -> void:
	var trigger := SpawnSafeZonePlacer.place(_world_root, null, _zone_service, null)
	assert_true(trigger.get_parent() == _world_root)

func test_returns_the_created_trigger() -> void:
	var trigger := SpawnSafeZonePlacer.place(_world_root, null, _zone_service, null)
	assert_eq(_world_root.get_child_count(), 1)
	assert_eq(_world_root.get_child(0), trigger)

func test_zone_service_knows_the_zone_after_placement() -> void:
	SpawnSafeZonePlacer.place(_world_root, null, _zone_service, null)
	var registered := _zone_service.get_zone_config(SpawnSafeZonePlacer.ZONE_ID)
	assert_not_null(registered)
	assert_eq(registered.tags, [&"safe"])

func test_null_network_bridge_does_not_crash() -> void:
	var trigger := SpawnSafeZonePlacer.place(_world_root, null, _zone_service, null)
	assert_not_null(trigger, "inject_network_bridge(null) darf place() nicht zum Absturz bringen.")
