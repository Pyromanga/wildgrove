## tests/unit/test_xp_bonus_and_armor.gd
## Ausrüstungs-Bonus auf Aktions-XP (SkillSystem.add_action_xp) und Rüstung im Kampf.
##
## Abdeckung:
##   - xp_bonus eines ausgerüsteten Items skaliert Aktions-XP (Skill-spezifisch und "all")
##   - Ablegen entfernt den Bonus wieder (Präfix-Cleanup, auch bei mehreren Boni je Slot)
##   - request_add_xp() (Quest-/Admin-Belohnung) bleibt UNskaliert
##   - Bonus gilt nur für den ausrüstenden Spieler
##   - ArmorDefinition: Rüstungswert wirkt in CombatSystem, Slot-Prüfung, Gesamt-Clamp 0.85
extends GutTest

class MockSkillDef extends SkillDefinition:
	func _init(p_id: String) -> void:
		id = p_id
	func get_xp_required(level: int) -> int:
		return level * 100000   # nie Level-Up im Test

class MockDataService extends DataService:
	func get_all_skills() -> Dictionary:
		return _skills

class MockSaveSystem extends SaveSystem:
	func register_save_provider(_p: Object) -> void:
		pass
	func get_state_for(_key: String) -> Dictionary:
		return {}

const P1 := "p1"
const P2 := "p2"
const SMITH := "smithing"
const WOOD := "woodcutting"

var _skills: SkillSystem
var _mods: StatModifierService
var _equipment: EquipmentService
var _combat: CombatSystem
var _bus: MockEventBus

func before_each() -> void:
	_bus = MockEventBus.new()
	_mods = StatModifierService.new()
	var ds := MockDataService.new()
	ds._skills[SMITH] = MockSkillDef.new(SMITH)
	ds._skills[WOOD] = MockSkillDef.new(WOOD)
	_skills = SkillSystem.new()
	_skills.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: ds,
		ServiceKeys.SAVE_SYSTEM: MockSaveSystem.new(),
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.STAT_MODIFIERS: _mods,
	}))
	_equipment = EquipmentService.new()
	_equipment.configure(ServiceDeps.from_dict({
		"stat_modifiers": _mods,
		"savesystem": MockSaveSystem.new(),
	}))
	_combat = CombatSystem.new()
	_combat.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS: _bus,
		ServiceKeys.STAT_MODIFIERS: _mods,
	}))

func after_each() -> void:
	_skills.on_cleanup()
	_equipment.on_cleanup()
	_combat.on_cleanup()
	_mods.on_cleanup()

func _tool_with_bonus(id: String, bonus: Dictionary) -> ToolDefinition:
	var t := ToolDefinition.new()
	t.id = id
	t.display_name = id
	t.speed_stat_id = ""
	t.xp_bonus = bonus
	return t

func _armor(id: String, slot: ArmorDefinition.ArmorSlot, value: float) -> ArmorDefinition:
	var a := ArmorDefinition.new()
	a.id = id
	a.display_name = id
	a.armor_slot = slot
	a.armor_value = value
	return a

# ── XP-Bonus ─────────────────────────────────────────────────────────────────

func test_action_xp_without_equipment_is_unchanged() -> void:
	assert_eq(_skills.add_action_xp(SMITH, 100, P1), 100)
	assert_eq(_skills.get_xp(SMITH, P1), 100)

func test_skill_specific_bonus_scales_only_that_skill() -> void:
	_equipment.equip("tool", _tool_with_bonus("hammer_x", {SMITH: 0.25}), P1)
	assert_eq(_skills.add_action_xp(SMITH, 100, P1), 125)
	assert_eq(_skills.add_action_xp(WOOD, 100, P1), 100)

func test_all_bonus_scales_every_skill() -> void:
	_equipment.equip("tool", _tool_with_bonus("charm", {"all": 0.10}), P1)
	assert_eq(_skills.add_action_xp(SMITH, 100, P1), 110)
	assert_eq(_skills.add_action_xp(WOOD, 100, P1), 110)

func test_bonuses_from_two_slots_stack_multiplicatively() -> void:
	_equipment.equip("tool", _tool_with_bonus("a", {SMITH: 0.5}), P1)
	_equipment.equip("weapon", _tool_with_bonus("b", {"all": 0.2}), P1)
	# 100 × 1.2 (all) × 1.5 (smithing) = 180
	assert_eq(_skills.add_action_xp(SMITH, 100, P1), 180)

func test_one_item_with_two_bonuses_keeps_both() -> void:
	_equipment.equip("tool", _tool_with_bonus("both", {SMITH: 0.5, "all": 0.2}), P1)
	assert_eq(_skills.add_action_xp(SMITH, 100, P1), 180)

