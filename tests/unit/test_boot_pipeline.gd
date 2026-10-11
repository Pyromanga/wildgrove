# res://tests/unit/test_boot_pipeline.gd
extends GutTest

## Unit-Tests für BootPipeline (drei Phasen: App / Character / World).
##
## BootPipeline extends RefCounted — kein SceneTree, kein AutoLoad, direkt testbar.
## Alle 6 Helfer werden durch Mocks ersetzt — getestet wird die Orchestrierung:
## welche Phasen aufgerufen werden, in welcher Reihenfolge, wie Fehler propagiert werden.
##
## Abgedeckt:
##   boot_app():       Erfolg, Phase 1/2/3 FAIL, Result.failed_phase korrekt
##   boot_character(): Erfolg, Phase C1/C2/C4 FAIL, SaveSystem aufgerufen
##   boot_world():     Erfolg, WorldService fehlt → FAIL
##   teardown_*:       Reihenfolge, end_session() aufgerufen, kein Crash ohne Services
##   Result:           to_string(), ok/failed_phase/reason

# ─────────────────────────────────────────────────────────────────────────────
# Mocks
# ─────────────────────────────────────────────────────────────────────────────

class MockValidator extends ServiceValidator:
	var global_result:  Array[ServiceDefinition] = [ServiceDefinition.new()]
	var session_result: Array[ServiceDefinition] = [ServiceDefinition.new()]
	var mock_config:    BootstrapConfig           = null
	func validate() -> Array[ServiceDefinition]:         return global_result
	func validate_session(_g = []) -> Array[ServiceDefinition]: return session_result
	func get_loaded_config() -> BootstrapConfig:         return mock_config

class MockResolver extends ServiceDependencyResolver:
	var result: Array[String] = ["dummy"]
	func resolve(_defs, _ext = []) -> Array[String]: return result

class MockFactory extends ServiceFactory:
	var result: bool = true
	var called: int  = 0
	func instantiate_all(_defs, _reg, _parent) -> bool:
		called += 1
		return result

class MockInitializer extends ServiceInitializer:
	var run_called:      int = 0
	var on_ready_called: int = 0
	func run(_ord, _reg, _fb = null) -> void:      run_called += 1
	func run_on_ready(_ord, _reg, _fb = null) -> void: on_ready_called += 1

class MockInstaller extends ServiceInstaller:
	var install_called:         int  = 0
	var install_session_called: int  = 0
	var install_result:         bool = true
	var install_session_result: bool = true
	func install(_reg: ServiceRegistry) -> bool:         install_called += 1;         return install_result
	func install_session(_reg: ServiceRegistry) -> bool: install_session_called += 1; return install_session_result

class MockTeardown extends ServiceTeardownManager:
	var execute_calls: Array = []
	func execute(reg: ServiceRegistry, order: Array[String] = []) -> void: execute_calls.append({reg = reg, order = order})

class MockSaveSystem extends SaveSystem:
	var begin_called:       bool   = false
	var end_called:         bool   = false
	var player_id_received: String = ""
	func begin_session(pid: String) -> void:
		begin_called       = true
		player_id_received = pid
	func end_session() -> void: end_called = true

class MockWorldService extends WorldService:
	var ready_called: bool   = false
	var ready_root:   Node3D = null
	var warmup_called: bool  = false
	func on_world_scene_ready(root: Node3D) -> void:
		ready_called = true
		ready_root   = root
	func warmup_mesh_cache() -> void: warmup_called = true

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────

var _pipeline:    BootPipeline
var _validator:   MockValidator
var _resolver:    MockResolver
var _factory:     MockFactory
var _initializer: MockInitializer
var _installer:   MockInstaller
var _teardown:    MockTeardown
var _parent:      Node

func before_each() -> void:
	_pipeline    = BootPipeline.new()
	_validator   = MockValidator.new()
	_resolver    = MockResolver.new()
	_factory     = MockFactory.new()
	_initializer = MockInitializer.new()
	_installer   = MockInstaller.new()
	_teardown    = MockTeardown.new()
	_pipeline.validator   = _validator
	_pipeline.resolver    = _resolver
	_pipeline.factory     = _factory
	_pipeline.initializer = _initializer
	_pipeline.installer   = _installer
	_pipeline.teardown    = _teardown
	_parent = add_child_autofree(Node.new())

func _make_app_scope() -> AppScope:
	return AppScope.new(ServiceRegistry.new())

