extends Node

## Kernel — Zentrale Service-Registry.
## Speichert Node-basierte Services (ServiceNode) und Pure Services (Service/RefCounted).
## Autoload: Kernel (muss nach Logger in project.godot stehen)

signal service_registered(service_name: String)
signal service_unregistered(service_name: String)

## Alle registrierten Services. Key: lowercase service name.
var _services: Dictionary = {}

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	Logger.log_debug("Kernel bereit.", "Kernel")

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Registriert einen Service (Node oder RefCounted).
## Wird automatisch von ServiceNode._ready() aufgerufen.
## Pure Services werden manuell von ServiceFactory registriert.
func register_service(service: Object) -> void:
	if not is_instance_valid(service):
		Logger.log_error("Versuch, ein ungültiges Objekt als Service zu registrieren!", "Kernel")
		return

	var s_name := _resolve_name(service)
	if s_name.is_empty():
		Logger.log_error("Service hat keinen auflösbaren Namen — Registrierung abgebrochen.", "Kernel")
		return

	if _services.has(s_name):
		Logger.log_warn("Service '%s' bereits registriert — wird überschrieben." % s_name, "Kernel")

	_services[s_name] = service
	Logger.log_debug("Service registriert: '%s' (%s)" % [s_name, service.get_class()], "Kernel")
	service_registered.emit(s_name)

## Holt einen Service über seinen Namen. Gibt null zurück wenn nicht gefunden.
func get_service(service_name: String) -> Object:
	var key := service_name.to_lower()
	var svc = _services.get(key)
	if not svc:
		Logger.log_error("Service nicht gefunden: '%s'" % service_name, "Kernel")
		return null
	if not is_instance_valid(svc):
		Logger.log_error("Service '%s' existiert in Registry, ist aber ungültig (freed?)." % service_name, "Kernel")
		_services.erase(key)
		return null
	return svc

## Prüft ob ein Service registriert ist ohne einen Error-Log auszulösen.
func has_service(service_name: String) -> bool:
	return _services.has(service_name.to_lower())

## Entfernt einen Service aus der Registry.
## Sollte in _exit_tree() von ServiceNode aufgerufen werden.
func unregister_service(service: Object) -> void:
	if not is_instance_valid(service):
		return

	var s_name := _resolve_name(service)
	if s_name.is_empty():
		return

	if _services.has(s_name):
		_services.erase(s_name)
		Logger.log_debug("Service entfernt: '%s'" % s_name, "Kernel")
		service_unregistered.emit(s_name)
	else:
		Logger.log_warn("unregister_service: '%s' war nicht registriert." % s_name, "Kernel")

## Gibt alle registrierten Service-Namen zurück (für Debugging).
func get_registered_names() -> Array[String]:
	var names: Array[String] = []
	for key in _services.keys():
		names.append(key)
	return names

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

## Löst den Registry-Schlüsselnamen eines Service-Objekts auf.
## Priorität: Node.name → get_class()
func _resolve_name(service: Object) -> String:
	if service is Node:
		var node_name := (service as Node).name
		if not node_name.is_empty():
			return node_name.to_lower()

	# RefCounted / Pure Service: hat kein Node.name
	# Wir nutzen get_class() als Fallback — nicht ideal, aber deterministisch.
	# Besser: Pure Services setzen service_name in ihrer Service-Basisklasse.
	var cls := service.get_class()
	if not cls.is_empty():
		return cls.to_lower()

	return ""