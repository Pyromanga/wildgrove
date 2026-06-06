class_name ContextMenuController
extends RefCounted

## ContextMenuController — verwaltet das Kontext-Menü.
##
## BUG-FIX (Session 3):
##   ALT: Engine.get_main_loop().root.get_nodes_in_group("player")
##   PROBLEM: Engine.get_main_loop() ist fragil, koppelt an die Engine-Instanz,
##            schwer testbar und liefert bei Unit-Tests null.
##   NEU: _hud.get_tree().get_nodes_in_group("player")
##   VORTEIL: Kontextgebunden (gleicher SceneTree wie das HUD), testbar,
##            klar aus welchem Tree die Suche startet.
##
## ARCHITEKTUR-HINWEIS:
##   ContextMenuController ist RefCounted (kein Node) — kein _ready(), kein _process().
##   Tweens und Timer werden über _hud.get_tree() und _hud (als Node-Proxy) erstellt.
##   Das ist bewusst: der Controller hält KEINE eigene Tree-Präsenz, er delegiert alles
##   an den HUD-Node den er kennt.

const LOG_CAT := "ContextMenu"

var _hud: HUD
var _event_bus: Object


func setup(hud: HUD, event_bus: Object) -> void:
	assert(is_instance_valid(hud), "ContextMenuController.setup: hud ist null!")
	assert(event_bus != null, "ContextMenuController.setup: event_bus ist null!")

	_hud = hud
	_event_bus = event_bus
	_event_bus.request_context_menu.connect(_on_open_requested)

	Logger.log_debug("ContextMenuController bereit.", LOG_CAT)


func _on_open_requested() -> void:
	Logger.log_debug("Kontext-Menü angefordert.", LOG_CAT)

	if not is_instance_valid(_hud):
		Logger.log_error("_hud ist nicht mehr valid — Kontext-Menü abgebrochen.", LOG_CAT)
		return

	# FIX: _hud.get_tree() statt Engine.get_main_loop().root
	# Klar, kontextgebunden, testbar.
	var players: Array = _hud.get_tree().get_nodes_in_group("player")
	if players.is_empty():
		Logger.log_warn("Kein Player in Gruppe 'player' gefunden.", LOG_CAT)
		return

	var player: Node = players[0]

	if not player.has_method("get_context_actions"):
		Logger.log_error(
			"Player '%s' hat keine get_context_actions()-Methode." % player.name, LOG_CAT
		)
		return

	var actions: Array = player.get_context_actions()
	Logger.log_info(
		"Kontext-Menü: %d Aktion(en) für Player '%s'." % [actions.size(), player.name], LOG_CAT
	)

	_show_menu(actions)


func show(actions: Array) -> void:
	Logger.log_debug("show() direkt aufgerufen mit %d Aktionen." % actions.size(), LOG_CAT)
	_show_menu(actions)


func _show_menu(actions: Array) -> void:
	if not is_instance_valid(_hud):
		Logger.log_error("_show_menu(): _hud invalid.", LOG_CAT)
		return

	# Altes Menü aufräumen
	var old_menus := _hud.get_tree().get_nodes_in_group("context_menu")
	for n in old_menus:
		n.queue_free()
	if not old_menus.is_empty():
		Logger.log_debug("Altes Kontext-Menü (%d Nodes) entfernt." % old_menus.size(), LOG_CAT)

	if actions.is_empty():
		Logger.log_debug("Keine Aktionen — Menü wird nicht gezeigt.", LOG_CAT)
		return

	var visuals := ContextMenuVisuals.new(_hud, actions)

	# Aktion ausführen wenn Button gedrückt
	visuals.action_triggered.connect(
		func(action: InteractableAction):
			Logger.log_info("Kontext-Aktion ausgewählt: '%s'." % action.label, LOG_CAT)
			visuals.destroy()
			if is_instance_valid(Services.interaction_executor):
				Services.interaction_executor.execute_action(action)
			else:
				Logger.log_error("InteractionExecutor-Service fehlt!", LOG_CAT)
	)

	# Auto-Close nach 5 Sekunden (Sicherheitsnetz — Menü schließt wenn nichts passiert)
	_hud.get_tree().create_timer(5.0).timeout.connect(
		func():
			if is_instance_valid(visuals):
				Logger.log_debug("Kontext-Menü Auto-Close nach 5s.", LOG_CAT)
				visuals.destroy()
	)

	Logger.log_info(
		"Kontext-Menü angezeigt: %d Aktion(en), Auto-Close in 5s." % actions.size(), LOG_CAT
	)
