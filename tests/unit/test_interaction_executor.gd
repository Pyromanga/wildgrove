# res://tests/unit/test_interaction_executor.gd
extends GutTest

## Unit-Tests für InteractionExecutor.
##
## Vorher ungetestet (Coverage-Lücke aus Architect-Review). Mit der Runde-4
## EventBus-Migration (deps.require(EVENT_BUS) statt AutoLoad) jetzt vollständig
## über MockEventBus isolierbar.
##
## Abgedeckt:
##   - configure(): _bus und _player_states korrekt gesetzt
##   - on_ready(): Signal-Connects auf injizierten Bus, nicht AutoLoad
##   - execute_action(): startet nur wenn Spieler frei ist
##   - execute_action(): blockiert wenn bereits eine Aktion läuft
##   - execute_action(): emittiert interaction_started
##   - execute_action(): setzt PlayerState auf BUSY
##   - cancel_interaction(): emittiert interaction_cancelled, setzt FREE
##   - cancel_interaction(): no-op wenn keine aktive Aktion
##   - _on_tween_finished(): emittiert interaction_finished, loot, xp, reward_text
##   - is_busy(): korrekt für aktive/inaktive Aktion
##   - on_cleanup(): disconnected beide Signale
##
## ADR-015 / MIGRATION-015 Phase 3 (Runde 5): Per-Player State —
##   - zwei Spieler können gleichzeitig beschäftigt sein
##   - cancel_interaction(peer_id) / _on_tween_finished(peer_id) /
##     movement_interrupted(peer_id) wirken nur auf den jeweiligen Spieler
##   - Default peer_id=1 bleibt rückwärtskompatibel zu Solo/Tier-1-Aufrufern

class MockPlayerStateService extends PlayerStateService:
	var _is_free: bool = true
	var last_state_set: int = -1
	func is_free(_pid: int = 1) -> bool: return _is_free
	func set_state(new_state: int, _pid: int = 1) -> void: last_state_set = new_state

## ADR-021 (R-5): spy statt echtem NetworkBridge — vermeidet SceneTree/
## multiplayer-Abhängigkeit von report_domain_event()'s echtem Tier-1/2-Zweig,
## der Test prüft nur DASS und mit WELCHEN Argumenten aufgerufen wird.
class MockNetworkBridge extends NetworkBridge:
	var reported_events: Array[Dictionary] = []
	func report_domain_event(event_name: String, payload: Dictionary, peer_id: int = 1) -> void:
		reported_events.append({"event_name": event_name, "payload": payload, "peer_id": peer_id})

var _executor: InteractionExecutor
var _bus:      MockEventBus
var _states:   MockPlayerStateService

func before_each() -> void:
	_executor = InteractionExecutor.new()
	_bus      = MockEventBus.new()
	_states   = MockPlayerStateService.new()
	_executor.configure(ServiceDeps.from_dict({
		ServiceKeys.PLAYER_STATES: _states,
		ServiceKeys.EVENT_BUS:     _bus,
	}))
	_executor.on_ready()

func _make_action(id: String = "chop", duration: float = 0.0) -> InteractableAction:
	var a := InteractableAction.new(id, "Test-Aktion")
	a.duration = duration
	return a

# ─────────────────────────────────────────────────────────────────────────────
# configure()
# ─────────────────────────────────────────────────────────────────────────────

func test_configure_sets_bus() -> void:
	assert_eq(_executor._bus, _bus, "_bus muss via deps.require(EVENT_BUS) gesetzt sein")

func test_configure_sets_player_states() -> void:
	assert_eq(_executor._player_states, _states, "_player_states muss gesetzt sein")

# ─────────────────────────────────────────────────────────────────────────────
# on_ready() — Signal-Connects auf injizierten Bus
# ─────────────────────────────────────────────────────────────────────────────

func test_on_ready_connects_movement_interrupted() -> void:
	assert_true(
		_bus.player().movement_interrupted.is_connected(_executor.cancel_interaction),
		"on_ready() muss movement_interrupted auf injiziertem Bus connecten"
	)

func test_on_ready_connects_interaction_execute_requested() -> void:
	assert_true(
		_bus.ui().interaction_execute_requested.is_connected(_executor.execute_action),
		"on_ready() muss interaction_execute_requested auf injiziertem Bus connecten"
	)

# ─────────────────────────────────────────────────────────────────────────────
# execute_action() — Guard-Verhalten
# ─────────────────────────────────────────────────────────────────────────────

func test_execute_action_starts_when_player_free() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action())
	assert_true(_executor.is_busy(), "execute_action() muss starten wenn Spieler frei ist")

func test_execute_action_blocked_when_player_busy() -> void:
	_states._is_free = false
	_executor.execute_action(_make_action())
	assert_false(_executor.is_busy(), "execute_action() darf nicht starten wenn Spieler beschäftigt ist")

