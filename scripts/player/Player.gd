extends CharacterBody3D
class_name Player

const LOG_CAT := "Player"

# Logik-Module (Pure GDScript / RefCounted)
var _mover: PlayerMover

# Komponenten (Nodes)
var visuals: PlayerVisuals
var camera:  PlayerCamera
var input:   TouchInput
var sensor:  InteractionSensor

func _ready() -> void:
	add_to_group("player")
	set_physics_process(false) # Schlafen bis Boot fertig
	EventBus.system.services_initialized.connect(_on_core_ready)
	EventBus.player.movement_interrupted.connect(_on_action_interrupted)

func _on_core_ready() -> void:
	_build_system()
	_apply_stats()
	set_physics_process(true)
	Logger.log_info("Enterprise Player-System online.", LOG_CAT)

func _physics_process(delta: float) -> void:
	var state = Services.player_states.get_state()
	
	# Strategie-Muster: Je nach State wählen wir die Loop
	match state:
		PlayerStateService.State.FREE: _loop_free(delta)
		PlayerStateService.State.BUSY: _loop_busy(delta)
		_: velocity = Vector3.ZERO; move_and_slide()

func _loop_free(delta: float) -> void:
	var move_dir = MathHelper.calculate_move_direction(camera, input.js_vec)
	
	# Delegation an Spezialisten
	velocity = _mover.calculate_velocity(velocity, move_dir, delta, is_on_floor())
	move_and_slide()
	
	visuals.handle_rotation(move_dir, delta)
	camera.handle_input(input, delta)

func _loop_busy(delta: float) -> void:
	# Automatischer Abbruch bei starkem Input
	if input.js_vec.length() > 0.5:
		EventBus.player.emit_movement_interrupted()
	
	velocity = velocity.move_toward(Vector3.ZERO, 15.0 * delta)
	move_and_slide()
	camera.handle_input(input, delta)

func _on_action_interrupted() -> void:
	# Visuelles Feedback für Abbruch
	visuals.play_effect("interrupted")

func _build_system() -> void:
	_setup_collision()
	
	_mover  = PlayerMover.new()
	visuals = PlayerVisuals.new(); add_child(visuals)
	camera  = PlayerCamera.new();  add_child(camera)
	input   = TouchInput.new();    add_child(input)
	sensor  = InteractionSensor.new(); add_child(sensor)

func _setup_collision() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45; cap.height = 1.8
	col.shape = cap; col.position.y = 0.9
	add_child(col)

func _apply_stats() -> void:
	# Single Source of Truth aus dem DataService
	_mover.speed   = Services.data.get_player_stat("speed", 6.0)
	_mover.gravity = Services.data.get_player_stat("gravity", 12.0)