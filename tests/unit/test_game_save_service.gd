# res://tests/unit/test_game_save_service.gd
extends GutTest

## Unit-Tests für GameSaveService (E-02).
##
## Strategie: GameSaveService extends Service (RefCounted) — kein add_child nötig.
## configure() mit Mock-SaveSystem. on_ready() nicht aufgerufen.
## Direkter Aufruf von save_all() für Tier-1-Tests.
##
## Abgedeckt:
##   - save_all(): Erfolg wenn SaveSystem vorhanden
##   - save_all(): false wenn kein SaveSystem
##   - Doppelaufruf-Schutz (_is_saving-Guard)
##   - save_all() ohne aktive Session → false (SaveSystem-Delegation)

# ─────────────────────────────────────────────────────────────────────────────
# Mock-SaveSystem
# ─────────────────────────────────────────────────────────────────────────────

## Muss "extends SaveSystem" sein, da GameSaveService.configure() per DI-Konvention
## hart auf SaveSystem castet (deps.require(...) as SaveSystem).
class MockSaveSystem extends SaveSystem:
	var save_called: int = 0
	var save_result: bool = true
	var has_session: bool = true
	# Kein _loaded_state nötig — save_game() ist der einzige getestete Pfad

	func save_game() -> bool:
		save_called += 1
		return save_result

	func has_active_session() -> bool:
		return has_session

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────

var _svc: GameSaveService
var _mock_ss: MockSaveSystem
var _bus: MockEventBus

func before_each() -> void:
	_mock_ss = MockSaveSystem.new()
	_bus     = MockEventBus.new()
	_svc     = GameSaveService.new()
	_svc.configure(ServiceDeps.from_dict({
		"savesystem": _mock_ss,
		"event_bus":  _bus,
	}))

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null
	_mock_ss = null

# ─────────────────────────────────────────────────────────────────────────────
# save_all() — Grundverhalten
# ─────────────────────────────────────────────────────────────────────────────

func test_save_all_returns_true_on_success() -> void:
	_mock_ss.save_result = true
	var ok := _svc.save_all()
	assert_true(ok, "save_all() muss true zurückgeben wenn SaveSystem.save_game() true")

func test_save_all_returns_false_on_failure() -> void:
	_mock_ss.save_result = false
	var ok := _svc.save_all()
	assert_false(ok, "save_all() muss false zurückgeben wenn SaveSystem.save_game() false")

func test_save_all_delegates_to_save_system() -> void:
	_svc.save_all()
	assert_eq(_mock_ss.save_called, 1, "save_all() muss SaveSystem.save_game() genau einmal aufrufen")

# ─────────────────────────────────────────────────────────────────────────────
# save_all() — kein SaveSystem
# ─────────────────────────────────────────────────────────────────────────────

func test_save_all_returns_false_without_save_system() -> void:
	var svc2 := GameSaveService.new()
	svc2.configure(ServiceDeps.from_dict({}))  # kein savesystem
	var ok := svc2.save_all()
	assert_false(ok, "Kein SaveSystem → save_all() muss false zurückgeben")
	svc2.on_cleanup()

# ─────────────────────────────────────────────────────────────────────────────
# Doppelaufruf-Schutz (_is_saving Guard)
# ─────────────────────────────────────────────────────────────────────────────

func test_double_call_guard_prevents_reentrant_save() -> void:
	## Wir simulieren einen Reentranz-Versuch, indem wir _is_saving manuell setzen.
	## In echtem Code würde dies durch einen EventBus-Callback passieren.
	_svc._is_saving = true
	var ok := _svc.save_all()
	assert_false(ok, "Zweiter Aufruf während laufendem Save muss false zurückgeben")
	assert_eq(_mock_ss.save_called, 0, "SaveSystem.save_game() darf nicht aufgerufen worden sein")

func test_is_saving_reset_after_save() -> void:
	_svc.save_all()
	assert_false(_svc._is_saving, "_is_saving muss nach save_all() zurückgesetzt sein")
