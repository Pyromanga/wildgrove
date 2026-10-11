# res://tests/unit/test_skill_system_signals.gd
extends GutTest

## Signal-Tests für SkillSystem (H-07 / EventBus-Injektion).
##
## Testet:
##   - xp_gained-Signal aus MockEventBus triggert (über _on_xp_gained/
##     _resolve_player_uuid) request_add_xp (on_ready-Connection)
##   - level_up-Signal wird emittiert wenn Schwellenwert erreicht
##   - on_cleanup() trennt alle Connections
##   - Kein globales Signal-Bleeding zwischen zwei Instanzen
##
## ADR-029 Plan-Schritt 4 (Round 65): xp_gained liefert weiterhin peer_id
## (int) — SkillSystem übersetzt das intern über
## NetworkBridge.get_player_id_for_peer() (_resolve_player_uuid()). Ohne
## NetworkBridge+SessionManager bleibt diese Übersetzung leer und
## _on_xp_gained() no-oppt (mit Logged Error) — dieselbe Verdrahtung wie
## test_quest_service_signals.gd (Round 64).

## XP-Kurve level * 100 — analog zu test_skill_system.gd, damit die
## Level-Up-Testwerte (100 / 150 / 300 XP) unverändert gelten.
class MockSkillDef extends SkillDefinition:
	func _init(p_id: String) -> void:
		id = p_id

	func get_xp_required(level: int) -> int:
		return level * 100

class MockDataService extends DataService:
	func get_all_skills() -> Dictionary:
		return _skills

var _bus:     MockEventBus
var _svc:     SkillSystem
var _save:    SaveSystem
var _session: SessionManager
var _network: NetworkBridge
var _ds:      MockDataService

const P1 := "p1"

func before_each() -> void:
	_bus  = MockEventBus.new()
	_save = _make_stub_save()

	_ds = MockDataService.new()
	_ds._skills["woodcutting"] = MockSkillDef.new("woodcutting")
	_ds._skills["mining"]      = MockSkillDef.new("mining")

	_session = SessionManager.new()
	_session.register_player_slot(1, P1)
	add_child_autofree(_session)

	_network = NetworkBridge.new()
	_network.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS:       _bus,
		ServiceKeys.SESSION_MANAGER: _session,
	}))
	add_child_autofree(_network)

	_svc  = SkillSystem.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:           _ds,
		ServiceKeys.SAVE_SYSTEM:    _save,
		ServiceKeys.EVENT_BUS:      _bus,
		ServiceKeys.NETWORK_BRIDGE: _network,
	}))
	_svc.on_ready()
	_svc.inject_network_bridge(_network)

func after_each() -> void:
	_svc.on_cleanup()
	_svc     = null
	_bus     = null
	_save    = null
	_session = null
	_network = null

# ─────────────────────────────────────────────────────────────────────────────
# on_ready Signal-Connections
# ─────────────────────────────────────────────────────────────────────────────

func test_on_ready_connects_xp_gained_to_on_xp_gained() -> void:
	assert_true(
		_bus.player().xp_gained.is_connected(_svc._on_xp_gained),
		"on_ready() muss xp_gained mit _on_xp_gained verbinden."
	)

func test_xp_gained_signal_triggers_xp_addition() -> void:
	## KERNTEST: Dieser Test war vor dem Refactor unmöglich.
	## xp_gained kommt vom MockEventBus — kein globaler AutoLoad nötig.
	_bus.player().emit_xp_gained("woodcutting", 50)
	assert_eq(_svc.get_xp("woodcutting", P1), 50,
		"xp_gained-Signal muss XP über request_add_xp addieren.")

func test_xp_gained_signal_accumulates_multiple_events() -> void:
	_bus.player().emit_xp_gained("woodcutting", 30)
	_bus.player().emit_xp_gained("woodcutting", 20)
	assert_eq(_svc.get_xp("woodcutting", P1), 50,
		"Mehrere xp_gained-Signale müssen akkumulieren.")

func test_xp_gained_signal_routes_to_correct_skill() -> void:
	_bus.player().emit_xp_gained("mining", 40)
	assert_eq(_svc.get_xp("mining", P1), 40,     "Mining muss 40 XP haben.")
	assert_eq(_svc.get_xp("woodcutting", P1), 0, "Woodcutting muss 0 XP haben.")

