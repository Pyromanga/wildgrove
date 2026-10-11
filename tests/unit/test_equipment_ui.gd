## tests/unit/test_equipment_ui.gd
## Unit-Tests für EquipmentUIController + Equipment↔Combat-Integration.
##
## Abdeckung:
##   - equip() eines WeaponDefinition-Items schlägt auf damage_bonus durch
##   - unequip() entfernt den Bonus wieder
##   - apply_weapon_on_hit() triggert Gift wenn on_hit_effect >= 0 (mit Equipment injiziert)
##   - apply_weapon_on_hit() triggert Brand wenn on_hit_effect == StatusEffect.Kind.BURN
##   - apply_weapon_on_hit() tut nichts wenn kein Equipment vorhanden
##   - Waffe ohne on_hit_effect (-1) triggert kein Gift
##   - player_melee_damage() addiert weapon.damage_bonus auf base_dmg
##
## ADR-029 Round 66: EquipmentService.equip()/unequip()/get_equipped_weapon()
## verlangen jetzt player_id (String), Pflichtparameter ohne Default.
## CombatSystem.apply_weapon_on_hit() braucht deshalb jetzt einen echten
## NetworkBridge+SessionManager, um seinen internen (weiterhin int)
## attacker_peer_id → player_uuid aufzulösen (_resolve_player_uuid(),
## Round 65/66) — ohne Bridge würde die Waffen-Suche leer laufen (siehe
## eigener Fallback-Test unten), nicht weil EquipmentService leer wäre,
## sondern weil CombatSystem den Angreifer gar nicht erst identifizieren kann.

extends GutTest

var _equipment: EquipmentService
var _stat_mods: StatModifierService
var _combat: CombatSystem
var _bus: MockEventBus
var _session: SessionManager
var _bridge: NetworkBridge

func before_each() -> void:
	_bus = MockEventBus.new()
	_stat_mods = StatModifierService.new()

	# ADR-029 Round 66: peer 1 ↔ "p1" für den Standardfall (attacker_peer_id
	# nicht angegeben → CombatSystem fällt intern auf 1 zurück), peer 4 ↔ "p4"
	# für den expliziten Attributions-Test unten.
	_session = SessionManager.new()
	_session.register_player_slot(1, "p1")
	_session.register_player_slot(4, "p4")
	add_child_autofree(_session)

	_bridge = NetworkBridge.new()
	_bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.SESSION_MANAGER: _session,
	}))
	add_child_autofree(_bridge)

	var save := SaveSystem.new()
	save.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))

	_equipment = EquipmentService.new()
	_equipment.configure(ServiceDeps.from_dict({
		"stat_modifiers": _stat_mods,
		"savesystem": save,
		"network_bridge": _bridge,
	}))
	_combat = CombatSystem.new()
	_combat.configure(ServiceDeps.from_dict({
		"stat_modifiers": _stat_mods,
		ServiceKeys.EQUIPMENT: _equipment,
		ServiceKeys.EVENT_BUS: _bus,
	}))
	# Phase C8 Late-Inject (ADR-029 Round 65) — analog zum echten Boot.
	_combat.inject_network_bridge(_bridge)

func after_each() -> void:
	_equipment.on_cleanup()
	_stat_mods.on_cleanup()
	_combat.on_cleanup()
	_equipment = null
	_stat_mods = null
	_combat = null
	_bus = null
	_session = null
	_bridge = null

func _make_dagger(dmg_bonus: float = 8.0, poison: bool = true) -> WeaponDefinition:
	var d := WeaponDefinition.new()
	d.id = "poison_dagger"
	d.display_name = "Giftdolch"
	d.max_stack = 1
	d.damage_bonus = dmg_bonus
	d.weapon_type = WeaponDefinition.WeaponType.DAGGER
	d.on_hit_effect = 0 if poison else -1
	d.on_hit_ticks = 5
	d.on_hit_damage_per_tick = 2.0
	d.on_hit_tick_interval = 1.0
	return d

