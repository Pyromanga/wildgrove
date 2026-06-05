class_name ServiceRegistry extends RefCounted

## ServiceRegistry — Internes Service-Verzeichnis & Definitions-Speicher.
## Hält sowohl die Live-Instanzen als auch deren Baupläne (Definitionen).

signal service_registered(service_name: String)
signal service_unregistered(service_name: String)

const LOG_CAT := "ServiceRegistry"

var _services: Dictionary = {}
var _definitions: Dictionary = {}  # Speichert die ServiceDefinition Objekte

# ─────────────────────────────────────────────
# Schreiben
# ─────────────────────────────────────────────


## Registriert einen Service zusammen mit seinem Bauplan.
func register(service: Object, definition: ServiceDefinition) -> void:
	if not is_instance_valid(service):
		Logger.log_error("Ungültiges Objekt bei Registrierung.", LOG_CAT)
		return

	if definition == null or definition.service_name.is_empty():
		Logger.log_error("Registrierung fehlgeschlagen: Definition ungültig.", LOG_CAT)
		return

	var key := definition.service_name.to_lower()

	if _services.has(key):
		Logger.log_warn("Service '%s' wird überschrieben." % key, LOG_CAT)

	_services[key] = service
	_definitions[key] = definition

	Logger.log_debug("Registriert: '%s'" % key, LOG_CAT)
	service_registered.emit(key)


func unregister(service_name: String) -> void:
	var key := service_name.to_lower()
	if _services.erase(key):
		_definitions.erase(key)
		Logger.log_debug("Entfernt: '%s'" % key, LOG_CAT)
		service_unregistered.emit(key)


func clear() -> void:
	_services.clear()
	_definitions.clear()
	Logger.log_debug("Registry geleert.", LOG_CAT)


# ─────────────────────────────────────────────
# Lesen
# ─────────────────────────────────────────────


## Gibt die Live-Instanz eines Services zurück.
func get_service(service_name: String) -> Object:
	var key := service_name.to_lower()
	var svc: Object = _services.get(key)

	if svc == null:
		return null  # Silent fail für den Initializer-Check

	if not is_instance_valid(svc):
		Logger.log_error(
			"Service '%s' ist bereits freigegeben (Stale Reference)." % service_name, LOG_CAT
		)
		_services.erase(key)
		_definitions.erase(key)
		return null

	return svc


## NEU: Gibt den Bauplan zurück (wichtig für Dependency Injection).
func get_definition(service_name: String) -> ServiceDefinition:
	return _definitions.get(service_name.to_lower()) as ServiceDefinition


func has_service(service_name: String) -> bool:
	return _services.has(service_name.to_lower())


func get_all_names() -> Array[String]:
	var names: Array[String] = []
	for key in _services.keys():
		names.append(key)
	return names
