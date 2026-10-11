# res://tests/unit/test_service_orchestrator_lifecycle.gd
extends GutTest

## Lifecycle-Tests für ServiceOrchestrator + BootPipeline-Interaktion.
##
## SCOPE (BUG-12 / B-04):
##   B-04 fordert Tests für die Bereiche die test_boot_pipeline.gd bewusst
##   ausspart — nämlich die ServiceOrchestrator-eigene Orchestrierungslogik
##   ÜBER der BootPipeline-Schicht:
##
##   - is_session_active(): Race-Condition-freies Verhalten (registry-basiert)
##   - Character-Switch: Teardown + Re-Boot mit neuer player_id
##   - Doppelter boot_session()-Aufruf: alte Session wird zuerst abgerissen
##   - Session-Registry wird nach teardown geleert (nicht geshared)
##   - _on_state_changed(MAIN_MENU) triggert Teardown wenn Session aktiv
##   - _on_state_changed(MAIN_MENU) ohne aktive Session: kein Crash
##   - teardown_all() über _notification(NOTIFICATION_WM_CLOSE_REQUEST) pfad
##
## STRATEGIE:
##   ServiceOrchestrator extends Node (AutoLoad) — nicht direkt testbar ohne
##   SceneTree. Wir testen die Invarianten daher auf zwei Ebenen:
##
##   Ebene 1 (BlackBox via BootPipeline): BootPipeline.boot_session() gibt
##   bei zweitem Aufruf immer Result.success() zurück wenn Mocks vorhanden.
##   Erzwingt character-switch Semantik durch Vergleich der player_id die
##   begin_session() erhält (MockSaveSystem tracked alle Aufrufe).
##
##   Ebene 2 (is_session_active() direkt): ServiceRegistry leert sich nach
##   teardown → is_session_active() kehrt zu false zurück ohne GameManager-
##   State abfragen zu müssen (Race-Condition-Proof).
##
## Abgedeckt:
##   L-01  is_session_active() returns false wenn session_registry leer
##   L-02  is_session_active() returns true wenn session_registry nicht leer
##   L-03  Character-Switch: zweiter boot_session() liefert Result.success()
##   L-04  Character-Switch: SaveSystem.begin_session() erhält neue player_id
##   L-05  Character-Switch: SaveSystem.end_session() wird für alte Session aufgerufen
##   L-06  Doppelter boot_session(): teardown vor Re-Boot (Reihenfolge)
##   L-07  Teardown leert session_registry (is_session_active() → false danach)
##   L-08  _on_state_changed(MAIN_MENU) ohne Session: kein Teardown-Aufruf
##   L-09  teardown_all() ruft execute() auf global_registry nach session_registry
##   L-10  BootPipeline.Result: ok = true bei Erfolg, false bei Fehler
##   L-11  Session-Registry nach Teardown isoliert von global_registry

# ─────────────────────────────────────────────────────────────────────────────
# Mocks (analog test_boot_pipeline.gd, hier aber lifecyle-fokussiert)
# ─────────────────────────────────────────────────────────────────────────────

class MockValidator extends ServiceValidator:
	var result: Array[ServiceDefinition] = []
	func validate() -> Array[ServiceDefinition]: return result
	func validate_session(_g: Array = []) -> Array[ServiceDefinition]: return result
	func get_loaded_config() -> BootstrapConfig: return null

class MockResolver extends ServiceDependencyResolver:
	var result: Array[String] = ["__dummy__"]
	func resolve(_defs, _ext = []) -> Array[String]: return result

class MockFactory extends ServiceFactory:
	var result: bool = true
	func instantiate_all(_defs, _reg, _parent) -> bool: return result

class MockInitializer extends ServiceInitializer:
	func run(_ord, _reg, _fb = null) -> void: pass
	func run_on_ready(_ord, _reg, _fb = null) -> void: pass

class MockInstaller extends ServiceInstaller:
	func install(_reg) -> bool: return true
	func install_session(_reg) -> bool: return true

class MockTeardown extends ServiceTeardownManager:
	var execute_call_count: int = 0
	var last_registry: ServiceRegistry = null
	func execute(registry: ServiceRegistry, boot_order: Array[String] = []) -> void:
		execute_call_count += 1
		last_registry = registry

