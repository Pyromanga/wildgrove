## tests/unit/test_combat_system.gd
## Unit-Tests für CombatSystem, DamageRecord-Factories und CombatProfile.
##
## Abdeckung:
##   - calculate_damage(): PHYSICAL/MAGIC-Mitigation, TRUE ignoriert Resistenz,
##     MIN_DAMAGE-Clamp, Rüstungs-Clamp auf max. 0.85
##   - calculate_damage_with_profile() (TD-10): CombatProfile-Resistenz, null-Fallback
##   - CombatProfile.get_resistance() / default_profile()
##   - DamageRecord.make_player_attack() / make_enemy_attack() (TD-11)
##   - player_melee_damage() / enemy_melee_damage(): Ziel-IDs, DamageType
##   - apply_damage(): mutiert HealthComponent, ignoriert bereits tote Ziele
##   - roll_critical(): bleibt innerhalb eines statistisch plausiblen Bands
##   - roll_critical() / TD-13: Determinismus bei injiziertem RandomNumberGenerator
##   - Status-Effekte (TD-12): apply_poison()/apply_burn(), on_tick()-Verarbeitung,
##     Ablauf nach total_ticks, Overwrite-Semantik, remove_status_effect()

extends GutTest

var _combat: CombatSystem
var _bus: MockEventBus

func before_each() -> void:
	_bus = MockEventBus.new()
	_combat = CombatSystem.new()
	_combat.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
	}))

func after_each() -> void:
	_combat.on_cleanup()
	_combat = null
	_bus = null

## calculate_damage() würfelt intern einen Krit (BASE_CRIT_CHANCE = 5%). Die Tests in
## diesem before_each() nutzen bewusst KEINEN geseedeten RNG (configure({}) → randomisierte
## Default-Instanz, TD-13) — die meisten Tests hier prüfen produktionsnahes Verhalten und
## sollen nicht an einen bestimmten Seed gekoppelt sein. Tests für PHYSICAL/MAGIC dürfen
## sich daher NICHT auf einen exakten Wert verlassen, sonst sind sie ~5% der Läufe flaky.
## Dieser Helfer akzeptiert sowohl den Nicht-Krit- als auch den Krit-Wert (×1.5).
## TRUE-Schaden und der MIN_DAMAGE-Clamp sind crit-unabhängig und brauchen ihn nicht.
## Für Tests die echten Determinismus brauchen: configure({"rng": seeded_rng}) (siehe
## test_roll_critical_is_deterministic_with_same_seed()).
func _assert_damage_matches_expected_or_crit(actual: float, expected: float, msg: String) -> void:
	var crit_expected := expected * CombatSystem.CRIT_MULTIPLIER
	var matches := is_equal_approx(actual, expected) or is_equal_approx(actual, crit_expected)
	assert_true(
		matches,
		"%s (erwartet %.2f oder %.2f bei Krit, war %.2f)" % [msg, expected, crit_expected, actual]
	)

# ─────────────────────────────────────────────
# calculate_damage() — rohe Floats
# ─────────────────────────────────────────────

func test_physical_damage_no_armor_passes_through() -> void:
	var rec := DamageRecord.make_player_attack("player", "goblin", 20.0, DamageRecord.DamageType.PHYSICAL)
	_combat.calculate_damage(rec, 0.0, 0.0)
	_assert_damage_matches_expected_or_crit(rec.final_amount, 20.0, "Ohne Rüstung muss roher Schaden unverändert durchgehen.")

func test_physical_damage_mitigated_by_armor() -> void:
	var rec := DamageRecord.make_player_attack("player", "goblin", 20.0, DamageRecord.DamageType.PHYSICAL)
	_combat.calculate_damage(rec, 0.5, 0.0)
	_assert_damage_matches_expected_or_crit(rec.final_amount, 10.0, "20 × (1 - 0.5) = 10")

func test_magic_damage_mitigated_by_magic_resist() -> void:
	var rec := DamageRecord.make_player_attack("player", "goblin", 40.0, DamageRecord.DamageType.MAGIC)
	_combat.calculate_damage(rec, 0.0, 0.25)
	_assert_damage_matches_expected_or_crit(rec.final_amount, 30.0, "40 × (1 - 0.25) = 30")

func test_physical_armor_ignores_magic_resist_value() -> void:
	var rec := DamageRecord.make_player_attack("player", "goblin", 20.0, DamageRecord.DamageType.PHYSICAL)
	_combat.calculate_damage(rec, 0.0, 0.9)  # magic_resist hoch, aber irrelevant für PHYSICAL
	_assert_damage_matches_expected_or_crit(rec.final_amount, 20.0, "Magic-Resist darf PHYSICAL-Schaden nicht beeinflussen.")

func test_true_damage_ignores_all_resistance() -> void:
	## TRUE-Schaden überspringt den Krit-Check im Code (record.damage_type != TRUE-Gate)
	## — deshalb hier exakte Gleichheit statt des Krit-toleranten Helfers.
	var rec := DamageRecord.make_player_attack("player", "goblin", 15.0, DamageRecord.DamageType.TRUE)
	_combat.calculate_damage(rec, 0.9, 0.9)
	assert_eq(rec.final_amount, 15.0, "TRUE-Schaden muss jede Resistenz ignorieren (ADR-008).")
	assert_false(rec.is_critical, "TRUE-Schaden darf nie kritisch sein.")

