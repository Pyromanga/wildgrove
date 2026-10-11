# res://tests/unit/test_character_scope.gd
extends GutTest

## Unit-Tests für CharacterScope.
##
## Abgedeckt:
##   - Initialisierung: player_id, registry, app_registry korrekt gesetzt
##   - create_world_scope(): gibt WorldScope zurück
##   - create_world_scope(): setzt has_world_scope() auf true
##   - create_world_scope(): zweiter Aufruf zerstört ersten Scope
##   - create_world_scope(): emittiert world_scope_ready Signal
##   - destroy_world_scope(): setzt has_world_scope() auf false
##   - destroy_world_scope(): auf leerem Scope kein Crash
##   - destroy(): ruft destroy_world_scope() auf
##   - get_service(): delegiert an character-registry
##   - Dep-Richtung: CharacterScope kennt AppScope, nicht WorldScope

var _parent:   Node
var _app_reg:  ServiceRegistry
var _char_reg: ServiceRegistry

func before_each() -> void:
	_parent   = add_child_autofree(Node.new())
	_app_reg  = ServiceRegistry.new()
	_char_reg = ServiceRegistry.new()

func _make_char_scope(pid: String = "p1") -> CharacterScope:
	return CharacterScope.new(_char_reg, _app_reg, pid, _parent)

func _make_world_root() -> Node3D:
	return add_child_autofree(Node3D.new())

# ─────────────────────────────────────────────────────────────────────────────
# Initialisierung
# ─────────────────────────────────────────────────────────────────────────────

func test_init_sets_player_id() -> void:
	var cs := _make_char_scope("hero_99")
	assert_eq(cs.player_id, "hero_99", "player_id muss 'hero_99' sein")

func test_init_sets_registry() -> void:
	var cs := _make_char_scope()
	assert_eq(cs.registry, _char_reg, "registry muss die übergebene Character-Registry sein")

func test_init_sets_app_registry() -> void:
	var cs := _make_char_scope()
	assert_eq(cs.app_registry, _app_reg, "app_registry muss die übergebene App-Registry sein")

func test_init_no_world_scope() -> void:
	var cs := _make_char_scope()
	assert_false(cs.has_world_scope(), "Frischer CharacterScope hat keinen WorldScope")

# ─────────────────────────────────────────────────────────────────────────────
# create_world_scope()
# ─────────────────────────────────────────────────────────────────────────────

func test_create_world_scope_returns_instance() -> void:
	var cs   := _make_char_scope()
	var root := _make_world_root()
	var ws   := cs.create_world_scope(root, _parent)
	assert_not_null(ws, "create_world_scope() muss WorldScope-Instanz zurückgeben")

func test_create_world_scope_sets_has_true() -> void:
	var cs   := _make_char_scope()
	var root := _make_world_root()
	cs.create_world_scope(root, _parent)
	assert_true(cs.has_world_scope(), "has_world_scope() muss true sein nach create")

func test_create_world_scope_sets_world_root() -> void:
	var cs   := _make_char_scope()
	var root := _make_world_root()
	var ws   := cs.create_world_scope(root, _parent)
	assert_eq(ws.world_root, root, "WorldScope.world_root muss der übergebene Node sein")

func test_create_world_scope_second_call_replaces_first() -> void:
	var cs    := _make_char_scope()
	var root1 := _make_world_root()
	var root2 := _make_world_root()
	var ws1   := cs.create_world_scope(root1, _parent)
	var ws2   := cs.create_world_scope(root2, _parent)
	assert_ne(ws1, ws2, "Zweiter Aufruf muss neuen WorldScope erzeugen")
	assert_eq(cs.get_world_scope(), ws2, "Aktiver WorldScope muss der neue sein")

func test_create_world_scope_emits_world_scope_ready() -> void:
	var cs        := _make_char_scope()
	var root      := _make_world_root()
	var signal_received := [false]
	var received_scope: Array = [null]
	cs.world_scope_ready.connect(func(ws: WorldScope) -> void:
		signal_received[0] = true
		received_scope[0]  = ws
	)
	var ws := cs.create_world_scope(root, _parent)
	assert_true(signal_received[0], "world_scope_ready Signal muss emittiert werden")
	assert_eq(received_scope[0], ws, "Signal muss den neuen WorldScope übergeben")

func test_create_world_scope_ready_signal_fires_before_return() -> void:
	# Signal muss synchron feuern — nicht deferred
	var cs       := _make_char_scope()
	var root     := _make_world_root()
	var fired    := [false]
	cs.world_scope_ready.connect(func(_ws): fired[0] = true)
	cs.create_world_scope(root, _parent)
	assert_true(fired[0], "world_scope_ready muss synchron feuern, nicht deferred")

# ─────────────────────────────────────────────────────────────────────────────
# destroy_world_scope()
# ─────────────────────────────────────────────────────────────────────────────

func test_destroy_world_scope_sets_has_false() -> void:
	var cs   := _make_char_scope()
	cs.create_world_scope(_make_world_root(), _parent)
	cs.destroy_world_scope()
	assert_false(cs.has_world_scope(), "has_world_scope() muss false sein nach destroy")

func test_destroy_world_scope_on_empty_no_crash() -> void:
	var cs := _make_char_scope()
	cs.destroy_world_scope()
	assert_true(true, "destroy_world_scope() auf leerem Scope darf nicht crashen")

func test_destroy_world_scope_clears_get() -> void:
	var cs := _make_char_scope()
	cs.create_world_scope(_make_world_root(), _parent)
	cs.destroy_world_scope()
	assert_null(cs.get_world_scope(), "get_world_scope() muss null sein nach destroy")

# ─────────────────────────────────────────────────────────────────────────────
# destroy()
# ─────────────────────────────────────────────────────────────────────────────

func test_destroy_also_destroys_world_scope() -> void:
	var cs := _make_char_scope()
	cs.create_world_scope(_make_world_root(), _parent)
	cs.destroy()
	assert_false(cs.has_world_scope(), "destroy() muss WorldScope mitlöschen")

func test_destroy_without_world_scope_no_crash() -> void:
	var cs := _make_char_scope()
	cs.destroy()
	assert_true(true, "destroy() ohne WorldScope darf nicht crashen")

# ─────────────────────────────────────────────────────────────────────────────
# get_service()
# ─────────────────────────────────────────────────────────────────────────────

func test_get_service_delegates_to_char_registry() -> void:
	var cs    := _make_char_scope()
	var dummy := _make_dummy_service("inv")
	_char_reg.register(dummy, _make_def("inv"))
	assert_eq(cs.get_service("inv"), dummy, "get_service() muss an char-registry delegieren")

func test_get_service_does_not_see_app_registry() -> void:
	var cs    := _make_char_scope()
	var dummy := _make_dummy_service("savesystem")
	_app_reg.register(dummy, _make_def("savesystem"))
	assert_null(
		cs.get_service("savesystem"),
		"get_service() darf nicht in app_registry schauen — falsche Scope-Richtung"
	)

# ─────────────────────────────────────────────────────────────────────────────
# Abhängigkeitsregel: CharacterScope kennt WorldScope nicht nach außen
# ─────────────────────────────────────────────────────────────────────────────

func test_char_registry_isolated_from_world_registry() -> void:
	var cs := _make_char_scope()
	var ws := cs.create_world_scope(_make_world_root(), _parent)
	var dummy := _make_dummy_service("world_svc")
	ws.registry.register(dummy, _make_def("world_svc"))
	assert_null(
		cs.get_service("world_svc"),
		"CharacterScope.get_service() darf nicht in WorldScope-Registry schauen"
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
