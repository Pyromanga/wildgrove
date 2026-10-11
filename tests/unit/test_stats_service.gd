# res://tests/unit/test_stats_service.gd
extends GutTest

## Unit-Tests für StatsService (ADR-047 "Statistiken").
##
## Strategie: StatsService extends Service (RefCounted). MockEventBus für
## die beiden autoritativen Quell-Signale (player().movement_stats_batch/
## world().enemy_killed), SpyNetworkBridge für die peer_id->player_id-
## Übersetzung (get_player_id_for_peer()).

const PEER_1 := 1
const PEER_2 := 2
const P1 := "player-1"
const P2 := "player-2"

var _svc: StatsService
var _bus: MockEventBus

class SpyNetworkBridge extends NetworkBridge:
	var peer_to_player: Dictionary = {}
	func get_player_id_for_peer(peer_id: int) -> String:
		return String(peer_to_player.get(peer_id, ""))

var _net: SpyNetworkBridge

func before_each() -> void:
	_bus = MockEventBus.new()
	_net = SpyNetworkBridge.new()
	_net.peer_to_player = {PEER_1: P1, PEER_2: P2}
	add_child_autofree(_net)

	_svc = StatsService.new()
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	_svc.inject_network_bridge(_net)

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null
	_bus = null
	_net = null

# ─────────────────────────────────────────────────────────────────────────────
# add_stat() / get_stat() / get_all_stats()
# ─────────────────────────────────────────────────────────────────────────────

func test_add_stat_accumulates() -> void:
	_svc.add_stat(P1, StatsService.STAT_METERS_WALKED, 100.0)
	_svc.add_stat(P1, StatsService.STAT_METERS_WALKED, 50.0)
	assert_eq(_svc.get_stat(P1, StatsService.STAT_METERS_WALKED), 150.0)

func test_add_stat_is_per_player() -> void:
	_svc.add_stat(P1, StatsService.STAT_NPCS_KILLED, 5.0)
	assert_eq(_svc.get_stat(P2, StatsService.STAT_NPCS_KILLED), 0.0)

func test_add_stat_ignores_empty_ids() -> void:
	_svc.add_stat("", StatsService.STAT_METERS_WALKED, 10.0)
	_svc.add_stat(P1, "", 10.0)
	assert_eq(_svc.get_all_stats(P1).size(), 0)

func test_stat_changed_signal_fires_with_delta_and_total() -> void:
	var events: Array = []
	_svc.stat_changed.connect(func(player_id, stat_name, delta, new_total): events.append([player_id, stat_name, delta, new_total]))
	_svc.add_stat(P1, StatsService.STAT_METERS_JUMPED, 10.0)
	_svc.add_stat(P1, StatsService.STAT_METERS_JUMPED, 5.0)
	assert_eq(events, [[P1, StatsService.STAT_METERS_JUMPED, 10.0, 10.0], [P1, StatsService.STAT_METERS_JUMPED, 5.0, 15.0]])

func test_get_all_stats_returns_a_copy() -> void:
	_svc.add_stat(P1, StatsService.STAT_METERS_WALKED, 10.0)
	var copy := _svc.get_all_stats(P1)
	copy[StatsService.STAT_METERS_WALKED] = 999.0
	assert_eq(_svc.get_stat(P1, StatsService.STAT_METERS_WALKED), 10.0)

func test_unknown_stat_defaults_to_zero() -> void:
	assert_eq(_svc.get_stat(P1, "never_tracked"), 0.0)

# ─────────────────────────────────────────────────────────────────────────────
# Trigger-Verdrahtung: movement_stats_batch
# ─────────────────────────────────────────────────────────────────────────────

func test_movement_stats_batch_adds_all_three_stats() -> void:
	_bus.player().emit_movement_stats_batch(PEER_1, 100.0, 20.0, 5.0)
	assert_eq(_svc.get_stat(P1, StatsService.STAT_METERS_WALKED), 100.0)
	assert_eq(_svc.get_stat(P1, StatsService.STAT_METERS_JUMPED), 20.0)
	assert_eq(_svc.get_stat(P1, StatsService.STAT_METERS_FALLEN), 5.0)

func test_movement_stats_batch_skips_zero_values() -> void:
	var events: Array = []
	_svc.stat_changed.connect(func(player_id, stat_name, delta, new_total): events.append(stat_name))
	_bus.player().emit_movement_stats_batch(PEER_1, 50.0, 0.0, 0.0)
	assert_eq(events, [StatsService.STAT_METERS_WALKED])

func test_movement_stats_batch_ignores_unresolvable_peer() -> void:
	_bus.player().emit_movement_stats_batch(999, 50.0, 0.0, 0.0)
	assert_eq(_svc.get_all_stats(P1).size(), 0)

func test_movement_stats_batch_resolves_correct_player_per_peer() -> void:
	_bus.player().emit_movement_stats_batch(PEER_1, 100.0, 0.0, 0.0)
	_bus.player().emit_movement_stats_batch(PEER_2, 300.0, 0.0, 0.0)
	assert_eq(_svc.get_stat(P1, StatsService.STAT_METERS_WALKED), 100.0)
	assert_eq(_svc.get_stat(P2, StatsService.STAT_METERS_WALKED), 300.0)

# ─────────────────────────────────────────────────────────────────────────────
# Trigger-Verdrahtung: enemy_killed
# ─────────────────────────────────────────────────────────────────────────────

func test_enemy_killed_increments_npcs_killed() -> void:
	_bus.world().emit_enemy_killed("goblin", Vector3.ZERO, PEER_1)
	assert_eq(_svc.get_stat(P1, StatsService.STAT_NPCS_KILLED), 1.0)

func test_enemy_killed_accumulates_across_multiple_kills() -> void:
	_bus.world().emit_enemy_killed("goblin", Vector3.ZERO, PEER_1)
	_bus.world().emit_enemy_killed("skeleton", Vector3.ZERO, PEER_1)
	_bus.world().emit_enemy_killed("goblin", Vector3.ZERO, PEER_1)
	assert_eq(_svc.get_stat(P1, StatsService.STAT_NPCS_KILLED), 3.0)

# ─────────────────────────────────────────────────────────────────────────────
# on_cleanup()
# ─────────────────────────────────────────────────────────────────────────────

func test_on_cleanup_disconnects_bus_signals() -> void:
	_svc.on_cleanup()
	_bus.world().emit_enemy_killed("goblin", Vector3.ZERO, PEER_1)
	_bus.player().emit_movement_stats_batch(PEER_1, 100.0, 0.0, 0.0)
	assert_eq(_svc.get_all_stats(P1).size(), 0, "Nach on_cleanup() dürfen die Bus-Signale keine Wirkung mehr haben.")

# ─────────────────────────────────────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────────────────────────────────────

func test_save_key_is_stats() -> void:
	assert_eq(_svc.get_save_key(), "stats")

func test_save_data_empty_by_default() -> void:
	assert_true((_svc.get_save_data()["stats"] as Dictionary).is_empty())

func test_save_data_round_trip_preserves_stats() -> void:
	_svc.add_stat(P1, StatsService.STAT_METERS_WALKED, 250.0)
	var snapshot := _svc.get_save_data()

	var svc2 := StatsService.new()
	svc2.configure(ServiceDeps.from_dict({}))
	svc2._restore_from_save(snapshot)

	assert_eq(svc2.get_stat(P1, StatsService.STAT_METERS_WALKED), 250.0)
	svc2.on_cleanup()