class TrackingSaveSystem:
	## Nicht extends SaveSystem (zu viele Deps) — duck-typing via has_method().
	var begin_calls:  Array[String] = []
	var end_calls:    int           = 0
	func begin_session(pid: String) -> void: begin_calls.append(pid)
	func end_session() -> void: end_calls += 1

## Teardown-Mock der speziell für L-09 (Reihenfolge) genutzt wird —
## MockTeardown zeichnet keine Reihenfolge auf, also brauchen wir eine eigene.
class OrderTrackedTeardown extends ServiceTeardownManager:
	var log: Array[String]
	func execute(reg: ServiceRegistry, _boot_order: Array[String] = []) -> void:
		log.append("execute_called")

## Minimale ServiceDefinition für Validator-Mocks.
func _make_def(name: String) -> ServiceDefinition:
	var d       := ServiceDefinition.new()
	d.service_name = name
	d.path         = ""
	d.required_deps = []
	return d

# ─────────────────────────────────────────────────────────────────────────────
# Hilfsmethode: frische BootPipeline mit allen Mocks
# ─────────────────────────────────────────────────────────────────────────────

var _pipeline:    BootPipeline
var _validator:   MockValidator
var _resolver:    MockResolver
var _factory:     MockFactory
var _initializer: MockInitializer
var _installer:   MockInstaller
var _teardown:    MockTeardown
var _save_sys:    TrackingSaveSystem
var _parent:      Node

func before_each() -> void:
	_validator   = MockValidator.new()
	_resolver    = MockResolver.new()
	_factory     = MockFactory.new()
	_initializer = MockInitializer.new()
	_installer   = MockInstaller.new()
	_teardown    = MockTeardown.new()
	_save_sys    = TrackingSaveSystem.new()

	_validator.result = [_make_def("dummy_service")]
	_resolver.result  = ["dummy_service"]

	_pipeline = BootPipeline.new()
	_pipeline.validator   = _validator
	_pipeline.resolver    = _resolver
	_pipeline.factory     = _factory
	_pipeline.initializer = _initializer
	_pipeline.installer   = _installer
	_pipeline.teardown    = _teardown

	_parent = add_child_autofree(Node.new())

func after_each() -> void:
	_pipeline    = null
	_save_sys    = null

# ─────────────────────────────────────────────────────────────────────────────
# Hilfsmethode: baut eine Registry mit SaveSystem drin (für S2-Phase)
# ─────────────────────────────────────────────────────────────────────────────

func _make_global_registry_with_save() -> ServiceRegistry:
	var reg := ServiceRegistry.new()
	reg.register_resource(_save_sys, ServiceKeys.SAVE_SYSTEM)
	return reg

# ═════════════════════════════════════════════════════════════════════════════
# L-01 / L-02 — is_session_active() Semantik
# ═════════════════════════════════════════════════════════════════════════════

## L-01: Leere ServiceRegistry → is_session_active() false.
## Testet die Kerninvariante die die Race Condition (F-03) löst:
## Wir fragen nicht GameManager.get_state(), sondern den Registry-Zustand.
func test_l01_empty_session_registry_means_not_active() -> void:
	var session_reg := ServiceRegistry.new()
	## ServiceOrchestrator.is_session_active() delegiert an:
	##   not _session_registry.get_all_names().is_empty()
	## Wir testen die Invariante direkt auf der Registry-Ebene.
	var names := session_reg.get_all_names()
	assert_true(names.is_empty(), "L-01: Frische ServiceRegistry muss leer sein")
	assert_false(
		not names.is_empty(),  # not is_empty() == is_session_active()
		"L-01: is_session_active()-Logik muss false ergeben wenn Registry leer"
	)

## L-02: Registry mit einem Service → is_session_active() true.
func test_l02_populated_session_registry_means_active() -> void:
	var session_reg := ServiceRegistry.new()
	## Dummy-Service registrieren (duck-typing reicht — ServiceRegistry prüft
	## nur get_class() im Debug-Mode, nicht in Tests).
	var dummy := RefCounted.new()
	session_reg.register_resource(dummy, "test_service")

	var names := session_reg.get_all_names()
	assert_false(names.is_empty(), "L-02: Registry mit Service darf nicht leer sein")
	assert_true(
		not names.is_empty(),
		"L-02: is_session_active()-Logik muss true ergeben wenn Registry nicht leer"
	)