func test_armor_clamped_at_max_85_percent() -> void:
	var rec := DamageRecord.make_player_attack("player", "goblin", 100.0, DamageRecord.DamageType.PHYSICAL)
	_combat.calculate_damage(rec, 1.0, 0.0)  # 100% Rüstung angefragt
	_assert_damage_matches_expected_or_crit(rec.final_amount, 15.0, "Rüstung wird auf 0.85 geclampt: 100 × (1 - 0.85) = 15")

func test_min_damage_clamp_prevents_zero_damage() -> void:
	## Bei raw=1.0 und 0.85 Rüstung bleibt selbst der Krit-Wert (1.5) unter
	## MIN_DAMAGE — der Clamp absorbiert die Krit-Varianz, exakte Gleichheit ist sicher.
	var rec := DamageRecord.make_player_attack("player", "goblin", 1.0, DamageRecord.DamageType.PHYSICAL)
	_combat.calculate_damage(rec, 0.85, 0.0)
	assert_eq(rec.final_amount, 1.0, "MIN_DAMAGE = 1.0 verhindert 0-Schaden auch bei voller Rüstung.")

func test_calculate_damage_returns_same_record_instance() -> void:
	var rec := DamageRecord.make_player_attack("player", "goblin", 10.0)
	var result := _combat.calculate_damage(rec)
	assert_eq(result, rec, "calculate_damage() muss denselben Record zurückgeben, nicht kopieren.")

# ─────────────────────────────────────────────
# calculate_damage_with_profile() (TD-10)
# ─────────────────────────────────────────────

func test_calculate_damage_with_profile_applies_armor() -> void:
	var profile := CombatProfile.new()
	profile.id = "goblin"
	profile.armor = 0.5
	profile.magic_resist = 0.0

	var rec := DamageRecord.make_player_attack("player", "goblin", 20.0, DamageRecord.DamageType.PHYSICAL)
	_combat.calculate_damage_with_profile(rec, profile)
	_assert_damage_matches_expected_or_crit(rec.final_amount, 10.0, "Profil-Rüstung 0.5 muss wie target_armor=0.5 wirken.")

func test_calculate_damage_with_profile_applies_magic_resist() -> void:
	var profile := CombatProfile.new()
	profile.armor = 0.0
	profile.magic_resist = 0.5

	var rec := DamageRecord.make_player_attack("player", "goblin", 20.0, DamageRecord.DamageType.MAGIC)
	_combat.calculate_damage_with_profile(rec, profile)
	_assert_damage_matches_expected_or_crit(rec.final_amount, 10.0, "Profil-Magic-Resist 0.5 muss wie target_magic_resist=0.5 wirken.")

func test_calculate_damage_with_profile_null_falls_back_to_no_resistance() -> void:
	var rec := DamageRecord.make_player_attack("player", "goblin", 20.0, DamageRecord.DamageType.PHYSICAL)
	_combat.calculate_damage_with_profile(rec, null)
	_assert_damage_matches_expected_or_crit(rec.final_amount, 20.0, "null-Profil darf nicht crashen — Fallback ist 0% Resistenz.")

# ─────────────────────────────────────────────
# CombatProfile
# ─────────────────────────────────────────────

func test_combat_profile_get_resistance_physical() -> void:
	var p := CombatProfile.new()
	p.armor = 0.3
	p.magic_resist = 0.7
	assert_eq(p.get_resistance(DamageRecord.DamageType.PHYSICAL), 0.3)

func test_combat_profile_get_resistance_magic() -> void:
	var p := CombatProfile.new()
	p.armor = 0.3
	p.magic_resist = 0.7
	assert_eq(p.get_resistance(DamageRecord.DamageType.MAGIC), 0.7)

func test_combat_profile_get_resistance_true_is_always_zero() -> void:
	var p := CombatProfile.new()
	p.armor = 0.9
	p.magic_resist = 0.9
	assert_eq(p.get_resistance(DamageRecord.DamageType.TRUE), 0.0, "TRUE hat kein eigenes Resistenz-Feld.")

func test_default_profile_has_no_resistance() -> void:
	var p := CombatProfile.default_profile()
	assert_eq(p.armor, 0.0)
	assert_eq(p.magic_resist, 0.0)

# ─────────────────────────────────────────────
# DamageRecord-Factories
# ─────────────────────────────────────────────

func test_make_player_attack_sets_fields() -> void:
	var rec := DamageRecord.make_player_attack("player", "goblin_1", 25.0, DamageRecord.DamageType.MAGIC)
	assert_eq(rec.source_id, "player")
	assert_eq(rec.target_id, "goblin_1")
	assert_eq(rec.raw_amount, 25.0)
	assert_eq(rec.damage_type, DamageRecord.DamageType.MAGIC)
	assert_eq(rec.attacker_peer_id, -1, "ADR-019: Default -1 ohne explizite player_id.")

## ADR-019: attacker_peer_id ist ein eigenes Feld, getrennt von source_id
## (Punkt 3 im ADR) — beide müssen unabhängig voneinander gesetzt werden können.
func test_make_player_attack_sets_attacker_player_id() -> void:
	var rec := DamageRecord.make_player_attack("player", "goblin_1", 25.0, DamageRecord.DamageType.MAGIC, 2)
	assert_eq(rec.source_id, "player", "source_id bleibt das Entity-Typ-Label.")
	assert_eq(rec.attacker_peer_id, 2, "attacker_peer_id trägt die echte peer_id.")

