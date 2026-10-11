class_name SpawnSafeZonePlacer
extends RefCounted

## SpawnSafeZonePlacer — platziert eine "safe"-getaggte `ZoneTriggerVolume`
## um den Welt-Spawnpunkt (ADR-032 "Safe-Zone-Vulnerabilitäts-Fenster" +
## grundsätzlicher Safe-Zone-Schutz brauchen mindestens EINE existierende
## "safe"-Zone, sonst ist die ganze Mechanik inert).
##
## Deutlich simpler als DesertPvpZonePlacer: keine Biom-Suche nötig, der
## Spawnpunkt ist immer Weltursprung (0,0) — dort liegt per TerrainSpawnPlateauLayer
## garantiert ebenes, trockenes Gelände.

const LOG_CAT := "SpawnSafeZonePlacer"

const ZONE_ID: StringName = &"safe_spawn"
const ZONE_RADIUS: float  = 25.0
const ZONE_HEIGHT: float  = 40.0

## Analog DesertPvpZonePlacer.place() — injiziert ZoneService/NetworkBridge
## sofort, unabhängig von WorldService._wire_zone_triggers().
static func place(
	world_root:    Node3D,
	terrain:   TerrainField,
	zone_service:  ZoneService,
	network:       NetworkBridge
) -> ZoneTriggerVolume:
	var y: float = 0.0
	if is_instance_valid(terrain):
		y = terrain.get_height_at(0.0, 0.0)

	var config := ZoneConfig.new()
	config.zone_id = ZONE_ID
	config.tags    = [&"safe"]

	var trigger := ZoneTriggerVolume.new()
	trigger.name        = "SpawnSafeZone"
	trigger.zone_config = config
	trigger.position    = Vector3(0.0, y + ZONE_HEIGHT * 0.5, 0.0)

	var shape := CylinderShape3D.new()
	shape.radius = ZONE_RADIUS
	shape.height = ZONE_HEIGHT
	var col := CollisionShape3D.new()
	col.shape = shape
	trigger.add_child(col)

	world_root.add_child(trigger)
	trigger.inject_zone_service(zone_service)
	trigger.inject_network_bridge(network)

	AppLogger.log_info(
		"Safe-Zone '%s' um Spawnpunkt platziert (Radius %.0fm)." % [ZONE_ID, ZONE_RADIUS],
		LOG_CAT
	)
	return trigger
