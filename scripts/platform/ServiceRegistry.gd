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
## Interface-Assertions feuern in Phase 3 (Registrierung), nicht erst beim configure()-Aufruf.
## Ein Tippfehler in einem Methodennamen ist damit sofort sichtbar (ADR-011 / H-06).
func register(service: Object, definition: ServiceDefinition) -> void:
	if not is_instance_valid(service):
		AppLogger.log_error("Ungültiges Objekt bei Registrierung.", LOG_CAT)
		return

	if definition == null or definition.service_name.is_empty():
		AppLogger.log_error("Registrierung fehlgeschlagen: Definition ungültig.", LOG_CAT)
		return

	assert(service.has_method("configure"),
		"Interface-Verletzung: '%s' fehlt configure(). Erbt es von Service oder ServiceNode?" \
		% definition.service_name)
	assert(service.has_method("on_ready"),
		"Interface-Verletzung: '%s' fehlt on_ready(). Erbt es von Service oder ServiceNode?" \
		% definition.service_name)
	assert(service.has_method("on_cleanup"),
		"Interface-Verletzung: '%s' fehlt on_cleanup(). Erbt es von Service oder ServiceNode?" \
		% definition.service_name)

	var key := definition.service_name.to_lower()

	if _services.has(key):
		AppLogger.log_warn("Service '%s' wird überschrieben." % key, LOG_CAT)

	_services[key] = service
	_definitions[key] = definition

	AppLogger.log_debug("Registriert: '%s'" % key, LOG_CAT)
	service_registered.emit(key)

func unregister(service_name: String) -> void:
	var key := service_name.to_lower()
	if _services.erase(key):
		_definitions.erase(key)
		AppLogger.log_debug("Entfernt: '%s'" % key, LOG_CAT)
		service_unregistered.emit(key)

## Registriert eine injectable Resource (.tres/.res) ohne Interface-Assertions.
## Resources implementieren configure()/on_ready()/on_cleanup() NICHT — das ist erwartet (ADR-011).
func register_resource(resource: Object, resource_name: String) -> void:
	if not is_instance_valid(resource):
		AppLogger.log_error("Ungültige Resource bei Registrierung: '%s'." % resource_name, LOG_CAT)
		return

	if resource_name.is_empty():
		AppLogger.log_error("register_resource: resource_name darf nicht leer sein.", LOG_CAT)
		return

	var key := resource_name.to_lower()

	if _services.has(key):
		AppLogger.log_warn("Resource '%s' wird überschrieben." % key, LOG_CAT)

	_services[key] = resource
	# Keine Definition für Resources — _definitions bleibt sauber.
	AppLogger.log_debug("Resource registriert: '%s'" % key, LOG_CAT)
	service_registered.emit(key)

func clear() -> void:
	_services.clear()
	_definitions.clear()
	AppLogger.log_debug("Registry geleert.", LOG_CAT)

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
		AppLogger.log_error(
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
