# res://tests/unit/test_player_state_service.gd
extends GutTest

## Unit-Tests für PlayerStateService (E-02).
##
## Strategie: PlayerStateService extends Service (RefCounted) — kein add_child nötig.
## configure() ohne deps. on_ready() nicht aufgerufen (kein EventBus-Connect nötig).
## Direkter Aufruf von set_state() / get_state() / is_free() etc.
##
## Abgedeckt:
##   - Startzustand: FREE für jeden Spieler
##   - set_state(): Übergänge FREE/BUSY/MENU
##   - is_free() / is_busy() / is_in_menu()
##   - Same-state: kein Doppel-Emit (indirekt: kein Crash)
##   - Multi-Tenanz: zwei peer_ids unabhängig

var _svc: PlayerStateService

func before_each() -> void:
	_svc = PlayerStateService.new()
	_svc.configure(ServiceDeps.from_dict({}))

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null

# ─────────────────────────────────────────────────────────────────────────────
# Startzustand
# ─────────────────────────────────────────────────────────────────────────────

func test_default_state_is_free() -> void:
	assert_eq(_svc.get_state(), PlayerStateService.State.FREE,
		"Startzustand muss FREE sein")

func test_is_free_true_by_default() -> void:
	assert_true(_svc.is_free(), "is_free() muss true im Startzustand sein")

func test_is_busy_false_by_default() -> void:
	assert_false(_svc.is_busy(), "is_busy() muss false im Startzustand sein")

func test_is_in_menu_false_by_default() -> void:
	assert_false(_svc.is_in_menu(), "is_in_menu() muss false im Startzustand sein")

# ─────────────────────────────────────────────────────────────────────────────
# set_state / Übergänge
# ─────────────────────────────────────────────────────────────────────────────

func test_set_busy() -> void:
	_svc.set_state(PlayerStateService.State.BUSY)
	assert_eq(_svc.get_state(), PlayerStateService.State.BUSY)
	assert_true(_svc.is_busy())
	assert_false(_svc.is_free())

func test_set_menu() -> void:
	_svc.set_state(PlayerStateService.State.MENU)
	assert_eq(_svc.get_state(), PlayerStateService.State.MENU)
	assert_true(_svc.is_in_menu())
	assert_false(_svc.is_free())

func test_set_free_from_busy() -> void:
	_svc.set_state(PlayerStateService.State.BUSY)
	_svc.set_state(PlayerStateService.State.FREE)
	assert_true(_svc.is_free(), "Rückkehr zu FREE muss funktionieren")

func test_set_same_state_no_crash() -> void:
	_svc.set_state(PlayerStateService.State.BUSY)
	_svc.set_state(PlayerStateService.State.BUSY)  # kein Crash, kein Doppel-Emit
	assert_true(_svc.is_busy(), "State muss gleich bleiben")

# ─────────────────────────────────────────────────────────────────────────────
# Multi-Tenanz (MIGRATION-010)
# ─────────────────────────────────────────────────────────────────────────────

func test_two_players_independent_state() -> void:
	_svc.set_state(PlayerStateService.State.BUSY, 1)
	_svc.set_state(PlayerStateService.State.MENU, 2)

	assert_true(_svc.is_busy(1),    "Spieler 1 muss BUSY sein")
	assert_false(_svc.is_busy(2),   "Spieler 2 darf nicht BUSY sein")
	assert_true(_svc.is_in_menu(2), "Spieler 2 muss MENU sein")
	assert_false(_svc.is_in_menu(1),"Spieler 1 darf nicht MENU sein")

func test_change_player1_does_not_affect_player2() -> void:
	_svc.set_state(PlayerStateService.State.FREE, 2)
	_svc.set_state(PlayerStateService.State.BUSY, 1)
	assert_true(_svc.is_free(2), "Spieler 2 muss unverändert FREE sein")

func test_default_state_for_new_player_is_free() -> void:
	# peer_id 99 — nie zuvor verwendet
	assert_true(_svc.is_free(99), "Neuer Spieler muss FREE sein (Default)")
