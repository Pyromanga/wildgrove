class_name ContextMenuController
extends RefCounted

## ContextMenuController — verwaltet das Kontext-Menü.
##
## FIX 1: War doppelt definiert (setup-Version + show-Version) — zusammengeführt.
## FIX 2: _show_menu() hatte leeren Body → "Expected indented block" Parse Error.
## FIX 3: Kernel.builder → Services.builder

var _hud:       HUD
var _event_bus: Object

func setup(hud: HUD, event_bus: Object) -> void:
	_hud       = hud
	_event_bus = event_bus
	_event_bus.request_context_menu.connect(_on_open_requested)

func _on_open_requested() -> void:
	var player: Node = Engine.get_main_loop().root.get_first_node_in_group("player")
	if player and player.has_method("get_context_actions"):
		_show_menu(player.get_context_actions())

func show(actions: Array) -> void:
	_show_menu(actions)

func _show_menu(actions: Array) -> void:
	if not is_instance_valid(_hud):
		return

	# Altes Menü aufräumen
	for n in _hud.get_tree().get_nodes_in_group("context_menu"):
		n.queue_free()

	if actions.is_empty():
		return

	# FIX: Kernel.builder → Services.builder
	var visuals := ContextMenuVisuals.new(_hud, actions)
	visuals.action_triggered.connect(func(action: InteractableAction):
		visuals.destroy()
		if is_instance_valid(Services.builder):
			Services.builder.execute_action(action)
	)

	# Auto-Close nach 5 Sekunden
	_hud.get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(visuals):
			visuals.destroy()
	)