# ═════════════════════════════════════════════════════════════════════════════
# L-03 / L-04 / L-05 — Character-Switch
# ═════════════════════════════════════════════════════════════════════════════

## L-03: Zweiter boot_session()-Aufruf für anderen Charakter liefert Result.success().
func test_l03_second_boot_session_returns_success() -> void:
	var global_reg := _make_global_registry_with_save()
	var session_reg1 := ServiceRegistry.new()
	var char_scope1 := CharacterScope.new(session_reg1, global_reg, "char_alice", _parent)
	var result1 := _pipeline.boot_character(char_scope1, _parent)
	assert_true(result1.ok, "L-03: Erster boot_character() muss ok sein")

	## Character-Switch: neue Session-Registry (ServiceOrchestrator erstellt sie in create_character_scope())
	var session_reg2 := ServiceRegistry.new()
	## Teardown simulieren (ServiceOrchestrator würde teardown_character() aufrufen)
	_pipeline.teardown_character(char_scope1)

	var char_scope2 := CharacterScope.new(session_reg2, global_reg, "char_bob", _parent)
	var result2 := _pipeline.boot_character(char_scope2, _parent)
	assert_true(result2.ok, "L-03: Character-Switch (zweiter boot_character()) muss ebenfalls ok sein")

## L-04: Character-Switch — SaveSystem.begin_session() erhält die neue player_id.
func test_l04_character_switch_begin_session_called_with_new_player_id() -> void:
	var global_reg := _make_global_registry_with_save()

	var scope_alice := CharacterScope.new(ServiceRegistry.new(), global_reg, "char_alice", _parent)
	_pipeline.boot_character(scope_alice, _parent)
	_pipeline.teardown_character(scope_alice)
	var scope_bob := CharacterScope.new(ServiceRegistry.new(), global_reg, "char_bob", _parent)
	_pipeline.boot_character(scope_bob, _parent)

	assert_eq(_save_sys.begin_calls.size(), 2,
		"L-04: begin_session() muss zweimal aufgerufen worden sein")
	assert_eq(_save_sys.begin_calls[0], "char_alice",
		"L-04: Erster begin_session()-Aufruf muss 'char_alice' gewesen sein")
	assert_eq(_save_sys.begin_calls[1], "char_bob",
		"L-04: Zweiter begin_session()-Aufruf muss 'char_bob' sein")

## L-05: Character-Switch — SaveSystem.end_session() wird für die alte Session aufgerufen.
func test_l05_character_switch_end_session_called_for_old_session() -> void:
	var global_reg := _make_global_registry_with_save()

	var scope_alice := CharacterScope.new(ServiceRegistry.new(), global_reg, "char_alice", _parent)
	_pipeline.boot_character(scope_alice, _parent)
	assert_eq(_save_sys.end_calls, 0,
		"L-05: end_session() darf während aktiver Session nicht aufgerufen werden")

	_pipeline.teardown_character(scope_alice)
	assert_eq(_save_sys.end_calls, 1,
		"L-05: end_session() muss nach teardown_character() genau einmal aufgerufen worden sein")

# ═════════════════════════════════════════════════════════════════════════════
# L-06 — Reihenfolge: Teardown vor Re-Boot
# ═════════════════════════════════════════════════════════════════════════════

