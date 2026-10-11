# res://tests/unit/test_player_stats.gd
extends GutTest

## Unit-Tests für PlayerStats (reiner RefCounted-Laufzeit-Zustand, keine Deps).
##
## Abgedeckt:
##   - take_damage()/heal(): Clamping, No-Op bei amount<=0, stats_depleted/
##     stats_restored-Signale inkl. Wiederholungsfall (mehrfacher Schaden
##     nach dem Tod feuert stats_depleted erneut — kein "nur beim ersten Mal
##     unter 0"-Guard im Code)
##   - drain_stamina()/restore_stamina(): symmetrisch zu take_damage()/
##     heal() (Clamping, No-Op bei amount<=0, stats_depleted/stats_restored).
##     HINWEIS: restore_stamina() hatte ursprünglich weder den amount<=0-Guard
##     noch die stats_restored("stamina")-Emission — beides nachgezogen, siehe
##     Kommentar direkt bei den restore_stamina()-Tests unten.
##   - is_alive(), get_health_percent()/get_stamina_percent() inkl. Guard
##     gegen Division durch 0 bei max<=0
##   - to_save_dict()/from_save_dict(): Round-Trip, Teil-Dictionary mit
##     fehlenden Keys (Fallback-Werte), Signal-Emission beim Restore

var _stats: PlayerStats


func before_each() -> void:
	_stats = PlayerStats.new()


func after_each() -> void:
	_stats = null


# ─────────────────────────────────────────────
# take_damage()
# ─────────────────────────────────────────────

func test_take_damage_reduces_health() -> void:
	_stats.take_damage(30.0)
	assert_eq(_stats.health_current, 70.0)

func test_take_damage_clamps_at_zero() -> void:
	_stats.take_damage(500.0)
	assert_eq(_stats.health_current, 0.0)

func test_take_damage_zero_or_negative_is_noop() -> void:
	_stats.take_damage(0.0)
	assert_eq(_stats.health_current, 100.0)
	_stats.take_damage(-10.0)
	assert_eq(_stats.health_current, 100.0, "Negativer Schaden darf nicht heilen.")

func test_take_damage_emits_health_changed() -> void:
	var received: Array = []
	_stats.health_changed.connect(func(cur, max_): received.append([cur, max_]))
	_stats.take_damage(25.0)
	assert_eq(received, [[75.0, 100.0]])

func test_take_damage_to_zero_emits_stats_depleted_health() -> void:
	var received: Array = []
	_stats.stats_depleted.connect(func(stat): received.append(stat))
	_stats.take_damage(100.0)
	assert_eq(received, ["health"])

func test_take_damage_while_already_dead_emits_stats_depleted_again() -> void:
	# Kein "nur beim Übergang"-Guard im Code -> jeder weitere Treffer nach
	# dem Tod feuert stats_depleted erneut.
	_stats.take_damage(100.0)
	var received: Array = []
	_stats.stats_depleted.connect(func(stat): received.append(stat))
	_stats.take_damage(10.0)
	assert_eq(received, ["health"])

func test_take_damage_not_yet_zero_does_not_emit_stats_depleted() -> void:
	var received: Array = []
	_stats.stats_depleted.connect(func(stat): received.append(stat))
	_stats.take_damage(50.0)
	assert_eq(received, [])


# ─────────────────────────────────────────────
# heal()
# ─────────────────────────────────────────────

func test_heal_increases_health() -> void:
	_stats.take_damage(50.0)
	_stats.heal(20.0)
	assert_eq(_stats.health_current, 70.0)

func test_heal_clamps_at_max() -> void:
	_stats.heal(500.0)
	assert_eq(_stats.health_current, 100.0)

func test_heal_zero_or_negative_is_noop() -> void:
	_stats.take_damage(30.0)
	_stats.heal(0.0)
	assert_eq(_stats.health_current, 70.0)
	_stats.heal(-5.0)
	assert_eq(_stats.health_current, 70.0)

func test_heal_from_zero_emits_stats_restored_health() -> void:
	_stats.take_damage(100.0)
	var received: Array = []
	_stats.stats_restored.connect(func(stat): received.append(stat))
	_stats.heal(1.0)
	assert_eq(received, ["health"])

func test_heal_while_not_depleted_does_not_emit_stats_restored() -> void:
	_stats.take_damage(10.0)  # noch am Leben, nicht depleted
	var received: Array = []
	_stats.stats_restored.connect(func(stat): received.append(stat))
	_stats.heal(5.0)
	assert_eq(received, [], "stats_restored nur beim Übergang von depleted -> lebendig.")

func test_heal_emits_health_changed() -> void:
	var received: Array = []
	_stats.health_changed.connect(func(cur, max_): received.append([cur, max_]))
	_stats.take_damage(50.0)
	received.clear()
	_stats.heal(10.0)
	assert_eq(received, [[60.0, 100.0]])


# ─────────────────────────────────────────────
# drain_stamina()
# ─────────────────────────────────────────────

func test_drain_stamina_reduces_stamina() -> void:
	_stats.drain_stamina(40.0)
	assert_eq(_stats.stamina_current, 60.0)

func test_drain_stamina_clamps_at_zero() -> void:
	_stats.drain_stamina(500.0)
	assert_eq(_stats.stamina_current, 0.0)

