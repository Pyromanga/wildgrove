class_name InteractionButtonController
extends Node

## InteractionButtonController — zeigt/versteckt den Interaktions-Button.
##
## Muss via hud.add_child(ctrl) in den SceneTree eingehängt werden damit
## _ready() und _process() feuern. Das erledigt InteractionButtonComponent.build().
##
## ersetzt. InteractionSensor emittiert jetzt proximity_changed wenn sich der
## nächste Interagierbare ändert — kein Frame-by-Frame get_nodes_in_group() mehr.

var _visuals: InteractionButtonVisuals
var _ctx: IUIContext
var _has_target: bool = false
var _is_busy: bool = false

func setup(visuals: InteractionButtonVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx = ctx
	# Button.pressed → Standard-Interaktion auf dem nächsten Interagierbaren
	_visuals.button.pressed.connect(_on_pressed)

func _ready() -> void:
	_ctx.bus().world().interaction_started.connect(_on_interaction_started)
	_ctx.bus().world().interaction_finished.connect(_on_interaction_ended)
	_ctx.bus().world().interaction_cancelled.connect(_on_interaction_ended)
	_ctx.bus().world().proximity_changed.connect(_on_proximity_changed)
	_update_button()

func _on_pressed() -> void:
	if not _has_target or _is_busy:
		return
	# ADR-015: ctx.get_local_player() statt get_nodes_in_group("player")[0] —
	# sonst könnte dieser Button in Multiplayer den falschen Spieler ansteuern.
	var player: Node3D = _ctx.get_local_player() if is_instance_valid(_ctx) else null
	if not is_instance_valid(player):
		AppLogger.log_warn("InteractionButton: kein lokaler Player gefunden.", "InteractionBtn")
		return
	if not player.has_method("get_context_actions"):
		return
	var actions: Array[InteractableAction] = player.get_context_actions()
	# Index 0 = Haupt-Aktion (z.B. "Eiche fällen"), Index 1+ = Untersuchen etc.
	# Inspect-Aktionen enden auf "_inspect" — Button soll IMMER die Primär-Aktion starten.
	for action in actions:
		if action is InteractableAction and not action.id.ends_with("_inspect"):
			AppLogger.log_info("InteractionButton Press → '%s'" % action.label, "InteractionBtn")
			_ctx.bus().ui().emit_interaction_execute_requested(action)
			return
	AppLogger.log_warn("InteractionButton: keine ausführbare Primär-Aktion gefunden.", "InteractionBtn")

func _on_proximity_changed(target: Node3D, in_range: bool) -> void:
	var new_has_target := in_range and is_instance_valid(target)
	if new_has_target != _has_target:
		_has_target = new_has_target
		_update_button()

func _on_interaction_started(_action_id: String, _label: String, _duration: float) -> void:
	_is_busy = true
	_update_button()

func _on_interaction_ended(_action_id: String, _label: String) -> void:
	_is_busy = false
	_update_button()

func _update_button() -> void:
	if is_instance_valid(_visuals):
		_visuals.set_active(_has_target and not _is_busy)
