class_name DesertPvpZonePlacer
extends RefCounted

## DesertPvpZonePlacer — platziert eine PvP-`ZoneTriggerVolume` "im Wüsten-Biom"
## (Anfrage Round 74).
##
## WARUM ÜBERHAUPT EIN SUCH-ALGORITHMUS UND KEINE FESTE KOORDINATE:
## Biome sind in diesem Projekt prozedural über Noise bestimmt (siehe
## TerrainField.get_biome_id_at()), nicht über eine handgezeichnete Weltkarte.
## Es gibt also keine Koordinate, die man a priori kennen und hart eintragen
## könnte — "wo die Wüste liegt" ist eine Eigenschaft der Noise-Funktion (und des
## world_seed), nicht eine Level-Design-Entscheidung mit fester Zahl. DIESER Code
## fragt stattdessen zur Laufzeit exakt dieselbe Funktion, die auch die Terrain-
## Einfärbung benutzt — läuft auf jedem Peer identisch (der world_seed wird beim
## Beitritt synchronisiert), findet also garantiert überall denselben Ort, ganz
## ohne Server-Replikation nötig.
##
## SUCHSTRATEGIE: Quadratische Spirale um den Weltursprung (0,0) — beginnt
## nah am Spawn (Wüste soll erreichbar sein, nicht am Kartenrand), wächst nach
## außen, bis STEP_SIZE * MAX_RING Meter erreicht sind. Bricht beim ERSTEN
## Treffer ab (kein "beste" Stelle, nur "erste gefundene" — für einen
## einzelnen PvP-Hotspot ausreichend).
##
## EHRLICHER HINWEIS: nicht gegen echte Godot-Laufzeit verifiziert (keine
## Godot-Binary in dieser Sandbox, siehe TODO-offene-probleme.md "Tests gegen
## die echte Godot/GUT-Runtime"). Die Such-/Platzierungslogik selbst
## (_find_desert_position()) ist reine GDScript-Arithmetik ohne Node-
## Abhängigkeit und deshalb per Unit-Test mit einem Fake-Biom-Lookup
## abgedeckt (test_desert_pvp_zone_placer.gd) — der Godot-spezifische Teil
## (Area3D/CollisionShape3D/add_child(), unten in place()) ist es nicht.

const LOG_CAT := "DesertPvpZonePlacer"

## Meter zwischen zwei Suchpunkten. Kleiner = genauer, aber mehr Abfragen.
const STEP_SIZE: float = 24.0
## Max. Anzahl Ringe der Spirale (Suchradius = STEP_SIZE * MAX_RING = 2400m).
const MAX_RING: int = 100

const ZONE_ID: StringName = &"pvp_desert"
## Zylinder-Radius/-Höhe der Trigger-Zone in Metern.
const ZONE_RADIUS: float = 40.0
const ZONE_HEIGHT: float = 30.0

## Sucht quadratisch-spiralförmig um (0,0) nach der ersten Position, an der
## biome_id_lookup(x, z) == "desert" liefert. `biome_id_lookup` ist bewusst
## ein Callable statt einer direkten TerrainField-Referenz — macht diese
## Methode ohne Godot-Engine testbar (siehe Klassenkommentar).
## Gibt Vector2(world_x, world_z) zurück, oder null wenn nichts gefunden wurde
## (z.B. wenn "desert" mit der aktuellen Noise-Konfiguration extrem selten ist).
static func _find_desert_position(biome_id_lookup: Callable) -> Variant:
	if biome_id_lookup.call(0.0, 0.0) == "desert":
		return Vector2.ZERO

	for ring in range(1, MAX_RING + 1):
		var r: float = ring * STEP_SIZE
		# Quadratring: alle Punkte auf dem Rand eines (2r × 2r)-Quadrats,
		# in STEP_SIZE-Schritten abgelaufen — deutlich weniger Abfragen als
		# ein volles Kreis-/Kreisscheiben-Sampling bei vergleichbarer Abdeckung.
		var steps_per_side: int = ring * 2
		for i in range(steps_per_side):
			var offset: float = -r + i * STEP_SIZE
			var candidates: Array[Vector2] = [
				Vector2(offset, -r), Vector2(offset, r),
				Vector2(-r, offset), Vector2(r, offset),
			]
			for c in candidates:
				if biome_id_lookup.call(c.x, c.y) == "desert":
					return c
	return null

## Sucht eine Wüsten-Position (via `terrain`) und platziert dort eine
## PvP-`ZoneTriggerVolume` als Kind von `world_root`. Injiziert sofort
## ZoneService/NetworkBridge (keine Abhängigkeit von der "zone_triggers"-
## Gruppen-Nachreichung in WorldService._wire_zone_triggers()/
## inject_network_bridge(), die zeitlich vor diesem Aufruf laufen — siehe
## WorldSpawner-Aufrufstelle). Gibt die erzeugte ZoneTriggerVolume zurück,
## oder null, falls keine Wüste im Suchradius gefunden wurde (Fehlerfall wird
## geloggt, nicht stillschweigend ignoriert).
static func place(
	world_root:    Node3D,
	terrain:   TerrainField,
	zone_service:  ZoneService,
	network:       NetworkBridge
) -> ZoneTriggerVolume:
	if not is_instance_valid(terrain):
		AppLogger.log_error("place(): kein TerrainField — Suche übersprungen.", LOG_CAT)
		return null

	var pos: Variant = _find_desert_position(terrain.get_biome_id_at)
	if pos == null:
		AppLogger.log_warn(
			"Keine Wüsten-Position im Suchradius (%dm) gefunden — keine PvP-Zone platziert." % int(STEP_SIZE * MAX_RING),
			LOG_CAT
		)
		return null

	var world_pos: Vector2 = pos
	# TerrainField.get_height_at() arbeitet in Weltkoordinaten — direkt verwendbar.
	var y: float = terrain.get_height_at(world_pos.x, world_pos.y)

	var config := ZoneConfig.new()
	config.zone_id = ZONE_ID
	config.tags     = [&"pvp"]

	var trigger := ZoneTriggerVolume.new()
	trigger.name        = "DesertPvpZone"
	trigger.zone_config = config
	trigger.position    = Vector3(world_pos.x, y + ZONE_HEIGHT * 0.5, world_pos.y)

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
		"PvP-Zone '%s' im Wüsten-Biom platziert bei (%.0f, %.0f, %.0f)." % [ZONE_ID, world_pos.x, y, world_pos.y],
		LOG_CAT
	)
	return trigger
