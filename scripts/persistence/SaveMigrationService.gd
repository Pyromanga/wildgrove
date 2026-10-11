# res://scripts/persistence/SaveMigrationService.gd
class_name SaveMigrationService extends RefCounted

## SaveMigrationService — Versionierte, verkettete Save-Migrationen.
##
## Beim Laden wird geprüft, ob Migrationen nötig sind, und diese
## der Reihe nach ausgeführt: v1 → v2 → v3 → ... → CURRENT_VERSION.
##
## VERWENDUNG (in SaveSystem._read_from_disk()):
##   var migrated := SaveMigrationService.migrate(raw_dict)
##
## MIGRATION HINZUFÜGEN:
##   1. CURRENT_VERSION um 1 erhöhen.
##   2. Neue Methode _migrate_vN_to_vN1(data) implementieren.
##   3. In _migration_steps[] registrieren.
##
## DESIGN:
##   - Jede Migration bekommt das gesamte Save-Dictionary
##     (nicht nur einen Sub-Block), da Migrationen auch Keys
##     umbenennen oder zwischen Blöcken verschieben können.
##   - Migrationen sind rein funktional: Input rein, Output raus, kein State.
##   - Ein fehlgeschlagener Parse-Wert wird mit Fallback behandelt — niemals crash.

const CURRENT_VERSION := 4
const LOG_CAT := "SaveMigration"

## Downgrade-Flag: true wenn beim letzten migrate()-Aufruf eine höhere Version
## als CURRENT_VERSION erkannt wurde. SaveSystem liest dieses Flag in begin_session()
## um ein Backup zu erstellen, bevor der nächste Save-Schreibzugriff die Datei
## mit dem älteren Schema überschreibt.
##
## DESIGN-ENTSCHEIDUNG: static var statt Signal — SaveMigrationService ist eine
## pure-static-Klasse (kein Objekt, kein AutoLoad). Das Flag ist zustandslos zwischen
## Aufrufen und wird von SaveSystem nach dem Lesen konsumiert (consume_downgrade_flag).
static var downgrade_detected: bool = false

## Konsumiert das Downgrade-Flag (lesen + zurücksetzen in einem Schritt).
## SaveSystem ruft das nach begin_session() auf.
static func consume_downgrade_flag() -> bool:
	var flag := downgrade_detected
	downgrade_detected = false
	return flag

## Einstiegspunkt — gibt ein migriertes Dictionary zurück.
## Ist data bereits auf CURRENT_VERSION, wird es unverändert zurückgegeben.
##
## DOWNGRADE-VERHALTEN (R14):
##   Wenn version > CURRENT_VERSION, wird downgrade_detected = true gesetzt.
##   SaveSystem liest das Flag und erstellt vor dem nächsten Schreibzugriff
##   ein versioniertes Backup (player_id.json.vN.bak), damit Nutzer auf die
##   neuere Software-Version zurückwechseln können ohne Datenverlust.
static func migrate(data: Dictionary) -> Dictionary:
	var version: int = data.get("schema_version", 0)

	if version == CURRENT_VERSION:
		return data

	if version > CURRENT_VERSION:
		AppLogger.log_warn(
			("Save-Version %d > Software-Version %d — Downgrade erkannt. " +
			"Backup wird vor dem nächsten Speichern erstellt.")
			% [version, CURRENT_VERSION],
			LOG_CAT
		)
		downgrade_detected = true
		return data

	AppLogger.log_info(
		"Migriere Save von v%d → v%d." % [version, CURRENT_VERSION],
		LOG_CAT
	)

	var migrated := data.duplicate(true)

	# Migrations-Kette: jede Stufe genau einmal ausführen
	if version < 1:
		migrated = _migrate_v0_to_v1(migrated)
		version = 1

	if version < 2:
		migrated = _migrate_v1_to_v2(migrated)
		version = 2

	if version < 3:
		migrated = _migrate_v2_to_v3(migrated)
		version = 3

	if version < 4:
		migrated = _migrate_v3_to_v4(migrated)
		version = 4

	migrated["schema_version"] = CURRENT_VERSION
	AppLogger.log_info("Migration abgeschlossen. Schema ist jetzt v%d." % CURRENT_VERSION, LOG_CAT)
	return migrated

# ─────────────────────────────────────────────
# Migrations-Implementierungen
# ─────────────────────────────────────────────