func test_drain_stamina_zero_or_negative_is_noop() -> void:
	_stats.drain_stamina(0.0)
	assert_eq(_stats.stamina_current, 100.0)
	_stats.drain_stamina(-10.0)
	assert_eq(_stats.stamina_current, 100.0)

func test_drain_stamina_to_zero_emits_stats_depleted_stamina() -> void:
	var received: Array = []
	_stats.stats_depleted.connect(func(stat): received.append(stat))
	_stats.drain_stamina(100.0)
	assert_eq(received, ["stamina"])


# ─────────────────────────────────────────────
# restore_stamina() — inzwischen symmetrisch zu heal() (siehe Fix-History:
# hatte ursprünglich weder Guard noch stats_restored-Emission)
# ─────────────────────────────────────────────

func test_restore_stamina_increases_stamina() -> void:
	_stats.drain_stamina(50.0)
	_stats.restore_stamina(20.0)
	assert_eq(_stats.stamina_current, 70.0)

func test_restore_stamina_clamps_at_max() -> void:
	_stats.restore_stamina(500.0)
	assert_eq(_stats.stamina_current, 100.0)

func test_restore_stamina_zero_or_negative_is_noop() -> void:
	_stats.drain_stamina(30.0)
	_stats.restore_stamina(0.0)
	assert_eq(_stats.stamina_current, 70.0)
	_stats.restore_stamina(-15.0)
	assert_eq(_stats.stamina_current, 70.0, "Negativer Wert darf Stamina nicht abziehen.")

func test_restore_stamina_from_zero_emits_stats_restored_stamina() -> void:
	_stats.drain_stamina(100.0)
	var received: Array = []
	_stats.stats_restored.connect(func(stat): received.append(stat))
	_stats.restore_stamina(1.0)
	assert_eq(received, ["stamina"])

func test_restore_stamina_while_not_depleted_does_not_emit_stats_restored() -> void:
	_stats.drain_stamina(10.0)  # noch nicht depleted
	var received: Array = []
	_stats.stats_restored.connect(func(stat): received.append(stat))
	_stats.restore_stamina(5.0)
	assert_eq(received, [])

func test_restore_stamina_emits_stamina_changed() -> void:
	var received: Array = []
	_stats.stamina_changed.connect(func(cur, max_): received.append([cur, max_]))
	_stats.drain_stamina(20.0)
	received.clear()
	_stats.restore_stamina(10.0)
	assert_eq(received, [[90.0, 100.0]])


# ─────────────────────────────────────────────
# is_alive() / get_health_percent() / get_stamina_percent()
# ─────────────────────────────────────────────

func test_is_alive_true_by_default() -> void:
	assert_true(_stats.is_alive())

func test_is_alive_false_after_lethal_damage() -> void:
	_stats.take_damage(100.0)
	assert_false(_stats.is_alive())

func test_get_health_percent_default_is_one() -> void:
	assert_eq(_stats.get_health_percent(), 1.0)

func test_get_health_percent_after_damage() -> void:
	_stats.take_damage(25.0)
	assert_eq(_stats.get_health_percent(), 0.75)

func test_get_health_percent_guards_against_zero_max() -> void:
	_stats.health_max = 0.0
	assert_eq(_stats.get_health_percent(), 0.0)

func test_get_stamina_percent_after_drain() -> void:
	_stats.drain_stamina(50.0)
	assert_eq(_stats.get_stamina_percent(), 0.5)

func test_get_stamina_percent_guards_against_zero_max() -> void:
	_stats.stamina_max = 0.0
	assert_eq(_stats.get_stamina_percent(), 0.0)


# ─────────────────────────────────────────────
# to_save_dict() / from_save_dict()
# ─────────────────────────────────────────────

func test_save_dict_round_trip() -> void:
	_stats.take_damage(30.0)
	_stats.drain_stamina(20.0)
	_stats.hunger_current = 40.0
	var snapshot := _stats.to_save_dict()

	var restored := PlayerStats.new()
	restored.from_save_dict(snapshot)

	assert_eq(restored.health_current, 70.0)
	assert_eq(restored.stamina_current, 80.0)
	assert_eq(restored.hunger_current, 40.0)

func test_from_save_dict_missing_keys_falls_back_to_current_values() -> void:
	var restored := PlayerStats.new()
	restored.health_max = 150.0
	restored.from_save_dict({})  # komplett leer
	assert_eq(restored.health_current, 150.0, "Fallback ist der VORHANDENE health_max, nicht ein Hardcoded-Default.")
	assert_eq(restored.health_max, 150.0)

func test_from_save_dict_emits_health_and_stamina_changed() -> void:
	var restored := PlayerStats.new()
	var health_received: Array = []
	var stamina_received: Array = []
	restored.health_changed.connect(func(cur, max_): health_received.append([cur, max_]))
	restored.stamina_changed.connect(func(cur, max_): stamina_received.append([cur, max_]))
	restored.from_save_dict({"health_current": 40.0, "stamina_current": 60.0})
	assert_eq(health_received, [[40.0, 100.0]])
	assert_eq(stamina_received, [[60.0, 100.0]])

func test_save_key_constant() -> void:
	assert_eq(PlayerStats.SAVE_KEY, "player_stats")