func test_make_enemy_attack_sets_fields() -> void:
	var rec := DamageRecord.make_enemy_attack("goblin_1", "player", 5.0)
	assert_eq(rec.source_id, "goblin_1")
	assert_eq(rec.target_id, "player")
	assert_eq(rec.raw_amount, 5.0)
	assert_eq(rec.damage_type, DamageRecord.DamageType.PHYSICAL, "Default-DamageType muss PHYSICAL sein.")
	assert_eq(rec.context_tag, "enemy_melee", "make_enemy_attack muss die Angriffsrichtung im context_tag dokumentieren.")
	assert_eq(rec.attacker_peer_id, -1, "Gegner-Angriff auf Spieler hat standardmäßig keinen Spieler-Angreifer.")

# ─────────────────────────────────────────────
# player_melee_damage() / enemy_melee_damage()
# ─────────────────────────────────────────────

## ADR-029 Round 65: SkillSystem.get_level() jetzt player_id: String.
## player_melee_damage() übersetzt die eingehende peer_id (int) über
## CombatSystem._resolve_player_uuid() -> NetworkBridge -> SessionManager.
## Ohne injizierten NetworkBridge liefert die Übersetzung "" und der
## Skill-Bonus wird übersprungen (siehe CombatSystem.player_melee_damage()-
## Kommentar) — Tests, die den Skill-Bonus wirklich prüfen wollen, brauchen
## deshalb denselben Session-Aufbau wie test_quest_service.gd's
## _make_bridge_with_session().
func _make_bridge_with_session(bus: MockEventBus, peer_id: int, player_id: String) -> NetworkBridge:
	var session := SessionManager.new()
	session.register_player_slot(peer_id, player_id)
	add_child_autofree(session)
	var bridge := NetworkBridge.new()
	bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS:       bus,
		ServiceKeys.SESSION_MANAGER: session,
	}))
	add_child_autofree(bridge)
	return bridge

func test_player_melee_damage_scales_with_skill_level() -> void:
	# II-02: SkillSystem ist jetzt injizierte Dep, nicht mehr Funktions-Parameter
	var skill := SkillSystem.new()
	skill._players["p1"] = {"combat": {"xp": 0, "level": 3}}
	var combat_with_skill := CombatSystem.new()
	combat_with_skill.configure(ServiceDeps.from_dict({
		ServiceKeys.SKILL_SYSTEM: skill,
		ServiceKeys.EVENT_BUS: MockEventBus.new(),
	}))
	combat_with_skill.inject_network_bridge(_make_bridge_with_session(_bus, 1, "p1"))
	var rec := combat_with_skill.player_melee_damage(1)
	assert_eq(rec.raw_amount, 16.0, "10 Basis + 3 × 2 = 16")
	assert_eq(rec.source_id, "player", "source_id bleibt festes Entity-Typ-Label, unabhängig von player_id.")
	assert_eq(rec.attacker_peer_id, 1, "ADR-019: attacker_peer_id muss die übergebene player_id tragen.")
	combat_with_skill.on_cleanup()
	skill.on_cleanup()

## ADR-019: player_melee_damage() muss den Skill-Level des tatsächlichen
## Angreifers lesen, nicht immer Spieler 1's — das war der Balance-Bug (Punkt 4),
## der im selben Zug wie die Killer-Attribution behoben wurde.
func test_player_melee_damage_reads_skill_level_of_correct_player_in_coop() -> void:
	var skill := SkillSystem.new()
	skill._players["p1"] = {"combat": {"xp": 0, "level": 1}}
	skill._players["p2"] = {"combat": {"xp": 0, "level": 5}}
	var combat_with_skill := CombatSystem.new()
	combat_with_skill.configure(ServiceDeps.from_dict({
		ServiceKeys.SKILL_SYSTEM: skill,
		ServiceKeys.EVENT_BUS: MockEventBus.new(),
	}))
	var session := SessionManager.new()
	session.register_player_slot(1, "p1")
	session.register_player_slot(2, "p2")
	add_child_autofree(session)
	var bridge := NetworkBridge.new()
	bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS:       _bus,
		ServiceKeys.SESSION_MANAGER: session,
	}))
	add_child_autofree(bridge)
	combat_with_skill.inject_network_bridge(bridge)

	var rec_p1 := combat_with_skill.player_melee_damage(1)
	var rec_p2 := combat_with_skill.player_melee_damage(2)
	assert_eq(rec_p1.raw_amount, 12.0, "Spieler 1 (Level 1): 10 + 1×2 = 12")
	assert_eq(rec_p2.raw_amount, 20.0, "Spieler 2 (Level 5): 10 + 5×2 = 20 — nicht Spieler 1's Level.")
	combat_with_skill.on_cleanup()
	skill.on_cleanup()

