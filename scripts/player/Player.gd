extends CharacterBody3D
class_name Player

## Player.gd — Zentraler Spieler-Controller.
##
## Boot-Timing:
##   Nach dem Boot ist services_initialized bereits emittiert wenn der Player
##   (via WorldFactory) in die Szene kommt. Das Signal ist history → kommt nicht nochmal.
##   Lösung: Direkt prüfen ob Services.game_manager bereits valid ist → sofort starten.

const LOG_CAT := "Player"

var _mover: PlayerMover
var visuals: PlayerVisuals
var camera: PlayerCamera
var input: TouchInput
var sensor: InteractionSensor


func _ready() -> void:
	add_to_group("player")
	set_physics_process(false)
	EventBus.player.movement_interrupted.connect(_on_action_interrupted)
	Logger.log_debug("Player _ready(). Warte auf Services...", LOG_CAT)

	if is_instance_valid(Services.game_manager):
		# Services bereits bereit (Normalfall: Player kommt nach dem Boot in die Szene)
		Logger.log_debug("Services bereits bereit — sofort initialisieren.", LOG_CAT)
		_on_core_ready()
	else:
		# Erster Boot: noch nicht initialisiert, auf Signal warten
		Logger.log_debug("Warte auf services_initialized Signal.", LOG_CAT)
		EventBus.system.services_initialized.connect(_on_core_ready, CONNECT_ONE_SHOT)


func _on_core_ready() -> void:
	Logger.log_info("Core bereit — Player-System initialisieren.", LOG_CAT)
	_build_system()
	_apply_stats()
	set_physics_process(true)
	Logger.log_info("Player-System online. Physics-Process aktiv.", LOG_CAT)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(Services.player_states):
		return

	match Services.player_states.get_state():
		PlayerStateService.State.FREE:
			_loop_free(delta)
		PlayerStateService.State.BUSY:
			_loop_busy(delta)
		_:
			velocity = Vector3.ZERO
			move_and_slide()


func _loop_free(delta: float) -> void:
	var move_dir := MathHelper.calculate_move_direction(camera, input.js_vec)
	velocity = _mover.calculate_velocity(velocity, move_dir, delta, is_on_floor())
	move_and_slide()
	visuals.handle_rotation(move_dir, delta)
	camera.handle_input(input, delta)


func _loop_busy(delta: float) -> void:
	# Starke Joystick-Bewegung während Busy → Interaktion abbrechen
	if input.js_vec.length() > 0.5:
		Logger.log_debug("Bewegung während Interaktion → interrupt.", LOG_CAT)
		EventBus.player.emit_movement_interrupted()
	velocity = velocity.move_toward(Vector3.ZERO, 15.0 * delta)
	move_and_slide()
	camera.handle_input(input, delta)


func _on_action_interrupted() -> void:
	Logger.log_debug("Aktion unterbrochen — Shake-Effekt.", LOG_CAT)
	visuals.play_effect("interrupted")


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func get_closest_interactable() -> Node3D:
	if not is_instance_valid(sensor):
		Logger.log_warn("get_closest_interactable(): kein Sensor!", LOG_CAT)
		return null
	return sensor.get_closest()


