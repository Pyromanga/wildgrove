# res://tests/unit/test_world_scope.gd
extends GutTest

## Unit-Tests für WorldScope.
##
## Abgedeckt:
##   - Initialisierung: alle drei Registries und world_root korrekt gesetzt
##   - get_service(): delegiert an world-registry
##   - get_character_service(): delegiert an char-registry
##   - get_app_service(): delegiert an app-registry
##   - get_world_root(): gibt root zurück
##   - destroy(): setzt world_root auf null
##   - destroy(): zweiter Aufruf kein Crash
##   - Dep-Richtung: WorldScope kennt nach oben, nicht nach unten

var _app_reg:  ServiceRegistry
var _char_reg: ServiceRegistry
var _world_reg: ServiceRegistry
var _world_root: Node3D

func before_each() -> void:
	_app_reg   = ServiceRegistry.new()
	_char_reg  = ServiceRegistry.new()
	_world_reg = ServiceRegistry.new()
	_world_root = add_child_autofree(Node3D.new())

func _make_world_scope() -> WorldScope:
	var parent: Node = add_child_autofree(Node.new())
	return WorldScope.new(_world_reg, _char_reg, _app_reg, _world_root, parent)

# ─────────────────────────────────────────────────────────────────────────────
# Initialisierung
# ─────────────────────────────────────────────────────────────────────────────

func test_init_sets_registry() -> void:
	var ws := _make_world_scope()
	assert_eq(ws.registry, _world_reg, "registry muss die world-registry sein")

func test_init_sets_char_registry() -> void:
	var ws := _make_world_scope()
	assert_eq(ws.char_registry, _char_reg, "char_registry muss korrekt gesetzt sein")

func test_init_sets_app_registry() -> void:
	var ws := _make_world_scope()
	assert_eq(ws.app_registry, _app_reg, "app_registry muss korrekt gesetzt sein")

func test_init_sets_world_root() -> void:
	var ws := _make_world_scope()
	assert_eq(ws.world_root, _world_root, "world_root muss korrekt gesetzt sein")

# ─────────────────────────────────────────────────────────────────────────────
# get_service() — eigene World-Registry
# ─────────────────────────────────────────────────────────────────────────────

func test_get_service_delegates_to_world_registry() -> void:
	var ws    := _make_world_scope()
	var dummy := _make_dummy_service("combat")
	_world_reg.register(dummy, _make_def("combat"))
	assert_eq(ws.get_service("combat"), dummy, "get_service() muss an world-registry delegieren")

func test_get_service_does_not_see_char_registry() -> void:
	var ws    := _make_world_scope()
	var dummy := _make_dummy_service("inventory")
	_char_reg.register(dummy, _make_def("inventory"))
	assert_null(
		ws.get_service("inventory"),
		"get_service() darf nicht in char_registry schauen"
	)

func test_get_service_unknown_returns_null() -> void:
	var ws := _make_world_scope()
	assert_null(ws.get_service("nonexistent"), "Unbekannter Key muss null zurückgeben")

# ─────────────────────────────────────────────────────────────────────────────
# get_character_service() — Cross-Scope nach oben ✅
# ─────────────────────────────────────────────────────────────────────────────

func test_get_character_service_delegates_to_char_registry() -> void:
	var ws    := _make_world_scope()
	var dummy := _make_dummy_service("questservice")
	_char_reg.register(dummy, _make_def("questservice"))
	assert_eq(
		ws.get_character_service("questservice"),
		dummy,
		"get_character_service() muss an char_registry delegieren"
	)

func test_get_character_service_unknown_returns_null() -> void:
	var ws := _make_world_scope()
	assert_null(ws.get_character_service("nope"), "Unbekannter Key muss null zurückgeben")

# ─────────────────────────────────────────────────────────────────────────────
# get_app_service() — Cross-Scope nach oben ✅
# ─────────────────────────────────────────────────────────────────────────────