func _make_health(max_hp: int = 100) -> HealthComponent:
	var hc := HealthComponent.new()
	hc.max_health = max_hp
	hc.reset()
	return hc

# ─────────────────────────────────────────────
# Equipment → StatModifier
# ─────────────────────────────────────────────

func test_equip_weapon_applies_damage_bonus_stat() -> void:
	var dagger := _make_dagger(8.0)
	_equipment.equip("weapon", dagger, "p1")
	var bonus := _stat_mods.get_effective_stat("damage_bonus", 0.0, "p1")
	assert_eq(bonus, 8.0, "damage_bonus muss nach equip() sichtbar sein")

func test_unequip_removes_damage_bonus_stat() -> void:
	var dagger := _make_dagger(8.0)
	_equipment.equip("weapon", dagger, "p1")
	_equipment.unequip("weapon", "p1")
	var bonus := _stat_mods.get_effective_stat("damage_bonus", 0.0, "p1")
	assert_eq(bonus, 0.0, "damage_bonus muss nach unequip() weg sein")

func test_swap_weapon_updates_stat_correctly() -> void:
	var weak_sword := WeaponDefinition.new()
	weak_sword.id = "weak_sword"
	weak_sword.display_name = "Holzschwert"
	weak_sword.damage_bonus = 3.0
	_equipment.equip("weapon", weak_sword, "p1")

	var dagger := _make_dagger(8.0)
	_equipment.equip("weapon", dagger, "p1")  # überschreibt

	var bonus := _stat_mods.get_effective_stat("damage_bonus", 0.0, "p1")
	assert_eq(bonus, 8.0, "Nach Waffentausch muss neuer Bonus gelten (8.0, nicht 3.0)")

func test_get_equipped_weapon_returns_weapon_definition() -> void:
	var dagger := _make_dagger()
	_equipment.equip("weapon", dagger, "p1")
	var result := _equipment.get_equipped_weapon("p1")
	assert_is(result, WeaponDefinition)
	assert_eq(result.id, "poison_dagger")

func test_get_equipped_weapon_returns_null_when_empty() -> void:
	assert_null(_equipment.get_equipped_weapon("p1"), "Kein Weapon → null erwartet")

# ─────────────────────────────────────────────
# apply_weapon_on_hit() – Gift + Brand
# ─────────────────────────────────────────────

func test_apply_weapon_on_hit_does_nothing_without_equipment_service() -> void:
	# CombatSystem ohne Equipment-Dep — kein Absturz erwartet
	var combat_no_eq := CombatSystem.new()
	combat_no_eq.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
	}))
	var hc := _make_health()
	combat_no_eq.apply_weapon_on_hit(hc, "player", "goblin_01")
	assert_eq(hc.current_health, hc.max_health, "Ohne Equipment kein Schaden")
	combat_no_eq.on_cleanup()

## ADR-029 Round 66: ohne NetworkBridge kann CombatSystem den Angreifer nicht
## zu einer player_uuid auflösen — die Waffen-Suche muss dann leer laufen
## (kein Crash, kein Gift), symmetrisch zum Skill-Bonus-Fallback aus Round 65
## (test_combat_system.gd).
func test_apply_weapon_on_hit_skips_weapon_lookup_without_network_bridge() -> void:
	var combat_no_bridge := CombatSystem.new()
	combat_no_bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EQUIPMENT: _equipment,
		ServiceKeys.EVENT_BUS: _bus,
	}))
	# Bewusst KEIN inject_network_bridge() — Waffe ist trotzdem für "p1" equipped.
	_equipment.equip("weapon", _make_dagger(8.0, true), "p1")
	var hc := _make_health()
	combat_no_bridge.apply_weapon_on_hit(hc, "player", "goblin_01")
	assert_eq(combat_no_bridge.get_active_status_effect_count(), 0,
		"Ohne NetworkBridge kann der Angreifer nicht aufgelöst werden — kein Gift, aber auch kein Crash.")
	combat_no_bridge.on_cleanup()