## Gibt alle verfügbaren Aktionen des nächsten Interagierbaren zurück.
## Wird von ContextMenuController aufgerufen wenn der Spieler den Kontext-Button drückt.
##
## STUB AUFGELÖST (Session 3):
##   Nutzt jetzt InteractableComponent.get_actions() via Meta-Lookup.
##   KEIN direktes Type-Casting nötig — Meta-Pattern ist typ-agnostisch.
##
## Meta-Lookup-Pattern:
##   InteractableComponent._ready() setzt: get_parent().set_meta("interactable_component", self)
##   Daher: target.get_meta("interactable_component") liefert die Komponente direkt.
func get_context_actions() -> Array:
	var target := get_closest_interactable()
	if not is_instance_valid(target):
		Logger.log_debug("get_context_actions(): kein Ziel in Reichweite.", LOG_CAT)
		return []

	Logger.log_debug(
		"get_context_actions(): Ziel '%s'. Suche interactable_component Meta." % target.name,
		LOG_CAT
	)

	# Primär: Meta-Lookup (gesetzt von InteractableComponent._ready())
	if target.has_meta("interactable_component"):
		var comp: InteractableComponent = target.get_meta("interactable_component")
		if is_instance_valid(comp):
			var actions := comp.get_actions()
			Logger.log_info(
				"get_context_actions(): %d Aktion(en) für '%s'." % [actions.size(), target.name],
				LOG_CAT
			)
			return actions
		Logger.log_warn(
			"interactable_component Meta auf '%s' ist invalid (freigegeben?)." % target.name,
			LOG_CAT
		)

	# Fallback: Child-Traversal (langsamer, aber robust)
	Logger.log_warn(
		"Kein Meta auf '%s' — nutze Child-Traversal als Fallback." % target.name, LOG_CAT
	)
	for child in target.get_children():
		if child is InteractableComponent:
			return (child as InteractableComponent).get_actions()

	# Letzter Fallback: Start-Default-Aktion über has_method
	if target.has_method("start_default_interaction"):
		Logger.log_warn("Letzter Fallback: generische Interagieren-Aktion.", LOG_CAT)
		var fallback := InteractableAction.new("interact", "Interagieren")
		fallback.duration = 1.5
		fallback.on_complete = func(): target.start_default_interaction()
		return [fallback]

	Logger.log_warn(
		"Kein interactable Interface auf '%s' gefunden." % target.name, LOG_CAT
	)
	return []


# ─────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────


func _build_system() -> void:
	Logger.log_debug("Baue Player-System (Collision, Mover, Visuals, Camera, Input, Sensor).", LOG_CAT)
	_setup_collision()
	_mover = PlayerMover.new()
	visuals = PlayerVisuals.new()
	camera = PlayerCamera.new()
	input = TouchInput.new()
	sensor = _build_sensor()

	add_child(visuals)
	add_child(camera)
	add_child(input)
	input.add_to_group("touch_input")
	add_child(sensor)

	Logger.log_debug(
		"Subsysteme bereit: mover=%s visuals=%s camera=%s input=%s sensor=%s"
		% [
			_mover.get_class(),
			visuals.get_class(),
			camera.get_class(),
			input.get_class(),
			sensor.get_class()
		],
		LOG_CAT
	)


func _build_sensor() -> InteractionSensor:
	var s := InteractionSensor.new()
	s.name = "InteractionSensor"
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	# 2.5m Radius: etwas kleiner als InteractableComponent.detection_radius (3.0m)
	# damit der Sensor nur tatsächlich erreichbare Ziele liefert (Randfall-Puffer)
	shape.radius = 2.5
	col.shape = shape
	s.add_child(col)
	s.monitoring = true
	s.monitorable = false
	Logger.log_debug("InteractionSensor erstellt (Radius: 2.5m).", LOG_CAT)
	return s


func _setup_collision() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9  # Kapsel-Zentrum bei 0.9m → Füße bei 0.0, Kopf bei 1.8m
	add_child(col)
	Logger.log_debug("Collision Capsule erstellt (r=0.45, h=1.8, y=0.9).", LOG_CAT)


func _apply_stats() -> void:
	if not is_instance_valid(Services.data):
		Logger.log_warn("DataService fehlt — Player nutzt Mover-Defaults.", LOG_CAT)
		return

	var s := Services.data.get_player_stat("speed", 6.0)
	var g := Services.data.get_player_stat("gravity", 12.0)
	_mover.speed = s
	_mover.gravity = g

	Logger.log_info("Stats angewandt: Speed=%.2f, Gravity=%.2f." % [s, g], LOG_CAT)

	if s <= 0.0:
		Logger.log_warn("Speed ist ≤ 0 — Spieler kann sich nicht bewegen!", LOG_CAT)
	if g <= 0.0:
		Logger.log_warn("Gravity ist ≤ 0 — Spieler fällt nicht! Physik prüfen.", LOG_CAT)
