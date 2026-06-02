extends Node3D
class_name InteractableComponent

## InteractableComponent — Koppelt ein World-Objekt an das Interaktions-System.
## Füge diese Komponente als Child zu jedem interagierbaren Objekt hinzu.

@export var data: InteractableData
@export var detection_radius: float = 3.0

const LOG_CAT := "Interactable"

var _bar_3d: Factory3D.Bar3D = null
var _label:  Label3D         = null

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	assert(data != null, "InteractableComponent braucht InteractableData!")
	add_to_group("interactable")
	_setup_visuals()
	_setup_detection()
	_connect_builder_signals()

# ─────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────

func _setup_visuals() -> void:
	_label          = Label3D.new()
	_label.text     = data.label
	_label.position = Vector3(0.0, 2.5, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.visible  = false
	add_child(_label)

	if Kernel.factory3d:
		_bar_3d = Kernel.factory3d.create_3d_bar(self)
	else:
		Logger.log_warn("Factory3D nicht verfügbar — 3D-Bar fehlt.", LOG_CAT)

func _setup_detection() -> void:
	var area  := Area3D.new()
	var col   := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = detection_radius
	col.shape    = shape
	area.add_child(col)
	add_child(area)

	area.body_entered.connect(func(b: Node3D):
		if b.is_in_group("player") and _label:
			_label.visible = true
	)
	area.body_exited.connect(func(b: Node3D):
		if b.is_in_group("player") and _label:
			_label.visible = false
	)

func _connect_builder_signals() -> void:
	if not Kernel.builder:
		Logger.log_warn("InteractionBuilder nicht verfügbar — Bar-Updates deaktiviert.", LOG_CAT)
		return
	Kernel.builder.interaction_started.connect(_on_started)
	Kernel.builder.interaction_completed.connect(_on_ended)
	Kernel.builder.interaction_cancelled.connect(_on_ended)

# ─────────────────────────────────────────────
# Interaktion
# ─────────────────────────────────────────────

func start_default_interaction() -> void:
	if not Kernel.builder:
		Logger.log_error("InteractionBuilder nicht verfügbar!", LOG_CAT)
		return

	var action              := InteractableAction.new(data.id, data.label)
	action.duration         = data.duration
	action.on_complete      = _handle_completion
	Kernel.builder.execute_action(action)

func _handle_completion() -> void:
	if data.xp_type != "none" and Kernel.events:
		Kernel.events.player.emit_xp(data.xp_type, data.xp_amount)

	if Kernel.inventory:
		for item_id in data.drops:
			Kernel.inventory.add_item(item_id, data.drops[item_id])

	if not data.inspect_text.is_empty() and Kernel.events:
		# Notification über Events statt direkten UIFactory-Aufruf
		Kernel.events.ui.emit_overlay_changed("notification:" + data.inspect_text, true)

	if get_parent().has_method("_on_interacted"):
		get_parent()._on_interacted(data.id)

# ─────────────────────────────────────────────
# Builder-Signal-Handler
# ─────────────────────────────────────────────

func _on_started(label: String, duration: float) -> void:
	if label != data.label or not _bar_3d:
		return
	_bar_3d.visible = true
	var t := create_tween()
	t.tween_method(func(v: float): _bar_3d.update(v), 0.0, 1.0, duration)

func _on_ended(_label: String) -> void:
	if _bar_3d:
		_bar_3d.visible = false