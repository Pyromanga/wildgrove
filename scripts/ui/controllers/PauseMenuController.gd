class_name PauseMenuController
extends Node

## PauseMenuController — steuert das In-Game-Optionsmenü.
##
## 4 Aktionen:
##   1. Speichern  → GameSaveService.save_all() via _ctx.bus().persistence().emit_save_requested()
##   2. Laden      → Szene neu laden (lädt automatisch den letzten Spielstand)
##   3. Einstellungen → Settings CanvasLayer togglen
##   4. Hauptmenü  → GameManager.change_state(MAIN_MENU)
##
## Settings.gd ist ein extends CanvasLayer — wir suchen ihn in der Gruppe "settings".

const LOG_CAT := "PauseMenu"

var _visuals: PauseMenuVisuals
var _ctx: IUIContext

func setup(visuals: PauseMenuVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx = ctx
	_visuals.build_buttons(
		_on_save,
		_on_load,
		_on_settings,
		_on_main_menu
	)
	_visuals.menu_button.pressed.connect(_on_menu_button_pressed)

func _ready() -> void:
	# Menü schließen wenn Interaktion beginnt (Spieler ist beschäftigt)
	_ctx.bus().world().interaction_started.connect(_on_interaction_started)
	# ESC / Pause-Key
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _visuals.is_open():
		_visuals.close()
		get_viewport().set_input_as_handled()

# ─────────────────────────────────────────────
# Handlers
# ─────────────────────────────────────────────

func _on_menu_button_pressed() -> void:
	_visuals.toggle()
	AppLogger.log_debug("Pause-Menü %s." % ("geöffnet" if _visuals.is_open() else "geschlossen"), LOG_CAT)

func _on_save() -> void:
	AppLogger.log_info("Speichern angefordert.", LOG_CAT)
	_visuals.close()
	_ctx.bus().persistence().emit_save_requested()
	_ctx.bus().ui().emit_notification_requested("💾 Spielstand gespeichert!")

func _on_load() -> void:
	AppLogger.log_info("Laden: Welt-Szene neu laden.", LOG_CAT)
	_visuals.close()
	# Einfachste Form: Szene neu laden → SaveSystem lädt automatisch letzten Stand
	_ctx.bus().ui().emit_scene_reload_requested()

func _on_settings() -> void:
	AppLogger.log_debug("Einstellungen öffnen.", LOG_CAT)
	_visuals.close()
	# Settings.gd ist ein CanvasLayer in der Gruppe "settings"
	var settings_nodes := get_tree().get_nodes_in_group("settings")
	if settings_nodes.is_empty():
		AppLogger.log_warn("Settings-Node nicht in Gruppe 'settings' gefunden.", LOG_CAT)
		_create_and_show_settings()
		return
	var s: Node = settings_nodes[0]
	if s.has_method("toggle"):
		s.toggle()

func _on_main_menu() -> void:
	AppLogger.log_info("Zurück zum Hauptmenü.", LOG_CAT)
	_visuals.close()
	_ctx.bus().ui().emit_main_menu_requested()

func _on_interaction_started(_id: String, _label: String, _dur: float) -> void:
	_visuals.close()

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _create_and_show_settings() -> void:
	## Erstellt ein frisches Settings-Panel wenn noch keines im Tree ist.
	## Passiert beim ersten Öffnen — danach bleibt es in der Gruppe "settings".
	var settings_script: GDScript = load("res://scripts/ui/Settings.gd")
	if not settings_script:
		AppLogger.log_error("Settings.gd nicht ladbar.", LOG_CAT)
		return
	var settings_node = settings_script.new()
	# setup() VOR add_child(): _ready() baut das Panel bereits aus den
	# aktuellen Settings-Werten auf, der Service muss also vorher sitzen.
	settings_node.setup(_ctx)
	# Als Kind des HUD-Canvas einhängen (bleibt bei Szenenwechsel erhalten)
	var hud_node := _get_hud_canvas()
	if hud_node:
		hud_node.add_child(settings_node)
	else:
		get_tree().root.add_child(settings_node)
	# toggle() wurde bereits in _ready() durch settings_node selbst gebaut
	# Wir öffnen es mit einem kurzen defer damit _ready() zuerst feuert
	settings_node.call_deferred("toggle")

func _get_hud_canvas() -> CanvasLayer:
	# HUDManager ist kein Service — Canvas via Gruppe suchen.
	var nodes := get_tree().get_nodes_in_group("hud_canvas")
	if not nodes.is_empty() and nodes[0] is CanvasLayer:
		return nodes[0] as CanvasLayer
	return null
