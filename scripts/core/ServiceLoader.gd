class_name ServiceLoader extends RefCounted

## ServiceLoader — Bootstrap-Orchestrator.
## Phase 1: setup_services  — instanziiert alle Services
## Phase 2: init_services   — ruft init() in Dep-Reihenfolge auf
## Phase 3: on_ready_services — ruft on_ready() auf
## Phase 4: bind_shortcuts  — Kernel-Shortcuts setzen

const LOG_CAT    := "ServiceLoader"
const CONFIG_PATH := "res://config/bootstrap_config.tres"

var _config_cache: Array[ServiceDefinition] = []

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func setup_services(parent: Node) -> void:
	Logger.log_info("=== Phase 1: SETUP ===", LOG_CAT)
	var defs := _get_config()
	if defs.is_empty():
		Logger.log_error("Keine Service-Definitionen — Bootstrap abgebrochen!", LOG_CAT)
		return

	var factory := ServiceFactory.new()
	var ok := 0
	for def in defs:
		if factory.create_service(def, parent):
			ok += 1
		else:
			Logger.log_error("Konnte '%s' nicht erstellen!" % def.service_name, LOG_CAT)

	Logger.log_info("Phase 1 fertig: %d/%d Services." % [ok, defs.size()], LOG_CAT)

func init_services() -> void:
	Logger.log_info("=== Phase 2: INIT ===", LOG_CAT)
	_run_lifecycle("init")
	Logger.log_info("Phase 2 fertig.", LOG_CAT)

func on_ready_services() -> void:
	Logger.log_info("=== Phase 3: ON_READY ===", LOG_CAT)
	_run_lifecycle("on_ready")
	Logger.log_info("Phase 3 fertig.", LOG_CAT)

## Phase 4: Kernel-Shortcuts binden.
## Immer nach on_ready_services() aufrufen.
func bind_shortcuts() -> void:
	Logger.log_info("=== Phase 4: BIND SHORTCUTS ===", LOG_CAT)
	Kernel.bind_shortcuts()

# ─────────────────────────────────────────────
# Lifecycle-Helper
# ─────────────────────────────────────────────

func _run_lifecycle(method: String) -> void:
	var ordered := _topological_sort()
	if ordered.is_empty():
		Logger.log_error("Topologische Sortierung fehlgeschlagen — %s abgebrochen!" % method, LOG_CAT)
		return

	for svc_name in ordered:
		var svc := _get_lifecycle_service(svc_name)
		if not svc:
			continue
		svc.call(method)

func _get_lifecycle_service(svc_name: String) -> Object:
	var obj := Kernel.get_service(svc_name)
	if not obj:
		return null
	if not obj.has_method("init") or not obj.has_method("on_ready"):
		Logger.log_warn("'%s' hat kein Lifecycle-Interface — übersprungen." % svc_name, LOG_CAT)
		return null
	return obj

# ─────────────────────────────────────────────
# Topologische Sortierung (Kahn's Algorithm)
# ─────────────────────────────────────────────

func _topological_sort() -> Array[String]:
	var defs := _get_config()
	if defs.is_empty():
		return []

	var known: Dictionary = {}
	for d in defs:
		known[d.service_name.to_lower()] = true

	var in_degree: Dictionary = {}
	var adj: Dictionary = {}
	for d in defs:
		var key := d.service_name.to_lower()
		in_degree[key] = 0
		adj[key] = []

	for d in defs:
		var key := d.service_name.to_lower()
		for dep_raw in d.deps:
			var dep := dep_raw.to_lower()
			if not known.has(dep):
				Logger.log_error("Unbekannte Dep '%s' in '%s'!" % [dep, d.service_name], LOG_CAT)
				return []
			adj[dep].append(key)
			in_degree[key] += 1

	var queue: Array[String] = []
	for name in in_degree:
		if in_degree[name] == 0:
			queue.append(name)

	var result: Array[String] = []
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		result.append(cur)
		for neighbor in adj[cur]:
			in_degree[neighbor] -= 1
			if in_degree[neighbor] == 0:
				queue.append(neighbor)

	if result.size() != defs.size():
		var result_set: Dictionary = {}
		for r in result:
			result_set[r] = true
		var missing: Array[String] = []
		for d in defs:
			if not result_set.has(d.service_name.to_lower()):
				missing.append(d.service_name)
		Logger.log_error("Zyklus erkannt! Betroffen: %s" % str(missing), LOG_CAT)
		return []

	return result

# ─────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────

func _get_config() -> Array[ServiceDefinition]:
	if not _config_cache.is_empty():
		return _config_cache

	var config := load(CONFIG_PATH) as BootstrapConfig
	if not config:
		push_error("[ServiceLoader] BootstrapConfig nicht gefunden: '%s'" % CONFIG_PATH)
		Logger.log_error("BootstrapConfig nicht gefunden: '%s'" % CONFIG_PATH, LOG_CAT)
		return []

	if config.services.is_empty():
		Logger.log_warn("BootstrapConfig ist leer.", LOG_CAT)
		return []

	_config_cache = config.services
	return _config_cache