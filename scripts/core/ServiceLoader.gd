class_name ServiceLoader extends RefCounted

const LOG_CAT := "ServiceLoader"
const CONFIG_PATH := "res://config/bootstrap_config.tres"

# Wir brauchen das Array hier nicht mehr als konstante Liste im Code!
# Wir holen es dynamisch.

func _get_services_config() -> Array:
    var config = load(CONFIG_PATH) as BootstrapConfig
    if not config:
        Logger.log_error("BootstrapConfig nicht gefunden bei: " + CONFIG_PATH, LOG_CAT)
        return []
    
    # Wandle die Resource-Objekte in das Format um, das dein Code erwartet
    var list = []
    for s in config.services:
        list.append({ "name": s.name, "path": s.path, "deps": s.deps })
    return list

func get_required_names() -> Array[String]:
    var names: Array[String] = []
    for s in _get_services_config():
        names.append(s["name"])
    return names

# Im ServiceLoader...
func setup_services(parent: Node) -> void:
    var factory = ServiceFactory.new()
    var services = _get_config_list()
    
    for s in services:
        factory.create_service(s.name, s.path, parent)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Phase 2 + 3: init() und on_ready() in topologischer Reihenfolge aufrufen.
## Erst aufrufen wenn alle _ready()-Calls abgeschlossen sind (nach setup_services-Awaits).
func init_services() -> void:
	Logger.log_info("=== Phase 2+3: INIT gestartet ===", LOG_CAT)
	
	Logger.log_debug("Berechne topologische Sortierung...", LOG_CAT)
	var ordered := _topological_sort()
	
	if ordered.is_empty():
		Logger.log_error("Topologische Sortierung fehlgeschlagen — Zyklus oder leere Liste. Init abgebrochen!", LOG_CAT)
		return
	
	Logger.log_debug("Sortierte Reihenfolge: %s" % str(ordered), LOG_CAT)

	# Phase 2: init()
	Logger.log_info("--- Phase 2: init() ---", LOG_CAT)
	for svc_name in ordered:
		var service := _get_service_interface(svc_name)
		if not service:
			Logger.log_warn("Service '%s' nicht als ServiceBase castbar — übersprungen." % svc_name, LOG_CAT)
			continue
		Logger.log_debug("Rufe init() auf: '%s'..." % svc_name, LOG_CAT)
		service.init()
		Logger.log_debug("init() abgeschlossen: '%s'" % svc_name, LOG_CAT)
	Logger.log_info("--- Phase 2: alle init() abgeschlossen ---", LOG_CAT)

	# Phase 3: on_ready()
	Logger.log_info("--- Phase 3: on_ready() ---", LOG_CAT)
	for svc_name in ordered:
		var service := _get_service_interface(svc_name)
		if not service:
			Logger.log_warn("Service '%s' nicht als ServiceBase castbar — übersprungen." % svc_name, LOG_CAT)
			continue
		Logger.log_debug("Rufe on_ready() auf: '%s'..." % svc_name, LOG_CAT)
		service.on_ready()
		Logger.log_debug("on_ready() abgeschlossen: '%s'" % svc_name, LOG_CAT)
	Logger.log_info("--- Phase 3: alle on_ready() abgeschlossen ---", LOG_CAT)

	Logger.log_info("=== Phase 2+3: INIT vollständig abgeschlossen ===", LOG_CAT)

# ─────────────────────────────────────────────
# Private Helpers
# ─────────────────────────────────────────────

func _create(service_name: String, parent: Node, path: String) -> void:
	Logger.log_debug("Lade Script: '%s' von '%s'..." % [service_name, path], LOG_CAT)
	
	var script = load(path)
	if not script:
		Logger.log_error("Script nicht gefunden: '%s' — Service '%s' wird nicht erstellt!" % [path, service_name], LOG_CAT)
		return
	
	Logger.log_debug("Script geladen. Erstelle Node...", LOG_CAT)
	var node := Node.new()
	node.name = service_name
	node.set_script(script)
	
	Logger.log_debug("Füge '%s' dem Tree hinzu (parent: '%s')..." % [service_name, parent.name], LOG_CAT)
	parent.add_child(node)
	# Ab hier läuft ServiceBase._ready() → Kernel.register_service()
	Logger.log_debug("Node '%s' im Tree. _ready() wird vom Engine aufgerufen." % service_name, LOG_CAT)

func _get_service_interface(svc_name: String) -> Object:
    var obj = Kernel.get_service(svc_name)
    if not obj:
        Logger.log_error("Service '%s' im Kernel nicht gefunden!" % svc_name, LOG_CAT)
        return null
    
    # Hier der Trick: Wir prüfen nicht auf eine Klasse, sondern auf das Vorhandensein der Methoden
    if obj.has_method("init") and obj.has_method("on_ready"):
        return obj
        
    Logger.log_error("Service '%s' hat kein gültiges Service-Interface!" % svc_name, LOG_CAT)
    return null

# ─────────────────────────────────────────────
# Topologische Sortierung (Kahn's Algorithm)
# ─────────────────────────────────────────────

func _topological_sort() -> Array[String]:
	Logger.log_debug("Starte Kahn's Algorithm...", LOG_CAT)
	
	# In-degree aufbauen (wie viele unerfüllte Deps hat jeder Service)
	var in_degree: Dictionary = {}
	var adj: Dictionary = {}  # dep → [services die dep brauchen]
	var services = _get_config_list()
	
	for s in _get_s:
		in_degree[s["name"]] = 0
		adj[s["name"]] = []
	
	for s in services:
		for dep in s["deps"]:
			if not adj.has(dep):
				Logger.log_error("Unbekannte Dependency '%s' in Service '%s'!" % [dep, s["name"]], LOG_CAT)
				return []
			adj[dep].append(s["name"])
			in_degree[s["name"]] += 1
	
	Logger.log_debug("In-Degrees: %s" % str(in_degree), LOG_CAT)
	
	# Queue mit allen Services ohne Abhängigkeiten starten
	var queue: Array[String] = []
	for svc_name in in_degree:
		if in_degree[svc_name] == 0:
			queue.append(svc_name)
	
	Logger.log_debug("Start-Queue (keine Deps): %s" % str(queue), LOG_CAT)
	
	var result: Array[String] = []
	
	while not queue.is_empty():
		var current: String = queue.pop_front()
		result.append(current)
		Logger.log_debug("Verarbeite: '%s' → Nachfolger: %s" % [current, str(adj[current])], LOG_CAT)
		
		for neighbor in adj[current]:
			in_degree[neighbor] -= 1
			Logger.log_debug("  in_degree[%s] jetzt: %d" % [neighbor, in_degree[neighbor]], LOG_CAT)
			if in_degree[neighbor] == 0:
				Logger.log_debug("  '%s' bereit (alle Deps erfüllt) → Queue" % neighbor, LOG_CAT)
				queue.append(neighbor)
	
	# Zyklus-Check: Wenn nicht alle Services in result → Zyklus vorhanden
	if result.size() != services.size():
		var missing: Array[String] = []
		for s in services:
			if not result.has(s["name"]):
				missing.append(s["name"])
		Logger.log_error("Zyklus erkannt! Folgende Services konnten nicht sortiert werden: %s" % str(missing), LOG_CAT)
		return []
	
	Logger.log_debug("Topologische Sortierung erfolgreich: %s" % str(result), LOG_CAT)
	return result