func test_execute_action_blocked_when_already_active() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action("first"))
	_executor.execute_action(_make_action("second"))
	# Zweite Aktion darf die erste nicht überschreiben
	assert_true(_executor.is_busy(), "Erste Aktion muss aktiv bleiben")

func test_execute_action_sets_player_state_busy() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action())
	assert_eq(_states.last_state_set, PlayerStateService.State.BUSY,
		"execute_action() muss PlayerState auf BUSY setzen")

func test_execute_action_emits_interaction_started() -> void:
	_states._is_free = true
	watch_signals(_bus.world())
	_executor.execute_action(_make_action("chop", 2.0))
	assert_signal_emitted(_bus.world(), "interaction_started",
		"execute_action() muss interaction_started über injizierten Bus emittieren")

func test_execute_action_emits_correct_action_id() -> void:
	_states._is_free = true
	watch_signals(_bus.world())
	_executor.execute_action(_make_action("mine", 1.5))
	assert_signal_emitted_with_parameters(
		_bus.world(), "interaction_started", ["mine", "Test-Aktion", 1.5]
	)

# ─────────────────────────────────────────────────────────────────────────────
# cancel_interaction()
# ─────────────────────────────────────────────────────────────────────────────

func test_cancel_interaction_noop_when_nothing_active() -> void:
	watch_signals(_bus.world())
	_executor.cancel_interaction()
	assert_signal_not_emitted(_bus.world(), "interaction_cancelled",
		"cancel_interaction() ohne aktive Aktion darf nichts emittieren")

func test_cancel_interaction_emits_interaction_cancelled() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action("chop"))
	watch_signals(_bus.world())
	_executor.cancel_interaction()
	assert_signal_emitted(_bus.world(), "interaction_cancelled",
		"cancel_interaction() muss interaction_cancelled über injizierten Bus emittieren")

func test_cancel_interaction_sets_player_state_free() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action("chop"))
	_executor.cancel_interaction()
	assert_eq(_states.last_state_set, PlayerStateService.State.FREE,
		"cancel_interaction() muss PlayerState zurück auf FREE setzen")

func test_cancel_interaction_clears_active_action() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action("chop"))
	_executor.cancel_interaction()
	assert_false(_executor.is_busy(), "Nach cancel_interaction() darf is_busy() nicht mehr true sein")

# ─────────────────────────────────────────────────────────────────────────────
# is_busy()
# ─────────────────────────────────────────────────────────────────────────────

func test_is_busy_false_initially() -> void:
	assert_false(_executor.is_busy(), "is_busy() muss initial false sein")

func test_is_busy_true_after_execute() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action())
	assert_true(_executor.is_busy(), "is_busy() muss true sein während Aktion läuft")

# ─────────────────────────────────────────────────────────────────────────────
# _on_tween_finished() — Completion-Pfad
# ─────────────────────────────────────────────────────────────────────────────

func test_completion_emits_interaction_finished() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action("chop", 0.0))
	watch_signals(_bus.world())
	_executor._on_tween_finished()
	assert_signal_emitted(_bus.world(), "interaction_finished",
		"_on_tween_finished() muss interaction_finished über injizierten Bus emittieren")

func test_completion_reports_interaction_finished_as_domain_event() -> void:
	# ADR-021 (R-5), Option C: zusätzlich zum rein lokalen interaction_finished-
	# Signal muss dasselbe Ereignis autoritätsseitig gemeldet werden, sonst
	# können Nicht-Host-Spieler INTERACT-Quest-Objectives nie abschließen.
	_states._is_free = true
	var mock_network := MockNetworkBridge.new()
	_executor.inject_network_bridge(mock_network)
	var action := _make_action("chop", 0.0)
	action.peer_id = 3
	_executor.execute_action(action)
	_executor._on_tween_finished(3)
	assert_eq(mock_network.reported_events.size(), 1,
		"_on_tween_finished() muss genau ein Domain-Event melden")
	assert_eq(mock_network.reported_events[0]["event_name"], "interaction_finished")
	assert_eq(mock_network.reported_events[0]["payload"]["action_id"], "chop")
	assert_eq(mock_network.reported_events[0]["peer_id"], 3,
		"Muss den echten peer_id melden, nicht Default 1")

func test_completion_without_network_bridge_does_not_crash() -> void:
	# Kein inject_network_bridge() aufgerufen (z.B. isolierter Unit-Test) — darf
	# nicht crashen, is_instance_valid()-Guard greift.
	_states._is_free = true
	_executor.execute_action(_make_action("chop", 0.0))
	_executor._on_tween_finished()
	assert_true(true, "_on_tween_finished() ohne NetworkBridge darf nicht crashen.")

