extends CharacterBody3D
class_name Player

## Player.gd — Zentraler Spieler-Controller.
##
## Timing-Problem behoben: services_initialized wurde bereits beim Boot emittiert.
## Wenn der Player nach dem Boot in die Szene geladen wird (Normalfall), ist das
## Signal history, und der CONNECT_ONE_SHOT-Listener feuert nie.
## Lösung: Wenn Services schon laufen, sofort initialisieren.

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

	# Wenn Services bereits initialisiert sind (Player kommt nach dem Boot in die Szene),
	# direkt starten — das Signal wurde bereits emittiert und kommt nicht nochmal.
	if is_instance_valid(Services.game_manager):
		_on_core_ready()
	else:
		# Erster Boot: noch nicht initialisiert, auf Signal warten.
		EventBus.system.services_initialized.connect(_on_core_ready, CONNECT_ONE_SHOT)


func _on_core_ready() -> void:
	_build_system()
	_apply_stats()
	set_physics_process(true)
	Logger.log_info("Player-System online.", LOG_CAT)


func _physics_process(delta: float) -> void:
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
	if input.js_vec.length() > 0.5:
		EventBus.player.emit_movement_interrupted()
	velocity = velocity.move_toward(Vector3.ZERO, 15.0 * delta)
	move_and_slide()
	camera.handle_input(input, delta)


func _on_action_interrupted() -> void:
	visuals.play_effect("interrupted")


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func get_closest_interactable() -> Node3D:
	return sensor.get_closest() if is_instance_valid(sensor) else null


## Gibt die verfügbaren Aktionen des nächsten Interagierbaren als Array zurück.
## Wird von ContextMenuController aufgerufen wenn der Spieler den Kontext-Button drückt.
##
## [STUB] Aktuell: gibt statische Dummy-Aktion zurück bis InteractableComponent
## eine get_actions()-API bekommt. Zukünftig:
##   var target := get_closest_interactable()
##   if target and target.has_method("get_actions"):
##       return target.get_actions()
func get_context_actions() -> Array:
	var target := get_closest_interactable()
	if not is_instance_valid(target):
		return []
	## [STUB] InteractableComponent hat noch keine get_actions()-Methode.
	## Wenn sie hinzugefügt wird: return target.get_actions()
	## Für jetzt: eine Standard-Interaktion anbieten wenn ein Ziel da ist.
	var fallback := InteractableAction.new("interact", "Interagieren")
	fallback.duration = 1.5
	fallback.on_complete = func(): target.start_default_interaction()
	return [fallback]


# ─────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────


func _build_system() -> void:
	_setup_collision()
	_mover = PlayerMover.new()
	visuals = PlayerVisuals.new()
	camera = PlayerCamera.new()
	input = TouchInput.new()
	sensor = InteractionSensor.new()
	add_child(visuals)
	add_child(camera)
	add_child(input)
	input.add_to_group("touch_input")
	add_child(sensor)


func _setup_collision() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)


func _apply_stats() -> void:
	var s = Services.data.get_player_stat("speed", 6.0)
	var g = Services.data.get_player_stat("gravity", 12.0)
	_mover.speed = s
	_mover.gravity = g
	Logger.log_info("Stats angewandt: Speed=%f, Gravity=%f" % [s, g], LOG_CAT)

	if s <= 0.0:
		Logger.log_warn("Speed ist 0 oder negativ — Spieler kann sich nicht bewegen!", LOG_CAT)
	if g <= 0.0:
		Logger.log_warn("Gravity ist 0 oder negativ — Spieler fällt nicht! Physik prüfen.", LOG_CAT)
