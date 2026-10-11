## tests/unit/test_stat_modifier.gd
## Unit-Tests für StatModifier (Daten) und StatModifierService (Logik).
##
## ADR-029 Plan-Schritt 4 (Round 69): player_id ist jetzt String
## (Pflichtparameter, kein Default mehr) statt peer_id (int, Default 1) —
## StatModifierService war der letzte verbliebene peer_id: int-Kernservice
## der ADR-029-Familie (siehe TODO-offene-probleme.md). "p1"/"p2"/"p3"/"p4"
## sind hier reine opake Test-Bucket-Keys, keine echten UUIDs — genügt,
## StatModifierService behandelt player_id ohnehin nur als Dictionary-Key.
## Der frühere "Default-peer_id-ist-1"-Test entfällt komplett — es gibt
## keinen Default mehr, jeder Aufruf ohne player_id ist jetzt ein
## Parse-Fehler statt eines stillen Fallbacks.
##
## Abdeckung:
##   - StatModifier.permanent() / .temporary() / .is_active()
##   - add_modifier / remove_modifier / has_modifier
##   - get_effective_stat: FLAT_ADD, PERCENT_ADD, PERCENT_MULTIPLY, Kombinationen
##   - Operationsreihenfolge (flat → percent_add → percent_multiply)
##   - cleanup_expired / cleanup_all_expired
##   - remove_modifiers_with_prefix
##   - modifier_changed Signal
##   - Edge Cases: leere source_id, unbekannter Stat, Überschreiben
##   - Multi-Tenancy: player_id-Isolation, clear_player()

extends GutTest

var _svc: StatModifierService

func before_each() -> void:
	_svc = StatModifierService.new()

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null

# ─────────────────────────────────────────────
# StatModifier Daten-Tests
# ─────────────────────────────────────────────

func test_permanent_modifier_is_always_active() -> void:
	var mod := StatModifier.permanent("src", "damage", StatModifier.Operation.FLAT_ADD, 5.0)
	assert_true(mod.is_active(), "Permanenter Modifier muss immer aktiv sein.")
	assert_eq(mod.expires_at, -1.0)

func test_temporary_modifier_is_active_before_expiry() -> void:
	var mod := StatModifier.temporary("src", "damage", StatModifier.Operation.FLAT_ADD, 5.0, 100.0)
	assert_true(mod.is_active(), "Modifier mit 100s Laufzeit muss aktiv sein.")

func test_expired_modifier_is_inactive() -> void:
	var mod := StatModifier.new()
	mod.source_id  = "src"
	mod.stat       = "damage"
	mod.operation  = StatModifier.Operation.FLAT_ADD
	mod.value      = 5.0
	mod.expires_at = 0.001  # schon abgelaufen (unix 0 = 1970)
	assert_false(mod.is_active(), "Modifier mit expires_at in der Vergangenheit muss inaktiv sein.")

func test_to_debug_string_contains_source_and_stat() -> void:
	var mod := StatModifier.permanent("my_sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0)
	var s := mod.to_debug_string()
	assert_true("my_sword" in s, "Debug-String muss source_id enthalten.")
	assert_true("damage" in s, "Debug-String muss stat enthalten.")

# ─────────────────────────────────────────────
# add / remove / has
# ─────────────────────────────────────────────

func test_add_modifier_returns_true_for_valid() -> void:
	var mod := StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 5.0)
	assert_true(_svc.add_modifier(mod, "p1"))

func test_add_modifier_rejects_empty_source_id() -> void:
	var mod := StatModifier.permanent("", "damage", StatModifier.Operation.FLAT_ADD, 5.0)
	assert_false(_svc.add_modifier(mod, "p1"), "Leere source_id muss abgelehnt werden.")

func test_add_modifier_rejects_empty_stat() -> void:
	var mod := StatModifier.permanent("sword", "", StatModifier.Operation.FLAT_ADD, 5.0)
	assert_false(_svc.add_modifier(mod, "p1"), "Leerer stat muss abgelehnt werden.")

func test_has_modifier_after_add() -> void:
	var mod := StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 5.0)
	_svc.add_modifier(mod, "p1")
	assert_true(_svc.has_modifier("sword", "p1"))

func test_has_modifier_false_when_not_added() -> void:
	assert_false(_svc.has_modifier("nonexistent", "p1"))

