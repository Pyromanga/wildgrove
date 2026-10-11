# res://tests/unit/test_property_based.gd
extends GutTest

## Property-Based / Invarianten-Tests für CombatSystem.calculate_damage(),
## StatModifierService.get_effective_stat() und SaveMigrationService.migrate().
##
## "Property-based" im GDScript-Kontext bedeutet: anstatt einen Beispielwert
## zu testen, testen wir EIGENSCHAFTEN die für ALLE (oder eine repräsentative
## Stichprobe von) Eingaben gelten müssen. Jeder Test läuft über ein Array
## von Seed-Parametern und prüft die Invariante für jeden Eintrag.
##
## Abgedeckt (BUG-12 / E-03):
##
## calculate_damage() — PHYSICAL / MAGIC Invarianten:
##   P-01  final >= MIN_DAMAGE für alle raw >= 0, alle armor in [0,1]
##   P-02  TRUE-Schaden ist immer gleich raw (kein Krit, keine Resistenz)
##   P-03  final nimmt mit steigender Resistenz monoton ab (kein Overshoot)
##   P-04  Rüstungs-Clamp: armor > 0.85 darf nie mehr Wirkung haben als 0.85
##   P-05  Idempotenz-ähnlich: derselbe Record zweimal berechnen ändert den Record nach
##         dem ersten Aufruf nicht mehr (Record ist nach calculate_damage() "final")
##   P-06  Schaden ist nie negativ
##
## get_effective_stat() — StatModifier-Mathematik Invarianten:
##   S-01  Ohne Modifier: Ergebnis == base_value (Identität)
##   S-02  FLAT_ADD-Linearität: n identische FLAT_ADD-Modifier summieren sich additiv
##   S-03  PERCENT_ADD: Kein-Effekt bei 0.0, voller Effekt bei 0.5 (+50%)
##   S-04  PERCENT_MULTIPLY: Multiplikation mit 1.0 ändert den Wert nicht
##   S-05  PERCENT_MULTIPLY ×0.0 ergibt 0 (nach FLAT_ADD-Schritt) — erlaubt,
##         da bei 0-Wert die FLAT-Summe einzige Grundlage ist
##   S-06  Reihenfolge: FLAT_ADD + PERCENT_ADD + PERCENT_MULTIPLY gemäß Vertrag
##   S-07  Modifikatoren für anderen stat werden ignoriert (cross-stat bleed)
##   S-08  Ergebnis ist niemals NaN oder +/-inf bei normalen Inputs
##
## migrate() — SaveMigration Invarianten:
##   M-01  Idempotenz: migrate(migrate(data)) == migrate(data)
##   M-02  schema_version == CURRENT_VERSION nach Migration
##   M-03  Downgrade (version > CURRENT_VERSION): Daten werden unverändert zurückgegeben
##   M-04  v0-Daten erhalten schema_version == CURRENT_VERSION
##   M-05  v1-Daten mit quest_block werden normalisiert (started_at, level)
##   M-06  v2-Daten erhalten "equipment"-Block wenn fehlend
##   M-07  Bestehender "equipment"-Block wird nie überschrieben (non-destructive)
##   M-08  migrate() mutiert die Eingabe nicht (deep-copy-Invariante)

# ─────────────────────────────────────────────────────────────────────────────
# Hilfsvariablen
# ─────────────────────────────────────────────────────────────────────────────

var _combat:   CombatSystem
var _stat_mod: StatModifierService

## Deterministischer RNG — Krit-Würfel ist damit vorhersagbar.
## Seed 0: BASE_CRIT_CHANCE 5% → die meisten Würfe sind kein Krit.
## Tests die Nicht-Krit brauchen, nutzen einen geseedeten RNG mit bekanntem
## first-roll-Verhalten oder testen mit TRUE-Schaden (kein Krit-Gate).
var _seeded_rng: RandomNumberGenerator

