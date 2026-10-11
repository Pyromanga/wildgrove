class_name PlayerSetup
extends RefCounted

## PlayerSetup — Baut das Player-Subsystem auf.
##
## Extrahiert aus Player.gd damit Player.gd nur noch Gameplay-Loop-Logik enthält.
## Wird einmalig in Player._on_core_ready() aufgerufen.
##
## Gibt alle erstellten Subsysteme zurück damit Player sie als Felder halten kann.

const LOG_CAT := "PlayerSetup"

static func build(player: CharacterBody3D) -> Dictionary:
	## Erstellt alle Subsysteme, fügt sie dem Player hinzu und gibt sie zurück.
	## Rückgabe: { mover, visuals, camera, input, sensor, picker, health }
	AppLogger.log_debug("Baue Player-System.", LOG_CAT)

	_setup_collision(player)

	var mover   := PlayerMover.new()
	var visuals := PlayerVisuals.new()
	var camera  := PlayerCamera.new()
	var input   := TouchInput.new()
	var sensor  := _build_sensor(player)
	var picker  := InteractionTargetPicker.new()

	player.add_child(visuals)
	player.add_child(camera)
	player.add_child(input)
	input.add_to_group("touch_input")
	# inject_bus() wird von Player.on_spawn() aufgerufen, NACHDEM build() zurückkehrt —
	# _bus ist hier in PlayerSetup noch nicht verfügbar (kein DI-Zugriff in Setup-Helper).
	player.add_child(sensor)
	player.add_child(picker)
	# setup() (nicht inject_bus) — picker braucht Camera/Sensor/Owner sofort,
	# den Bus erst später (analog sensor/input, siehe Kommentar oben).
	picker.setup(camera, sensor, player)

	var health := _build_health(player)

	AppLogger.log_debug(
		"Subsysteme: mover=%s visuals=%s camera=%s input=%s sensor=%s picker=%s" % [
			mover.get_class(), visuals.get_class(),
			camera.get_class(), input.get_class(), sensor.get_class(), picker.get_class()
		], LOG_CAT
	)

	return {
		"mover":   mover,
		"visuals": visuals,
		"camera":  camera,
		"input":   input,
		"sensor":  sensor,
		"picker":  picker,
		"health":  health,
	}

## ctx: IEntityContext — injiziert via on_spawn().
static func apply_stats(mover: PlayerMover, ctx: IEntityContext) -> void:
	var data := ctx.get_data() if ctx else null
	if not is_instance_valid(data):
		AppLogger.log_warn("DataService fehlt im Context — Player nutzt Mover-Defaults.", LOG_CAT)
		return
	mover.speed   = data.get_player_stat("speed",   6.0)
	mover.gravity = data.get_player_stat("gravity", 12.0)
	AppLogger.log_info(
		"Stats: Speed=%.2f, Gravity=%.2f." % [mover.speed, mover.gravity], LOG_CAT
	)

static func _setup_collision(player: CharacterBody3D) -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.8
	col.shape  = cap
	col.position.y = 0.9
	player.add_child(col)
	AppLogger.log_debug("Collision Capsule (r=0.45, h=1.8, y=0.9).", LOG_CAT)

static func _build_sensor(player: CharacterBody3D) -> InteractionSensor:
	var s   := InteractionSensor.new()
	s.name  = "InteractionSensor"
	var col := CollisionShape3D.new()
	var sh  := SphereShape3D.new()
	sh.radius   = 2.5
	col.shape   = sh
	s.add_child(col)
	s.monitoring   = true
	s.monitorable  = false
	AppLogger.log_debug("InteractionSensor (Radius: 2.5m).", LOG_CAT)
	return s

static func _build_health(player: CharacterBody3D) -> HealthComponent:
	var health       := HealthComponent.new()
	health.name      = "HealthComponent"
	health.max_health = 100
	player.add_child(health)
	# health_changed → IEventBus Connect erfolgt in Player.on_spawn() NACH _bus-Injection
	# (PlayerSetup ist static/DI-frei, kennt keinen IEventBus).
	return health
