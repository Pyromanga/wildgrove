extends Node

func _ready() -> void:
    # Wenn Logger geladen wurde, muss das hier funktionieren:
    Logger.log_info("Minimaler Bootstrap gestartet. Kernel ist deaktiviert.", "Main")
    
    # Teste ob das Terminal da ist
    if has_node("/root/SimpleTerminal"):
        Logger.log_debug("SimpleTerminal Autoload gefunden.", "Main")
    else:
        Logger.log_warn("SimpleTerminal Autoload fehlt!", "Main")