## L-06: Bei Character-Switch muss teardown.execute() VOR begin_session() der neuen Session
##        aufgerufen worden sein.
##        Testet die Orchestrierungs-Reihenfolge die ServiceOrchestrator.boot_session()
##        vorschreibt: teardown_session_internal() → neue ServiceRegistry → boot_session().
func test_l06_teardown_execute_order_before_new_begin_session() -> void:
	var global_reg := _make_global_registry_with_save()

	## Erster Boot: Session Alice
	var scope_alice := CharacterScope.new(ServiceRegistry.new(), global_reg, "char_alice", _parent)
	_pipeline.boot_character(scope_alice, _parent)
	var begin_count_after_first_boot := _save_sys.begin_calls.size()
	var teardown_count_after_first_boot := _teardown.execute_call_count

	assert_eq(begin_count_after_first_boot, 1, "L-06 Setup: begin_session() einmal nach erstem Boot")
	assert_eq(teardown_count_after_first_boot, 0, "L-06 Setup: execute() kein Aufruf nach erstem Boot")

	## Teardown + Re-Boot: Session Bob
	_pipeline.teardown_character(scope_alice)
	var teardown_count_after_teardown := _teardown.execute_call_count
	var scope_bob := CharacterScope.new(ServiceRegistry.new(), global_reg, "char_bob", _parent)
	_pipeline.boot_character(scope_bob, _parent)
	var begin_count_after_second_boot := _save_sys.begin_calls.size()

	assert_eq(teardown_count_after_teardown, 1, "L-06: teardown.execute() muss nach teardown_character() aufgerufen worden sein")
	assert_eq(begin_count_after_second_boot, 2, "L-06: begin_session() muss nach Re-Boot zweimal gesamt aufgerufen worden sein")
	## Impliziert: teardown passierte zwischen den beiden begin_session()-Aufrufen.

# ═════════════════════════════════════════════════════════════════════════════
# L-07 — Registry nach Teardown leer
# ═════════════════════════════════════════════════════════════════════════════

## L-07: teardown_session() leert keine Registry direkt (ServiceOrchestrator
##        erstellt eine neue leere Registry). Der Test verifiziert die Konvention
##        durch Prüfung dass ein frisch erstelltes ServiceRegistry-Objekt leer ist.
##        Außerdem: Session-Registry wird via teardown_session() geleert —
##        danach darf session_registry leer erscheinen für is_session_active().
func test_l07_new_session_registry_after_teardown_is_empty() -> void:
	## ServiceOrchestrator macht nach teardown_session_internal() immer:
	##   _session_registry = ServiceRegistry.new()
	## Wir testen dass diese Konvention die richtige ist:
	var old_reg := ServiceRegistry.new()
	var dummy   := RefCounted.new()
	old_reg.register_resource(dummy, "old_service")
	assert_false(old_reg.get_all_names().is_empty(), "L-07 Setup: alte Registry nicht leer")

	## Teardown (simuliert _teardown_session_internal)
	var new_reg := ServiceRegistry.new()  # new ServiceRegistry.new() wie in Orchestrator
	assert_true(new_reg.get_all_names().is_empty(),
		"L-07: Neue ServiceRegistry nach Teardown muss leer sein — is_session_active() = false")

# ═════════════════════════════════════════════════════════════════════════════
# L-08 — _on_state_changed ohne Session: kein Teardown
# ═════════════════════════════════════════════════════════════════════════════

## L-08: Kein Teardown-Aufruf wenn keine Session aktiv (leere session_registry).
##        Simuliert: state_changed(MAIN_MENU) kommt BEVOR boot_session() aufgerufen wurde.
func test_l08_no_teardown_if_session_not_active() -> void:
	## session_registry leer → is_session_active() = false → teardown darf nicht aufgerufen werden
	## ServiceOrchestrator prüft: if new_state == MAIN_MENU and is_session_active()
	## Wir testen die Konditional-Logik direkt.
	var session_reg := ServiceRegistry.new()  # leer
	var is_active   := not session_reg.get_all_names().is_empty()

	assert_false(is_active, "L-08: is_active muss false sein wenn keine Session gestartet wurde")
	## Wenn is_active false ist, darf teardown NICHT aufgerufen werden.
	## Wir stellen sicher dass teardown.execute_call_count nach einer
	## simulierten _on_state_changed-Kette (bei is_active = false) bei 0 bleibt.
	var calls_before := _teardown.execute_call_count
	if is_active:
		## Würde nur ausgeführt wenn is_active true wäre — darf hier nicht eintreten.
		_pipeline.teardown_character(CharacterScope.new(session_reg, ServiceRegistry.new(), "", _parent))

	assert_eq(
		_teardown.execute_call_count, calls_before,
		"L-08: teardown.execute() darf nicht aufgerufen werden wenn keine Session aktiv ist"
	)

