extends Node

## MainSimple.gd — Minimaler Einstiegspunkt ohne ServiceOrchestrator.
## Nützlich für schnelle Tests einzelner Systeme.


func _ready() -> void:
	Logger.log_info("Minimaler Bootstrap gestartet. ServiceOrchestrator ist deaktiviert.", "Main")

	if has_node("/root/SimpleTerminal"):
		Logger.log_debug("SimpleTerminal Autoload gefunden.", "Main")
	else:
		Logger.log_warn("SimpleTerminal Autoload fehlt!", "Main")
