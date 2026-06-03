extends CharacterBody3D
class_name Player

const LOG_CAT := "Player"

# Komponenten-Referenzen (werden in _build_nodes initialisiert)
var mover:   PlayerMover
var visuals: PlayerVisuals
var camera:  PlayerCamera
var input:   TouchInput
var sensor:  InteractionSensor

func _ready() -> void:
	add_to_group("player")
	set_physics_process(false)
	EventBus.system.services_initialized.connect(_wake_up)

func _wake_up() -> void:
	_build_nodes()
	set_physics_process(true)
	Logger.log_info("Pro-Player erwacht.", LOG_CAT)

func _physics_process(delta: float) -> void:
	# 1. State abfragen
	if not Services.player_states.is_free():
		velocity = Vector3.ZERO # Im Menü/Busy nicht bewegen
		move_and_slide()
		return

	# 2. Input verarbeiten
	# Wir delegieren die Arbeit an die Spezialisten:
	var move_dir = MathHelper.calculate_move_direction(camera, input.js_vec)
	
	# Mover berechnet die Geschwindigkeit
	velocity = mover.calculate_velocity(velocity, move_dir, delta, is_on_floor())
	move_and_slide()
	
	# Visuals kümmert sich um die Drehung des Charakters
	visuals.handle_rotation(move_dir, delta)
	
	# Camera verarbeitet den Rest des Touch-Inputs
	camera.handle_input(input, delta)

func _build_nodes() -> void:
	# Hier rufen wir die spezialisierten "Builder" auf
	# Die Collision bleibt im Root, da CharacterBody3D sie dort erwartet
	_setup_main_collision()
	
	mover   = PlayerMover.new()
	visuals = PlayerVisuals.new() # Erzeugt Mesh & Dreh-Logik
	camera  = PlayerCamera.new()  # Erzeugt SpringArm & Cam
	input   = TouchInput.new()
	sensor  = InteractionSensor.new()
	
	add_child(visuals)
	add_child(camera)
	add_child(input)
	add_child(sensor)
	# Mover ist ein reines Logik-Objekt (RefCounted), braucht kein add_child