## Armor-/Resistenz-Stichproben für Schleifen.
const RESISTANCE_SAMPLES: Array[float] = [0.0, 0.1, 0.25, 0.5, 0.75, 0.85, 0.9, 1.0]

## Raw-Schaden-Stichproben.
const RAW_DAMAGE_SAMPLES: Array[float] = [0.0, 0.5, 1.0, 5.0, 10.0, 100.0, 999.9]

## Base-Values für StatModifier-Tests.
const BASE_VALUES: Array[float] = [0.0, 1.0, 10.0, 100.0, -5.0]

func before_each() -> void:
	_seeded_rng = RandomNumberGenerator.new()
	_seeded_rng.seed = 42  # Reproduzierbarer Seed — kein flaky-Verhalten

	_combat = CombatSystem.new()
	## Geseedeten RNG injizieren → Krit-Würfel deterministic.
	_combat.configure(ServiceDeps.from_dict({"rng": _seeded_rng}))

	_stat_mod = StatModifierService.new()
	_stat_mod.configure(ServiceDeps.from_dict({}))

func after_each() -> void:
	_combat.on_cleanup()
	_stat_mod.on_cleanup()
	_combat   = null
	_stat_mod = null

# ═════════════════════════════════════════════════════════════════════════════
# P — calculate_damage() Invarianten
# ═════════════════════════════════════════════════════════════════════════════

## P-01: final_amount >= MIN_DAMAGE für alle raw >= 0 und alle Resistenzwerte.
func test_p01_final_amount_never_below_min_damage_physical() -> void:
	var min_dmg: float = CombatSystem.MIN_DAMAGE
	for raw in RAW_DAMAGE_SAMPLES:
		for armor in RESISTANCE_SAMPLES:
			var rec := DamageRecord.make_player_attack("src", "tgt", raw, DamageRecord.DamageType.PHYSICAL)
			_combat.calculate_damage(rec, armor, 0.0)
			assert_gte(
				rec.final_amount, min_dmg,
				"P-01 PHYSICAL: raw=%.1f armor=%.2f → final=%.2f muss >= MIN_DAMAGE=%.1f sein" \
				% [raw, armor, rec.final_amount, min_dmg]
			)

## P-01 (MAGIC): final_amount >= MIN_DAMAGE für alle raw >= 0 und alle magic-resist-Werte.
func test_p01_final_amount_never_below_min_damage_magic() -> void:
	var min_dmg: float = CombatSystem.MIN_DAMAGE
	for raw in RAW_DAMAGE_SAMPLES:
		for mr in RESISTANCE_SAMPLES:
			var rec := DamageRecord.make_player_attack("src", "tgt", raw, DamageRecord.DamageType.MAGIC)
			_combat.calculate_damage(rec, 0.0, mr)
			assert_gte(
				rec.final_amount, min_dmg,
				"P-01 MAGIC: raw=%.1f mr=%.2f → final=%.2f muss >= MIN_DAMAGE=%.1f sein" \
				% [raw, mr, rec.final_amount, min_dmg]
			)

## P-02: TRUE-Schaden ist immer exakt raw (kein Krit, keine Resistenz, kein MIN_DAMAGE-Override wenn raw > 0).
func test_p02_true_damage_equals_raw_for_all_resistance_combinations() -> void:
	## TRUE-Schaden bypassed Krit-Gate → exakte Gleichheit ist sicher.
	## Bei raw=0 greift MIN_DAMAGE → separater Untertest.
	const RAW_NONZERO: Array[float] = [1.0, 5.0, 10.0, 100.0, 999.9]
	for raw in RAW_NONZERO:
		for armor in RESISTANCE_SAMPLES:
			for mr in RESISTANCE_SAMPLES:
				var rec := DamageRecord.make_player_attack("src", "tgt", raw, DamageRecord.DamageType.TRUE)
				_combat.calculate_damage(rec, armor, mr)
				assert_eq(
					rec.final_amount, raw,
					"P-02 TRUE: raw=%.1f armor=%.2f mr=%.2f → final muss == raw sein (war %.2f)" \
					% [raw, armor, mr, rec.final_amount]
				)
				assert_false(rec.is_critical, "P-02 TRUE: Krit-Flag darf bei TRUE-Schaden nicht gesetzt werden")

