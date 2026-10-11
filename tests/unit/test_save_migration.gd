# res://tests/unit/test_save_migration.gd
extends GutTest

## Tests für SaveMigrationService — pure static functions, kein SceneTree nötig.
##
## Abgedeckte Pfade:
##   - Bereits aktueller Save (CURRENT_VERSION) → unverändert
##   - v0 → v2 (volle Kette)
##   - v1 → v2 (halbe Kette)
##   - Downgrade-Warnung (Version > CURRENT_VERSION)
##   - v1 → v2 mit fehlendem quest_progress-Block → kein Crash
##   - v1 → v2: fehlende Felder werden aufgefüllt
##   - v1 → v2: bestehende valide Felder bleiben erhalten

const CURRENT := SaveMigrationService.CURRENT_VERSION

# ─────────────────────────────────────────────
# Aktuelle Version → unverändert zurück
# ─────────────────────────────────────────────

func test_current_version_passthrough() -> void:
	var data := { "schema_version": CURRENT, "inventory": { "gold": 99 } }
	var result := SaveMigrationService.migrate(data)
	assert_eq(result["schema_version"], CURRENT)
	assert_eq(result["inventory"]["gold"], 99, "Inventar muss unberührt bleiben")

# ─────────────────────────────────────────────
# v0 → v2 (volle Migrationskette)
# ─────────────────────────────────────────────

func test_v0_migrates_to_current() -> void:
	var data := {}  # kein schema_version → v0
	var result := SaveMigrationService.migrate(data)
	assert_eq(result["schema_version"], CURRENT)

func test_v0_with_quest_gets_normalized() -> void:
	# v0-Save mit Quest-Block im alten Format (kein level, kein started_at)
	var data := {
		"quest_progress": {
			"active": {
				"quest_wood_01": {
					"status":     "started",
					"objectives": { "chop_5": 3 }
				}
			}
		}
	}
	var result := SaveMigrationService.migrate(data)
	assert_eq(result["schema_version"], CURRENT)
	var entry: Dictionary = result["quest_progress"]["active"]["quest_wood_01"]
	assert_eq(entry.get("level"),      1,         "level muss auf 1 defaulten")
	assert_eq(entry.get("started_at"), 0,         "started_at muss auf 0 defaulten")
	assert_eq(entry.get("status"),     "started",  "status bleibt erhalten")
	assert_eq(entry["objectives"]["chop_5"], 3,    "objectives-Progress bleibt erhalten")

# ─────────────────────────────────────────────
# v1 → v2 (halbe Kette)
# ─────────────────────────────────────────────

func test_v1_migrates_to_current() -> void:
	var data := { "schema_version": 1 }
	var result := SaveMigrationService.migrate(data)
	assert_eq(result["schema_version"], CURRENT)

func test_v1_missing_fields_get_defaults() -> void:
	var data := {
		"schema_version": 1,
		"quest_progress": {
			"active": {
				"quest_mining_01": {
					"status":     "started",
					"objectives": { "mine_10": 5 }
					# level und started_at fehlen absichtlich
				}
			}
		}
	}
	var result := SaveMigrationService.migrate(data)
	var entry: Dictionary = result["quest_progress"]["active"]["quest_mining_01"]
	assert_eq(entry.get("level"),      1, "level Default 1")
	assert_eq(entry.get("started_at"), 0, "started_at Default 0")

func test_v1_existing_fields_preserved() -> void:
	var data := {
		"schema_version": 1,
		"quest_progress": {
			"active": {
				"quest_farming_01": {
					"status":     "started",
					"level":      3,
					"started_at": 1700000000,
					"objectives": { "plant_5": 5 }
				}
			}
		}
	}
	var result := SaveMigrationService.migrate(data)
	var entry: Dictionary = result["quest_progress"]["active"]["quest_farming_01"]
	assert_eq(entry.get("level"),      3,          "Vorhandenes level bleibt erhalten")
	assert_eq(entry.get("started_at"), 1700000000, "Vorhandenes started_at bleibt erhalten")

