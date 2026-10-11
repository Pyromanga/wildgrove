class_name EngineLogBridge extends Logger

## EngineLogBridge — Brücke zwischen Godots nativer Logger-Klasse (Godot 4.5+,
## GH-91006 / bitwes/Gut#715) und AppLogger (res://scripts/logger/Logger.gd).
##
## HEISST BEWUSST NICHT "Logger". Genau dieser Name kollidierte früher mit
## der nativen Engine-Klasse "Logger" (siehe project.godot Autoload-
## Kommentar sowie der GUT-Bug: "The member 'Logger' shadows a native
## class."). Von "Logger" zu ERBEN ist dagegen der vorgesehene Weg, um an
## das native Interface zu kommen — nur der eigene Klassenname darf nicht
## nochmal "Logger" lauten.
##
## Fängt SCRIPT ERROR / push_error() / push_warning() / print() der Engine
## ab, die bisher NUR in der Godot-Konsole/im Debugger landeten und NIE im
## AppLogger-Ringpuffer oder in wildgrove.log auftauchten. Damit landen jetzt
## auch native Engine-Fehler (inkl. GDScript-Backtrace) in der exportierten
## Log-Datei — nützlich z.B. für Bug-Reports von Spielern ohne Editor-Zugriff.
##
## Registrierung: AppLogger._ready() → OS.add_logger(EngineLogBridge.new()),
## abgesichert mit ClassDB.class_exists("Logger") für Godot < 4.5.
##
## WICHTIG — Rekursionsgefahr:
##   _log_error()/_log_message() dürfen NIEMALS push_error(), push_warning()
##   oder print() aufrufen — jedes davon würde den nativen Logger erneut
##   triggern. Wir rufen ausschließlich AppLogger.ingest_engine_event() auf,
##   das intern ebenfalls keins von beiden tut (siehe Logger.gd).

func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	script_backtraces: Array[ScriptBacktrace]
) -> void:
	var level: int = AppLogger.LogLevel.WARN if error_type == ERROR_TYPE_WARNING else AppLogger.LogLevel.ERROR
	var headline: String = rationale if not rationale.is_empty() else code
	var location := "%s:%d @ %s()" % [file, line, function]
	var message := "%s\n  %s" % [headline, location]

	if level == AppLogger.LogLevel.ERROR:
		var bt := _format_gdscript_backtrace(script_backtraces)
		if not bt.is_empty():
			message += "\n" + bt

	AppLogger.ingest_engine_event(message, "Engine", level)

func _log_message(message: String, is_error: bool) -> void:
	# Eigene AppLogger-prints tragen OWN_PRINT_MARKER als Präfix — die
	# ignorieren wir hier, sonst landet jeder AppLogger-Eintrag doppelt
	# im Puffer (einmal über _print_log()/_record(), einmal hier).
	if message.begins_with(AppLogger.OWN_PRINT_MARKER):
		return
	var level: int = AppLogger.LogLevel.ERROR if is_error else AppLogger.LogLevel.DEBUG
	AppLogger.ingest_engine_event(message.trim_suffix("\n"), "Engine", level)

## Extrahiert den GDScript-Teil aus script_backtraces (kann zusätzlich einen
## C#-Backtrace enthalten, falls das Projekt beides nutzt — hier nicht der Fall).
func _format_gdscript_backtrace(script_backtraces: Array[ScriptBacktrace]) -> String:
	var idx: int = script_backtraces.find_custom(
		func(bt: ScriptBacktrace) -> bool: return bt.get_language_name() == "GDScript"
	)
	return "" if idx == -1 else str(script_backtraces[idx])