## ADR-020 / R-1 (Round 43): InteractionExecutor darf Loot/XP NICHT mehr selbst
## berechnen/emittieren — das lief hier vorher unguarded auf jedem ausführenden
## Peer (R-1) und ist jetzt nach InteractionResolver verschoben, aufgerufen aus
## dem authority-geguardeten _on_interacted()-Hook der jeweiligen Entity, NICHT
## von hier aus. Diese Tests sind Regressions-Schutz gegen ein Wieder-Einführen
## der alten, hier fälschbaren Berechnung — nicht mehr Tests FÜR eine Fähigkeit
## dieser Klasse. Der alte `action.drops`-Test existierte nie funktionsfähig
## (InteractableAction hat kein `drops`-Feld, nur `loot_table`) — beim Aufräumen
## dieser Runde entfernt statt migriert.
func test_completion_does_not_emit_loot_collected() -> void:
	_states._is_free = true
	var action := _make_action("mine", 0.0)
	var table := LootTable.new()
	var entry := LootEntry.new()
	entry.item_id      = "iron_ore"
	entry.weight        = 999.0
	entry.quantity_min  = 2
	entry.quantity_max  = 2
	table.entries       = [entry]
	table.max_rolls     = 1
	action.loot_table   = table
	_executor.execute_action(action)
	watch_signals(_bus.world())
	_executor._on_tween_finished()
	assert_signal_not_emitted(_bus.world(), "loot_collected",
		"InteractionExecutor darf loot_collected nicht mehr selbst emittieren (ADR-020/R-1) — das ist jetzt Aufgabe von InteractionResolver, aufgerufen aus dem authority-Hook der Entity.")

func test_completion_does_not_emit_xp_gained() -> void:
	_states._is_free = true
	var action := _make_action("chop", 0.0)
	action.xp_type   = "woodcutting"
	action.xp_amount = 5
	_executor.execute_action(action)
	watch_signals(_bus.player())
	_executor._on_tween_finished()
	assert_signal_not_emitted(_bus.player(), "xp_gained",
		"InteractionExecutor darf xp_gained nicht mehr selbst emittieren (ADR-020/R-1) — das ist jetzt Aufgabe von InteractionResolver, aufgerufen aus dem authority-Hook der Entity.")

func test_completion_without_xp_type_none_no_xp_emitted() -> void:
	_states._is_free = true
	var action := _make_action("inspect", 0.0)
	action.xp_type = "none"
	_executor.execute_action(action)
	watch_signals(_bus.player())
	_executor._on_tween_finished()
	assert_signal_not_emitted(_bus.player(), "xp_gained",
		"xp_type='none' darf kein xp_gained Signal emittieren")

func test_completion_with_inspect_text_emits_reward_text() -> void:
	_states._is_free = true
	var action := _make_action("inspect", 0.0)
	action.inspect_text = "Ein gewöhnlicher Stein."
	_executor.execute_action(action)
	watch_signals(_bus.world())
	_executor._on_tween_finished()
	assert_signal_emitted_with_parameters(
		_bus.world(), "interaction_reward_text", ["Ein gewöhnlicher Stein."]
	)

func test_completion_calls_on_complete_callback() -> void:
	_states._is_free = true
	var action  := _make_action("chop", 0.0)
	var called  := [false]
	action.on_complete = func(_peer_id: int) -> void: called[0] = true
	_executor.execute_action(action)
	_executor._on_tween_finished()
	assert_true(called[0], "_on_tween_finished() muss on_complete-Callback aufrufen")

func test_completion_passes_peer_id_to_on_complete() -> void:
	## ADR-015 / MIGRATION-015 Phase 4: on_complete bekommt jetzt den echten
	## peer_id durchgereicht, nicht nur irgendeinen Wert.
	_states._is_free = true
	var action := _make_action("chop", 0.0)
	action.peer_id = 7
	var received := [-1]
	action.on_complete = func(peer_id: int) -> void: received[0] = peer_id
	_executor.execute_action(action)
	_executor._on_tween_finished(7)
	assert_eq(received[0], 7, "on_complete muss den peer_id erhalten, der die Aktion ausgeführt hat")

func test_completion_sets_player_state_free() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action("chop", 0.0))
	_executor._on_tween_finished()
	assert_eq(_states.last_state_set, PlayerStateService.State.FREE,
		"_on_tween_finished() muss PlayerState zurück auf FREE setzen")

func test_completion_clears_active_action() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action("chop", 0.0))
	_executor._on_tween_finished()
	assert_false(_executor.is_busy(), "Nach Completion darf is_busy() nicht mehr true sein")

func test_tween_finished_noop_when_nothing_active() -> void:
	watch_signals(_bus.world())
	_executor._on_tween_finished()
	assert_signal_not_emitted(_bus.world(), "interaction_finished",
		"_on_tween_finished() ohne aktive Aktion darf nichts emittieren")