## v0 → v1: Ursprüngliches Format hatte kein schema_version-Feld.
## Kein Inhalt ändert sich — nur das Version-Tag wird gesetzt.
## Alle bestehenden Keys bleiben unberührt.
static func _migrate_v0_to_v1(data: Dictionary) -> Dictionary:
	AppLogger.log_debug("Migration v0→v1: schema_version hinzugefügt.", LOG_CAT)
	data["schema_version"] = 1
	# Quest-Format: active_quests war ein flaches Dictionary ohne typed records.
	# Wird in v2 validiert — hier nur tagging.
	return data

## v1 → v2: QuestService bekommt typed QuestProgressRecord-Format.
## Alte Struktur: { "quest_id": { "status": "started", "objectives": { "obj_id": int } } }
## Neue Struktur: { "quest_id": { "status": "started", "level": 1, "objectives": { "obj_id": int }, "started_at": 0 } }
static func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	AppLogger.log_debug("Migration v1→v2: QuestProgressRecord-Felder normalisiert.", LOG_CAT)

	var quest_block: Variant = data.get("quest_progress")
	if not quest_block is Dictionary:
		return data

	var qb := quest_block as Dictionary
	var active: Variant = qb.get("active")
	if not active is Dictionary:
		return data

	var active_dict := active as Dictionary
	for quest_id in active_dict.keys():
		var entry: Variant = active_dict[quest_id]
		if not entry is Dictionary:
			AppLogger.log_warn(
				"Migration v1→v2: Quest-Eintrag '%s' war kein Dictionary (korrupt?) — durch Default ersetzt." % quest_id,
				LOG_CAT
			)
			active_dict[quest_id] = {"status": "started", "level": 1, "objectives": {}, "started_at": 0}
			continue
		var e := entry as Dictionary
		# Fehlende Felder mit Defaults auffüllen
		if not e.has("level"):       e["level"]      = 1
		if not e.has("started_at"):  e["started_at"] = 0
		if not e.has("status"):      e["status"]     = "started"
		if not e.has("objectives"):  e["objectives"] = {}

	return data

## v2 → v3: EquipmentService becomes a SaveProvider.
## Old saves have no "equipment" key — insert an empty dict so EquipmentService
## receives a valid (empty) state instead of a missing-key lookup returning {}.
static func _migrate_v2_to_v3(data: Dictionary) -> Dictionary:
	AppLogger.log_debug("Migration v2→v3: \"equipment\" block hinzugefügt.", LOG_CAT)
	if not data.has("equipment"):
		data["equipment"] = {}
	return data

## v3 → v4 (ADR-035 Phase 1, Round 88): InventorySystem/BankService speichern
## Items jetzt als ItemInstance-Objekte (uuid/durability) statt roher int-Menge
## — siehe ItemInstance.gd Klassenkommentar. Altes Format:
##   "inventory": { player_id: { item_id: quantity(int) } }
##   "bank":      { "items": { player_id: { item_id: quantity(int) } }, "gold": {...} }
## Neues Format je item_id-Eintrag: { item_id, quantity, uuid, durability }.
## uuid wird hier einmalig lokal vergeben (kein Autoritäts-Constraint nötig —
## Migration läuft ausschließlich beim lokalen Save-Lesen, nie über das Netz).
static func _migrate_v3_to_v4(data: Dictionary) -> Dictionary:
	AppLogger.log_debug(
		"Migration v3→v4: Inventory/Bank-Items auf ItemInstance-Objekte (uuid/durability) umgestellt.",
		LOG_CAT
	)
	if data.get("inventory") is Dictionary:
		data["inventory"] = _migrate_item_qty_block(data["inventory"] as Dictionary)

	if data.get("bank") is Dictionary:
		var bank: Dictionary = data["bank"]
		if bank.get("items") is Dictionary:
			bank["items"] = _migrate_item_qty_block(bank["items"] as Dictionary)
		data["bank"] = bank

	return data

## Gemeinsamer Helfer für _migrate_v3_to_v4(): wandelt einen
## { player_id: { item_id: quantity(int) } }-Block in
## { player_id: { item_id: {item_id, quantity, uuid, durability} } } um.
## Einträge, die bereits im neuen Format sind (Dictionary statt int), werden
## unverändert übernommen — defensiv, sollte im v3-Datenbestand nicht vorkommen.
static func _migrate_item_qty_block(block: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for pid in block:
		var raw: Variant = block[pid]
		if not raw is Dictionary:
			out[pid] = raw
			continue
		var items := raw as Dictionary
		var migrated_items: Dictionary = {}
		for item_id in items:
			var value: Variant = items[item_id]
			if value is Dictionary:
				migrated_items[item_id] = value
			else:
				migrated_items[item_id] = {
					"item_id":    item_id,
					"quantity":   int(value),
					"durability": 100.0,
					"uuid":       UuidGen.generate_v4(),
				}
		out[pid] = migrated_items
	return out
