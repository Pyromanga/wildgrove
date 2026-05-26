extends Node3D
## Interactable.gd — Nutzt GameEvents & Factory

signal completed

@export var label: String = "Interagieren"
@export var time: float = 3.0

var _is_busy: bool = false
var _timer: float = 0.0
var _bar: Node3D

func _ready() -> void:
	add_to_group("interactable")
	_bar = Factory.create_3d_bar(self)
	_setup_collision()

func _setup_collision():
	var area = Area3D.new()
	var col = CollisionShape3D.new()
	col.shape = SphereShape3D.new(); col.shape.radius = 3.0
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(func(b): if b.is_in_group("player"): GameEvents.interaction_started.emit(label, 0))
	area.body_exited.connect(func(b): if b.is_in_group("player"): stop())

func interact(_player):
	if _is_busy: return
	_is_busy = true
	_timer = 0.0
	_bar.visible = true
	GameEvents.log("Starte: " + label)

func stop():
	_is_busy = false
	_bar.visible = false

func _process(delta):
	if _is_busy:
		_timer += delta
		var p = clamp(_timer / time, 0.0, 1.0)
		_bar.get_node("Fill").scale.x = p
		
		# Billboard-Effekt (Balken zur Kamera)
		var cam = get_viewport().get_camera_3d()
		if cam: _bar.look_at(cam.global_position)
		
		if _timer >= time:
			stop()
			completed.emit()
			GameEvents.log("Erfolg: " + label)