func _make_char_scope(app_scope: AppScope, pid: String = "p1") -> CharacterScope:
	var app_reg  := app_scope.registry
	var char_reg := ServiceRegistry.new()
	var ss       := MockSaveSystem.new()
	ss.service_name = "savesystem"
	char_reg  # unused here — SaveSystem lives in app_reg
	app_reg.register(ss, _make_def("savesystem"))
	return CharacterScope.new(ServiceRegistry.new(), app_reg, pid, _parent)

func _make_world_scope(char_scope: CharacterScope) -> WorldScope:
	var root: Node3D = add_child_autofree(Node3D.new())
	return WorldScope.new(ServiceRegistry.new(), char_scope.registry, char_scope.app_registry, root, _parent)

func _make_def(svc_name: String) -> ServiceDefinition:
	var d := ServiceDefinition.new()
	d.service_name = svc_name
	d.path         = "res://scripts/platform/Service.gd"
	d.required_deps = []
	return d

# ─────────────────────────────────────────────────────────────────────────────
# boot_app() — Erfolg
# ─────────────────────────────────────────────────────────────────────────────

func test_boot_app_success_returns_ok() -> void:
	var app    := _make_app_scope()
	var result := _pipeline.boot_app(app, _parent)
	assert_true(result.ok, "boot_app() muss Result.ok = true zurückgeben")

func test_boot_app_calls_factory() -> void:
	_pipeline.boot_app(_make_app_scope(), _parent)
	assert_eq(_factory.called, 1, "factory.instantiate_all() muss einmal aufgerufen werden")

func test_boot_app_calls_configure_then_on_ready() -> void:
	_pipeline.boot_app(_make_app_scope(), _parent)
	assert_eq(_initializer.run_called,      1, "configure() muss aufgerufen werden")
	assert_eq(_initializer.on_ready_called, 1, "on_ready() muss aufgerufen werden")

func test_boot_app_calls_installer() -> void:
	_pipeline.boot_app(_make_app_scope(), _parent)
	assert_eq(_installer.install_called, 1, "installer.install() muss aufgerufen werden")

## Regression: fehlender kritischer Service (z.B. 'ticker') wurde früher nur geloggt,
## boot_app() meldete trotzdem Result.ok = true. install() = false muss den Boot jetzt
## tatsächlich abbrechen.
func test_boot_app_installer_missing_critical_fails_boot() -> void:
	_installer.install_result = false
	var result := _pipeline.boot_app(_make_app_scope(), _parent)
	assert_false(result.ok, "fehlender kritischer Global-Service muss Result.ok = false ergeben")
	assert_eq(result.failed_phase, "install_app")

# ─────────────────────────────────────────────────────────────────────────────
# boot_app() — Error-Paths
# ─────────────────────────────────────────────────────────────────────────────

func test_boot_app_phase1_fail_empty_validator() -> void:
	_validator.global_result = []
	var result := _pipeline.boot_app(_make_app_scope(), _parent)
	assert_false(result.ok, "Leerer Validator → Result.ok muss false sein")
	assert_eq(result.failed_phase, "validate_app")

func test_boot_app_phase1_fail_no_factory_call() -> void:
	_validator.global_result = []
	_pipeline.boot_app(_make_app_scope(), _parent)
	assert_eq(_factory.called, 0, "factory darf bei Phase-1-Fail nicht aufgerufen werden")

func test_boot_app_phase2_fail_empty_resolver() -> void:
	_resolver.result = []
	var result := _pipeline.boot_app(_make_app_scope(), _parent)
	assert_false(result.ok, "Leerer Resolver → Result.ok muss false sein")
	assert_eq(result.failed_phase, "resolve_app")

func test_boot_app_phase3_fail_factory_returns_false() -> void:
	_factory.result = false
	var result := _pipeline.boot_app(_make_app_scope(), _parent)
	assert_false(result.ok, "Factory-Fehler → Result.ok muss false sein")
	assert_eq(result.failed_phase, "factory_app")

func test_boot_app_phase3_fail_no_configure_call() -> void:
	_factory.result = false
	_pipeline.boot_app(_make_app_scope(), _parent)
	assert_eq(_initializer.run_called, 0, "configure() darf bei Phase-3-Fail nicht aufgerufen werden")

# ─────────────────────────────────────────────────────────────────────────────
# boot_character() — Erfolg
# ─────────────────────────────────────────────────────────────────────────────

