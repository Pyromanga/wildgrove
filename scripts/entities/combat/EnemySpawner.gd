class_name EnemySpawner
extends RefCounted

## EnemySpawner — Spawnt Tiere und feindliche NPCs in der Spielwelt.
##
## Ausgelagert aus WorldSpawner._spawn_animals() + _spawn_enemies() (v28).
## Tiere: Deer, Rabbit, Boar, Fox, Squirrel, Sheep — werden zufällig verteilt platziert
## (Startbereich-Population; die laufende Weltgenerierung abseits davon läuft separat über
## ChunkEntitySpawner._spawn_animal()/ANIMAL_TYPES — siehe dortigen Kommentar, bewusst zwei
## unabhängige Spawnwege mit unterschiedlichem Zweck: hier einmalig+dicht um den Startpunkt,
## dort laufend+dünn je geladenem Chunk).
## Feinde: Goblins, Skelette — werden in Randzone der Welt gespawnt.
##
## Kein Node, kein Service. Wird von WorldSpawner instanziiert.

const LOG_CAT := "EnemySpawner"

var _entity_orchestrator: EntityOrchestrator
var _terrain: TerrainField

func _init(orchestrator: EntityOrchestrator, terrain: TerrainField) -> void:
	_entity_orchestrator = orchestrator
	_terrain   = terrain

# ─────────────────────────────────────────────
# Tiere
# ─────────────────────────────────────────────

func spawn_animals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system()) ^ 0xABCDEF

	# Wunsch "ein paar mehr Tiere einbauen": Fox/Squirrel/Sheep ergänzt. min_dist grob nach
	# "wie sehr würde es stören, wenn zwei davon fast übereinander stehen" gewählt (kleine,
	# unauffällige Tiere wie Rabbit/Squirrel dürfen dichter stehen als große wie Boar).
	var configs := [
		{"type": "deer",     "count": 4, "min_dist": 6.0},
		{"type": "rabbit",   "count": 6, "min_dist": 3.0},
		{"type": "boar",     "count": 3, "min_dist": 7.0},
		{"type": "fox",      "count": 3, "min_dist": 5.0},
		{"type": "squirrel", "count": 5, "min_dist": 2.5},
		{"type": "sheep",    "count": 4, "min_dist": 4.0},
	]

	var all_positions: Array[Vector3] = []
	for cfg in configs:
		var placed := 0
		var attempts := 0
		while placed < cfg["count"] and attempts < 60:
			attempts += 1
			var x := rng.randf_range(-25.0, 25.0)
			var z := rng.randf_range(-25.0, 25.0)
			var candidate := Vector3(x, 0.0, z)
			if candidate.length() < 8.0:
				continue
			var too_close := false
			for other in all_positions:
				if candidate.distance_to(other) < cfg["min_dist"]:
					too_close = true
					break
			if too_close:
				continue
			if is_instance_valid(_terrain):
				var h := _terrain.get_height_at(x, z)
				if h < 0.3:
					continue
				candidate.y = h
			all_positions.append(candidate)
			_entity_orchestrator.spawn_entity(cfg["type"], candidate)
			placed += 1

	AppLogger.log_info("Tiere gespawnt: %d." % all_positions.size(), LOG_CAT)

# ─────────────────────────────────────────────
# Feinde
# ─────────────────────────────────────────────

func spawn_enemies() -> void:
	# BUG-FIX: 'skeleton' ist vollständig implementiert (SkeletonNPC.gd),
	# in WorldEntityRegistry registriert und im EntityPool vorgesehen
	# (set_max_size_for('skeleton', 6)) — wurde aber nirgends je gespawnt.
	# Jetzt als zweiter Gegnertyp mit in der Rotation.
	var enemy_types: Array[String] = ["goblin", "skeleton"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system()) ^ 0x1337
	for _i in range(5):
		var x := rng.randf_range(-20.0, 20.0)
		var z := rng.randf_range(-20.0, 20.0)
		if Vector2(x, z).length() < 10.0:
			continue
		var h := 1.5
		if is_instance_valid(_terrain):
			h = _terrain.get_height_at(x, z)
		if h > 0.3:
			var enemy_type: String = enemy_types[rng.randi_range(0, enemy_types.size() - 1)]
			_entity_orchestrator.spawn_entity(enemy_type, Vector3(x, h, z))
	AppLogger.log_info("Feindliche NPCs gespawnt.", LOG_CAT)