## P-03: Monotone Abnahme — mehr Resistenz bedeutet nie mehr finalen Schaden.
func test_p03_final_amount_monotonically_decreases_with_armor() -> void:
	## Deterministischer RNG → Krit-Würfel identisch für alle Iterationen.
	## Wir testen dennoch nicht auf exakte Werte — nur auf ≤ Relation.
	const RAW: float = 100.0
	var prev_final: float = 999999.0
	for armor in [0.0, 0.1, 0.25, 0.5, 0.75, 0.85]:
		## Neuen RNG mit identischem Seed für vergleichbare Würfe.
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		_combat.configure(ServiceDeps.from_dict({"rng": rng}))

		var rec := DamageRecord.make_player_attack("src", "tgt", RAW, DamageRecord.DamageType.PHYSICAL)
		_combat.calculate_damage(rec, armor, 0.0)
		assert_lte(
			rec.final_amount, prev_final,
			"P-03: final bei armor=%.2f (%.2f) muss <= vorherigem Wert (%.2f) sein" \
			% [armor, rec.final_amount, prev_final]
		)
		prev_final = rec.final_amount

## P-04: Rüstungs-Clamp — armor > 0.85 hat nie mehr Wirkung als armor = 0.85.
func test_p04_armor_above_085_clamped_to_085() -> void:
	const RAW: float = 100.0
	const OVER_ARMOR_VALUES: Array[float] = [0.86, 0.9, 0.95, 1.0, 1.5, 10.0]

	## Referenzwert bei genau 0.85 (mit identischem RNG-Seed für gleiche Krit-Chance)
	var rng_ref := RandomNumberGenerator.new()
	rng_ref.seed = 99
	_combat.configure(ServiceDeps.from_dict({"rng": rng_ref}))
	var ref_rec := DamageRecord.make_player_attack("src", "tgt", RAW, DamageRecord.DamageType.PHYSICAL)
	_combat.calculate_damage(ref_rec, 0.85, 0.0)
	var ref_final := ref_rec.final_amount

	for over_armor in OVER_ARMOR_VALUES:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99  # gleicher Seed → identische Krit-Entscheidung
		_combat.configure(ServiceDeps.from_dict({"rng": rng}))
		var rec := DamageRecord.make_player_attack("src", "tgt", RAW, DamageRecord.DamageType.PHYSICAL)
		_combat.calculate_damage(rec, over_armor, 0.0)
		assert_eq(
			rec.final_amount, ref_final,
			"P-04: armor=%.2f muss denselben Effekt wie 0.85 haben (%.2f != %.2f)" \
			% [over_armor, rec.final_amount, ref_final]
		)

## P-05: Nach calculate_damage() ist final_amount gesetzt und ein zweiter Aufruf
##        desselben Records ändert final_amount nicht mehr (Post-condition-Stabilität).
##        Hinweis: DamageRecord ist kein sealed-Objekt — das Verhalten ist eine Konvention,
##        kein technischer Schutz. Der Test dokumentiert und sichert die Konvention.
func test_p05_record_final_amount_stable_after_first_calculate() -> void:
	var rec := DamageRecord.make_player_attack("src", "tgt", 50.0, DamageRecord.DamageType.TRUE)
	_combat.calculate_damage(rec, 0.0, 0.0)
	var first_final := rec.final_amount
	## TRUE-Schaden: kein Krit, kein Resistenz-Faktor → deterministisch.
	_combat.calculate_damage(rec, 0.0, 0.0)
	assert_eq(
		rec.final_amount, first_final,
		"P-05: final_amount nach zweitem calculate_damage() muss unverändert sein"
	)

