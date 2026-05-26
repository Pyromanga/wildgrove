extends Node3D

signal completed # Wird gefeuert, wenn der Balken voll ist

@export var label: String = "Interagieren"
@export var duration: float = 3.0

var _is_active: bool = false
var _time: float = 0.0
var _bar: Node3D

func _ready() -> void:
	add_to_group("interactable")
	_bar = Factory.create_3d_bar(self)
	_setup_detection_area()

func _setup_detection_area() -> void:
	var area = Area3D.new()
	var col = CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 3.5
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(func(b): if b.is_in_group("player"): GameEvents.log("Nähe: " + label))

func start_interaction() -> void:
	if _is_active: return
	_is_active = true
	_time = 0.0
	_bar.visible = true
	GameEvents.log("Starte " + label)

func _process(delta: float) -> void:
	if _is_active:
		_time += delta
		var progress = _time / duration
		
		# Nutze die Factory-Logik statt direktem get_node()
		if _bar.has_meta("update_bar"):
			_bar.get_meta("update_bar").call(progress)
		
		if _time >= duration:
			_is_active = false
			_bar.visible = false
			completed.emit()