func test_get_app_service_delegates_to_app_registry() -> void:
	var ws    := _make_world_scope()
	var dummy := _make_dummy_service("savesystem")
	_app_reg.register(dummy, _make_def("savesystem"))
	assert_eq(
		ws.get_app_service("savesystem"),
		dummy,
		"get_app_service() muss an app_registry delegieren"
	)

func test_get_app_service_unknown_returns_null() -> void:
	var ws := _make_world_scope()
	assert_null(ws.get_app_service("nope"), "Unbekannter Key muss null zurückgeben")

# ─────────────────────────────────────────────────────────────────────────────
# get_world_root()
# ─────────────────────────────────────────────────────────────────────────────

func test_get_world_root_returns_root() -> void:
	var ws := _make_world_scope()
	assert_eq(ws.get_world_root(), _world_root, "get_world_root() muss den root zurückgeben")

func test_get_world_root_null_after_destroy() -> void:
	var ws := _make_world_scope()
	ws.destroy()
	assert_null(ws.get_world_root(), "get_world_root() muss null sein nach destroy()")

# ─────────────────────────────────────────────────────────────────────────────
# destroy()
# ─────────────────────────────────────────────────────────────────────────────

func test_destroy_sets_world_root_null() -> void:
	var ws := _make_world_scope()
	ws.destroy()
	assert_null(ws.world_root, "world_root muss null sein nach destroy()")

func test_destroy_twice_no_crash() -> void:
	var ws := _make_world_scope()
	ws.destroy()
	ws.destroy()
	assert_true(true, "Zweites destroy() darf nicht crashen")

# ─────────────────────────────────────────────────────────────────────────────
# Abhängigkeitsregel: WorldScope darf nicht nach unten schauen
# (kein vierter Scope unter World — zukunftssicher dokumentiert)
# ─────────────────────────────────────────────────────────────────────────────

func test_world_scope_has_no_create_child_scope_method() -> void:
	var ws := _make_world_scope()
	assert_false(
		ws.has_method("create_child_scope"),
		"WorldScope darf keine create_child_scope()-Methode haben — kein Scope unter World"
	)

# ─────────────────────────────────────────────────────────────────────────────
# Scope-Isolation: Registries sind unabhängig
# ─────────────────────────────────────────────────────────────────────────────

func test_three_registries_fully_isolated() -> void:
	var ws := _make_world_scope()

	var app_svc   := _make_dummy_service("app_svc")
	var char_svc  := _make_dummy_service("char_svc")
	var world_svc := _make_dummy_service("world_svc")

	_app_reg.register(app_svc,   _make_def("app_svc"))
	_char_reg.register(char_svc, _make_def("char_svc"))
	_world_reg.register(world_svc, _make_def("world_svc"))

	# Jeder Accessor liefert nur seinen eigenen Service
	assert_eq(ws.get_app_service("app_svc"),       app_svc,   "app_reg korrekt")
	assert_eq(ws.get_character_service("char_svc"), char_svc,  "char_reg korrekt")
	assert_eq(ws.get_service("world_svc"),          world_svc, "world_reg korrekt")

	# Keine Kreuzung
	assert_null(ws.get_service("app_svc"),             "world_reg darf app_svc nicht sehen")
	assert_null(ws.get_service("char_svc"),             "world_reg darf char_svc nicht sehen")
	assert_null(ws.get_character_service("world_svc"),  "char_reg darf world_svc nicht sehen")
	assert_null(ws.get_app_service("world_svc"),        "app_reg darf world_svc nicht sehen")

# ─────────────────────────────────────────────────────────────────────────────
# Hilfsmethoden
# ─────────────────────────────────────────────────────────────────────────────

func _make_def(svc_name: String) -> ServiceDefinition:
	var d          := ServiceDefinition.new()
	d.service_name  = svc_name
	d.path          = "res://scripts/platform/Service.gd"
	d.required_deps = []
	return d

func _make_dummy_service(svc_name: String) -> Service:
	var s          := Service.new()
	s.service_name  = svc_name
	return s
