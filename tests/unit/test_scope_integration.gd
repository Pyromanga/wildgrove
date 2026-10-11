# res://tests/unit/test_scope_integration.gd
extends GutTest

## Integrations-Tests: vollständige Scope-Kette App → Character → World.
##
## Testet das Zusammenspiel aller drei Scopes — nicht die Einzelteile
## (die liegen in test_app_scope, test_character_scope, test_world_scope).
##
## Abgedeckt:
##   - Vollständige Kette: App erzeugt Character, Character erzeugt World
##   - Teardown in korrekter Reihenfolge: World → Character → App
##   - Dep-Richtung über alle drei Ebenen: World sieht Character + App, nicht umgekehrt
##   - WorldScope.world_scope_ready wird durch CharacterScope korrekt weitergeleitet
##   - Session-Wechsel: zweite Session hat frische Registries (kein State-Bleed)
##   - Scope-Lifetime: World-Teardown löscht World-Services, nicht Character-Services

var _parent: Node

func before_each() -> void:
	_parent = add_child_autofree(Node.new())

# ─────────────────────────────────────────────────────────────────────────────
# Vollständige Kette aufbauen
# ─────────────────────────────────────────────────────────────────────────────

func test_full_chain_app_to_world() -> void:
	var app := AppScope.new(ServiceRegistry.new())
	var cs  := app.create_character_scope("p1", _parent)
	var ws  := cs.create_world_scope(add_child_autofree(Node3D.new()), _parent)

	assert_not_null(app, "AppScope muss existieren")
	assert_not_null(cs,  "CharacterScope muss existieren")
	assert_not_null(ws,  "WorldScope muss existieren")

func test_full_chain_world_root_accessible() -> void:
	var app  := AppScope.new(ServiceRegistry.new())
	var cs   := app.create_character_scope("p1", _parent)
	var root: Node3D = add_child_autofree(Node3D.new())
	var ws   := cs.create_world_scope(root, _parent)
	assert_eq(ws.get_world_root(), root, "WorldScope muss den korrekten root haben")

func test_world_scope_ready_signal_propagates_to_app_via_char() -> void:
	var app      := AppScope.new(ServiceRegistry.new())
	var cs       := app.create_character_scope("p1", _parent)
	var received := [false]
	cs.world_scope_ready.connect(func(_ws): received[0] = true)
	cs.create_world_scope(add_child_autofree(Node3D.new()), _parent)
	assert_true(received[0], "world_scope_ready Signal muss durch CharacterScope propagiert werden")

# ─────────────────────────────────────────────────────────────────────────────
# Dependency-Richtung über alle drei Ebenen
# ─────────────────────────────────────────────────────────────────────────────

func test_world_sees_character_services() -> void:
	var app  := AppScope.new(ServiceRegistry.new())
	var cs   := app.create_character_scope("p1", _parent)
	var dummy := _make_dummy_service("inventory")
	cs.registry.register(dummy, _make_def("inventory"))
	var ws := cs.create_world_scope(add_child_autofree(Node3D.new()), _parent)
	assert_eq(
		ws.get_character_service("inventory"),
		dummy,
		"WorldScope muss Character-Services via get_character_service() sehen"
	)

func test_world_sees_app_services() -> void:
	var app_reg := ServiceRegistry.new()
	var app     := AppScope.new(app_reg)
	var dummy   := _make_dummy_service("savesystem")
	app_reg.register(dummy, _make_def("savesystem"))
	var cs := app.create_character_scope("p1", _parent)
	var ws := cs.create_world_scope(add_child_autofree(Node3D.new()), _parent)
	assert_eq(
		ws.get_app_service("savesystem"),
		dummy,
		"WorldScope muss App-Services via get_app_service() sehen"
	)

func test_character_cannot_see_world_services() -> void:
	var app   := AppScope.new(ServiceRegistry.new())
	var cs    := app.create_character_scope("p1", _parent)
	var ws    := cs.create_world_scope(add_child_autofree(Node3D.new()), _parent)
	var dummy := _make_dummy_service("worldsvc")
	ws.registry.register(dummy, _make_def("worldsvc"))
	assert_null(
		cs.get_service("worldsvc"),
		"CharacterScope darf World-Services nicht sehen — falsche Dep-Richtung"
	)

func test_app_cannot_see_character_services() -> void:
	var app   := AppScope.new(ServiceRegistry.new())
	var cs    := app.create_character_scope("p1", _parent)
	var dummy := _make_dummy_service("questsvc")
	cs.registry.register(dummy, _make_def("questsvc"))
	assert_null(
		app.get_service("questsvc"),
		"AppScope darf Character-Services nicht sehen — falsche Dep-Richtung"
	)