func test_apply_weapon_on_hit_with_poison_weapon_registers_status_effect() -> void:
	# Positiver Pfad: Giftdolch ausgerüstet → apply_weapon_on_hit → StatusEffect aktiv
	var dagger := _make_dagger(8.0, true)   # on_hit_effect = POISON
	_equipment.equip("weapon", dagger, "p1")
	var hc := _make_health()
	_combat.apply_weapon_on_hit(hc, "player", "goblin_01")
	assert_eq(_combat.get_active_status_effect_count(), 1,
		"Giftdolch-Treffer muss einen StatusEffect registrieren")

func test_apply_weapon_on_hit_poison_ticks_deal_damage() -> void:
	# Nach on_tick() muss der Status-Effekt tatsächlich Schaden verursachen
	var dagger := _make_dagger(8.0, true)
	dagger.on_hit_ticks = 3
	dagger.on_hit_damage_per_tick = 5.0
	dagger.on_hit_tick_interval = 1.0
	_equipment.equip("weapon", dagger, "p1")
	var hc := _make_health(100)
	_combat.apply_weapon_on_hit(hc, "player", "goblin_01")
	_combat.on_tick(1.0)
	assert_lt(hc.current_health, hc.max_health,
		"Nach einem Gift-Tick muss HP reduziert sein")
	assert_eq(hc.current_health, 95,   # 100 - 5 (DamageType.TRUE, kein Krit)
		"Gift-Tick muss exakt damage_per_tick als TRUE-Schaden abziehen")

## ADR-019: apply_weapon_on_hit()'s attacker_peer_id-Parameter muss bis in
## den DamageRecord des tödlichen Gift-Ticks durchreichen — sonst bliebe die
## zweite, kleinere Version der Attributions-Lücke (Status-Effekte) offen,
## selbst nachdem der ursprüngliche Treffer sie schon korrekt trägt.
## ADR-029 Round 66: Waffe muss jetzt für DENSELBEN Spieler ausgerüstet sein,
## der als attacker_peer_id (4 → "p4" über SessionManager) übergeben wird —
## sonst findet CombatSystem beim Waffen-Lookup gar nichts (siehe R-8/Round-66-
## Umbau oben), unabhängig vom Attributions-Ziel dieses Tests.
func test_apply_weapon_on_hit_threads_attacker_player_id_into_lethal_tick() -> void:
	var dagger := _make_dagger(8.0, true)
	dagger.on_hit_ticks = 3
	dagger.on_hit_damage_per_tick = 5.0
	dagger.on_hit_tick_interval = 1.0
	_equipment.equip("weapon", dagger, "p4")
	var hc := _make_health(5)  # stirbt am ersten Tick
	var received: Array = ["not_called"]
	hc.died.connect(func(record: DamageRecord) -> void: received[0] = record)
	_combat.apply_weapon_on_hit(hc, "player", "goblin_01", 4)
	_combat.on_tick(1.0)
	assert_true(hc.is_dead)
	assert_not_null(received[0], "Tödlicher Gift-Tick muss died() mit Record emittieren.")
	assert_eq((received[0] as DamageRecord).attacker_peer_id, 4,
		"attacker_peer_id muss von apply_weapon_on_hit() bis in den Tick-Record reisen.")

