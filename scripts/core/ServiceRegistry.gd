# res://scripts/core/services/ServiceRegistry.gd
class_name ServiceRegistry extends RefCounted

## ServiceRegistry — Internes Service-Verzeichnis.
##
## Nur der ServiceOrchestrator und seine Pipeline-Klassen sprechen direkt
## mit der Registry. Gameplay-Code nutzt den DependencyContainer.
##
## Schlüssel sind immer lowercase (service_name.to_lower()).

signal service_registered(service_name: String)
signal service_unregistered(service_name: String)

const LOG_CAT := "ServiceRegistry"

var _services: Dictionary = {}

# ─────────────────────────────────────────────
# Schreiben
# ─────────────────────────────────────────────

func register(service: Object) -> void:
	if not is_instance_valid(service):
		Logger.log_error("Ungültiges Objekt — Registrierung abgebrochen.", LOG_CAT)
		return

	var key := _resolve_key(service)
	if key.is_empty():
		Logger.log_error("Service hat keinen auflösbaren Namen — Registrierung abgebrochen.", LOG_CAT)
		return

	if _services.has(key):
		Logger.log_warn("Service '%s' wird überschrieben." % key, LOG_CAT)

	_services[key] = service
	Logger.log_debug("Registriert: '%s'" % key, LOG_CAT)
	service_registered.emit(key)

func unregister(service: Object) -> void:
	if not is_instance_valid(service):
		return
	var key := _resolve_key(service)
	if key.is_empty():
		return
	if _services.erase(key):
		Logger.log_debug("Entfernt: '%s'" % key, LOG_CAT)
		service_unregistered.emit(key)

func clear() -> void:
	_services.clear()
	Logger.log_debug("Registry geleert.", LOG_CAT)

# ─────────────────────────────────────────────
# Lesen
# ─────────────────────────────────────────────

func get_service(service_name: String) -> Object:
	var key := service_name.to_lower()
	var svc: Object = _services.get(key)
	if svc == null:
		Logger.log_error("Service nicht gefunden: '%s'" % service_name, LOG_CAT)
		return null
	if not is_instance_valid(svc):
		Logger.log_error("Service '%s' ist bereits freigegeben." % service_name, LOG_CAT)
		_services.erase(key)
		return null
	return svc

func has_service(service_name: String) -> bool:
	return _services.has(service_name.to_lower())

func get_all() -> Array[Object]:
	var result: Array[Object] = []
	for svc in _services.values():
		if is_instance_valid(svc):
			result.append(svc)
	return result

func get_all_names() -> Array[String]:
	var names: Array[String] = []
	for key in _services.keys():
		names.append(key)
	return names

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _resolve_key(service: Object) -> String:
	if service is Node:
		var n := (service as Node).name
		if not n.is_empty():
			return n.to_lower()
	if service is Service:
		var sn := (service as Service).service_name
		if not sn.is_empty():
			return sn.to_lower()
	var cls := service.get_class()
	return cls.to_lower() if not cls.is_empty() else ""