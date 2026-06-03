extends Node3D
class_name InteractableComponent

## InteractableComponent — Koppelt ein World-Objekt an das Interaktions-System.

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

	# NEU: Sicherer Zugriff über Services
	if Services.factory3d:
		_bar_3d = Services.factory3d.create_3d_bar(self)
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
	# NEU: Der InteractionBuilder ist jetzt ein Service
	if not Services.builder:
		Logger.log_warn("InteractionBuilder Service nicht verfügbar.", LOG_CAT)
		return
		
	Services.builder.interaction_started.connect(_on_started)
	Services.builder.interaction_completed.connect(_on_ended)
	Services.builder.interaction_cancelled.connect(_on_ended)

# ─────────────────────────────────────────────
# Interaktion
# ─────────────────────────────────────────────

func start_default_interaction() -> void:
	if not Services.builder:
		Logger.log_error("InteractionBuilder Service fehlt!", LOG_CAT)
		return

	var action              := InteractableAction.new(data.id, data.label)
	action.duration         = data.duration
	action.on_complete      = _handle_completion
	
	Services.builder.execute_action(action)

func _handle_completion() -> void:
	# 1. XP vergeben über EventBus
	if data.xp_type != "none":
		EventBus.player.emit_xp(data.xp_type, data.xp_amount)

	# 2. Loot ins Inventar
	if Services.inventory:
		for item_id in data.drops:
			Services.inventory.add_item(item_id, data.drops[item_id])

	# 3. UI-Benachrichtigung über EventBus
	if not data.inspect_text.is_empty():
		EventBus.ui.emit_overlay_changed("notification:" + data.inspect_text, true)

	# 4. Rückmeldung an das Parent-Objekt (OakTree/IronOre)
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
	# Update der Bar über die Factory3D Hilfsklasse
	t.tween_method(func(v: float): _bar_3d.update(v), 0.0, 1.0, duration)

func _on_ended(label: String) -> void:
	if label == data.label and _bar_3d:
		_bar_3d.visible = false