# ─────────────────────────────────────────────────────────────────────────────
# on_cleanup()
# ─────────────────────────────────────────────────────────────────────────────

func test_on_cleanup_disconnects_movement_interrupted() -> void:
	_executor.on_cleanup()
	assert_false(
		_bus.player().movement_interrupted.is_connected(_executor.cancel_interaction),
		"on_cleanup() muss movement_interrupted disconnecten"
	)

func test_on_cleanup_disconnects_interaction_execute_requested() -> void:
	_executor.on_cleanup()
	assert_false(
		_bus.ui().interaction_execute_requested.is_connected(_executor.execute_action),
		"on_cleanup() muss interaction_execute_requested disconnecten"
	)

func test_on_cleanup_twice_no_crash() -> void:
	_executor.on_cleanup()
	_executor.on_cleanup()
	assert_true(true, "Zweites on_cleanup() darf nicht crashen (is_connected-Guard)")

# ─────────────────────────────────────────────────────────────────────────────
# ADR-015 / MIGRATION-015 Phase 3 — Per-Player State
#
# Regressions-Schutz für den Kern-Bug: vorher hielt InteractionExecutor
# _active_action/_active_tween GLOBAL, nicht pro Spieler. Sobald Spieler A
# eine Interaktion startete, lehnte execute_action() für JEDEN anderen
# Spieler ab — kein Edge-Case, sondern der Normalfall bei zwei gleichzeitig
# aktiven Spielern.
# ─────────────────────────────────────────────────────────────────────────────

func _make_action_for(peer_id: int, id: String = "chop", duration: float = 0.0) -> InteractableAction:
	var a := _make_action(id, duration)
	a.peer_id = peer_id
	return a

func test_two_players_can_be_busy_simultaneously() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action_for(1, "chop"))
	_executor.execute_action(_make_action_for(2, "mine"))
	assert_true(_executor.is_busy(1), "Spieler 1 muss beschäftigt sein")
	assert_true(_executor.is_busy(2), "Spieler 2 darf NICHT durch Spieler 1 blockiert werden")

func test_player_starting_second_action_does_not_block_other_player() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action_for(1, "first"))
	# Spieler 2 startet währenddessen etwas anderes — muss unabhängig funktionieren.
	_executor.execute_action(_make_action_for(2, "second"))
	assert_true(_executor.is_busy(1))
	assert_true(_executor.is_busy(2))
	# Spieler 1 selbst darf weiterhin nicht überschrieben werden (Re-Entrancy-Guard).
	_executor.execute_action(_make_action_for(1, "third"))
	assert_eq(_executor._active[1]["action"].id, "first",
		"Spieler 1s laufende Aktion darf nicht durch eine dritte Anfrage überschrieben werden")

func test_cancel_interaction_only_cancels_that_player() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action_for(1, "chop"))
	_executor.execute_action(_make_action_for(2, "mine"))
	_executor.cancel_interaction(1)
	assert_false(_executor.is_busy(1), "Spieler 1 muss nach cancel_interaction(1) frei sein")
	assert_true(_executor.is_busy(2), "Spieler 2 darf von cancel_interaction(1) unberührt bleiben")

func test_tween_finished_only_completes_that_player() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action_for(1, "chop"))
	_executor.execute_action(_make_action_for(2, "mine"))
	watch_signals(_bus.world())
	_executor._on_tween_finished(1)
	assert_false(_executor.is_busy(1), "Spieler 1 muss nach Completion frei sein")
	assert_true(_executor.is_busy(2), "Spieler 2 darf von Spieler 1s Completion unberührt bleiben")
	assert_signal_emitted(_bus.world(), "interaction_finished")

func test_movement_interrupted_cancels_only_that_player() -> void:
	_states._is_free = true
	_executor.execute_action(_make_action_for(1, "chop"))
	_executor.execute_action(_make_action_for(2, "mine"))
	_bus.player().emit_movement_interrupted(2)
	assert_true(_executor.is_busy(1), "movement_interrupted(2) darf Spieler 1 nicht abbrechen")
	assert_false(_executor.is_busy(2), "movement_interrupted(2) muss Spieler 2 abbrechen")

func test_default_peer_id_is_one_for_backwards_compatibility() -> void:
	# InteractableAction.peer_id default = 1 → bestehende Solo/Tier-1-Aufrufer
	# ohne explizites peer_id verhalten sich unverändert.
	_states._is_free = true
	_executor.execute_action(_make_action("chop"))
	assert_true(_executor.is_busy(), "is_busy() ohne Argument muss Spieler 1 (Default) meinen")
	assert_true(_executor.is_busy(1), "is_busy(1) muss identisch zu is_busy() sein")