# ─────────────────────────────────────────────────────────────────────────────
# level_up Signal
# ─────────────────────────────────────────────────────────────────────────────

func test_level_up_signal_emitted_on_threshold() -> void:
	## SkillSystem verwendet Fallback: level * 100 XP für den nächsten Level.
	## Level 1 → Level 2 braucht 100 XP.
	watch_signals(_bus.player())
	_bus.player().emit_xp_gained("woodcutting", 100)
	assert_signal_emitted(_bus.player(), "level_up",
		"level_up muss emittiert werden wenn XP-Schwellenwert erreicht.")

func test_level_up_signal_carries_skill_and_level() -> void:
	watch_signals(_bus.player())
	_bus.player().emit_xp_gained("woodcutting", 100)
	assert_signal_emitted_with_parameters(
		_bus.player(), "level_up", ["woodcutting", 2]
	)

func test_no_level_up_below_threshold() -> void:
	watch_signals(_bus.player())
	_bus.player().emit_xp_gained("woodcutting", 99)
	assert_signal_not_emitted(_bus.player(), "level_up",
		"level_up darf nicht emittiert werden unter dem XP-Schwellenwert.")

func test_multiple_level_ups_in_one_xp_burst() -> void:
	## 300 XP: Level 1→2 (100 XP), 2→3 (200 XP) — beide in einem Signal.
	watch_signals(_bus.player())
	_bus.player().emit_xp_gained("woodcutting", 300)
	var count = get_signal_emit_count(_bus.player(), "level_up")
	assert_eq(count, 2,
		"300 XP sollten zwei level_up-Signale auslösen (Level 2 und Level 3).")

# ─────────────────────────────────────────────────────────────────────────────
# on_cleanup
# ─────────────────────────────────────────────────────────────────────────────

func test_on_cleanup_disconnects_xp_gained() -> void:
	_svc.on_cleanup()
	assert_false(
		_bus.player().xp_gained.is_connected(_svc._on_xp_gained),
		"on_cleanup() muss xp_gained disconnecten."
	)

func test_xp_gained_after_cleanup_does_not_add_xp() -> void:
	_svc.on_cleanup()
	_bus.player().emit_xp_gained("woodcutting", 50)
	# Nach cleanup ist Connection getrennt — XP kommt nicht an
	assert_eq(_svc.get_xp("woodcutting", P1), 0,
		"Nach on_cleanup() darf xp_gained keine XP mehr addieren.")

# ─────────────────────────────────────────────────────────────────────────────
# Kein Signal-Bleeding
# ─────────────────────────────────────────────────────────────────────────────

func test_two_instances_dont_share_xp_from_same_signal_source() -> void:
	var bus2 := MockEventBus.new()
	var ds2  := MockDataService.new()
	ds2._skills["woodcutting"] = MockSkillDef.new("woodcutting")
	ds2._skills["mining"]      = MockSkillDef.new("mining")

	var session2 := SessionManager.new()
	session2.register_player_slot(1, P1)
	add_child_autofree(session2)

	var network2 := NetworkBridge.new()
	network2.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS:       bus2,
		ServiceKeys.SESSION_MANAGER: session2,
	}))
	add_child_autofree(network2)

	var svc2  := SkillSystem.new()
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:           ds2,
		ServiceKeys.SAVE_SYSTEM:    _make_stub_save(),
		ServiceKeys.EVENT_BUS:      bus2,
		ServiceKeys.NETWORK_BRIDGE: network2,
	}))
	svc2.on_ready()
	svc2.inject_network_bridge(network2)

	# Nur _bus.player().emit_xp_gained — nicht bus2
	_bus.player().emit_xp_gained("woodcutting", 50)

	assert_eq(_svc.get_xp("woodcutting", P1), 50, "Instanz 1 muss XP haben.")
	assert_eq(svc2.get_xp("woodcutting", P1), 0,  "Instanz 2 darf keine XP haben (kein Bleeding).")

	svc2.on_cleanup()

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _make_stub_save() -> SaveSystem:
	var stub := SaveSystem.new()
	stub.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new()}))
	return stub