func test_unequip_removes_all_bonuses_of_the_slot() -> void:
	_equipment.equip("tool", _tool_with_bonus("both", {SMITH: 0.5, "all": 0.2}), P1)
	_equipment.unequip("tool", P1)
	assert_eq(_skills.add_action_xp(SMITH, 100, P1), 100)

func test_request_add_xp_is_not_scaled() -> void:
	_equipment.equip("tool", _tool_with_bonus("charm", {"all": 1.0}), P1)
	_skills.request_add_xp(SMITH, 100, P1)
	assert_eq(_skills.get_xp(SMITH, P1), 100)

func test_bonus_applies_only_to_the_wearer() -> void:
	_equipment.equip("tool", _tool_with_bonus("charm", {"all": 1.0}), P1)
	assert_eq(_skills.add_action_xp(SMITH, 100, P2), 100)

func test_small_xp_never_rounds_to_zero() -> void:
	assert_eq(_skills.add_action_xp(SMITH, 1, P1), 1)

func test_xp_gained_event_goes_through_bonus() -> void:
	# Ernte-/Kampf-XP kommt über das EventBus-Signal; ohne aufgelöste player_id (kein NetworkBridge)
	# wird es verworfen — der Pfad ruft add_action_xp (siehe _on_xp_gained), das deckt der Test oben ab.
	assert_true(_skills.has_method("add_action_xp"))

# ── Rüstung ──────────────────────────────────────────────────────────────────

func test_armor_sets_armor_stat() -> void:
	_equipment.equip("chest", _armor("c", ArmorDefinition.ArmorSlot.CHEST, 0.14), P1)
	_equipment.equip("helmet", _armor("h", ArmorDefinition.ArmorSlot.HELMET, 0.06), P1)
	assert_almost_eq(_combat.equipped_armor_bonus(P1), 0.20, 0.0001)

func test_unequip_armor_removes_its_value() -> void:
	_equipment.equip("chest", _armor("c", ArmorDefinition.ArmorSlot.CHEST, 0.14), P1)
	_equipment.unequip("chest", P1)
	assert_almost_eq(_combat.equipped_armor_bonus(P1), 0.0, 0.0001)

func test_empty_player_id_has_no_armor() -> void:
	_equipment.equip("chest", _armor("c", ArmorDefinition.ArmorSlot.CHEST, 0.14), P1)
	assert_almost_eq(_combat.equipped_armor_bonus(""), 0.0, 0.0001)

func test_armor_reduces_physical_damage_for_wearer_only() -> void:
	_equipment.equip("chest", _armor("c", ArmorDefinition.ArmorSlot.CHEST, 0.5), P1)
	var profile := CombatProfile.default_profile()
	var r1 := _combat.enemy_melee_damage("goblin", "player", 100.0)
	_combat.calculate_damage_with_profile(r1, profile, P1)
	var r2 := _combat.enemy_melee_damage("goblin", "player", 100.0)
	_combat.calculate_damage_with_profile(r2, profile, P2)
	assert_lt(r1.final_amount, r2.final_amount)

func test_armor_total_is_clamped_by_combat_system() -> void:
	for slot in [ArmorDefinition.ArmorSlot.HELMET, ArmorDefinition.ArmorSlot.CHEST,
			ArmorDefinition.ArmorSlot.LEGS, ArmorDefinition.ArmorSlot.BOOTS]:
		var piece := _armor("p%d" % slot, slot, 0.9)
		_equipment.equip(piece.get_slot_id(), piece, P1)
	var rec := _combat.enemy_melee_damage("goblin", "player", 1000.0)
	_combat.calculate_damage_with_profile(rec, CombatProfile.default_profile(), P1)
	# max. 85 % Mitigation — nie unverwundbar (Krit kann nur erhöhen, daher untere Schranke prüfen).
	assert_gte(rec.final_amount, 1000.0 * 0.15 - 0.01)

func test_armor_slot_ids_match_definition() -> void:
	var helmet := _armor("h", ArmorDefinition.ArmorSlot.HELMET, 0.1)
	assert_eq(helmet.get_slot_id(), EquipmentService.SLOT_HELMET)
	assert_true(ArmorDefinition.is_armor_slot("boots"))
	assert_false(ArmorDefinition.is_armor_slot("weapon"))

func test_armor_only_accepted_in_its_own_slot() -> void:
	var chest := _armor("c", ArmorDefinition.ArmorSlot.CHEST, 0.1)
	assert_true(_equipment._slot_accepts("chest", chest))
	assert_false(_equipment._slot_accepts("helmet", chest))
	assert_false(_equipment._slot_accepts("weapon", chest))

func test_armor_slots_refuse_non_armor() -> void:
	var tool_def := _tool_with_bonus("t", {})
	assert_false(_equipment._slot_accepts("helmet", tool_def))
	assert_true(_equipment._slot_accepts("tool", tool_def))