func test_remove_modifier_returns_true() -> void:
	var mod := StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 5.0)
	_svc.add_modifier(mod, "p1")
	assert_true(_svc.remove_modifier("sword", "p1"))
	assert_false(_svc.has_modifier("sword", "p1"))

func test_remove_modifier_returns_false_when_missing() -> void:
	assert_false(_svc.remove_modifier("nonexistent", "p1"), "Entfernen eines nicht-existenten Modifiers muss false zurückgeben.")

func test_overwrite_modifier_same_source_id() -> void:
	var mod1 := StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 5.0)
	var mod2 := StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0)
	_svc.add_modifier(mod1, "p1")
	_svc.add_modifier(mod2, "p1")
	var effective := _svc.get_effective_stat("damage", 0.0, "p1")
	assert_eq(effective, 10.0, "Überschriebener Modifier muss den neuen Wert haben.")

# ─────────────────────────────────────────────
# get_effective_stat — Einzeloperationen
# ─────────────────────────────────────────────

func test_effective_stat_no_modifiers_returns_base() -> void:
	assert_eq(_svc.get_effective_stat("damage", 50.0, "p1"), 50.0)

func test_effective_stat_flat_add() -> void:
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p1")
	assert_eq(_svc.get_effective_stat("damage", 100.0, "p1"), 110.0)

func test_effective_stat_multiple_flat_add() -> void:
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p1")
	_svc.add_modifier(StatModifier.permanent("ring", "damage", StatModifier.Operation.FLAT_ADD, 5.0), "p1")
	assert_eq(_svc.get_effective_stat("damage", 100.0, "p1"), 115.0)

func test_effective_stat_percent_add() -> void:
	_svc.add_modifier(StatModifier.permanent("buff", "damage", StatModifier.Operation.PERCENT_ADD, 0.20), "p1")
	var result := _svc.get_effective_stat("damage", 100.0, "p1")
	assert_almost_eq(result, 120.0, 0.001, "100 × (1 + 0.20) = 120")

func test_effective_stat_percent_multiply() -> void:
	_svc.add_modifier(StatModifier.permanent("debuff", "damage", StatModifier.Operation.PERCENT_MULTIPLY, 0.5), "p1")
	var result := _svc.get_effective_stat("damage", 100.0, "p1")
	assert_almost_eq(result, 50.0, 0.001, "100 × 0.5 = 50")

# ─────────────────────────────────────────────
# get_effective_stat — Operationsreihenfolge
# ─────────────────────────────────────────────

func test_effective_stat_operation_order() -> void:
	## base=100, FLAT_ADD +20 → 120, PERCENT_ADD +0.15 → 138, PERCENT_MULTIPLY ×0.5 → 69
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 20.0), "p1")
	_svc.add_modifier(StatModifier.permanent("buff", "damage", StatModifier.Operation.PERCENT_ADD, 0.15), "p1")
	_svc.add_modifier(StatModifier.permanent("debuff", "damage", StatModifier.Operation.PERCENT_MULTIPLY, 0.5), "p1")
	var result := _svc.get_effective_stat("damage", 100.0, "p1")
	assert_almost_eq(result, 69.0, 0.001, "Operationsreihenfolge: flat → percent_add → percent_multiply")

func test_effective_stat_ignores_other_stats() -> void:
	_svc.add_modifier(StatModifier.permanent("boots", "move_speed", StatModifier.Operation.FLAT_ADD, 2.0), "p1")
	assert_eq(_svc.get_effective_stat("damage", 100.0, "p1"), 100.0, "Modifier für anderen Stat darf keinen Einfluss haben.")

func test_effective_stat_unresolvable_player_id_returns_base() -> void:
	## Leerer player_id (z.B. gescheiterte peer_id → uuid Übersetzung an der
	## Aufrufgrenze) ist ein gültiger, expliziter "unbekannt"-Wert — kein
	## Crash, behandelt als "kein Bonus" (siehe Klassenkommentar).
	assert_eq(_svc.get_effective_stat("damage", 50.0, ""), 50.0)

# ─────────────────────────────────────────────
# Zeitbasierte Modifier
# ─────────────────────────────────────────────

