extends Node3D
## Interactable.gd — Fokus auf Logik, UI kommt aus der Factory

signal interaction_completed(result: Dictionary)

@export var interaction_label: String = "Interagieren"
@export var interaction_time: float   = 3.0

var _is_busy: bool = false
var _timer: float = 0.0
var _ui_bar: Node3D

func _ready() -> void:
	add_to_group("interactable")
	_setup_area()
	# UI über Factory erstellen
	_ui_bar = UIFactory.create_3d_progress_bar(self)

func _setup_area():
	var area = Area3D.new()
	var col = CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 3.0
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(_on_entered)
	area.body_exited.connect(func(_b): stop())

func _process(delta):
	if _is_busy:
		_timer += delta
		var progress = clamp(_timer / interaction_time, 0.0, 1.0)
		_ui_bar.get_node("Fill").scale.x = progress
		
		# Billboard
		var cam = get_viewport().get_camera_3d()
		if cam: _ui_bar.look_at(cam.global_position)
		
		if _timer >= interaction_time:
			_is_busy = false
			_ui_bar.visible = false
			interaction_completed.emit({})

func interact(_player):
	if _is_busy: return
	_is_busy = true
	_timer = 0.0
	_ui_bar.visible = true

func stop():
	_is_busy = false
	_ui_bar.visible = false

func _on_entered(body):
	if body.is_in_group("player"):
		# Nachricht an das HUD (via Gruppe, damit wir keine harten Pfade brauchen)
		get_tree().call_group("hud_layer", "show_interact_button", interaction_label)