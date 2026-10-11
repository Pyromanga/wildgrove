# res://tests/unit/test_app_scope.gd
extends GutTest

## Unit-Tests für AppScope.
##
## AppScope ist RefCounted — kein SceneTree, direkt testbar.
##
## Abgedeckt:
##   - Initialisierung: registry wird korrekt gesetzt
##   - create_character_scope(): gibt CharacterScope zurück
##   - create_character_scope(): setzt has_character_scope() auf true
##   - create_character_scope(): zweiter Aufruf zerstört ersten Scope
##   - destroy_character_scope(): setzt has_character_scope() auf false
##   - destroy_character_scope(): auf leerem Scope kein Crash
##   - get_character_scope(): gibt nil zurück wenn kein Scope aktiv
##   - get_character_scope(): gibt aktiven Scope zurück
##   - get_service(): delegiert an registry

var _parent: Node

func before_each() -> void:
	_parent = add_child_autofree(Node.new())

# ─────────────────────────────────────────────────────────────────────────────
# Initialisierung
# ─────────────────────────────────────────────────────────────────────────────

func test_init_sets_registry() -> void:
	var reg   := ServiceRegistry.new()
	var scope := AppScope.new(reg)
	assert_eq(scope.registry, reg, "registry muss die übergebene Instanz sein")

func test_init_no_character_scope() -> void:
	var scope := AppScope.new(ServiceRegistry.new())
	assert_false(scope.has_character_scope(), "Frischer AppScope hat keinen CharacterScope")

# ─────────────────────────────────────────────────────────────────────────────
# create_character_scope()
# ─────────────────────────────────────────────────────────────────────────────

func test_create_character_scope_returns_instance() -> void:
	var scope := AppScope.new(ServiceRegistry.new())
	var cs    := scope.create_character_scope("p1", _parent)
	assert_not_null(cs, "create_character_scope() muss eine CharacterScope-Instanz zurückgeben")

func test_create_character_scope_sets_player_id() -> void:
	var scope := AppScope.new(ServiceRegistry.new())
	var cs    := scope.create_character_scope("hero_42", _parent)
	assert_eq(cs.player_id, "hero_42", "CharacterScope.player_id muss 'hero_42' sein")

func test_create_character_scope_sets_has_true() -> void:
	var scope := AppScope.new(ServiceRegistry.new())
	scope.create_character_scope("p1", _parent)
	assert_true(scope.has_character_scope(), "has_character_scope() muss true sein nach create")

func test_create_character_scope_second_call_replaces_first() -> void:
	var scope := AppScope.new(ServiceRegistry.new())
	var cs1   := scope.create_character_scope("p1", _parent)
	var cs2   := scope.create_character_scope("p2", _parent)
	assert_ne(cs1, cs2, "Zweiter create-Aufruf muss neuen Scope erzeugen")
	assert_eq(scope.get_character_scope(), cs2, "Aktiver Scope muss der neue sein")

func test_create_character_scope_second_call_has_new_player_id() -> void:
	var scope := AppScope.new(ServiceRegistry.new())
	scope.create_character_scope("p1", _parent)
	var cs2 := scope.create_character_scope("p2", _parent)
	assert_eq(cs2.player_id, "p2", "Neuer CharacterScope muss player_id 'p2' haben")

# ─────────────────────────────────────────────────────────────────────────────
# destroy_character_scope()
# ─────────────────────────────────────────────────────────────────────────────

func test_destroy_character_scope_sets_has_false() -> void:
	var scope := AppScope.new(ServiceRegistry.new())
	scope.create_character_scope("p1", _parent)
	scope.destroy_character_scope()
	assert_false(scope.has_character_scope(), "has_character_scope() muss false sein nach destroy")

func test_destroy_character_scope_on_empty_no_crash() -> void:
	var scope := AppScope.new(ServiceRegistry.new())
	# kein create_character_scope() vorher — darf nicht crashen
	scope.destroy_character_scope()
	assert_true(true, "destroy auf leerem AppScope darf nicht crashen")

func test_destroy_character_scope_clears_get() -> void:
	var scope := AppScope.new(ServiceRegistry.new())
	scope.create_character_scope("p1", _parent)
	scope.destroy_character_scope()
	assert_null(scope.get_character_scope(), "get_character_scope() muss null sein nach destroy")

# ─────────────────────────────────────────────────────────────────────────────
# get_character_scope()
# ─────────────────────────────────────────────────────────────────────────────

func test_get_character_scope_null_before_create() -> void:
	var scope := AppScope.new(ServiceRegistry.new())
	assert_null(scope.get_character_scope(), "get_character_scope() muss null sein vor create")

func test_get_character_scope_returns_active_scope() -> void:
	var scope := AppScope.new(ServiceRegistry.new())
	var cs    := scope.create_character_scope("p1", _parent)
	assert_eq(scope.get_character_scope(), cs, "get_character_scope() muss den aktiven Scope zurückgeben")

# ─────────────────────────────────────────────────────────────────────────────
# get_service()
# ─────────────────────────────────────────────────────────────────────────────

func test_get_service_delegates_to_registry() -> void:
	var reg   := ServiceRegistry.new()
	var scope := AppScope.new(reg)
	# Dummy-Service direkt in Registry registrieren
	var dummy := _make_dummy_service("testsvc")
	reg.register(dummy, _make_def("testsvc"))
	assert_eq(scope.get_service("testsvc"), dummy, "get_service() muss an registry delegieren")

func test_get_service_unknown_key_returns_null() -> void:
	var scope := AppScope.new(ServiceRegistry.new())
	assert_null(scope.get_service("nonexistent"), "Unbekannter Key muss null zurückgeben")

# ─────────────────────────────────────────────────────────────────────────────
# Abhängigkeitsregel: AppScope kennt CharacterScope nicht nach außen
# ─────────────────────────────────────────────────────────────────────────────

func test_app_scope_registry_isolated_from_character_registry() -> void:
	var app_reg   := ServiceRegistry.new()
	var scope     := AppScope.new(app_reg)
	var cs        := scope.create_character_scope("p1", _parent)
	# Ein Service in CharacterScope-Registry soll im AppScope nicht sichtbar sein
	var dummy := _make_dummy_service("char_svc")
	cs.registry.register(dummy, _make_def("char_svc"))
	assert_null(
		scope.get_service("char_svc"),
		"AppScope.get_service() darf nicht in CharacterScope-Registry schauen"
	)

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