func test_cleanup_expired_removes_expired_modifiers() -> void:
	var expired := StatModifier.new()
	expired.source_id  = "old_buff"
	expired.stat       = "damage"
	expired.operation  = StatModifier.Operation.FLAT_ADD
	expired.value      = 20.0
	expired.expires_at = 0.001  # in der Vergangenheit
	_svc.add_modifier(expired, "p1")

	var permanent := StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 5.0)
	_svc.add_modifier(permanent, "p1")

	var removed := _svc.cleanup_expired("p1")
	assert_eq(removed, 1, "Genau ein Modifier muss entfernt worden sein.")
	assert_false(_svc.has_modifier("old_buff", "p1"))
	assert_true(_svc.has_modifier("sword", "p1"))

func test_expired_modifier_not_counted_in_effective_stat() -> void:
	var expired := StatModifier.new()
	expired.source_id  = "old_buff"
	expired.stat       = "damage"
	expired.operation  = StatModifier.Operation.FLAT_ADD
	expired.value      = 99.0
	expired.expires_at = 0.001
	_svc.add_modifier(expired, "p1")

	var result := _svc.get_effective_stat("damage", 100.0, "p1")
	assert_eq(result, 100.0, "Abgelaufene Modifier dürfen nicht in den Effektivwert eingehen.")

func test_cleanup_all_expired_covers_every_known_player() -> void:
	## Gegenstück zu cleanup_expired(player_id) — wird von CombatSystem.on_tick()
	## für ALLE Spieler aufgerufen, nicht nur einen (verhindert Modifier-Leak
	## für Spieler 2-N in Multiplayer, siehe Klassenkommentar).
	var expired_p1 := StatModifier.new()
	expired_p1.source_id  = "buff"
	expired_p1.stat       = "damage"
	expired_p1.operation  = StatModifier.Operation.FLAT_ADD
	expired_p1.value      = 5.0
	expired_p1.expires_at = 0.001
	_svc.add_modifier(expired_p1, "p1")

	var expired_p2 := StatModifier.new()
	expired_p2.source_id  = "buff"
	expired_p2.stat       = "damage"
	expired_p2.operation  = StatModifier.Operation.FLAT_ADD
	expired_p2.value      = 5.0
	expired_p2.expires_at = 0.001
	_svc.add_modifier(expired_p2, "p2")

	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p1")

	var removed := _svc.cleanup_all_expired()
	assert_eq(removed, 2, "Beide abgelaufenen Modifier (p1 und p2) müssen entfernt worden sein.")
	assert_false(_svc.has_modifier("buff", "p1"))
	assert_false(_svc.has_modifier("buff", "p2"))
	assert_true(_svc.has_modifier("sword", "p1"), "Nicht-abgelaufener Modifier bleibt erhalten.")

# ─────────────────────────────────────────────
# Prefix-Remove
# ─────────────────────────────────────────────

func test_remove_modifiers_with_prefix() -> void:
	_svc.add_modifier(StatModifier.permanent("equipment_sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p1")
	_svc.add_modifier(StatModifier.permanent("equipment_ring", "damage", StatModifier.Operation.FLAT_ADD, 5.0), "p1")
	_svc.add_modifier(StatModifier.permanent("buff_haste", "move_speed", StatModifier.Operation.FLAT_ADD, 2.0), "p1")

	var removed := _svc.remove_modifiers_with_prefix("equipment_", "p1")
	assert_eq(removed, 2, "Zwei Equipment-Modifier müssen entfernt werden.")
	assert_false(_svc.has_modifier("equipment_sword", "p1"))
	assert_false(_svc.has_modifier("equipment_ring", "p1"))
	assert_true(_svc.has_modifier("buff_haste", "p1"), "Buff darf nicht entfernt worden sein.")

func test_remove_modifiers_with_prefix_only_affects_target_player() -> void:
	_svc.add_modifier(StatModifier.permanent("equipment_sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p1")
	_svc.add_modifier(StatModifier.permanent("equipment_sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p2")

	_svc.remove_modifiers_with_prefix("equipment_", "p1")

	assert_false(_svc.has_modifier("equipment_sword", "p1"))
	assert_true(_svc.has_modifier("equipment_sword", "p2"), "Player p2 Modifier muss unberührt bleiben.")

# ─────────────────────────────────────────────
# Signal
# ─────────────────────────────────────────────

func test_modifier_changed_emitted_on_add() -> void:
	watch_signals(_svc)
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 5.0), "p1")
	assert_signal_emitted_with_parameters(_svc, "modifier_changed", ["damage"])

func test_modifier_changed_emitted_on_remove() -> void:
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 5.0), "p1")
	watch_signals(_svc)
	_svc.remove_modifier("sword", "p1")
	assert_signal_emitted_with_parameters(_svc, "modifier_changed", ["damage"])

