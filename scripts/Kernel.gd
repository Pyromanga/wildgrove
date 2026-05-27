extends Node
class_name Kernel

## Kernel.gd — Die Service-Registry
## Zentraler Hub für alle Services. Services registrieren sich selbst via ServiceBase.

# Wird gefeuert, wenn ein Service dem Kernel bekannt gemacht wird
signal service_registered(service_name: String)

var services: Dictionary = {}

func _ready() -> void:
	Logger.log_debug("Kernel Registry initialisiert.", "Kernel")

## Registriert einen Service-Node im System
func register_service(node: Node) -> void:
	var s_name = node.name.to_lower()
	services[s_name] = node
	
	# Signal an alle, die auf diesen Service warten
	service_registered.emit(s_name)
	Logger.log_debug("Service registriert: " + node.name, "Kernel")

## Zugriff via Kernel.service_name (dank _get)
func _get(property):
	if services.has(property):
		return services[property]
	return null

## Holt einen Service. Nützlich, wenn man sichergehen will, dass er existiert
func get_service(service_name: String) -> Node:
	return services.get(service_name.to_lower())

## Hilfsmethode, um zu prüfen, ob ein Service schon da ist
func has_service(service_name: String) -> bool:
	return services.has(service_name.to_lower())