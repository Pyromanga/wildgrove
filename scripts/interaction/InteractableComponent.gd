extends Node3D
class_name InteractableComponent

## InteractableComponent — Koppelt ein World-Objekt an das Interaktions-System.
##
## Kernregel: Diese Klasse emittiert NUR Events via EventBus — sie ruft keine
## Services direkt auf. Früher stand hier Services.inventory.add_item() und
## EventBus.ui.emit_overlay_changed() direkt im Completion-Handler. Das bedeutete,
## dass jedes interagierbare Objekt in der Welt implizit das Inventar und das HUD
## kennen musste.
##
## Jetzt:
##   Drops    → EventBus.world.emit_loot_collected(item_id, qty)
##              InventorySystem lauscht darauf und fügt die Items hinzu.
##   Texte    → EventBus.world.emit_interaction_reward_text(text)
##              NotificationController lauscht und zeigt den Text.
##   3D-Bar   → verbindet sich mit EventBus.world (statt Services.interaction_executor)
##              — gleiche Signale, aber über den globalen Bus abgerufen.

@export var data: InteractableData
@export var detection_radius: float = 3.0

const LOG_CAT := "Interactable"

var _bar_3d: Factory3D.Bar3D = null
var _label: Label3D = null

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────


func _ready() -> void:
	assert(data != null, "InteractableComponent braucht InteractableData!")
	add_to_group("interactable")

	_setup_visuals()
	_setup_detection()
	_connect_world_events()


# ─────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────


func _setup_visuals() -> void:
	_label = Label3D.new()
	_label.text = data.label
	_label.position = Vector3(0.0, 2.5, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.visible = false
	add_child(_label)

	if Services.factory3d:
		_bar_3d = Services.factory3d.create_3d_bar(self)
	else:
		Logger.log_warn("Factory3D nicht verfügbar — 3D-Bar fehlt.", LOG_CAT)


func _setup_detection() -> void:
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = detection_radius
	col.shape = shape
	area.add_child(col)
	add_child(area)

	area.body_entered.connect(
		func(b: Node3D):
			if b.is_in_group("player") and _label:
				_label.visible = true
	)
	area.body_exited.connect(
		func(b: Node3D):
			if b.is_in_group("player") and _label:
				_label.visible = false
	)


func _connect_world_events() -> void:
	# Verbindet sich mit EventBus.world — nicht mehr mit Services.interaction_executor.
	# Beide emittieren dieselben Signale, aber der Bus ist die einzige Source of Truth.
	EventBus.world.interaction_started.connect(_on_started)
	EventBus.world.interaction_finished.connect(_on_ended)
	EventBus.world.interaction_cancelled.connect(_on_ended)


# ─────────────────────────────────────────────
# Interaktion
# ─────────────────────────────────────────────


func start_default_interaction() -> void:
	if not Services.interaction_executor:
		Logger.log_error("InteractionExecutor Service fehlt!", LOG_CAT)
		return

	var action := InteractableAction.new(data.id, data.label)
	action.duration = data.duration
	action.on_complete = _handle_completion

	Services.interaction_executor.execute_action(action)


func _handle_completion() -> void:
	# Drops — via EventBus, nicht direkt ins Inventar
	for item_id in data.drops:
		EventBus.world.emit_loot_collected(item_id, data.drops[item_id])

	# XP — unverändert, da PlayerEvents der korrekte Kanal ist
	if data.xp_type != "none":
		EventBus.player.emit_xp(data.xp_type, data.xp_amount)

	# Belohnungstext — via WorldEvent statt direktem UI-Aufruf
	if not data.inspect_text.is_empty():
		EventBus.world.emit_interaction_reward_text(data.inspect_text)

	# Rückmeldung an das Parent-Objekt (OakTree/IronOre)
	if get_parent().has_method("_on_interacted"):
		get_parent()._on_interacted(data.id)


# ─────────────────────────────────────────────
# World-Event-Handler (für 3D-Bar)
# ─────────────────────────────────────────────


func _on_started(label: String, duration: float) -> void:
	if label != data.label or not _bar_3d:
		return

	_bar_3d.visible = true
	var t := create_tween()
	t.tween_method(func(v: float): _bar_3d.update(v), 0.0, 1.0, duration)


func _on_ended(label: String) -> void:
	if label == data.label and _bar_3d:
		_bar_3d.visible = false
