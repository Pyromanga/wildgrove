extends Node3D
class_name InteractableComponent

## InteractableComponent — Koppelt ein World-Objekt an das Interaktions-System.
##
## Verantwortung:
##   - Gruppe "interactable" auf dem PARENT-Node setzen (für InteractionSensor)
##   - Meta "interactable_component" auf Parent setzen (für Player.get_context_actions)
##   - Eigene Area3D für Proximity-Detection (Label + Events)
##   - Interaktion via InteractionExecutor ausführen
##   - Completion-Ergebnisse nur via EventBus weitergeben (KEIN direkter Service-Call)
##
## ARCHITEKTUR-REGEL: Emittiert NUR via EventBus — keine direkten Service-Calls.
##   Drops    → EventBus.world.emit_loot_collected(item_id, qty)
##   XP       → EventBus.player.emit_xp(type, amount)
##   Text     → EventBus.world.emit_interaction_reward_text(text)
##   Nähe     → EventBus.world.emit_proximity_changed(target, in_range)
##
## WARUM META statt direktes Child-Lookup?
##   Player.get_context_actions() kennt den Entity-Typ nicht (OakTree, IronOre etc.).
##   Statt fragiles find_child("*Interactable*") zu nutzen, speichert die Komponente
##   sich selbst als Meta auf dem Parent-Node. Jeder Caller kann dann sicher
##   target.get_meta("interactable_component") nutzen ohne Typ-Wissen.

@export var data: InteractableData
@export var detection_radius: float = 3.0

const LOG_CAT := "Interactable"

var _bar_3d: Factory3D.Bar3D = null
var _label: Label3D = null


# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────


func _ready() -> void:
	assert(data != null, "InteractableComponent braucht InteractableData! (data == null)")

	# Parent in Gruppe "interactable" eintragen.
	# get_overlapping_bodies() gibt den Physics-Body zurück (Parent), NICHT diesen Node.
	get_parent().add_to_group("interactable")

	# Meta für typsicheren Zugriff ohne Child-Traversal.
	# Player.get_context_actions() und andere nutzen:
	#   var comp := target.get_meta("interactable_component", null)
	get_parent().set_meta("interactable_component", self)

	_setup_visuals()
	_setup_detection()
	_connect_world_events()

	Logger.log_info(
		"Bereit: '%s' | Parent: '%s' | Radius: %.1fm | Drops: %s"
		% [data.label, get_parent().name, detection_radius, str(data.drops)],
		LOG_CAT
	)


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


## Gibt alle verfügbaren Aktionen für dieses Interagierbare zurück.
## Wird von Player.get_context_actions() aufgerufen.
## Jede Aktion enthält alle Daten (duration, drops, xp) und den on_complete-Callback.
func get_actions() -> Array[InteractableAction]:
	var actions: Array[InteractableAction] = []

	var action := InteractableAction.new(data.id, data.label)
	action.duration = data.duration
	action.xp_type = data.xp_type
	action.xp_amount = data.xp_amount
	action.drops = data.drops
	action.inspect_text = data.inspect_text
	action.on_complete = _handle_completion

	actions.append(action)

	Logger.log_debug(
		"get_actions() aufgerufen: '%s' — 1 Aktion zurückgegeben." % data.label, LOG_CAT
	)
	return actions


## Startet die Standard-Interaktion (erste verfügbare Aktion).
## Aufgerufen wenn der Spieler direkt interagiert (kein Kontext-Menü).
func start_default_interaction() -> void:
	if not is_instance_valid(Services.interaction_executor):
		Logger.log_error("InteractionExecutor-Service fehlt!", LOG_CAT)
		return

	var actions := get_actions()
	if actions.is_empty():
		Logger.log_warn("Keine Aktionen verfügbar für '%s'." % data.label, LOG_CAT)
		return

	Logger.log_info("Starte Standard-Interaktion: '%s'." % actions[0].label, LOG_CAT)
	Services.interaction_executor.execute_action(actions[0])


# ─────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────


