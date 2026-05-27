extends Node
class_name Kernel

# Globale Referenzen (jetzt dynamisch)
var services: Dictionary = {}

func _ready() -> void:
	Logger.log_debug("Kernel Registry bereit.", "Kernel")

# Jeder Service meldet sich hier an, sobald er bereit ist
func register_service(node: Node) -> void:
	var service_name = node.name.to_lower()
	services[service_name] = node
	Logger.log_debug("Service registriert: " + node.name, "Kernel")

# Zugriffsmethode
func get_service(service_name: String) -> Node:
	return services.get(service_name.to_lower())