func test_app_cannot_see_world_services() -> void:
	var app   := AppScope.new(ServiceRegistry.new())
	var cs    := app.create_character_scope("p1", _parent)
	var ws    := cs.create_world_scope(add_child_autofree(Node3D.new()), _parent)
	var dummy := _make_dummy_service("combatsys")
	ws.registry.register(dummy, _make_def("combatsys"))
	assert_null(
		app.get_service("combatsys"),
		"AppScope darf World-Services nicht sehen — falsche Dep-Richtung"
	)

# ─────────────────────────────────────────────────────────────────────────────
# Teardown-Reihenfolge: World → Character → App
# ─────────────────────────────────────────────────────────────────────────────

func test_teardown_world_only_removes_world_scope() -> void:
	var app := AppScope.new(ServiceRegistry.new())
	var cs  := app.create_character_scope("p1", _parent)
	cs.create_world_scope(add_child_autofree(Node3D.new()), _parent)
	cs.destroy_world_scope()
	assert_false(cs.has_world_scope(),    "WorldScope muss weg sein")
	assert_true(app.has_character_scope(), "CharacterScope muss noch existieren")

func test_teardown_character_also_removes_world() -> void:
	var app := AppScope.new(ServiceRegistry.new())
	var cs  := app.create_character_scope("p1", _parent)
	cs.create_world_scope(add_child_autofree(Node3D.new()), _parent)
	app.destroy_character_scope()
	assert_false(app.has_character_scope(), "CharacterScope muss weg sein")

func test_teardown_full_chain_no_crash() -> void:
	var app := AppScope.new(ServiceRegistry.new())
	var cs  := app.create_character_scope("p1", _parent)
	cs.create_world_scope(add_child_autofree(Node3D.new()), _parent)
	# World → Character → App
	cs.destroy_world_scope()
	app.destroy_character_scope()
	assert_false(app.has_character_scope(), "App muss nach Full-Teardown leer sein")

func test_teardown_without_world_scope_no_crash() -> void:
	var app := AppScope.new(ServiceRegistry.new())
	app.create_character_scope("p1", _parent)
	# kein World-Scope — darf nicht crashen
	app.destroy_character_scope()
	assert_true(true, "Teardown ohne WorldScope darf nicht crashen")

# ─────────────────────────────────────────────────────────────────────────────
# Session-Wechsel: frische Registries, kein State-Bleed
# ─────────────────────────────────────────────────────────────────────────────

func test_second_session_has_fresh_registry() -> void:
	var app  := AppScope.new(ServiceRegistry.new())
	var cs1  := app.create_character_scope("p1", _parent)
	var dummy := _make_dummy_service("inventory")
	cs1.registry.register(dummy, _make_def("inventory"))

	# Session wechseln
	app.destroy_character_scope()
	var cs2 := app.create_character_scope("p2", _parent)

	assert_null(
		cs2.get_service("inventory"),
		"Zweite Session darf keinen State aus erster Session erben"
	)

func test_second_session_different_player_id() -> void:
	var app := AppScope.new(ServiceRegistry.new())
	app.create_character_scope("p1", _parent)
	app.destroy_character_scope()
	var cs2 := app.create_character_scope("p2", _parent)
	assert_eq(cs2.player_id, "p2", "Zweite Session muss neue player_id haben")

func test_world_scope_fresh_after_session_change() -> void:
	var app  := AppScope.new(ServiceRegistry.new())
	var cs1  := app.create_character_scope("p1", _parent)
	var root1: Node3D = add_child_autofree(Node3D.new())
	var ws1  := cs1.create_world_scope(root1, _parent)
	var dummy := _make_dummy_service("combatsys")
	ws1.registry.register(dummy, _make_def("combatsys"))

	# Full teardown und neue Session
	app.destroy_character_scope()
	var cs2  := app.create_character_scope("p2", _parent)
	var root2: Node3D = add_child_autofree(Node3D.new())
	var ws2  := cs2.create_world_scope(root2, _parent)

	assert_null(
		ws2.get_service("combatsys"),
		"Neuer WorldScope darf keinen State aus alter Session haben"
	)

# ─────────────────────────────────────────────────────────────────────────────
# Scope-Lifetime: Services leben und sterben mit ihrem Scope
# ─────────────────────────────────────────────────────────────────────────────

func test_world_service_survives_world_teardown_in_char_scope() -> void:
	# Ein Service in CharacterScope muss WorldScope-Teardown überleben
	var app   := AppScope.new(ServiceRegistry.new())
	var cs    := app.create_character_scope("p1", _parent)
	var dummy := _make_dummy_service("questsvc")
	cs.registry.register(dummy, _make_def("questsvc"))
	cs.create_world_scope(add_child_autofree(Node3D.new()), _parent)
	cs.destroy_world_scope()
	assert_eq(
		cs.get_service("questsvc"),
		dummy,
		"Character-Services müssen WorldScope-Teardown überleben"
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
