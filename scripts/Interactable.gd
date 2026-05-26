extends Node3D
## Interactable.gd

signal interaction_completed(src: Node3D, res: Dictionary)

@export var interaction_label: String = "Interagieren"
@export var interaction_time: float   = 3.0

var _is_busy: bool = false
var _timer: float = 0.0
var _bar: Node3D

func _ready() -> void:
	add_to_group("interactable")
	_bar = Factory.create_3d_bar(self)
	_setup_area()

func _setup_area() -> void:
	var area := Area3D.new()
	var col  := CollisionShape3D.new()
	col.shape = SphereShape3D.new(); col.shape.radius = 3.0
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(_on_entered)
	area.body_exited.connect(_on_exited)

func interact(_player: Node3D) -> void:
	if _is_busy: return
	_is_busy = true
	_timer = 0.0
	_bar.visible = true
	GameEvents.log("Aktion gestartet: " + interaction_label)

func _process(delta: float) -> void:
	if _is_busy:
		_timer += delta
		var p = clamp(_timer / interaction_time, 0.0, 1.0)
		_bar.get_node("Fill").scale.x = p
		
		if _timer >= interaction_time:
			_is_busy = false
			_bar.visible = false
			interaction_completed.emit(self, {})
			GameEvents.log("Aktion beendet: " + interaction_label)

func _on_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		GameEvents.log("Nähe von: " + interaction_label)
		get_tree().call_group("hud_layer", "show_interact_button", interaction_label)

func _on_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_is_busy = false
		_bar.visible = false
		get_tree().call_group("hud_layer", "hide_interact_button")