func _setup_visuals() -> void:
	_label = Label3D.new()
	_label.text      = data.label
	_label.position  = Vector3(0.0, 2.5, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.visible   = false
	add_child(_label)

	# Factory3D ist jetzt in WorldService — kein eigener Service mehr
	if is_instance_valid(Services.world) and is_instance_valid(Services.world.factory3d):
		_bar_3d = Services.world.factory3d.create_3d_bar(self)
		Logger.log_debug("3D-Bar via WorldService.factory3d erstellt.", LOG_CAT)
	else:
		Logger.log_warn("Factory3D nicht verfügbar — 3D-Fortschrittsbar fehlt.", LOG_CAT)


func _setup_detection() -> void:
	var area := Area3D.new()
	area.name = "DetectionArea"
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = detection_radius
	col.shape = shape
	area.add_child(col)
	add_child(area)

	area.body_entered.connect(_on_player_entered)
	area.body_exited.connect(_on_player_exited)
	Logger.log_debug("DetectionArea erstellt (Radius: %.1fm)." % detection_radius, LOG_CAT)


func _connect_world_events() -> void:
	EventBus.world.interaction_started.connect(_on_interaction_started)
	EventBus.world.interaction_finished.connect(_on_interaction_ended)
	EventBus.world.interaction_cancelled.connect(_on_interaction_ended)


# ─────────────────────────────────────────────
# Proximity-Events (von Area3D)
# ─────────────────────────────────────────────


func _on_player_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if is_instance_valid(_label):
		_label.visible = true
	Logger.log_info(
		"Spieler in Reichweite: '%s' (%.1fm Radius)." % [data.label, detection_radius], LOG_CAT
	)
	EventBus.world.emit_proximity_changed(get_parent(), true)


func _on_player_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if is_instance_valid(_label):
		_label.visible = false
	Logger.log_info("Spieler außer Reichweite: '%s'." % data.label, LOG_CAT)
	EventBus.world.emit_proximity_changed(get_parent(), false)


# ─────────────────────────────────────────────
# Interaktions-Completion
# ─────────────────────────────────────────────


func _handle_completion() -> void:
	Logger.log_info(
		"Interaktion abgeschlossen: '%s'. Verteile Rewards." % data.label, LOG_CAT
	)

	# Drops: LootTable hat Vorrang, legacy drops-Dictionary als Fallback
	var resolved_drops: Dictionary = {}
	if data.loot_table:
		resolved_drops = data.loot_table.roll()
		Logger.log_debug("LootTable gerollt: %s" % str(resolved_drops), LOG_CAT)
	elif not data.drops.is_empty():
		resolved_drops = data.drops
		Logger.log_debug("Legacy-Drops: %s" % str(resolved_drops), LOG_CAT)

	for item_id in resolved_drops:
		var qty: int = resolved_drops[item_id]
		EventBus.world.emit_loot_collected(item_id, qty)
		Logger.log_debug("Drop: %dx '%s'." % [qty, item_id], LOG_CAT)

	# XP → SkillSystem hört auf dieses Signal
	if data.xp_type != "none" and data.xp_amount > 0:
		EventBus.player.emit_xp(data.xp_type, data.xp_amount)
		Logger.log_debug("XP: +%d %s." % [data.xp_amount, data.xp_type], LOG_CAT)

	# Inspect-Text → NotificationController hört auf dieses Signal
	if not data.inspect_text.is_empty():
		EventBus.world.emit_interaction_reward_text(data.inspect_text)

	# Parent-Callback (z.B. OakTree._on_interacted("chop"))
	if get_parent().has_method("_on_interacted"):
		get_parent()._on_interacted(data.id)
		Logger.log_debug("_on_interacted('%s') auf Parent '%s' aufgerufen." % [data.id, get_parent().name], LOG_CAT)


# ─────────────────────────────────────────────
# 3D-Bar Update (World-Event-Handler)
# ─────────────────────────────────────────────


func _on_interaction_started(action_id: String, _label: String, duration: float) -> void:
	## Matcht per action_id (eindeutig, z.B. "chop_oak") statt per label
	## ("Eiche fällen" würde bei mehreren Bäumen alle Bars gleichzeitig zeigen).
	if action_id != data.action_id or not is_instance_valid(_bar_3d):
		return
	_bar_3d.visible = true
	var t := create_tween()
	t.tween_method(func(v: float): _bar_3d.update(v), 0.0, 1.0, duration)
	Logger.log_debug("3D-Bar Fortschritt gestartet (%.1fs)." % duration, LOG_CAT)


func _on_interaction_ended(action_id: String, _label: String) -> void:
	if action_id == data.action_id and is_instance_valid(_bar_3d):
		_bar_3d.visible = false
