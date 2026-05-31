extends Node

## Kernel.gd — Die Service-Registry
signal service_registered(service_name: String)

var services: Dictionary = {}

func _ready() -> void:
    Logger.log_debug("Kernel Registry initialisiert.", "Kernel")

func register_service(node: Node) -> void:
    if not node:
        Logger.log_error("Versuch, einen null-Node als Service zu registrieren!", "Kernel")
        return
        
    var s_name = node.name.to_lower()
    services[s_name] = node
    
    Logger.log_debug("Service registriert: " + node.name, "Kernel")
    service_registered.emit(s_name)

## Sicherer Zugriff via Kernel.service_name
func _get(property: StringName):
    # Wichtig: Wir prüfen nur Strings, die Kleingeschrieben in unserer Liste sind
    var prop_str = str(property).to_lower()
    if services.has(prop_str):
        return services[prop_str]
    
    # WARNUNG: Hier kein Logger.log_error! 
    # Godot fragt intern oft nach Properties (z.B. script, name, etc.).
    # Wenn wir hier jedes Mal loggen, spammen wir alles zu oder erzeugen Loops.
    return null

func get_service(service_name: String) -> Node:
    var s = services.get(service_name.to_lower())
    if not s:
        Logger.log_error("Service explizit angefordert, aber nicht gefunden: " + service_name, "Kernel")
    return s

func has_service(service_name: String) -> bool:
    return services.has(service_name.to_lower())

func unregister_service(node: Node) -> void:
    if not node: return
    var s_name = node.name.to_lower()
    if services.has(s_name):
        services.erase(s_name)
        Logger.log_debug("Service entfernt: " + node.name, "Kernel")