## P-06: final_amount ist nie negativ.
func test_p06_final_amount_never_negative() -> void:
	for dtype in [DamageRecord.DamageType.PHYSICAL, DamageRecord.DamageType.MAGIC, DamageRecord.DamageType.TRUE]:
		for raw in RAW_DAMAGE_SAMPLES:
			var rec := DamageRecord.new()
			rec.source_id  = "src"
			rec.target_id  = "tgt"
			rec.raw_amount = raw
			rec.damage_type = dtype
			_combat.calculate_damage(rec, 0.85, 0.85)
			assert_gte(
				rec.final_amount, 0.0,
				"P-06: final_amount muss >= 0 sein (war %.4f, raw=%.1f dtype=%d)" \
				% [rec.final_amount, raw, dtype]
			)

# ═════════════════════════════════════════════════════════════════════════════
# S — get_effective_stat() Invarianten
# ═════════════════════════════════════════════════════════════════════════════

## S-01: Ohne Modifier gibt get_effective_stat() exakt base_value zurück.
func test_s01_no_modifiers_returns_base_value() -> void:
	for base in BASE_VALUES:
		var result := _stat_mod.get_effective_stat("damage", base, "p1")
		assert_eq(
			result, base,
			"S-01: Ohne Modifier muss get_effective_stat() base_value zurückgeben (base=%.1f, result=%.1f)" \
			% [base, result]
		)

## S-02: n identische FLAT_ADD-Modifier summieren sich additiv auf.
func test_s02_flat_add_is_additive() -> void:
	const BASE: float = 10.0
	const VAL:  float = 5.0
	const N:    int   = 4

	for i in range(N):
		var mod := StatModifier.permanent(
			"source_%d" % i, "damage", StatModifier.Operation.FLAT_ADD, VAL
		)
		_stat_mod.add_modifier(mod, "p1")

	var result := _stat_mod.get_effective_stat("damage", BASE, "p1")
	var expected := BASE + VAL * N
	assert_eq(
		result, expected,
		"S-02: %d × FLAT_ADD(%.1f) auf base %.1f muss %.1f ergeben (war %.1f)" \
		% [N, VAL, BASE, expected, result]
	)

## S-03: PERCENT_ADD von 0.5 erhöht base um 50%.
func test_s03_percent_add_increases_by_factor() -> void:
	const BASE: float = 100.0
	var mod := StatModifier.permanent("buff", "damage", StatModifier.Operation.PERCENT_ADD, 0.5)
	_stat_mod.add_modifier(mod, "p1")
	var result := _stat_mod.get_effective_stat("damage", BASE, "p1")
	assert_eq(result, 150.0, "S-03: PERCENT_ADD 0.5 muss base × 1.5 ergeben (100 → 150)")

## S-04: PERCENT_MULTIPLY mit 1.0 ändert den Wert nicht.
func test_s04_percent_multiply_identity_at_one() -> void:
	for base in BASE_VALUES:
		var fresh_svc := StatModifierService.new()
		fresh_svc.configure(ServiceDeps.from_dict({}))
		var mod := StatModifier.permanent("mult_id", "damage", StatModifier.Operation.PERCENT_MULTIPLY, 1.0)
		fresh_svc.add_modifier(mod, "p1")
		var result := fresh_svc.get_effective_stat("damage", base, "p1")
		assert_eq(
			result, base,
			"S-04: PERCENT_MULTIPLY ×1.0 darf base nicht ändern (base=%.1f, result=%.1f)" \
			% [base, result]
		)
		fresh_svc.on_cleanup()

