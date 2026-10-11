# res://tests/unit/test_aura_service.gd
extends GutTest

## Unit-Tests für AuraService (ADR-036 "Aura/Gesinnung").
##
## Strategie: AuraService extends Service (RefCounted) — kein add_child nötig
## (analog test_pvp_service.gd). savesystem/network_bridge sind beide
## optional_deps — Tests konfigurieren sie nur dort, wo der jeweilige Test
## sie braucht (Save-Round-Trip bzw. Routing).
##
## Abgedeckt:
##   - get_aura(): Default 0 für unbekannten Spieler
##   - apply_kill_penalty(): senkt Aura, geclamped an AURA_MIN
##   - is_below_vulnerability_threshold(): Grenzfall exakt AN der Schwelle
##     (muss false liefern — "unterhalb", nicht "auf")
##   - request_thank()/on_thank_confirmed(): Erfolg, Cooldown-Ablehnung,
##     Selbst-Dank abgelehnt, Gain-Formel (negative vs. nicht-negative Aura),
##     geclamped an AURA_MAX
##   - Cooldown ist PAAR-symmetrisch (a→b sperrt auch b→a) UND
##     richtungsunabhängig als Schlüssel (_pair_key sortiert)
##   - Save-Interface: get_save_key(), Round-Trip für Aura UND Cooldowns,
##     abgelaufene Cooldowns werden beim Speichern gefiltert

const P1 := "p1"
const P2 := "p2"
const P3 := "p3"

var _svc: AuraService
var _save: SaveSystem

func before_each() -> void:
	_save = SaveSystem.new()
	_save.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new()}))
	_svc = AuraService.new()
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save}))

func after_each() -> void:
	_svc = null

# ─────────────────────────────────────────────────────────────────────────────
# get_aura() / apply_kill_penalty()
# ─────────────────────────────────────────────────────────────────────────────

func test_get_aura_defaults_to_zero() -> void:
	assert_eq(_svc.get_aura(P1), 0)

func test_apply_kill_penalty_lowers_aura() -> void:
	_svc.apply_kill_penalty(P1)
	assert_eq(_svc.get_aura(P1), AuraService.KILL_PENALTY)

func test_apply_kill_penalty_accumulates() -> void:
	_svc.apply_kill_penalty(P1)
	_svc.apply_kill_penalty(P1)
	assert_eq(_svc.get_aura(P1), AuraService.KILL_PENALTY * 2)

func test_apply_kill_penalty_clamps_at_aura_min() -> void:
	for i in range(100):
		_svc.apply_kill_penalty(P1)
	assert_eq(_svc.get_aura(P1), AuraService.AURA_MIN)

func test_apply_kill_penalty_emits_aura_changed() -> void:
	var received := []
	_svc.aura_changed.connect(func(pid, new_aura, delta): received.append([pid, new_aura, delta]))
	_svc.apply_kill_penalty(P1)
	assert_eq(received, [[P1, AuraService.KILL_PENALTY, AuraService.KILL_PENALTY]])

func test_apply_kill_penalty_empty_player_id_is_noop() -> void:
	_svc.apply_kill_penalty("")
	assert_eq(_svc.get_aura(""), 0)

# ─────────────────────────────────────────────────────────────────────────────
# is_below_vulnerability_threshold()
# ─────────────────────────────────────────────────────────────────────────────

func test_is_below_vulnerability_threshold_false_by_default() -> void:
	assert_false(_svc.is_below_vulnerability_threshold(P1))

func test_is_below_vulnerability_threshold_true_when_below() -> void:
	_svc._aura[P1] = AuraService.AURA_VULNERABILITY_THRESHOLD - 1
	assert_true(_svc.is_below_vulnerability_threshold(P1))

func test_is_below_vulnerability_threshold_false_exactly_at_threshold() -> void:
	# Grenzfall: "unterhalb", nicht "auf" der Schwelle.
	_svc._aura[P1] = AuraService.AURA_VULNERABILITY_THRESHOLD
	assert_false(_svc.is_below_vulnerability_threshold(P1))

# ─────────────────────────────────────────────────────────────────────────────
# request_thank() / on_thank_confirmed()
# ─────────────────────────────────────────────────────────────────────────────

func test_thank_raises_aura_of_target() -> void:
	_svc.on_thank_confirmed(P1, P2)
	assert_gt(_svc.get_aura(P2), 0)
	assert_eq(_svc.get_aura(P1), 0, "Der Dankende selbst bekommt keine Aura-Änderung")

func test_thank_gain_non_negative_aura_is_fixed_amount() -> void:
	_svc.on_thank_confirmed(P1, P2)
	assert_eq(_svc.get_aura(P2), AuraService.THANK_GAIN_NON_NEGATIVE)

func test_thank_gain_negative_aura_is_proportional_with_floor() -> void:
	_svc._aura[P2] = -1000
	_svc.on_thank_confirmed(P1, P2)
	var expected_gain := maxi(
		AuraService.THANK_MIN_GAIN_NEGATIVE,
		int(round(1000.0 * AuraService.THANK_GAIN_NEGATIVE_PCT))
	)
	assert_eq(_svc.get_aura(P2), -1000 + expected_gain)