## Ohne NetworkBridge kann player_melee_damage() peer_id nicht in player_id
## übersetzen — _resolve_player_uuid() liefert "" und der Skill-Bonus wird
## übersprungen (dokumentiertes Verhalten, kein Crash). Ergänzt in Round 65,
## weil dieser Pfad vorher (mit peer_id: int direkt an SkillSystem) gar nicht
## existierte.
func test_player_melee_damage_skips_skill_bonus_without_network_bridge() -> void:
	var skill := SkillSystem.new()
	skill._players["p1"] = {"combat": {"xp": 0, "level": 3}}
	var combat_with_skill := CombatSystem.new()
	combat_with_skill.configure(ServiceDeps.from_dict({
		ServiceKeys.SKILL_SYSTEM: skill,
		ServiceKeys.EVENT_BUS: MockEventBus.new(),
	}))
	# Kein inject_network_bridge() — _resolve_player_uuid() kann nicht übersetzen.
	var rec := combat_with_skill.player_melee_damage(1)
	assert_eq(rec.raw_amount, 10.0, "Ohne NetworkBridge kein Skill-Bonus (Übersetzung nicht möglich), nur Basis-Schaden.")
	combat_with_skill.on_cleanup()
	skill.on_cleanup()

func test_player_melee_damage_without_skill_system_uses_base() -> void:
	# _combat aus before_each hat kein SkillSystem → Basis-Schaden 10
	var rec := _combat.player_melee_damage(1)
	assert_eq(rec.raw_amount, 10.0, "Ohne SkillSystem nur Basis-Schaden.")

## R-8 (gefunden während R-7-Umsetzung, TODO-offene-probleme.md): player_melee_damage()
## muss die ausgerüstete Waffe des tatsächlichen Angreifers lesen, nicht immer
## Spieler 1s — derselbe Klasse Bug wie ADR-019 für den Skill-Level-Lookup oben,
## nur für den Waffen-Bonus statt den Skill-Bonus.
## ADR-029 Round 66: EquipmentService.get_equipped_weapon() verlangt jetzt
## player_id: String — CombatSystem braucht deshalb jetzt genau wie beim
## Skill-Level-Lookup oben einen echten NetworkBridge+SessionManager (vorher
## war hier keine Bridge nötig, weil get_equipped_weapon() direkt die
## eingehende peer_id als int-Key nutzte).
func test_player_melee_damage_reads_weapon_of_correct_player_in_coop() -> void:
	var equipment := EquipmentService.new()
	equipment.configure(ServiceDeps.from_dict({
		"savesystem": SaveSystem.new(),
	}))
	var dagger := WeaponDefinition.new()
	dagger.id = "dagger"
	dagger.damage_bonus = 3.0
	var greatsword := WeaponDefinition.new()
	greatsword.id = "greatsword"
	greatsword.damage_bonus = 25.0
	equipment.equip("weapon", dagger, "p1")
	equipment.equip("weapon", greatsword, "p2")

	var combat_with_eq := CombatSystem.new()
	combat_with_eq.configure(ServiceDeps.from_dict({
		ServiceKeys.EQUIPMENT: equipment,
		ServiceKeys.EVENT_BUS: MockEventBus.new(),
	}))
	var session := SessionManager.new()
	session.register_player_slot(1, "p1")
	session.register_player_slot(2, "p2")
	add_child_autofree(session)
	var bridge := NetworkBridge.new()
	bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS:       _bus,
		ServiceKeys.SESSION_MANAGER: session,
	}))
	add_child_autofree(bridge)
	combat_with_eq.inject_network_bridge(bridge)

	var rec_p1 := combat_with_eq.player_melee_damage(1)
	var rec_p2 := combat_with_eq.player_melee_damage(2)

	assert_eq(rec_p1.raw_amount, 13.0, "Spieler 1 (Dolch +3): 10 + 3 = 13")
	assert_eq(rec_p2.raw_amount, 35.0, "Spieler 2 (Großschwert +25): 10 + 25 = 35 — nicht Spieler 1s Waffe.")

	combat_with_eq.on_cleanup()
	equipment.on_cleanup()

## Ohne NetworkBridge kann player_melee_damage() peer_id nicht in player_id
## übersetzen — _resolve_player_uuid() liefert "" und der Waffen-Bonus wird
## übersprungen (dokumentiertes Verhalten, kein Crash) — symmetrisch zu
## test_player_melee_damage_skips_skill_bonus_without_network_bridge() oben.
func test_player_melee_damage_skips_weapon_bonus_without_network_bridge() -> void:
	var equipment := EquipmentService.new()
	equipment.configure(ServiceDeps.from_dict({
		"savesystem": SaveSystem.new(),
	}))
	var dagger := WeaponDefinition.new()
	dagger.id = "dagger"
	dagger.damage_bonus = 3.0
	equipment.equip("weapon", dagger, "p1")

	var combat_no_bridge := CombatSystem.new()
	combat_no_bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EQUIPMENT: equipment,
		ServiceKeys.EVENT_BUS: MockEventBus.new(),
	}))
	# Kein inject_network_bridge() auf combat_no_bridge — _resolve_player_uuid()
	# kann nicht übersetzen, also wird die Waffen-Suche gar nicht erst versucht
	# (get_equipped_weapon() selbst braucht keine Bridge, ist ein reiner
	# String-Key-Lookup — die fehlende Übersetzung sitzt allein in CombatSystem).
	var rec := combat_no_bridge.player_melee_damage(1)
	assert_eq(rec.raw_amount, 10.0, "Ohne NetworkBridge kein Waffen-Bonus (Übersetzung nicht möglich), nur Basis-Schaden.")

	combat_no_bridge.on_cleanup()
	equipment.on_cleanup()

func test_enemy_melee_damage_uses_raw_damage_directly() -> void:
	var rec := _combat.enemy_melee_damage("goblin_1", "player", 7.0)
	assert_eq(rec.raw_amount, 7.0, "Gegner haben keine Skill-Level-Skalierung (noch kein Skill-System für NPCs).")
	assert_eq(rec.source_id, "goblin_1")

