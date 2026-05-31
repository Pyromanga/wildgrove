class_name BaseEvents extends RefCounted

## BaseEvents.gd
## Basisklasse für alle Event-Namespaces.
## Übernimmt das Logging damit emit_*() Funktionen es nicht selbst machen müssen.

var _category: String

func _init(category: String) -> void:
	_category = category

func _log(msg: String) -> void:
	Logger.log_debug(msg, _category)

func _log_info(msg: String) -> void:
	Logger.log_info(msg, _category)

func _log_warn(msg: String) -> void:
	Logger.log_warn(msg, _category)