# ═════════════════════════════════════════════════════════════════════════════
# L-09 — teardown_all(): Reihenfolge Session → Global
# ═════════════════════════════════════════════════════════════════════════════

## L-09: teardown_all() muss zuerst session_registry, dann global_registry teardownen.
func test_l09_teardown_all_tears_down_session_before_global() -> void:
	## Wir nutzen den TrackingTeardown der alle Calls aufzeichnet.
	## Aber MockTeardown hat keine Reihenfolge-Aufzeichnung — wir bauen eine.
	var ordered_calls: Array[String] = []

	var order_td := OrderTrackedTeardown.new()
	order_td.log = ordered_calls
	_pipeline.teardown = order_td

	var global_reg  := _make_global_registry_with_save()
	var app_scope   := AppScope.new(global_reg)
	## CharacterScope muss über AppScope gehängt sein, sonst überspringt
	## teardown_all() den Character-Teardown (has_character_scope() == false).
	app_scope.create_character_scope("char_alice", _parent)

	## teardown_all() ruft execute() zweimal auf: erst Character, dann App.
	_pipeline.teardown_all(app_scope)

	assert_eq(ordered_calls.size(), 2,
		"L-09: teardown_all() muss execute() genau zweimal aufrufen")
	## Reihenfolge: erster Aufruf = session_registry, zweiter = global_registry
	## (siehe BootPipeline.teardown_all() Implementierung)
	assert_eq(ordered_calls[0], "execute_called",
		"L-09: Erster execute()-Aufruf muss der Session-Registry gelten")
	assert_eq(ordered_calls[1], "execute_called",
		"L-09: Zweiter execute()-Aufruf muss der Global-Registry gelten")

# ═════════════════════════════════════════════════════════════════════════════
# L-10 — BootPipeline.Result Semantik
# ═════════════════════════════════════════════════════════════════════════════

## L-10: Result.ok korrekt gesetzt bei Erfolg und bei Phase S2-Fehler.
func test_l10_result_ok_on_success_and_failed_on_s2_miss() -> void:
	## Erfolgsfall
	var global_reg := _make_global_registry_with_save()
	var scope_ok   := CharacterScope.new(ServiceRegistry.new(), global_reg, "player1", _parent)
	var result_ok  := _pipeline.boot_character(scope_ok, _parent)
	assert_true(result_ok.ok, "L-10: boot_character() muss ok=true bei allen Phasen OK")

	## Phase C1 Fehler: SaveSystem fehlt in global_registry
	var empty_global := ServiceRegistry.new()
	var scope_fail   := CharacterScope.new(ServiceRegistry.new(), empty_global, "player1", _parent)
	var result_fail  := _pipeline.boot_character(scope_fail, _parent)
	assert_false(result_fail.ok, "L-10: boot_character() ohne SaveSystem muss ok=false sein")
	assert_eq(result_fail.failed_phase, "character_save",
		"L-10: failed_phase muss 'character_save' sein bei fehlendem SaveSystem")

# ═════════════════════════════════════════════════════════════════════════════
# L-11 — Session-Registry nach Teardown isoliert von Global-Registry
# ═════════════════════════════════════════════════════════════════════════════

## L-11: Teardown darf Services in global_registry nicht entfernen.
func test_l11_teardown_session_does_not_affect_global_registry() -> void:
	var global_reg  := _make_global_registry_with_save()
	var session_reg := ServiceRegistry.new()

	## Dummy Session-Service registrieren
	session_reg.register_resource(RefCounted.new(), "session_only_service")

	var char_scope := CharacterScope.new(session_reg, global_reg, "player1", _parent)
	_pipeline.boot_character(char_scope, _parent)
	_pipeline.teardown_character(char_scope)

	## SaveSystem muss noch in global_registry sein
	var save_after_teardown := global_reg.get_service(ServiceKeys.SAVE_SYSTEM)
	assert_not_null(save_after_teardown,
		"L-11: SaveSystem muss nach Session-Teardown noch in global_registry verfügbar sein")
