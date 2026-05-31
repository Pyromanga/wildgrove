# InteractableComponent.gd
extends Node3D
class_name InteractableComponent

@export var data: InteractableData
@export var detection_radius: float = 3.0

var _bar_3d: Factory3D.Bar3D
var _label: Label3D

func _ready() -> void:
	# Nur die Komponente ist in der Gruppe!
	add_to_group("interactable")
	_setup_visuals()
	_setup_detection()
	
	# Builder-Signale für die Progressbar
	Kernel.builder.interaction_started.connect(_on_started)
	Kernel.builder.interaction_completed.connect(_on_ended)
	Kernel.builder.interaction_cancelled.connect(_on_ended)

func _setup_visuals() -> void:
	# Label erstellen
	_label = Label3D.new()
	_label.text = data.label if data else "!!!"
	_label.position.y = 2.5
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.visible = false
	add_child(_label)
	
	# Bar via Factory
	if Kernel.factory3d:
		_bar_3d = Kernel.factory3d.create_3d_bar(self)

func _setup_detection() -> void:
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = detection_radius
	col.shape = shape
	area.add_child(col)
	add_child(area)
	
	area.body_entered.connect(func(b): if b.is_in_group("player"): _label.visible = true)
	area.body_exited.connect(func(b): if b.is_in_group("player"): _label.visible = false)

# --- Das Gehirn der Interaktion ---

func start_default_interaction() -> void:
	# Wir bauen eine Action "on the fly" für den Builder
	var action = InteractableAction.new(data.id, data.label)
	action.duration = data.duration
	action.on_complete = _handle_completion
	Kernel.builder.execute_action(action)

func _handle_completion() -> void:
	# XP geben
	if data.xp_type != "none":
		Kernel.events.player.emit_xp(data.xp_type, data.xp_amount)
	
	# Drops geben
	for item_id in data.drops:
		Kernel.inventory.add_item(item_id, data.drops[item_id])
		
	# Popup zeigen
	if data.inspect_text != "":
		Kernel.ui_factory.show_popup(data.inspect_text)
	
	# Dem Parent (dem Baum) sagen: Wir sind fertig!
	if get_parent().has_method("_on_interacted"):
		get_parent()._on_interacted(data.id)

func _on_started(l: String, d: float) -> void:
	if l == data.label and _bar_3d:
		_bar_3d.visible = true
		var t = create_tween()
		t.tween_method(func(v): _bar_3d.update(v), 0.0, 1.0, d)

func _on_ended(_l: String) -> void:
	if _bar_3d: _bar_3d.visible = false