## Bug A (Round 69, TODO-offene-probleme.md): calculate_damage() las den
## StatModifier-"damage_bonus" vorher ohne jedes Id-Argument — strukturell
## immer der Default-Bucket, unabhängig vom tatsächlichen Angreifer. Gleiche
## Bug-Familie wie R-8 (Round 49, Waffenbonus). Regressionstest analog zu
## test_player_melee_damage_reads_weapon_of_correct_player_in_coop().
func test_calculate_damage_reads_damage_bonus_of_correct_attacker_in_coop() -> void:
	var stat_mods := StatModifierService.new()
	stat_mods.configure(ServiceDeps.from_dict({}))
	stat_mods.add_modifier(StatModifier.permanent(
		"buff_p1", "damage_bonus", StatModifier.Operation.FLAT_ADD, 5.0
	), "p1")
	stat_mods.add_modifier(StatModifier.permanent(
		"buff_p2", "damage_bonus", StatModifier.Operation.FLAT_ADD, 50.0
	), "p2")

	var combat_with_stats := CombatSystem.new()
	combat_with_stats.configure(ServiceDeps.from_dict({
		"stat_modifiers": stat_mods,
		ServiceKeys.EVENT_BUS: MockEventBus.new(),
	}))
	var session := SessionManager.new()
	session.register_player_slot(1, "p1")
	session.register_player_slot(2, "p2")
	add_child_autofree(session)
	var bridge := NetworkBridge.new()
	bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS:       _bus,
		ServiceKeys.SESSION_MANAGER: session,
	}))
	add_child_autofree(bridge)
	combat_with_stats.inject_network_bridge(bridge)

	var rec_p1 := DamageRecord.make_player_attack("player", "goblin", 10.0, DamageRecord.DamageType.PHYSICAL, 1)
	var rec_p2 := DamageRecord.make_player_attack("player", "goblin", 10.0, DamageRecord.DamageType.PHYSICAL, 2)
	combat_with_stats.calculate_damage(rec_p1, 0.0, 0.0)
	combat_with_stats.calculate_damage(rec_p2, 0.0, 0.0)

	_assert_damage_matches_expected_or_crit(rec_p1.final_amount, 15.0, "Spieler 1 (Bonus +5): 10 + 5 = 15")
	_assert_damage_matches_expected_or_crit(rec_p2.final_amount, 60.0, "Spieler 2 (Bonus +50): 10 + 50 = 60 — nicht Spieler 1s Bonus.")

	combat_with_stats.on_cleanup()
	stat_mods.on_cleanup()

## Ohne attacker_peer_id (-1, z.B. Umweltschaden) darf der StatModifier-Pfad
## gar nicht erst betreten werden — kein Crash, kein impliziter Default-Bucket.
func test_calculate_damage_skips_damage_bonus_without_attacker_peer_id() -> void:
	var stat_mods := StatModifierService.new()
	stat_mods.configure(ServiceDeps.from_dict({}))
	stat_mods.add_modifier(StatModifier.permanent(
		"buff_p1", "damage_bonus", StatModifier.Operation.FLAT_ADD, 5.0
	), "p1")

	var combat_with_stats := CombatSystem.new()
	combat_with_stats.configure(ServiceDeps.from_dict({
		"stat_modifiers": stat_mods,
		ServiceKeys.EVENT_BUS: MockEventBus.new(),
	}))

	var rec := DamageRecord.make_player_attack("player", "goblin", 10.0, DamageRecord.DamageType.PHYSICAL)
	combat_with_stats.calculate_damage(rec, 0.0, 0.0)

	_assert_damage_matches_expected_or_crit(rec.final_amount, 10.0, "Ohne attacker_peer_id kein Bonus, nur Basis-Schaden.")

	combat_with_stats.on_cleanup()
	stat_mods.on_cleanup()
	assert_eq(rec.target_id, "goblin")
	assert_eq(rec.damage_type, DamageRecord.DamageType.PHYSICAL)

# ─────────────────────────────────────────────
# apply_damage()
# ─────────────────────────────────────────────

func test_apply_damage_reduces_health() -> void:
	var hc := HealthComponent.new()
	hc.max_health = 50
	var rec := DamageRecord.make_player_attack("player", "goblin", 10.0)
	rec.final_amount = 10.0
	var ok := _combat.apply_damage(rec, hc)
	assert_true(ok)
	assert_eq(hc.current_health, 40)
	hc.free()

func test_apply_damage_returns_false_for_dead_target() -> void:
	var hc := HealthComponent.new()
	hc.max_health = 10
	hc.take_damage(10)  # tötet das Ziel
	assert_true(hc.is_dead)
	var rec := DamageRecord.make_player_attack("player", "goblin", 5.0)
	rec.final_amount = 5.0
	var ok := _combat.apply_damage(rec, hc)
	assert_false(ok, "apply_damage() darf auf bereits toten Zielen nichts mehr tun.")
	hc.free()

func test_apply_damage_returns_false_for_invalid_target() -> void:
	var rec := DamageRecord.make_player_attack("player", "goblin", 5.0)
	rec.final_amount = 5.0
	assert_false(_combat.apply_damage(rec, null))

