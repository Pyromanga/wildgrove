# res://scripts/core/Kernel.gd
extends Node

## Kernel — Die zentrale Service-Registry.
## Speichert sowohl Node-basierte Services als auch reine RefCounted-Objekte.
## Sorgt für die zentrale Verwaltung und den Lebenszyklus.

signal service_registered(service_name: String)

## Alle Services werden hier referenziert.
var services: Dictionary = {}

func _ready() -> void:
	Logger.log_debug("Kernel Registry initialisiert.", "Kernel")

## Registriert einen Service (Node oder RefCounted).
func register_service(service: Object) -> void:
	if not service:
		Logger.log_error("Versuch, ein null-Object als Service zu registrieren!", "Kernel")
		return
		
	# Identitäts-Check: Hat das Objekt einen Namen? Wenn nein, nutze den Klassennamen.
	var s_name := ""
	if "name" in service and not str(service.name).is_empty():
		s_name = str(service.name).to_lower()
	else:
		s_name = service.get_class().to_lower()
	
	services[s_name] = service
	
	Logger.log_debug("Service registriert: %s" % s_name, "Kernel")
	service_registered.emit(s_name)

## Holt einen Service über seinen Namen.
func get_service(service_name: String) -> Object:
	var s = services.get(service_name.to_lower())
	if not s:
		Logger.log_error("Service explizit angefordert, aber nicht gefunden: %s" % service_name, "Kernel")
	return s

## Prüft, ob ein Service existiert.
func has_service(service_name: String) -> bool:
	return services.has(service_name.to_lower())

## Entfernt einen Service aus der Registry (wichtig bei _exit_tree von Nodes).
func unregister_service(service: Object) -> void:
	if not service: return
	
	var s_name := ""
	if "name" in service:
		s_name = str(service.name).to_lower()
	else:
		s_name = service.get_class().to_lower()
		
	if services.has(s_name):
		services.erase(s_name)
		Logger.log_debug("Service entfernt: %s" % s_name, "Kernel")