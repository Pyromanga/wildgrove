# res://tests/unit/test_service_deps_declared.gd
extends GutTest

## Architektur-Wächter: JEDE Dependency, die ein Service in configure() über
## deps.get_optional()/deps.require() liest, MUSS in seiner ServiceDefinition
## (config/BootstrapConfig.tres: required_deps/optional_deps) deklariert sein.
##
## Hintergrund (Quest-Bug): ServiceInitializer reicht jedem Service NUR die deklarierten
## Deps. Eine nicht deklarierte optionale Dep liefert get_optional() lautlos als null —
## WorldService las so "quest" nie, alle Quest-NPC-Dialoge blieben wirkungslos, ohne
## eine einzige Fehlermeldung. Dieser Test macht diese Fehlerklasse zur Build-Zeit sichtbar.

## network_bridge wird in Produktion NACH configure() über inject_network_bridge() gesetzt
## (BootPipeline Phase C8), weil NetworkBridge selbst von allen anderen abhängt (Zyklus).
## Der configure()-Read ist nur der Test-Injektionspfad (Tests übergeben ihn per deps) —
## bekannte Altlast, siehe docs/architecture-hygiene.md.
const IGNORED_KEYS: Array[String] = ["network_bridge"]

const READ_PATTERN := "deps\\.(?:get_optional|require|has)\\(\\s*ServiceKeys\\.([A-Z0-9_]+)\\s*\\)"

func _key_value(const_name: String) -> String:
	var map: Dictionary = (ServiceKeys as Script).get_script_constant_map()
	return String(map.get(const_name, "")).to_lower()

func _undeclared_for(def: ServiceDefinition) -> Array[String]:
	var missing: Array[String] = []
	var f := FileAccess.open(def.path, FileAccess.READ)
	if f == null:
		return missing   # Pfad-Fehler meldet test_service_validator
	var source := f.get_as_text()
	var re := RegEx.new()
	re.compile(READ_PATTERN)
	var declared: Array[String] = []
	for d in def.all_deps():
		declared.append(d.to_lower())
	for m in re.search_all(source):
		var key := _key_value(m.get_string(1))
		if key.is_empty():
			missing.append("ServiceKeys.%s (unbekannte Konstante)" % m.get_string(1))
		elif IGNORED_KEYS.has(key):
			continue
		elif not declared.has(key) and not missing.has(key):
			missing.append(key)
	return missing

func test_every_dep_read_in_configure_is_declared() -> void:
	var cfg: BootstrapConfig = load("res://config/BootstrapConfig.tres")
	assert_not_null(cfg)
	var all_defs: Array[ServiceDefinition] = []
	all_defs.append_array(cfg.global_services)
	all_defs.append_array(cfg.session_services)
	assert_gt(all_defs.size(), 0)
	for def in all_defs:
		var missing := _undeclared_for(def)
		assert_eq(missing.size(), 0,
			"Service '%s' liest nicht deklarierte Deps %s — in BootstrapConfig.tres required_deps/optional_deps ergänzen." % [def.service_name, str(missing)])

func test_world_service_declares_quest() -> void:
	# Direkte Regression zum Quest-NPC-Bug.
	var cfg: BootstrapConfig = load("res://config/BootstrapConfig.tres")
	for def in cfg.session_services:
		if def.service_name == "world":
			assert_true(ServiceKeys.QUEST in def.all_deps(), "world muss 'quest' deklarieren (EntityContext.get_quest_service)")
			return
	fail_test("world-Service nicht in session_services gefunden")