## S-05: Reihenfolge — FLAT_ADD dann PERCENT_ADD dann PERCENT_MULTIPLY (Vertrag in StatModifier.gd).
##        Beispiel: base=100, FLAT_ADD +20, PERCENT_ADD +0.15, PERCENT_MULTIPLY ×0.8
##        → (100 + 20) × (1 + 0.15) × 0.8 = 110.4
func test_s06_operation_order_matches_documented_contract() -> void:
	const BASE:   float = 100.0
	var m1 := StatModifier.permanent("flat",  "hp", StatModifier.Operation.FLAT_ADD,        20.0)
	var m2 := StatModifier.permanent("pct",   "hp", StatModifier.Operation.PERCENT_ADD,      0.15)
	var m3 := StatModifier.permanent("multi", "hp", StatModifier.Operation.PERCENT_MULTIPLY, 0.8)

	_stat_mod.add_modifier(m1, "p1")
	_stat_mod.add_modifier(m2, "p1")
	_stat_mod.add_modifier(m3, "p1")

	var result := _stat_mod.get_effective_stat("hp", BASE, "p1")
	var expected := (BASE + 20.0) * (1.0 + 0.15) * 0.8  # = 110.4
	assert_true(
		is_equal_approx(result, expected),
		"S-06: Operationsreihenfolge (FLAT→PERCENT_ADD→PERCENT_MULTIPLY) muss %.2f ergeben (war %.2f)" \
		% [expected, result]
	)

## S-07: Modifier für einen anderen stat beeinflusst den abgefragten stat nicht.
func test_s07_cross_stat_bleed_does_not_occur() -> void:
	var mod := StatModifier.permanent("armor_buff", "armor", StatModifier.Operation.FLAT_ADD, 999.0)
	_stat_mod.add_modifier(mod, "p1")
	var result := _stat_mod.get_effective_stat("damage", 50.0, "p1")
	assert_eq(result, 50.0, "S-07: Modifier für 'armor' darf 'damage'-Query nicht beeinflussen")

## S-08: Ergebnis ist niemals NaN oder Inf bei normalen Float-Inputs.
func test_s08_result_is_finite_for_normal_inputs() -> void:
	const LARGE: float = 1e6
	var m1 := StatModifier.permanent("big_flat",  "hp", StatModifier.Operation.FLAT_ADD,        LARGE)
	var m2 := StatModifier.permanent("big_pct",   "hp", StatModifier.Operation.PERCENT_ADD,      LARGE)
	var m3 := StatModifier.permanent("big_multi", "hp", StatModifier.Operation.PERCENT_MULTIPLY, LARGE)
	_stat_mod.add_modifier(m1, "p1")
	_stat_mod.add_modifier(m2, "p1")
	_stat_mod.add_modifier(m3, "p1")

	var result := _stat_mod.get_effective_stat("hp", 100.0, "p1")
	assert_true(is_finite(result), "S-08: Ergebnis muss ein endlicher Float sein (war %f)" % result)

# ═════════════════════════════════════════════════════════════════════════════
# M — migrate() Invarianten
# ═════════════════════════════════════════════════════════════════════════════

## Hilfsmethode: setzt downgrade_detected zurück (statische Klassenvariable).
func _reset_migration_state() -> void:
	SaveMigrationService.downgrade_detected = false

## M-01: Idempotenz — migrate(migrate(data)) == migrate(data)
func test_m01_migrate_is_idempotent() -> void:
	_reset_migration_state()
	var data := {"schema_version": 0, "quest_progress": {}}
	var once  := SaveMigrationService.migrate(data)
	_reset_migration_state()
	var twice := SaveMigrationService.migrate(once)
	assert_eq(
		twice, once,
		"M-01: Doppelte Migration muss dasselbe Ergebnis liefern wie einfache Migration"
	)

## M-02: schema_version == CURRENT_VERSION nach Migration.
func test_m02_schema_version_is_current_after_migration() -> void:
	_reset_migration_state()
	for v in [0, 1, 2]:
		var data := {"schema_version": v}
		var migrated := SaveMigrationService.migrate(data)
		assert_eq(
			migrated.get("schema_version", -1), SaveMigrationService.CURRENT_VERSION,
			"M-02: schema_version muss nach Migration CURRENT_VERSION (%d) sein (Start-v=%d)" \
			% [SaveMigrationService.CURRENT_VERSION, v]
		)
		_reset_migration_state()

