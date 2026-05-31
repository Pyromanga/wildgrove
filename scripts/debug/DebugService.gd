extends ServiceBase
class_name DebugService

## DebugService.gd
## Instanziiert die DebugConsoleUI und hängt sie in den SceneTree.
## Nur im Debug-Build aktiv — in Release-Builds ist die UI nicht sichtbar.

const LOG_CAT := "DebugService"

var _ui: DebugConsoleUI

func _ready() -> void:
	Logger.log_debug("DebugService._ready()", LOG_CAT)
	super._ready()

func init() -> void:
	super.init()
	Logger.log_debug("init() — prüfe Build-Typ...", LOG_CAT)

	if not OS.is_debug_build():
		Logger.log_info("Release-Build erkannt — DebugConsoleUI wird nicht erstellt.", LOG_CAT)
		return

	Logger.log_info("Debug-Build erkannt — erstelle DebugConsoleUI...", LOG_CAT)

func on_ready() -> void:
	super.on_ready()

	if not OS.is_debug_build():
		return

	Logger.log_debug("on_ready() — hole DebugConsole Service...", LOG_CAT)
	var console := Kernel.get_service("debug_console") as DebugConsole
	if not console:
		Logger.log_error("DebugConsole Service nicht gefunden! UI kann nicht erstellt werden.", LOG_CAT)
		return

	Logger.log_debug("DebugConsole gefunden. Erstelle UI-Node...", LOG_CAT)
	_ui = DebugConsoleUI.new()
	_ui.name = "DebugConsoleUI"

	# An Root-Viewport hängen damit es immer sichtbar ist
	get_tree().root.add_child(_ui)
	Logger.log_debug("DebugConsoleUI im Tree. Rufe setup() auf...", LOG_CAT)

	_ui.setup(console)
	Logger.log_info("DebugConsoleUI erfolgreich initialisiert. F1 oder 4-Finger-Tap zum Öffnen.", LOG_CAT)