# ─────────────────────────────────────────────
# get_modifiers_for_stat
# ─────────────────────────────────────────────

func test_get_modifiers_for_stat_returns_correct_entries() -> void:
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p1")
	_svc.add_modifier(StatModifier.permanent("ring", "damage", StatModifier.Operation.PERCENT_ADD, 0.1), "p1")
	_svc.add_modifier(StatModifier.permanent("boots", "move_speed", StatModifier.Operation.FLAT_ADD, 2.0), "p1")

	var damage_mods := _svc.get_modifiers_for_stat("damage", "p1")
	assert_eq(damage_mods.size(), 2, "Zwei Damage-Modifier erwartet.")
	for mod in damage_mods:
		assert_eq(mod.stat, "damage")

func test_get_modifiers_for_stat_only_returns_target_player() -> void:
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p1")
	_svc.add_modifier(StatModifier.permanent("axe", "damage", StatModifier.Operation.FLAT_ADD, 20.0), "p2")

	var p1_mods := _svc.get_modifiers_for_stat("damage", "p1")
	assert_eq(p1_mods.size(), 1)
	assert_eq(p1_mods[0].source_id, "sword")

# ─────────────────────────────────────────────
# Multi-Tenancy (ADR-029)
# ─────────────────────────────────────────────

func test_different_player_ids_are_isolated() -> void:
	## Modifier für player p1 und p2 dürfen sich nicht gegenseitig beeinflussen.
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p1")
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 50.0), "p2")

	assert_eq(_svc.get_effective_stat("damage", 100.0, "p1"), 110.0, "Player p1 muss seinen eigenen Modifier haben.")
	assert_eq(_svc.get_effective_stat("damage", 100.0, "p2"), 150.0, "Player p2 muss seinen eigenen Modifier haben.")

func test_remove_modifier_only_affects_target_player() -> void:
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p1")
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p2")

	_svc.remove_modifier("sword", "p1")

	assert_false(_svc.has_modifier("sword", "p1"), "Player p1 Modifier muss entfernt sein.")
	assert_true(_svc.has_modifier("sword", "p2"), "Player p2 Modifier muss unberührt bleiben.")

func test_clear_player_removes_all_modifiers_for_that_player() -> void:
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p3")
	_svc.add_modifier(StatModifier.permanent("boots", "move_speed", StatModifier.Operation.FLAT_ADD, 2.0), "p3")
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p4")

	_svc.clear_player("p3")

	assert_false(_svc.has_modifier("sword", "p3"))
	assert_false(_svc.has_modifier("boots", "p3"))
	assert_true(_svc.has_modifier("sword", "p4"), "Player p4 Modifier bleibt erhalten.")

func test_clear_player_unknown_player_id_is_noop() -> void:
	## clear_player() für eine player_id ohne jeden Modifier darf nicht crashen
	## und darf kein modifier_changed emittieren.
	watch_signals(_svc)
	_svc.clear_player("never_seen")
	assert_signal_not_emitted(_svc, "modifier_changed")

func test_cleanup_expired_only_affects_target_player() -> void:
	var expired := StatModifier.new()
	expired.source_id  = "buff"
	expired.stat       = "damage"
	expired.operation  = StatModifier.Operation.FLAT_ADD
	expired.value      = 5.0
	expired.expires_at = 0.001
	_svc.add_modifier(expired, "p1")

	var same_key_p2 := StatModifier.permanent("buff", "damage", StatModifier.Operation.FLAT_ADD, 5.0)
	_svc.add_modifier(same_key_p2, "p2")

	_svc.cleanup_expired("p1")

	assert_false(_svc.has_modifier("buff", "p1"), "Abgelaufener Modifier von Player p1 muss weg sein.")
	assert_true(_svc.has_modifier("buff", "p2"), "Player p2 Modifier muss unberührt bleiben.")

func test_get_debug_report_only_returns_target_player() -> void:
	_svc.add_modifier(StatModifier.permanent("sword", "damage", StatModifier.Operation.FLAT_ADD, 10.0), "p1")
	_svc.add_modifier(StatModifier.permanent("axe", "damage", StatModifier.Operation.FLAT_ADD, 20.0), "p2")

	var report := _svc.get_debug_report("p1")
	assert_eq(report.size(), 1)
	assert_true("sword" in report[0])