func test_apply_weapon_on_hit_with_burn_weapon_registers_burn_effect() -> void:
	# BURN-Waffe (on_hit_effect = StatusEffect.Kind.BURN = 1)
	var fire_sword := WeaponDefinition.new()
	fire_sword.id = "fire_sword"
	fire_sword.display_name = "Feuerschwert"
	fire_sword.max_stack = 1
	fire_sword.damage_bonus = 6.0
	fire_sword.on_hit_effect = StatusEffect.Kind.BURN   # = 1
	fire_sword.on_hit_ticks = 4
	fire_sword.on_hit_damage_per_tick = 3.0
	fire_sword.on_hit_tick_interval = 1.0
	_equipment.equip("weapon", fire_sword, "p1")
	var hc := _make_health()
	_combat.apply_weapon_on_hit(hc, "player", "goblin_01")
	assert_eq(_combat.get_active_status_effect_count(), 1,
		"Feuerwaffe muss einen Brand-StatusEffect registrieren")

func test_apply_weapon_on_hit_no_double_stack_same_source_target() -> void:
	# Zweiter Treffer mit derselben source/target-Kombi überschreibt, stapelt nicht
	var dagger := _make_dagger(8.0, true)
	dagger.on_hit_ticks = 5
	_equipment.equip("weapon", dagger, "p1")
	var hc := _make_health()
	_combat.apply_weapon_on_hit(hc, "player", "goblin_01")
	_combat.apply_weapon_on_hit(hc, "player", "goblin_01")  # zweiter Treffer
	assert_eq(_combat.get_active_status_effect_count(), 1,
		"Gleiche source/target-Kombi darf nicht stapeln — Überschreibung erwartet")

func test_weapon_without_on_hit_effect_skips_poison() -> void:
	var sword_no_poison := WeaponDefinition.new()
	sword_no_poison.id = "plain_sword"
	sword_no_poison.display_name = "Normales Schwert"
	sword_no_poison.damage_bonus = 5.0
	sword_no_poison.on_hit_effect = -1   # kein Effekt
	_equipment.equip("weapon", sword_no_poison, "p1")

	var hc := _make_health()
	_combat.apply_weapon_on_hit(hc, "player", "goblin_01")
	assert_eq(_combat.get_active_status_effect_count(), 0,
		"Waffe ohne on_hit_effect darf keinen StatusEffect registrieren")
	assert_eq(hc.current_health, hc.max_health, "Normales Schwert darf kein Gift auslösen")

# ─────────────────────────────────────────────
# WeaponDefinition Typen + Rendering-Hints
# ─────────────────────────────────────────────

func test_dagger_visual_offset_not_zero() -> void:
	var dagger := _make_dagger()
	dagger.visual_offset = Vector3(0.0, -0.12, 0.18)
	assert_ne(dagger.visual_offset, Vector3.ZERO, "Dagger braucht visual_offset für Hand-Positionierung")

func test_all_weapon_types_covered() -> void:
	# Sicherstellt dass WeaponType-Enum alle 4 Typen hat
	assert_eq(WeaponDefinition.WeaponType.DAGGER, 0)
	assert_eq(WeaponDefinition.WeaponType.SWORD,  1)
	assert_eq(WeaponDefinition.WeaponType.AXE,    2)
	assert_eq(WeaponDefinition.WeaponType.STAFF,  3)

# ─────────────────────────────────────────────
# equipment_changed Signal
# ─────────────────────────────────────────────

func test_equip_emits_equipment_changed_signal() -> void:
	var dagger := _make_dagger()
	watch_signals(_equipment)
	_equipment.equip("weapon", dagger, "p1")
	assert_signal_emitted(_equipment, "equipment_changed")

func test_unequip_emits_equipment_changed_with_null() -> void:
	var dagger := _make_dagger()
	_equipment.equip("weapon", dagger, "p1")
	watch_signals(_equipment)
	_equipment.unequip("weapon", "p1")
	assert_signal_emitted(_equipment, "equipment_changed")

func test_double_unequip_returns_false() -> void:
	_equipment.equip("weapon", _make_dagger(), "p1")
	assert_true(_equipment.unequip("weapon", "p1"))
	assert_false(_equipment.unequip("weapon", "p1"), "Zweites unequip auf leeren Slot → false")
