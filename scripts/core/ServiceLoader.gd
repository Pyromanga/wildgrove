class_name ServiceLoader extends RefCounted

## ServiceLoader — Bootstrap-Orchestrator.
## Phase 1 (setup_services):  Lädt Config, instanziiert alle Services via ServiceFactory.
## Phase 2 (init_services):   Ruft init() in topologischer Reihenfolge auf.
## Phase 3 (on_ready_services): Ruft on_ready() in topologischer Reihenfolge auf.
##
## Aufruf aus Main.gd:
##   var loader = ServiceLoader.new()
##   loader.setup_services(self)      # synchron
##   await get_tree().process_frame   # sicherstellen dass alle _ready() gelaufen sind
##   loader.init_services()
##   loader.on_ready_services()

const LOG_CAT := "ServiceLoader"
const CONFIG_PATH := "res://config/bootstrap_config.tres"

# Cache damit wir die Config nicht mehrfach laden
var _config_cache: Array[ServiceDefinition] = []

# ─────────────────────────────────────────────
# Phase 1
# ─────────────────────────────────────────────

## Lädt alle Services aus der Config und hängt sie in den Baum.
## parent: Normalerweise Main-Node.
func setup_services(parent: Node) -> void:
	Logger.log_info("=== Phase 1: SETUP gestartet ===", LOG_CAT)
	var definitions := _get_config()

	if definitions.is_empty():
		Logger.log_error("Keine Service-Definitionen gefunden — Bootstrap abgebrochen!", LOG_CAT)
		return

	var factory := ServiceFactory.new()
	var success_count := 0

	for definition in definitions:
		var instance = factory.create_service(definition, parent)
		if instance:
			success_count += 1
		else:
			Logger.log_error("Service '%s' konnte nicht erstellt werden!" % definition.service_name, LOG_CAT)

	Logger.log_info(
		"=== Phase 1: SETUP abgeschlossen (%d/%d Services erstellt) ===" % [success_count, definitions.size()],
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Phase 2
# ─────────────────────────────────────────────

## Ruft init() auf allen Services in Dependency-Reihenfolge auf.
## Erst aufrufen nachdem alle _ready()-Calls gelaufen sind!
func init_services() -> void:
	Logger.log_info("=== Phase 2: INIT gestartet ===", LOG_CAT)
	var ordered := _topological_sort()

	if ordered.is_empty():
		Logger.log_error("Topologische Sortierung fehlgeschlagen — Init abgebrochen!", LOG_CAT)
		return

	Logger.log_debug("Init-Reihenfolge: %s" % str(ordered), LOG_CAT)

	for svc_name in ordered:
		var service := _get_lifecycle_service(svc_name)
		if not service:
			continue
		Logger.log_debug("init() → '%s'" % svc_name, LOG_CAT)
		service.call("init")
		Logger.log_debug("init() ✓ '%s'" % svc_name, LOG_CAT)

	Logger.log_info("=== Phase 2: INIT abgeschlossen ===", LOG_CAT)

# ─────────────────────────────────────────────
# Phase 3
# ─────────────────────────────────────────────

## Ruft on_ready() auf allen Services in Dependency-Reihenfolge auf.
func on_ready_services() -> void:
	Logger.log_info("=== Phase 3: ON_READY gestartet ===", LOG_CAT)
	var ordered := _topological_sort()

	if ordered.is_empty():
		Logger.log_error("Topologische Sortierung fehlgeschlagen — on_ready abgebrochen!", LOG_CAT)
		return

	for svc_name in ordered:
		var service := _get_lifecycle_service(svc_name)
		if not service:
			continue
		Logger.log_debug("on_ready() → '%s'" % svc_name, LOG_CAT)
		service.call("on_ready")
		Logger.log_debug("on_ready() ✓ '%s'" % svc_name, LOG_CAT)

	Logger.log_info("=== Phase 3: ON_READY abgeschlossen ===", LOG_CAT)

# ─────────────────────────────────────────────
# Topologische Sortierung (Kahn's Algorithm)
# ─────────────────────────────────────────────

func _topological_sort() -> Array[String]:
	Logger.log_debug("Starte Kahn's Algorithm...", LOG_CAT)

	var definitions := _get_config()
	if definitions.is_empty():
		Logger.log_error("Keine Definitionen für topologische Sortierung!", LOG_CAT)
		return []

	# Bekannte Service-Namen aufbauen
	var known_names: Dictionary = {}
	for d in definitions:
		known_names[d.service_name.to_lower()] = true

	# In-Degree und Adjazenzliste aufbauen
	var in_degree: Dictionary = {}
	var adj: Dictionary = {}   # dep_name → [services die dep brauchen]

	for d in definitions:
		var key := d.service_name.to_lower()
		in_degree[key] = 0
		adj[key] = []

	for d in definitions:
		var key := d.service_name.to_lower()
		for dep_raw in d.deps:
			var dep := dep_raw.to_lower()
			if not known_names.has(dep):
				Logger.log_error(
					"Unbekannte Dependency '%s' in Service '%s'!" % [dep, d.service_name],
					LOG_CAT
				)
				return []
			adj[dep].append(key)
			in_degree[key] += 1

	# Queue mit Services ohne Abhängigkeiten starten
	var queue: Array[String] = []
	for svc_name in in_degree:
		if in_degree[svc_name] == 0:
			queue.append(svc_name)

	Logger.log_debug("Start-Queue (keine Deps): %s" % str(queue), LOG_CAT)

	var result: Array[String] = []

	while not queue.is_empty():
		var current: String = queue.pop_front()
		result.append(current)

		for neighbor in adj[current]:
			in_degree[neighbor] -= 1
			if in_degree[neighbor] == 0:
				queue.append(neighbor)

	# Zyklus-Check
	if result.size() != definitions.size():
		var missing: Array[String] = []
		var result_set: Dictionary = {}
		for r in result:
			result_set[r] = true
		for d in definitions:
			if not result_set.has(d.service_name.to_lower()):
				missing.append(d.service_name)
		Logger.log_error(
			"Zyklus erkannt! Services die nicht sortiert werden konnten: %s" % str(missing),
			LOG_CAT
		)
		return []

	Logger.log_debug("Sortierung erfolgreich: %s" % str(result), LOG_CAT)
	return result

# ─────────────────────────────────────────────
# Private Helpers
# ─────────────────────────────────────────────

## Lädt und cached die BootstrapConfig.
## Gibt ein leeres Array bei Fehler zurück — nie null.
func _get_config() -> Array[ServiceDefinition]:
	if not _config_cache.is_empty():
		return _config_cache

	var config = load(CONFIG_PATH) as BootstrapConfig
	if not config:
		# push_error damit das auch ohne Logger sichtbar ist
		push_error("[ServiceLoader] BootstrapConfig nicht gefunden: '%s'" % CONFIG_PATH)
		Logger.log_error("BootstrapConfig nicht gefunden: '%s'" % CONFIG_PATH, LOG_CAT)
		return []

	if config.services.is_empty():
		Logger.log_warn("BootstrapConfig ist leer — keine Services definiert.", LOG_CAT)
		return []

	_config_cache = config.services
	Logger.log_debug("Config geladen: %d Service-Definitionen." % _config_cache.size(), LOG_CAT)
	return _config_cache

## Holt ein Service-Objekt aus dem Kernel und prüft ob es das Lifecycle-Interface hat.
## Gibt null zurück wenn nicht gefunden oder Interface fehlt.
func _get_lifecycle_service(svc_name: String) -> Object:
	var obj := Kernel.get_service(svc_name)
	if not obj:
		# Kernel.get_service loggt den Error bereits
		return null

	if not obj.has_method("init") or not obj.has_method("on_ready"):
		Logger.log_warn(
			"Service '%s' hat kein Lifecycle-Interface (init/on_ready fehlt) — übersprungen." % svc_name,
			LOG_CAT
		)
		return null

	return obj