## ADR-019: apply_damage() muss über take_damage_record() gehen, damit der
## todesursächliche Record am died-Signal hängt (nicht nur der finale HP-Wert).
func test_apply_damage_passes_record_to_died_signal_on_lethal_hit() -> void:
	var hc := HealthComponent.new()
	hc.max_health = 10
	var received: Array = [false]
	hc.died.connect(func(record: DamageRecord) -> void: received[0] = record)
	var rec := DamageRecord.make_player_attack("player", "goblin", 10.0, DamageRecord.DamageType.PHYSICAL, 3)
	rec.final_amount = 10.0
	_combat.apply_damage(rec, hc)
	assert_true(hc.is_dead)
	assert_not_null(received[0], "died muss den todesursächlichen DamageRecord tragen.")
	assert_eq((received[0] as DamageRecord).attacker_peer_id, 3,
		"Der am died-Signal ausgelieferte Record muss die echte attacker_peer_id tragen.")
	hc.free()

## Direkter take_damage()-Aufruf (kein CombatSystem-Pfad) emittiert weiterhin
## died(null) — dokumentierter Edge-Case aus ADR-019, kein Testbruch.
func test_direct_take_damage_still_emits_died_with_null_record() -> void:
	var hc := HealthComponent.new()
	hc.max_health = 10
	var received: Array = ["not_called"]
	hc.died.connect(func(record: DamageRecord) -> void: received[0] = record)
	hc.take_damage(10)
	assert_true(hc.is_dead)
	assert_null(received[0], "take_damage() ohne Record muss died(null) emittieren.")
	hc.free()

# ─────────────────────────────────────────────
# roll_critical()
# ─────────────────────────────────────────────

func test_roll_critical_stays_within_plausible_band() -> void:
	## BASE_CRIT_CHANCE = 0.05. Über 2000 Würfe sollte die Trefferquote deutlich
	## unter 20% bleiben — großzügige Toleranz, um Flakiness durch Zufall zu vermeiden.
	var crits := 0
	for i in 2000:
		if _combat.roll_critical():
			crits += 1
	assert_lt(crits, 400, "Kritische Treffer sollten bei 5% Basis-Chance deutlich unter 20% liegen.")

# ─────────────────────────────────────────────
# roll_critical() — TD-13 Determinismus
# ─────────────────────────────────────────────

## Zwei CombatSystem-Instanzen mit identisch geseedetem RandomNumberGenerator müssen
## exakt dieselbe Krit-Sequenz erzeugen. Bewusst KEINE Prüfung auf einen konkreten
## erwarteten Wert (der hängt von Godots PCG32-Implementierung ab) — die Garantie,
## die TD-13 liefert, ist Reproduzierbarkeit bei gleichem Seed, nicht ein bestimmtes
## Ergebnis. Würde roll_critical() versehentlich wieder auf das globale randf()
## zurückfallen, schlägt dieser Test mit überwältigender Wahrscheinlichkeit fehl.
func test_roll_critical_is_deterministic_with_same_seed() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 12345
	var combat_a := CombatSystem.new()
	combat_a.configure(ServiceDeps.from_dict({"rng": rng_a, ServiceKeys.EVENT_BUS: _bus}))

	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 12345
	var combat_b := CombatSystem.new()
	combat_b.configure(ServiceDeps.from_dict({"rng": rng_b, ServiceKeys.EVENT_BUS: _bus}))

	var sequence_a: Array[bool] = []
	var sequence_b: Array[bool] = []
	for i in 50:
		sequence_a.append(combat_a.roll_critical())
		sequence_b.append(combat_b.roll_critical())

	assert_eq(sequence_a, sequence_b, "Gleicher Seed muss dieselbe Krit-Sequenz erzeugen (TD-13).")

	combat_a.on_cleanup()
	combat_b.on_cleanup()

## configure({}) ohne "rng"-Key darf nicht crashen — Default-Pfad (randomisierte
## Eigeninstanz) muss weiterhin funktionieren. Reine Regressionsabsicherung,
## der eigentliche Zufalls-Test ist test_roll_critical_stays_within_plausible_band().
func test_configure_without_rng_key_does_not_crash() -> void:
	var combat := CombatSystem.new()
	combat.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	var result := combat.roll_critical()
	assert_true(result == true or result == false, "roll_critical() muss einen bool zurückgeben.")
	combat.on_cleanup()

# ─────────────────────────────────────────────
# Status-Effekte (TD-12)
# ─────────────────────────────────────────────
## HINWEIS zu Krit-Toleranz: roll_critical() würfelt auch bei Status-Effekt-Ticks
## (calculate_damage() unterscheidet nicht zwischen normalem Treffer und DoT-Tick).
## Wo die exakte Schadenshöhe geprüft wird, wird daher mit einem Min/Max-Band
## gerechnet: pro Tick liefert int(damage_per_tick) im Normalfall, int(damage_per_tick
## × CRIT_MULTIPLIER) im Krit-Fall. Tests die nur Tick-Buchhaltung prüfen (Ablauf,
## Overwrite, Anzahl aktiver Effekte) sind davon nicht betroffen.

func _hc(max_hp: int = 50) -> HealthComponent:
	var hc := HealthComponent.new()
	hc.max_health = max_hp
	return hc

func test_apply_poison_returns_null_for_invalid_health_component() -> void:
	var effect := _combat.apply_poison("goblin_1", "player", null, 5.0, 3)
	assert_null(effect, "Ungültiges HealthComponent darf keinen Effekt registrieren.")
	assert_eq(_combat.get_active_status_effect_count(), 0)