func test_boot_character_success_returns_ok() -> void:
	var app := _make_app_scope()
	var cs  := _make_char_scope(app)
	var result := _pipeline.boot_character(cs, _parent)
	assert_true(result.ok, "boot_character() muss Result.ok = true zurückgeben")

func test_boot_character_calls_begin_session() -> void:
	var app    := _make_app_scope()
	var cs     := _make_char_scope(app, "hero_42")
	_pipeline.boot_character(cs, _parent)
	var ss := app.registry.get_service("savesystem") as MockSaveSystem
	assert_true(ss.begin_called, "SaveSystem.begin_session() muss aufgerufen werden")
	assert_eq(ss.player_id_received, "hero_42")

func test_boot_character_calls_configure_and_on_ready() -> void:
	var app := _make_app_scope()
	var cs  := _make_char_scope(app)
	_pipeline.boot_character(cs, _parent)
	assert_eq(_initializer.run_called,      1, "configure() muss aufgerufen werden")
	assert_eq(_initializer.on_ready_called, 1, "on_ready() muss aufgerufen werden")

func test_boot_character_calls_install_session() -> void:
	var app := _make_app_scope()
	var cs  := _make_char_scope(app)
	_pipeline.boot_character(cs, _parent)
	assert_eq(_installer.install_session_called, 1, "installer.install_session() muss aufgerufen werden")

## Regression: gleicher Bug wie oben, nur auf Character-Ebene (z.B. 'combat' fehlt,
## weil eine seiner Deps beim Global-Boot nie registriert wurde).
func test_boot_character_installer_missing_critical_fails_boot() -> void:
	_installer.install_session_result = false
	var app    := _make_app_scope()
	var cs     := _make_char_scope(app)
	var result := _pipeline.boot_character(cs, _parent)
	assert_false(result.ok, "fehlender kritischer Session-Service muss Result.ok = false ergeben")
	assert_eq(result.failed_phase, "install_character")

# ─────────────────────────────────────────────────────────────────────────────
# boot_character() — Error-Paths
# ─────────────────────────────────────────────────────────────────────────────

func test_boot_character_phase_c1_fail_no_save_system() -> void:
	var app    := AppScope.new(ServiceRegistry.new())  # kein SaveSystem
	var cs     := CharacterScope.new(ServiceRegistry.new(), app.registry, "p1", _parent)
	var result := _pipeline.boot_character(cs, _parent)
	assert_false(result.ok, "Fehlendes SaveSystem → Result.ok muss false sein")
	assert_eq(result.failed_phase, "character_save")

func test_boot_character_phase_c2_fail_empty_validator() -> void:
	_validator.session_result = []
	var app    := _make_app_scope()
	var cs     := _make_char_scope(app)
	var result := _pipeline.boot_character(cs, _parent)
	assert_false(result.ok)
	assert_eq(result.failed_phase, "validate_character")

func test_boot_character_phase_c4_fail_factory() -> void:
	_factory.result = false
	var app    := _make_app_scope()
	var cs     := _make_char_scope(app)
	var result := _pipeline.boot_character(cs, _parent)
	assert_false(result.ok)
	assert_eq(result.failed_phase, "factory_character")

func test_boot_character_c2_fail_no_configure() -> void:
	_validator.session_result = []
	var app := _make_app_scope()
	var cs  := _make_char_scope(app)
	_pipeline.boot_character(cs, _parent)
	assert_eq(_initializer.run_called, 0, "configure() darf bei C2-Fail nicht aufgerufen werden")

# ─────────────────────────────────────────────────────────────────────────────
# boot_world() — Erfolg
# ─────────────────────────────────────────────────────────────────────────────

func test_boot_world_success_returns_ok() -> void:
	var app := _make_app_scope()
	var cs  := _make_char_scope(app)
	# WorldService in char_registry registrieren
	var mock_ws := MockWorldService.new()
	mock_ws.service_name = ServiceKeys.WORLD
	cs.registry.register(mock_ws, _make_def(ServiceKeys.WORLD))
	var ws     := _make_world_scope(cs)
	var result := await _pipeline.boot_world(ws, _parent)
	assert_true(result.ok, "boot_world() muss Result.ok = true zurückgeben")

func test_boot_world_calls_on_world_scene_ready() -> void:
	var app     := _make_app_scope()
	var cs      := _make_char_scope(app)
	var mock_ws := MockWorldService.new()
	mock_ws.service_name = ServiceKeys.WORLD
	cs.registry.register(mock_ws, _make_def(ServiceKeys.WORLD))
	var ws   := _make_world_scope(cs)
	_pipeline.boot_world(ws, _parent)
	assert_true(mock_ws.ready_called, "WorldService.on_world_scene_ready() muss aufgerufen werden")

