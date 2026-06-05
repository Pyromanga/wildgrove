class_name ContextMenuController
extends RefCounted

## ContextMenuController — verwaltet das Kontext-Menü.
##
## Gefixt: _on_open_requested() rief player.get_context_actions() auf, eine Methode
## die auf Player.gd NICHT existiert hat. Jetzt läuft das korrekt über
## InteractionSensor → get_closest_interactable() → get_actions().
##
## Player.get_context_actions() ist jetzt als Stub definiert (Player.gd).

var _hud: HUD
var _event_bus: Object


func setup(hud: HUD, event_bus: Object) -> void:
	_hud = hud
	_event_bus = event_bus
	_event_bus.request_context_menu.connect(_on_open_requested)


func _on_open_requested() -> void:
	var players: Array = Engine.get_main_loop().root.get_nodes_in_group("player")
	if players.is_empty():
		return

	var player: Node = players[0]
	# get_context_actions() ist auf Player als Stub definiert und gibt die
	# Aktionen des nächsten Interagierbar-Gegenstands zurück.
	if player.has_method("get_context_actions"):
		_show_menu(player.get_context_actions())


func show(actions: Array) -> void:
	_show_menu(actions)


func _show_menu(actions: Array) -> void:
	if not is_instance_valid(_hud):
		return

	for n in _hud.get_tree().get_nodes_in_group("context_menu"):
		n.queue_free()

	if actions.is_empty():
		return

	var visuals := ContextMenuVisuals.new(_hud, actions)
	visuals.action_triggered.connect(
		func(action: InteractableAction):
			visuals.destroy()
			if is_instance_valid(Services.interaction_executor):
				Services.interaction_executor.execute_action(action)
	)

	_hud.get_tree().create_timer(5.0).timeout.connect(
		func():
			if is_instance_valid(visuals):
				visuals.destroy()
	)