# ─────────────────────────────────────────────
# v3 → v4 (ADR-035 Phase 1, Round 88): Inventory/Bank-Items → ItemInstance-Form
# ─────────────────────────────────────────────

func test_v3_inventory_qty_converted_to_item_instance_dict() -> void:
	var data := {
		"schema_version": 3,
		"inventory": { "p1": { "iron_ore": 7 } },
	}
	var result := SaveMigrationService.migrate(data)
	assert_eq(result["schema_version"], CURRENT)
	var entry: Dictionary = result["inventory"]["p1"]["iron_ore"]
	assert_eq(int(entry["quantity"]), 7, "Menge muss erhalten bleiben")
	assert_eq(entry["item_id"], "iron_ore")
	assert_false(String(entry.get("uuid", "")).is_empty(), "Migration muss eine uuid vergeben")
	assert_almost_eq(float(entry.get("durability", 0.0)), 100.0, 0.01, "Durability-Default 100.0")

func test_v3_bank_items_converted_gold_untouched() -> void:
	var data := {
		"schema_version": 3,
		"bank": {
			"items": { "p1": { "log_oak": 3 } },
			"gold":  { "p1": 500 },
		},
	}
	var result := SaveMigrationService.migrate(data)
	var entry: Dictionary = result["bank"]["items"]["p1"]["log_oak"]
	assert_eq(int(entry["quantity"]), 3)
	assert_false(String(entry.get("uuid", "")).is_empty())
	assert_eq(int(result["bank"]["gold"]["p1"]), 500, "Gold-Block darf von der Item-Migration nicht berührt werden")

func test_v3_migration_assigns_distinct_uuids_per_item() -> void:
	var data := {
		"schema_version": 3,
		"inventory": { "p1": { "iron_ore": 1, "log_oak": 1 } },
	}
	var result := SaveMigrationService.migrate(data)
	var uuid_a: String = result["inventory"]["p1"]["iron_ore"]["uuid"]
	var uuid_b: String = result["inventory"]["p1"]["log_oak"]["uuid"]
	assert_ne(uuid_a, uuid_b, "Verschiedene Items dürfen nicht dieselbe uuid bekommen")

func test_v3_missing_inventory_and_bank_blocks_no_crash() -> void:
	var data := { "schema_version": 3 }
	var result := SaveMigrationService.migrate(data)
	assert_eq(result["schema_version"], CURRENT, "Migration muss auch ohne inventory/bank-Block durchlaufen")

func test_v3_already_dict_format_passed_through() -> void:
	# Defensiv: falls ein item_id-Eintrag schon im neuen Format ist, nicht doppelt umwandeln.
	var data := {
		"schema_version": 3,
		"inventory": { "p1": { "iron_ore": { "item_id": "iron_ore", "quantity": 4, "uuid": "existing-uuid", "durability": 80.0 } } },
	}
	var result := SaveMigrationService.migrate(data)
	var entry: Dictionary = result["inventory"]["p1"]["iron_ore"]
	assert_eq(entry["uuid"], "existing-uuid", "Bereits migrierter Eintrag darf uuid nicht überschreiben")
	assert_almost_eq(float(entry["durability"]), 80.0, 0.01)

func test_current_version_inventory_item_instance_untouched() -> void:
	var data := {
		"schema_version": CURRENT,
		"inventory": { "p1": { "iron_ore": { "item_id": "iron_ore", "quantity": 9, "uuid": "abc", "durability": 50.0 } } },
	}
	var result := SaveMigrationService.migrate(data)
	assert_eq(result["inventory"]["p1"]["iron_ore"]["quantity"], 9, "Aktuelle Version darf unverändert bleiben")

# ─────────────────────────────────────────────
# Edge Cases
# ─────────────────────────────────────────────

func test_missing_quest_block_no_crash() -> void:
	# v1-Save ohne quest_progress → keine Exception
	var data := { "schema_version": 1, "inventory": {} }
	var result := SaveMigrationService.migrate(data)
	assert_eq(result["schema_version"], CURRENT, "Migration trotzdem abgeschlossen")