func test_boot_world_passes_correct_root() -> void:
	var app     := _make_app_scope()
	var cs      := _make_char_scope(app)
	var mock_ws := MockWorldService.new()
	mock_ws.service_name = ServiceKeys.WORLD
	cs.registry.register(mock_ws, _make_def(ServiceKeys.WORLD))
	var root: Node3D = add_child_autofree(Node3D.new())
	var ws   := WorldScope.new(ServiceRegistry.new(), cs.registry, app.registry, root, _parent)
	_pipeline.boot_world(ws, _parent)
	assert_eq(mock_ws.ready_root, root, "on_world_scene_ready() muss den korrekten root bekommen")

func test_boot_world_calls_warmup_mesh_cache() -> void:
	var app     := _make_app_scope()
	var cs      := _make_char_scope(app)
	var mock_ws := MockWorldService.new()
	mock_ws.service_name = ServiceKeys.WORLD
	cs.registry.register(mock_ws, _make_def(ServiceKeys.WORLD))
	var ws := _make_world_scope(cs)
	_pipeline.boot_world(ws, _parent)
	assert_true(mock_ws.warmup_called, "warmup_mesh_cache() muss aufgerufen werden")

func test_boot_world_fail_no_world_service() -> void:
	var app    := _make_app_scope()
	var cs     := _make_char_scope(app)
	# kein WorldService in char_registry
	var ws     := _make_world_scope(cs)
	var result := await _pipeline.boot_world(ws, _parent)
	assert_false(result.ok, "Fehlender WorldService → Result.ok muss false sein")
	assert_eq(result.failed_phase, "world_service")

# ─────────────────────────────────────────────────────────────────────────────
# teardown_character()
# ─────────────────────────────────────────────────────────────────────────────

func test_teardown_character_calls_end_session() -> void:
	var app := _make_app_scope()
	var cs  := _make_char_scope(app)
	_pipeline.teardown_character(cs)
	var ss := app.registry.get_service("savesystem") as MockSaveSystem
	assert_true(ss.end_called, "SaveSystem.end_session() muss aufgerufen werden")

func test_teardown_character_without_save_system_no_crash() -> void:
	var app    := AppScope.new(ServiceRegistry.new())
	var cs     := CharacterScope.new(ServiceRegistry.new(), app.registry, "p1", _parent)
	_pipeline.teardown_character(cs)
	assert_true(true, "teardown ohne SaveSystem darf nicht crashen")

# ─────────────────────────────────────────────────────────────────────────────
# teardown_all()
# ─────────────────────────────────────────────────────────────────────────────

func test_teardown_all_without_character_scope_no_crash() -> void:
	var app := _make_app_scope()
	_pipeline.teardown_all(app)
	assert_true(true, "teardown_all ohne CharacterScope darf nicht crashen")

func test_teardown_all_calls_execute_for_app() -> void:
	var app := _make_app_scope()
	_pipeline.teardown_all(app)
	assert_eq(_teardown.execute_calls.size(), 1, "teardown.execute() muss einmal aufgerufen werden (app)")

func test_teardown_all_with_character_calls_execute_twice() -> void:
	var app := _make_app_scope()
	var cs  := _make_char_scope(app)
	app._character_scope = cs  # direkt setzen ohne boot
	_pipeline.teardown_all(app)
	assert_eq(_teardown.execute_calls.size(), 2, "teardown.execute() muss zweimal aufgerufen werden")

# ─────────────────────────────────────────────────────────────────────────────
# Result
# ─────────────────────────────────────────────────────────────────────────────

func test_result_success_to_string() -> void:
	var r := BootPipeline.Result.success()
	assert_true(r.ok)
	assert_true("ok" in r.to_string(), "to_string() muss 'ok' enthalten")

func test_result_failure_fields() -> void:
	var r := BootPipeline.Result.failure("test_phase", "test_reason")
	assert_false(r.ok)
	assert_eq(r.failed_phase, "test_phase")
	assert_eq(r.reason, "test_reason")

func test_result_failure_to_string_contains_phase() -> void:
	var r := BootPipeline.Result.failure("my_phase", "my_reason")
	assert_true("my_phase" in r.to_string())