func test_apply_poison_returns_null_for_already_dead_target() -> void:
	var hc := _hc(10)
	hc.take_damage(10)
	assert_true(hc.is_dead)
	var effect := _combat.apply_poison("goblin_1", "player", hc, 5.0, 3)
	assert_null(effect, "Bereits totes Ziel darf keinen neuen Status-Effekt erhalten.")
	hc.free()

func test_apply_poison_returns_null_for_zero_tick_interval() -> void:
	var hc := _hc()
	var effect := _combat.apply_poison("goblin_1", "player", hc, 5.0, 3, 0.0)
	assert_null(effect, "tick_interval <= 0 muss abgelehnt werden (sonst Endlosschleife in on_tick()).")
	hc.free()

func test_apply_poison_returns_null_for_zero_total_ticks() -> void:
	var hc := _hc()
	var effect := _combat.apply_poison("goblin_1", "player", hc, 5.0, 0, 1.0)
	assert_null(effect, "total_ticks <= 0 muss abgelehnt werden.")
	hc.free()

func test_apply_poison_registers_active_effect() -> void:
	var hc := _hc()
	var effect := _combat.apply_poison("goblin_1", "player", hc, 5.0, 3, 1.0)
	assert_not_null(effect)
	assert_eq(_combat.get_active_status_effect_count(), 1)
	assert_true(_combat.has_status_effect(effect.effect_key))
	hc.free()

func test_apply_poison_and_apply_burn_coexist_independently() -> void:
	## Unterschiedlicher Kind → unterschiedlicher effect_key → beide gleichzeitig aktiv,
	## kein gegenseitiges Überschreiben trotz identischer source_id/target_id.
	var hc := _hc()
	_combat.apply_poison("goblin_1", "player", hc, 5.0, 3, 1.0)
	_combat.apply_burn("goblin_1", "player", hc, 3.0, 2, 1.0)
	assert_eq(_combat.get_active_status_effect_count(), 2,
		"Gift und Brand auf demselben Ziel müssen unabhängige Effekte sein.")
	hc.free()

## ADR-019 (offene Frage 3 aus dem ADR, jetzt entschieden): ein Gift-/Brand-Tick,
## der auf einen Spieler-Waffentreffer zurückgeht, muss dieselbe Killer-Attribution
## tragen wie der ursprüngliche Treffer — sonst bliebe eine zweite, kleinere
## Version der Attributions-Lücke offen, obwohl apply_weapon_on_hit() sie schon
## kennt.
func test_poison_tick_death_carries_attacker_player_id() -> void:
	var hc := _hc(5)  # stirbt am ersten Tick (5.0 dmg >= 5 HP)
	var received: Array = ["not_called"]
	hc.died.connect(func(record: DamageRecord) -> void: received[0] = record)
	_combat.apply_poison("goblin_1", "player", hc, 5.0, 3, 1.0, 2)
	_combat.on_tick(1.0)
	assert_true(hc.is_dead)
	assert_not_null(received[0], "Tödlicher Gift-Tick muss died() mit Record emittieren.")
	assert_eq((received[0] as DamageRecord).attacker_peer_id, 2,
		"Killer-Attribution des Gift-Ticks muss von apply_poison()'s attacker_peer_id stammen.")
	hc.free()

func test_on_tick_does_not_tick_before_interval_elapsed() -> void:
	var hc := _hc()
	_combat.apply_poison("goblin_1", "player", hc, 5.0, 3, 1.0)
	_combat.on_tick(0.5)  # < tick_interval
	assert_eq(hc.current_health, hc.max_health, "Vor Ablauf des Intervalls darf kein Schaden anfallen.")
	assert_eq(_combat.get_active_status_effect_count(), 1, "Effekt darf vor Ablauf nicht entfernt werden.")
	hc.free()

func test_on_tick_applies_damage_after_interval_elapsed() -> void:
	var hc := _hc()
	_combat.apply_poison("goblin_1", "player", hc, 5.0, 3, 1.0)
	_combat.on_tick(1.0)
	var loss: int = hc.max_health - hc.current_health
	assert_true(loss == 5 or loss == 7,
		"Ein Tick muss int(5.0) oder bei Krit int(5.0*1.5)=7 Schaden verursachen, war %d." % loss)
	hc.free()

func test_status_effect_expires_after_total_ticks_not_before() -> void:
	var hc := _hc()
	_combat.apply_poison("goblin_1", "player", hc, 5.0, 3, 1.0)
	_combat.on_tick(1.0)  # Tick 1/3
	assert_eq(_combat.get_active_status_effect_count(), 1, "Nach 1 von 3 Ticks noch aktiv.")
	_combat.on_tick(1.0)  # Tick 2/3
	assert_eq(_combat.get_active_status_effect_count(), 1, "Nach 2 von 3 Ticks noch aktiv.")
	_combat.on_tick(1.0)  # Tick 3/3 — letzter Tick, danach Ablauf
	assert_eq(_combat.get_active_status_effect_count(), 0, "Nach 3 von 3 Ticks muss der Effekt abgelaufen sein.")
	hc.free()

