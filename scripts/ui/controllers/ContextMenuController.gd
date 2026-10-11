class_name ContextMenuController
extends RefCounted

## ContextMenuController — verwaltet das Kontext-Menü.
##
## ADR-015: _on_open_requested() nutzt _ctx.get_local_player() (Authority-Abgleich
## über get_multiplayer_authority()) statt _hud.get_tree().get_nodes_in_group("player")[0].
## Letzteres war zwar testbarer/kontextgebundener als der noch ältere
## Engine.get_main_loop()-Zugriff, aber "Index 0 in der Gruppe" ist in Hosted
## Coop mit zwei Spielern nicht zuverlässig "ich selbst" — siehe ADR-015.
##
## ARCHITEKTUR-HINWEIS:
##   ContextMenuController ist RefCounted (kein Node) — kein _ready(), kein _process().
##   Tweens und Timer werden über _hud.get_tree() und _hud (als Node-Proxy) erstellt.
##   Das ist bewusst: der Controller hält KEINE eigene Tree-Präsenz, er delegiert alles
##   an den HUD-Node den er kennt.

const LOG_CAT := "ContextMenu"

var _hud: HUD
var _ctx: IUIContext

## BUGFIX (entdeckt im Zuge von Bug #2, gleiche Root Cause): kein teardown()
## bislang — ohne teardown() bleibt dieser Controller nach jedem HUD-Rebuild
## (world_scene_ready) als Zombie-Listener auf request_context_menu am Leben,
## siehe FloatingTextController für die ausführliche Erklärung desselben
## Musters. _show_menu() räumt zwar über die "context_menu"-Gruppe alte
## Menü-Nodes tree-weit auf, mehrere Zombies auf demselben Signal bauen das
## Menü aber unnötig mehrfach hintereinander auf (Flackern) statt einmal sauber.
var _is_setup: bool = false

func setup(hud: HUD, ctx: IUIContext) -> void:
	assert(is_instance_valid(hud), "ContextMenuController.setup: hud ist null!")
	assert(ctx != null, "ContextMenuController.setup: ctx ist null!")

	if _is_setup:
		teardown()

	_hud = hud
	_ctx = ctx
	_ctx.bus().ui().request_context_menu.connect(_on_open_requested)
	_is_setup = true

	AppLogger.log_debug("ContextMenuController bereit.", LOG_CAT)

## MUSS von HUDManager vor dem Verwerfen dieses Controllers aufgerufen werden
## (siehe HUDManager._on_world_scene_ready()) — sonst bleibt dieser Controller
## als Zombie-Listener am Leben.
func teardown() -> void:
	if is_instance_valid(_ctx) and is_instance_valid(_ctx.bus()):
		if _ctx.bus().ui().request_context_menu.is_connected(_on_open_requested):
			_ctx.bus().ui().request_context_menu.disconnect(_on_open_requested)
	_is_setup = false

func _on_open_requested() -> void:
	AppLogger.log_debug("Kontext-Menü angefordert.", LOG_CAT)

	if not is_instance_valid(_hud):
		AppLogger.log_error("_hud ist nicht mehr valid — Kontext-Menü abgebrochen.", LOG_CAT)
		return

	# ADR-015: ctx.get_local_player() statt get_nodes_in_group("player")[0] —
	# sonst könnte das Kontext-Menü Aktionen für den falschen Spieler bauen,
	# sobald mehr als ein Player-Node in der Gruppe steht (Hosted Coop).
	var player: Node3D = _ctx.get_local_player() if is_instance_valid(_ctx) else null
	if not is_instance_valid(player):
		AppLogger.log_warn("Kein lokaler Player gefunden.", LOG_CAT)
		return

	if not player.has_method("get_all_nearby_context_actions"):
		AppLogger.log_error(
			"Player '%s' hat keine get_all_nearby_context_actions()-Methode." % player.name, LOG_CAT
		)
		return

	# BUGFIX (2026-09-26, "Kontextmenü soll alles anzeigen was in der Nähe ist"): vorher nur
	# get_context_actions() (EIN Ziel, das nächste/ausgewählte) — z.B. bei einer Leiter mit
	# großer Collision-Box waren Erze daneben per Tap gar nicht erreichbar. Jetzt Aktionen
	# für ALLE Interactables in Reichweite, ausgewähltes Ziel zuerst (siehe Player-Klassenkomm.).
	var actions: Array[InteractableAction] = player.get_all_nearby_context_actions()
	AppLogger.log_info(
		"Kontext-Menü: %d Aktion(en) für Player '%s'." % [actions.size(), player.name], LOG_CAT
	)

	_show_menu(actions)

func show(actions: Array[InteractableAction]) -> void:
	AppLogger.log_debug("show() direkt aufgerufen mit %d Aktionen." % actions.size(), LOG_CAT)
	_show_menu(actions)

func _show_menu(actions: Array[InteractableAction]) -> void:
	if not is_instance_valid(_hud):
		AppLogger.log_error("_show_menu(): _hud invalid.", LOG_CAT)
		return

	# Altes Menü aufräumen
	var old_menus := _hud.get_tree().get_nodes_in_group("context_menu")
	for n in old_menus:
		n.queue_free()
	if not old_menus.is_empty():
		AppLogger.log_debug("Altes Kontext-Menü (%d Nodes) entfernt." % old_menus.size(), LOG_CAT)

	if actions.is_empty():
		AppLogger.log_debug("Keine Aktionen — Menü wird nicht gezeigt.", LOG_CAT)
		return

	var visuals := ContextMenuVisuals.new()
	visuals.setup(_hud, actions)

	# Aktion ausführen wenn Button gedrückt
	visuals.action_triggered.connect(
		func(action: InteractableAction):
			AppLogger.log_info("Kontext-Aktion ausgewählt: '%s'." % action.label, LOG_CAT)
			visuals.destroy()
			_ctx.bus().ui().emit_interaction_execute_requested(action)
	)

	# Auto-Close nach 5 Sekunden (Sicherheitsnetz — Menü schließt wenn nichts passiert)
	# BUGFIX (2026-09-13): siehe NotificationVisuals.gd — derselbe Timer-
	# Kindknoten-Fix statt verwaistem get_tree().create_timer(), das gegen
	# ein vorzeitig zerstörtes 'visuals' feuern und 'Lambda capture at
	# index 0 was freed' loggen könnte.
	var auto_close := Timer.new()
	auto_close.wait_time = 5.0
	auto_close.one_shot  = true
	visuals.add_child(auto_close)
	auto_close.timeout.connect(func() -> void:
		AppLogger.log_debug("Kontext-Menü Auto-Close nach 5s.", LOG_CAT)
		visuals.destroy()
	)
	auto_close.start()

	AppLogger.log_info(
		"Kontext-Menü angezeigt: %d Aktion(en), Auto-Close in 5s." % actions.size(), LOG_CAT
	)