func test_corrupt_active_quest_entry_replaced() -> void:
	# Einzelner Quest-Eintrag ist kein Dictionary → soll mit Defaults ersetzt werden
	var data := {
		"schema_version": 1,
		"quest_progress": {
			"active": {
				"quest_broken": "not_a_dict"
			}
		}
	}
	var result := SaveMigrationService.migrate(data)
	var entry: Variant = result["quest_progress"]["active"]["quest_broken"]
	assert_true(entry is Dictionary, "Kaputtes Entry muss als Dictionary ersetzt werden")
	assert_eq((entry as Dictionary).get("status"), "started")

func test_downgrade_returns_data_unchanged() -> void:
	# Save-Version ist höher als Software → warnen aber nicht crashen
	var future_version := CURRENT + 5
	var data := { "schema_version": future_version, "custom_field": "xyz" }
	var result := SaveMigrationService.migrate(data)
	assert_eq(result["schema_version"], future_version, "Downgrade: Version bleibt wie sie ist")
	assert_eq(result.get("custom_field"), "xyz",        "Downgrade: Daten bleiben erhalten")

# ─────────────────────────────────────────────
# R14: Downgrade-Flag
# ─────────────────────────────────────────────

func test_downgrade_sets_detected_flag() -> void:
	# Reset sicherstellen
	SaveMigrationService.consume_downgrade_flag()

	var future_version := CURRENT + 1
	var data := { "schema_version": future_version }
	SaveMigrationService.migrate(data)

	assert_true(SaveMigrationService.downgrade_detected,
		"downgrade_detected muss nach Downgrade-Erkennung true sein.")
	# Cleanup
	SaveMigrationService.consume_downgrade_flag()

func test_no_downgrade_flag_for_current_version() -> void:
	SaveMigrationService.consume_downgrade_flag()
	SaveMigrationService.migrate({ "schema_version": CURRENT })
	assert_false(SaveMigrationService.downgrade_detected,
		"Kein Downgrade für aktuelle Version — Flag muss false bleiben.")

func test_no_downgrade_flag_for_upward_migration() -> void:
	SaveMigrationService.consume_downgrade_flag()
	SaveMigrationService.migrate({ "schema_version": 0 })
	assert_false(SaveMigrationService.downgrade_detected,
		"Aufwärts-Migration ist kein Downgrade — Flag muss false bleiben.")

func test_consume_downgrade_flag_returns_true_and_resets() -> void:
	SaveMigrationService.consume_downgrade_flag()  # Reset
	SaveMigrationService.migrate({ "schema_version": CURRENT + 1 })

	var first := SaveMigrationService.consume_downgrade_flag()
	var second := SaveMigrationService.consume_downgrade_flag()

	assert_true(first,   "Erstes consume_downgrade_flag() muss true zurückgeben.")
	assert_false(second, "Zweites consume_downgrade_flag() muss false zurückgeben (Flag verbraucht).")

func test_consume_downgrade_flag_is_false_when_not_triggered() -> void:
	SaveMigrationService.consume_downgrade_flag()  # Reset
	var flag := SaveMigrationService.consume_downgrade_flag()
	assert_false(flag, "Ohne vorherigen Downgrade-Aufruf muss das Flag false sein.")

func test_downgrade_flag_for_large_version_jump() -> void:
	SaveMigrationService.consume_downgrade_flag()
	SaveMigrationService.migrate({ "schema_version": CURRENT + 99 })
	assert_true(SaveMigrationService.downgrade_detected,
		"Auch ein großer Versions-Sprung muss das Flag setzen.")
	SaveMigrationService.consume_downgrade_flag()

func test_downgrade_flag_not_set_for_version_1_below_current() -> void:
	# Version direkt unter CURRENT ist eine normale Aufwärts-Migration
	SaveMigrationService.consume_downgrade_flag()
	SaveMigrationService.migrate({ "schema_version": CURRENT - 1 })
	assert_false(SaveMigrationService.downgrade_detected,
		"Version CURRENT-1 ist keine Downgrade-Version — Flag muss false bleiben.")
	SaveMigrationService.consume_downgrade_flag()