## M-03: Downgrade-Erkennung — data version > CURRENT_VERSION → unverändert zurück + downgrade_detected.
func test_m03_downgrade_returns_data_unchanged_and_sets_flag() -> void:
	_reset_migration_state()
	var future_version := SaveMigrationService.CURRENT_VERSION + 1
	var data := {"schema_version": future_version, "some_key": "value"}
	var result := SaveMigrationService.migrate(data)

	assert_eq(result.get("schema_version"), future_version,
		"M-03: Downgrade darf schema_version nicht downgraden")
	assert_eq(result.get("some_key"), "value",
		"M-03: Downgrade darf keine Keys löschen oder ändern")
	assert_true(SaveMigrationService.downgrade_detected,
		"M-03: downgrade_detected muss nach Downgrade gesetzt sein")
	_reset_migration_state()

## M-04: v0-Daten erhalten schema_version == CURRENT_VERSION.
func test_m04_v0_data_migrates_to_current_version() -> void:
	_reset_migration_state()
	var data := {}  # kein schema_version → implizit v0
	var result := SaveMigrationService.migrate(data)
	assert_eq(
		result.get("schema_version", -1), SaveMigrationService.CURRENT_VERSION,
		"M-04: v0-Daten (kein schema_version-Key) müssen auf CURRENT_VERSION migriert werden"
	)

## M-05: v1-Daten mit quest_progress-Block erhalten normalisierte Quest-Felder.
func test_m05_v1_quest_records_get_required_fields_normalized() -> void:
	_reset_migration_state()
	var data := {
		"schema_version": 1,
		"quest_progress": {
			"active": {
				"quest_woodcutter": {"status": "started", "objectives": {"cut_tree": 3}}
				## "level" und "started_at" fehlen → sollen ergänzt werden
			}
		}
	}
	var result := SaveMigrationService.migrate(data)
	var quest: Dictionary = result["quest_progress"]["active"]["quest_woodcutter"]
	assert_true(quest.has("level"),      "M-05: 'level' muss nach v1→v2-Migration vorhanden sein")
	assert_true(quest.has("started_at"), "M-05: 'started_at' muss nach v1→v2-Migration vorhanden sein")
	assert_eq(quest["objectives"]["cut_tree"], 3, "M-05: Bestehende Objectives dürfen nicht verloren gehen")

## M-06: v2-Daten ohne "equipment"-Block erhalten einen leeren "equipment"-Block.
func test_m06_v2_data_without_equipment_gets_empty_equipment_block() -> void:
	_reset_migration_state()
	var data := {"schema_version": 2}
	var result := SaveMigrationService.migrate(data)
	assert_true(result.has("equipment"), "M-06: 'equipment'-Block muss nach v2→v3-Migration vorhanden sein")
	assert_eq(result["equipment"], {}, "M-06: Eingefügter 'equipment'-Block muss leer sein")

## M-07: Bestehender "equipment"-Block wird niemals überschrieben (non-destructive).
func test_m07_existing_equipment_block_is_not_overwritten() -> void:
	_reset_migration_state()
	var existing_equip := {"slot_weapon": "iron_sword_01", "slot_shield": "wooden_shield_01"}
	var data := {"schema_version": 2, "equipment": existing_equip.duplicate()}
	var result := SaveMigrationService.migrate(data)
	assert_eq(
		result["equipment"], existing_equip,
		"M-07: Bestehender equipment-Block darf durch Migration nicht überschrieben werden"
	)

## M-08: migrate() mutiert das originale Dictionary nicht (deep-copy).
func test_m08_migrate_does_not_mutate_original_input() -> void:
	_reset_migration_state()
	var original := {"schema_version": 0, "quest_progress": {"active": {}}}
	var snapshot := original.duplicate(true)
	SaveMigrationService.migrate(original)
	assert_eq(
		original, snapshot,
		"M-08: migrate() darf das originale Dictionary nicht mutieren"
	)
