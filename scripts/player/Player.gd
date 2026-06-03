extends CharacterBody3D
class_name Player

## Die Zentrale. Sie hält die Referenzen und steuert den Lifecycle.

@onready var visuals: Node3D = $Visuals
@onready var camera:  PlayerCamera = $CameraRig
@onready var input:   TouchInput  = $InputProvider
@onready var sensor:  InteractionSensor = $InteractionSensor

func _ready() -> void:
	# 1. Schlafen bis Orchestrator fertig
	set_physics_process(false)
	EventBus.system.services_initialized.connect(_wake_up)

func _wake_up() -> void:
	# 2. Stats laden & Komponenten initialisieren
	_apply_stats()
	set_physics_process(true)

func _apply_stats() -> void:
	var speed = Services.data.get_player_stat("speed", 6.0)
	# Wir geben die Stats an die Fach-Komponenten weiter (Dependency Injection)
	# $Mover.setup(speed) 
	pass

func _physics_process(delta: float) -> void:
	var state = Services.player_states.get_state()
	
	match state:
		PlayerStateService.State.FREE:
			_handle_standard_loop(delta)
		PlayerStateService.State.BUSY:
			_handle_busy_loop(delta)

func _handle_standard_loop(delta: float) -> void:
	# Hier rufen wir die spezialisierten Funktionen auf
	var move_vec = MathHelper.calculate_move_direction(camera, input.js_vec)

func _setup_collision() -> void:
    var col_shape := CollisionShape3D.new()
    var capsule   := CapsuleShape3D.new()
    
    capsule.radius = 0.45
    capsule.height = 1.8
    
    col_shape.shape = capsule
    # WICHTIG: Die Kapsel so verschieben, dass die Füße am Boden des Player-Nodes sind
    col_shape.position = Vector3(0, 0.9, 0) 
    
    add_child(col_shape)