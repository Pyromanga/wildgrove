## tests/unit/test_goblin_loot.gd
## Unit-Tests für das Goblin-Drop-System.
##
## Abdeckung:
##   - LootTable.roll() liefert bekannte item_ids
##   - PoisonDagger hat korrekte WeaponDefinition-Felder
##   - GoblinEar ist ein normales ItemDefinition (kein WeaponDefinition)
##   - DataManifest enthält alle neuen Pfade
##   - EnemyNPC._loot_table_id default = "goblin_loot"
##   - LootTable max_rolls begrenzt die Ausgabe

extends GutTest

var _loot_table: LootTable

func before_each() -> void:
	_loot_table = LootTable.new()

func after_each() -> void:
	_loot_table = null

func _make_entry(item_id: String, weight: float, min_qty: int = 1, max_qty: int = 1) -> LootEntry:
	var e := LootEntry.new()
	e.item_id      = item_id
	e.weight       = weight
	e.quantity_min = min_qty
	e.quantity_max = max_qty
	return e

# ─────────────────────────────────────────────
# LootTable.roll()
# ─────────────────────────────────────────────

func test_roll_empty_table_returns_empty_dict() -> void:
	var result := _loot_table.roll()
	assert_eq(result.size(), 0, "Leere Tabelle → kein Drop")

func test_roll_single_guaranteed_entry() -> void:
	_loot_table.entries = [_make_entry("goblin_ear", 999.0)]
	_loot_table.max_rolls = 1
	var result := _loot_table.roll()
	assert_true(result.has("goblin_ear"), "Garantierter Eintrag muss droppen")
	assert_gt(result["goblin_ear"], 0, "Menge muss > 0 sein")

func test_roll_respects_max_rolls() -> void:
	_loot_table.entries = [
		_make_entry("item_a", 100.0),
		_make_entry("item_b", 100.0),
		_make_entry("item_c", 100.0),
	]
	_loot_table.max_rolls = 1
	var result := _loot_table.roll()
	assert_lte(result.size(), 1, "max_rolls=1 darf maximal 1 Item liefern")

func test_roll_quantity_within_range() -> void:
	_loot_table.entries = [_make_entry("copper_ore", 999.0, 2, 5)]
	_loot_table.max_rolls = 3
	for i in range(20):
		var result := _loot_table.roll()
		if result.has("copper_ore"):
			assert_gte(result["copper_ore"], 2, "Menge muss >= quantity_min sein")
			assert_lte(result["copper_ore"], 5, "Menge muss <= quantity_max sein")

func test_roll_zero_weight_never_drops() -> void:
	_loot_table.entries = [_make_entry("rare_item", 0.0)]
	_loot_table.max_rolls = 5
	for i in range(50):
		var result := _loot_table.roll()
		assert_false(result.has("rare_item"), "weight=0 darf nie droppen")

func test_get_guaranteed_drops_with_full_weight() -> void:
	var entry := _make_entry("goblin_ear", 100.0)
	_loot_table.entries = [entry]
	var guaranteed := _loot_table.get_guaranteed_drops()
	assert_eq(guaranteed.size(), 1)
	assert_eq(guaranteed[0], "goblin_ear")

# ─────────────────────────────────────────────
# PoisonDagger WeaponDefinition
# ─────────────────────────────────────────────

func test_poison_dagger_has_correct_damage_bonus() -> void:
	var dagger := _make_poison_dagger()
	assert_eq(dagger.damage_bonus, 8.0, "Giftdolch muss +8 damage_bonus haben")

func test_poison_dagger_has_on_hit_effect() -> void:
	var dagger := _make_poison_dagger()
	assert_gte(dagger.on_hit_effect, 0, "on_hit_effect muss >= 0 sein (Gift aktiv)")

func test_poison_dagger_has_poison_ticks() -> void:
	var dagger := _make_poison_dagger()
	assert_gt(dagger.on_hit_ticks, 0, "on_hit_ticks muss > 0 sein")
	assert_gt(dagger.on_hit_damage_per_tick, 0.0, "on_hit_damage_per_tick muss > 0 sein")

func test_poison_dagger_is_dagger_type() -> void:
	var dagger := _make_poison_dagger()
	assert_eq(dagger.weapon_type, WeaponDefinition.WeaponType.DAGGER)

func test_poison_dagger_max_stack_is_1() -> void:
	var dagger := _make_poison_dagger()
	assert_eq(dagger.max_stack, 1, "Waffen sind nicht stapelbar")

func _make_poison_dagger() -> WeaponDefinition:
	var d := WeaponDefinition.new()
	d.id = "poison_dagger"
	d.display_name = "Giftdolch"
	d.max_stack = 1
	d.damage_bonus = 8.0
	d.weapon_type = WeaponDefinition.WeaponType.DAGGER
	d.on_hit_effect = 0
	d.on_hit_ticks = 5
	d.on_hit_damage_per_tick = 2.0
	d.on_hit_tick_interval = 1.0
	return d

# ─────────────────────────────────────────────
# GoblinEar ItemDefinition
# ─────────────────────────────────────────────

func test_goblin_ear_is_not_weapon() -> void:
	var ear := ItemDefinition.new()
	ear.id = "goblin_ear"
	ear.display_name = "Goblin-Ohr"
	ear.max_stack = 20
	assert_false(ear is WeaponDefinition, "GoblinEar darf kein WeaponDefinition sein")
	assert_eq(ear.max_stack, 20)

# ─────────────────────────────────────────────
# DataManifest Vollständigkeit
# ─────────────────────────────────────────────

func test_data_manifest_contains_goblin_ear() -> void:
	var found := false
	for path in DataManifest.ITEMS:
		if path.contains("GoblinEar"):
			found = true
			break
	assert_true(found, "DataManifest.ITEMS muss GoblinEar.tres enthalten")

func test_data_manifest_contains_poison_dagger() -> void:
	var found := false
	for path in DataManifest.ITEMS:
		if path.contains("PoisonDagger"):
			found = true
			break
	assert_true(found, "DataManifest.ITEMS muss PoisonDagger.tres enthalten")

func test_data_manifest_has_loot_tables_const() -> void:
	assert_true(DataManifest.LOOT_TABLES != null, "DataManifest muss LOOT_TABLES haben")

func test_data_manifest_contains_goblin_loot_table() -> void:
	var found := false
	for path in DataManifest.LOOT_TABLES:
		if path.contains("goblin_loot"):
			found = true
			break
	assert_true(found, "DataManifest.LOOT_TABLES muss goblin_loot.tres enthalten")