func test_thank_gain_negative_aura_respects_floor_for_small_deficits() -> void:
	# Kleines Defizit → prozentualer Gain würde unter den Sockel fallen,
	# THANK_MIN_GAIN_NEGATIVE muss greifen.
	_svc._aura[P2] = -10
	_svc.on_thank_confirmed(P1, P2)
	assert_eq(_svc.get_aura(P2), -10 + AuraService.THANK_MIN_GAIN_NEGATIVE)

func test_thank_clamps_at_aura_max() -> void:
	_svc._aura[P2] = AuraService.AURA_MAX - 5
	_svc.on_thank_confirmed(P1, P2)
	assert_eq(_svc.get_aura(P2), AuraService.AURA_MAX)

func test_thank_self_is_rejected() -> void:
	var failed := []
	_svc.thank_failed.connect(func(pid, reason): failed.append(reason))
	_svc.on_thank_confirmed(P1, P1)
	assert_eq(failed, ["invalid_target"])
	assert_eq(_svc.get_aura(P1), 0)

func test_thank_empty_ids_rejected() -> void:
	var failed := []
	_svc.thank_failed.connect(func(pid, reason): failed.append(reason))
	_svc.on_thank_confirmed("", P2)
	assert_eq(failed, ["invalid_target"])

func test_second_thank_within_cooldown_is_rejected() -> void:
	_svc.on_thank_confirmed(P1, P2)
	var gained_after_first := _svc.get_aura(P2)

	var failed := []
	_svc.thank_failed.connect(func(pid, reason): failed.append(reason))
	_svc.on_thank_confirmed(P1, P2)

	assert_eq(failed, ["cooldown_active"])
	assert_eq(_svc.get_aura(P2), gained_after_first, "Zweiter Dank darf keine weitere Aura vergeben")

func test_cooldown_is_pair_symmetric_regardless_of_direction() -> void:
	# a→b sperrt auch b→a — derselbe Paar-Schlüssel, nicht zwei getrennte Cooldowns.
	_svc.on_thank_confirmed(P1, P2)
	var failed := []
	_svc.thank_failed.connect(func(pid, reason): failed.append(reason))
	_svc.on_thank_confirmed(P2, P1)  # umgekehrte Richtung
	assert_eq(failed, ["cooldown_active"])

func test_cooldown_does_not_block_different_pairs() -> void:
	_svc.on_thank_confirmed(P1, P2)
	_svc.on_thank_confirmed(P1, P3)  # anderes Ziel — eigener Cooldown
	assert_gt(_svc.get_aura(P3), 0)

func test_thank_emits_no_failure_signal_on_success() -> void:
	var failed := []
	_svc.thank_failed.connect(func(pid, reason): failed.append(reason))
	_svc.on_thank_confirmed(P1, P2)
	assert_eq(failed.size(), 0)

# ─────────────────────────────────────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────────────────────────────────────

func test_save_key_is_aura() -> void:
	assert_eq(_svc.get_save_key(), "aura")

func test_save_data_round_trip_preserves_aura_and_cooldown() -> void:
	_svc.apply_kill_penalty(P1)
	_svc.on_thank_confirmed(P2, P1)
	var snapshot := _svc.get_save_data()

	var svc2 := AuraService.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save}))
	svc2._restore_from_save(snapshot)

	assert_eq(svc2.get_aura(P1), _svc.get_aura(P1), "Aura muss Round-Trip überleben")

	# Cooldown muss ebenfalls überlebt haben — zweiter Dank sofort danach
	# muss weiterhin abgelehnt werden.
	var failed := []
	svc2.thank_failed.connect(func(pid, reason): failed.append(reason))
	svc2.on_thank_confirmed(P2, P1)
	assert_eq(failed, ["cooldown_active"], "Cooldown muss Round-Trip überleben (sonst Exploit via Neustart)")

func test_save_data_filters_expired_cooldowns() -> void:
	_svc.on_thank_confirmed(P1, P2)
	# Cooldown künstlich in die Vergangenheit versetzen (abgelaufen).
	var key: String = _svc._pair_key(P1, P2)
	_svc._thank_cooldowns[key] = _svc._now() - AuraService.THANK_COOLDOWN_SEC - 10.0

	var saved := _svc.get_save_data()
	assert_false((saved["thank_cooldowns"] as Dictionary).has(key), "Abgelaufener Cooldown darf nicht mit-gespeichert werden")

func test_save_data_empty_by_default() -> void:
	var saved := _svc.get_save_data()
	assert_eq((saved["aura"] as Dictionary).size(), 0)
	assert_eq((saved["thank_cooldowns"] as Dictionary).size(), 0)

# ─────────────────────────────────────────────
# inject_network_bridge() — Round 113 Nachtrag
# ─────────────────────────────────────────────

func test_inject_network_bridge_sets_the_reference() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_svc.inject_network_bridge(bridge)
	assert_same(_svc._network, bridge)
