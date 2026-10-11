# res://tests/unit/test_player_state_service_signals.gd
extends GutTest

## Signal-Tests für PlayerStateService (H-07 / EventBus-Injektion).
##
## Testet das Signal-Wiring das vorher komplett unbetestbar war:
##   - state_changed von MockEventBus triggert _on_game_state_changed
##   - player_state_changed wird korrekt emittiert
##   - input_reset_requested wird bei FREE-Transition emittiert

var _bus: MockEventBus
var _svc: PlayerStateService

func before_each() -> void:
	_bus = MockEventBus.new()
	_svc = PlayerStateService.new()
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	_svc.on_ready()

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null
	_bus = null

# ─────────────────────────────────────────────────────────────────────────────
# on_ready Connections
# ─────────────────────────────────────────────────────────────────────────────

func test_on_ready_connects_state_changed() -> void:
	assert_true(
		_bus.system().state_changed.is_connected(_svc._on_game_state_changed),
		"on_ready() muss system.state_changed mit _on_game_state_changed verbinden."
	)

# ─────────────────────────────────────────────────────────────────────────────
# state_changed → PlayerStateService Reaktion (vorher KOMPLETT unbetestbar)
# ─────────────────────────────────────────────────────────────────────────────

func test_game_state_playing_sets_player_free() -> void:
	# Zuerst in MENU setzen
	_bus.system().state_changed.emit(GameEnums.State.MAIN_MENU)
	assert_eq(_svc.get_state(), PlayerStateService.State.MENU,
		"MAIN_MENU state muss Player auf MENU setzen.")

	# Dann PLAYING → FREE
	_bus.system().state_changed.emit(GameEnums.State.PLAYING)
	assert_eq(_svc.get_state(), PlayerStateService.State.FREE,
		"PLAYING state muss Player auf FREE setzen.")

func test_game_state_non_playing_sets_player_menu() -> void:
	_bus.system().state_changed.emit(GameEnums.State.MAIN_MENU)
	assert_eq(_svc.get_state(), PlayerStateService.State.MENU,
		"Nicht-PLAYING state muss Player auf MENU setzen.")

func test_game_state_paused_sets_player_menu() -> void:
	_bus.system().state_changed.emit(GameEnums.State.PAUSED)
	assert_eq(_svc.get_state(), PlayerStateService.State.MENU,
		"PAUSED state muss Player auf MENU setzen.")

# ─────────────────────────────────────────────────────────────────────────────
# player_state_changed Signal Output
# ─────────────────────────────────────────────────────────────────────────────

func test_player_state_changed_emitted_on_set_state() -> void:
	watch_signals(_bus.player())
	_svc.set_state(PlayerStateService.State.BUSY)
	assert_signal_emitted(_bus.player(), "player_state_changed",
		"player_state_changed muss nach set_state() emittiert werden.")

func test_player_state_changed_carries_new_state() -> void:
	watch_signals(_bus.player())
	_svc.set_state(PlayerStateService.State.BUSY)
	assert_signal_emitted_with_parameters(
		_bus.player(), "player_state_changed",
		[PlayerStateService.State.BUSY]
	)

func test_player_state_changed_not_emitted_if_same_state() -> void:
	# State ist schon FREE (default)
	watch_signals(_bus.player())
	_svc.set_state(PlayerStateService.State.FREE)
	assert_signal_not_emitted(_bus.player(), "player_state_changed",
		"player_state_changed darf nicht emittiert werden wenn State gleich bleibt."
	)

# ─────────────────────────────────────────────────────────────────────────────
# input_reset_requested bei FREE-Transition
# ─────────────────────────────────────────────────────────────────────────────

func test_input_reset_requested_emitted_on_transition_to_free() -> void:
	_svc.set_state(PlayerStateService.State.BUSY)
	watch_signals(_bus.player())
	_svc.set_state(PlayerStateService.State.FREE)
	assert_signal_emitted(_bus.player(), "input_reset_requested",
		"input_reset_requested muss emittiert werden wenn State auf FREE wechselt."
	)

func test_input_reset_not_emitted_on_transition_to_busy() -> void:
	watch_signals(_bus.player())
	_svc.set_state(PlayerStateService.State.BUSY)
	assert_signal_not_emitted(_bus.player(), "input_reset_requested",
		"input_reset_requested darf nicht bei BUSY-Transition emittiert werden."
	)

# ─────────────────────────────────────────────────────────────────────────────
# Vollständiger Durchlauf: game state_changed → player reagiert → Signal raus
# ─────────────────────────────────────────────────────────────────────────────

func test_full_round_trip_game_state_to_player_signal() -> void:
	## DER KRITISCHE END-TO-END-PFAD:
	## GameManager emittiert state_changed → PlayerStateService reagiert →
	## player_state_changed emittiert → UI kann darauf reagieren.
	## Vor dem Refactor war dieser Pfad in keinem einzigen Test abgedeckt.
	_svc.set_state(PlayerStateService.State.BUSY)
	watch_signals(_bus.player())

	_bus.system().state_changed.emit(GameEnums.State.PLAYING)

	assert_signal_emitted(_bus.player(), "player_state_changed",
		"Game state_changed muss über PlayerStateService player_state_changed auslösen.")
	assert_signal_emitted(_bus.player(), "input_reset_requested",
		"Wechsel zu FREE muss input_reset_requested auslösen.")

# ─────────────────────────────────────────────────────────────────────────────
# on_cleanup
# ─────────────────────────────────────────────────────────────────────────────

func test_on_cleanup_disconnects_state_changed() -> void:
	_svc.on_cleanup()
	assert_false(
		_bus.system().state_changed.is_connected(_svc._on_game_state_changed),
		"on_cleanup() muss state_changed disconnecten."
	)

func test_state_changed_after_cleanup_does_not_change_player_state() -> void:
	_svc.set_state(PlayerStateService.State.BUSY)
	_svc.on_cleanup()
	_bus.system().state_changed.emit(GameEnums.State.PLAYING)
	assert_eq(_svc.get_state(), PlayerStateService.State.BUSY,
		"Nach on_cleanup() darf state_changed den Player-State nicht mehr ändern."
	)