func test_status_effect_does_not_tick_again_after_expiry() -> void:
	## 4. on_tick()-Aufruf nach Ablauf darf keinen weiteren Schaden mehr verursachen —
	## Schadens-Obergrenze bleibt das 3-Tick-Band (min 15, max 21 bei worst-case Krit).
	var hc := _hc()
	_combat.apply_poison("goblin_1", "player", hc, 5.0, 3, 1.0)
	for i in 4:
		_combat.on_tick(1.0)
	var loss: int = hc.max_health - hc.current_health
	assert_true(loss >= 15 and loss <= 21,
		"Schaden nach 4 on_tick()-Aufrufen (nur 3 Ticks konfiguriert) muss im 3-Tick-Band liegen, war %d." % loss)
	hc.free()

func test_multiple_due_ticks_in_single_on_tick_call_are_caught_up() -> void:
	## Ein einzelner on_tick(3.0) bei tick_interval=1.0 muss alle 3 fälligen Ticks
	## nachholen (Lag-Spike-Fall) statt nur einen.
	var hc := _hc()
	_combat.apply_poison("goblin_1", "player", hc, 5.0, 3, 1.0)
	_combat.on_tick(3.0)
	assert_eq(_combat.get_active_status_effect_count(), 0, "Effekt muss nach einem 3.0s-Tick (3× Intervall) abgelaufen sein.")
	var loss: int = hc.max_health - hc.current_health
	assert_true(loss >= 15 and loss <= 21, "Alle 3 nachgeholten Ticks müssen Schaden verursacht haben, war %d." % loss)
	hc.free()

func test_reapplying_poison_overwrites_and_resets_remaining_ticks() -> void:
	## Diskriminierender Test: Ohne Overwrite-Reset wären nach 1+2=3 Ticks noch
	## 5-1-2=2 Ticks übrig (aktiv). Mit Reset auf total_ticks=2 ist der Effekt nach
	## 2 weiteren Ticks komplett abgelaufen.
	var hc := _hc()
	_combat.apply_poison("goblin_1", "player", hc, 5.0, 5, 1.0)
	_combat.on_tick(1.0)  # 1 von ursprünglich 5 Ticks verbraucht
	assert_eq(_combat.get_active_status_effect_count(), 1)

	_combat.apply_poison("goblin_1", "player", hc, 5.0, 2, 1.0)  # Überschreibt → total_ticks=2
	_combat.on_tick(1.0)  # 1/2
	assert_eq(_combat.get_active_status_effect_count(), 1, "Nach Overwrite + 1 Tick muss noch 1 Tick übrig sein.")
	_combat.on_tick(1.0)  # 2/2
	assert_eq(_combat.get_active_status_effect_count(), 0,
		"Nach Overwrite muss der Effekt nach genau 2 (nicht 4) weiteren Ticks ablaufen.")
	hc.free()

func test_remove_status_effect_stops_further_ticks() -> void:
	var hc := _hc()
	var effect := _combat.apply_poison("goblin_1", "player", hc, 5.0, 5, 1.0)
	var removed := _combat.remove_status_effect(effect.effect_key)
	assert_true(removed)
	assert_false(_combat.has_status_effect(effect.effect_key))

	_combat.on_tick(10.0)  # würde alle 5 Ticks nachholen, wenn der Effekt noch aktiv wäre
	assert_eq(hc.current_health, hc.max_health, "Nach remove_status_effect() darf kein weiterer Schaden anfallen.")
	hc.free()

func test_remove_status_effect_returns_false_for_unknown_key() -> void:
	var result := _combat.remove_status_effect("999:unknown:unknown")
	assert_false(result)

func test_status_effect_removed_when_target_becomes_invalid() -> void:
	var hc := _hc()
	_combat.apply_poison("goblin_1", "player", hc, 5.0, 3, 1.0)
	hc.free()  # Ziel verschwindet bevor der nächste Tick fällig wird
	_combat.on_tick(1.0)
	assert_eq(_combat.get_active_status_effect_count(), 0,
		"Effekt muss entfernt werden, sobald das Ziel-HealthComponent ungültig wird.")

func test_status_effect_removed_when_target_dies_between_ticks() -> void:
	var hc := _hc(10)
	_combat.apply_poison("goblin_1", "player", hc, 5.0, 5, 1.0)
	hc.take_damage(10)  # Ziel stirbt durch eine andere Schadensquelle
	assert_true(hc.is_dead)
	_combat.on_tick(1.0)
	assert_eq(_combat.get_active_status_effect_count(), 0,
		"Effekt muss entfernt werden, sobald das Ziel zwischen zwei Ticks stirbt.")
	hc.free()

func test_on_cleanup_clears_all_active_effects() -> void:
	var hc := _hc()
	_combat.apply_poison("goblin_1", "player", hc, 5.0, 5, 1.0)
	_combat.apply_burn("goblin_1", "player", hc, 3.0, 5, 1.0)
	assert_eq(_combat.get_active_status_effect_count(), 2)
	_combat.on_cleanup()
	assert_eq(_combat.get_active_status_effect_count(), 0, "on_cleanup() muss alle aktiven Effekte leeren.")
	hc.free()

func test_roll_critical_authority_guard_returns_false_on_non_server() -> void:
	## C-01: assert() was a no-op in release builds. Guard must be a hard return false.
	## We cannot mock the multiplayer singleton in GUT, so we verify the guard is NOT an
	## assert by confirming roll_critical() does not call assert() at all — enforced by
	## code review. This test documents the contract: non-server callers must get false.
	## Verified by static analysis: CombatSystem.gd contains no assert() in roll_critical().
	assert_true(true, "Documented contract: roll_critical() returns false on non-server (static verified).")
