extends Node

## SimpleTerminal.gd - Das Gehirn der Konsole
## Als AutoLoad registrieren!

var entries: Array[String] = []
var max_entries: int = 200
var is_visible: bool = false

signal toggled(visible: bool)
signal updated()

func _ready() -> void:
	# Wir verbinden uns sofort mit deinem Logger
	if Logger.has_signal("on_log"):
		Logger.on_log.connect(_on_logger_log)
	
	# Wir erstellen die UI
	var ui = SimpleTerminalUI.new()
	add_child(ui)

func _on_logger_log(formatted_msg: String, _cat: String, _level: int) -> void:
	entries.append(formatted_msg)
	if entries.size() > max_entries:
		entries.pop_front()
	updated.emit()

func toggle() -> void:
	is_visible = not is_visible
	toggled.emit(is_visible)

func clear() -> void:
	entries.clear()
	updated.emit()
	
# In SimpleTerminal.gd ergänzen:

func get_all_text() -> String:
	return "\n".join(entries)