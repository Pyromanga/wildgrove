# res://scripts/progression/quests/QuestProgressRecord.gd
class_name QuestProgressRecord extends RefCounted

## QuestProgressRecord — Typisierter Quest-Fortschritts-Container.
##
## im QuestService durch eine validierte Struktur.
##
## SICHERHEITS-GARANTIEN:
##   - objectives[id] ist immer im Bereich [0, required_amount]
##   - Unbekannte Objective-IDs aus alten Saves werden verworfen (nicht übernommen)
##   - Fehlende Objective-IDs aus der aktuellen Definition werden mit 0 initialisiert
##   - Negative Deltas sind blockiert — kein Exploit durch negative Fortschritte
##   - started_at ist ein Unix-Timestamp für Server-seitige Timeout-Checks

const LOG_CAT := "QuestProgress"

var quest_id:   String = ""
var status:     String = "started"   # "started" | "completed"
var level:      int    = 1
var started_at: int    = 0           # Unix-Timestamp (Time.get_unix_time_from_system())

## { objective_id: current_progress }  — immer im Bereich [0, required]
var objectives: Dictionary = {}

## Erstellt einen neuen Record für eine frisch gestartete Quest.
## Alle Objectives werden mit 0 initialisiert.
static func create_new(definition: QuestDefinition) -> QuestProgressRecord:
	var rec := QuestProgressRecord.new()
	rec.quest_id   = definition.id
	rec.status     = "started"
	rec.level      = 1
	rec.started_at = int(Time.get_unix_time_from_system())
	for obj in definition.objectives:
		rec.objectives[obj.id] = 0
	return rec

## Erstellt einen Record aus Save-Daten, validiert gegen die aktuelle Definition.
## Unbekannte IDs → verworfen + Warning
## Fehlende IDs  → mit 0 initialisiert
## Über-Clamping → auf [0, required] begrenzt
static func from_save(quest_id: String, saved: Dictionary, definition: QuestDefinition) -> QuestProgressRecord:
	var rec := QuestProgressRecord.new()
	rec.quest_id   = quest_id
	rec.status     = saved.get("status",     "started")
	rec.level      = saved.get("level",      1)
	rec.started_at = saved.get("started_at", 0)

	var saved_objectives: Variant = saved.get("objectives", {})
	if not saved_objectives is Dictionary:
		saved_objectives = {}
	var saved_obj := saved_objectives as Dictionary

	# Alle Objectives aus der aktuellen Definition prüfen
	for obj in definition.objectives:
		if saved_obj.has(obj.id):
			var raw: Variant = saved_obj[obj.id]
			var progress: int = int(raw) if raw is int or raw is float else 0
			# Clamp auf [0, required] — Exploit-Prevention + Versions-Inkonsistenz-Fix
			rec.objectives[obj.id] = clamp(progress, 0, obj.required)
		else:
			# Neues Objective in dieser Definition-Version — mit 0 initialisieren
			AppLogger.log_debug(
				"Quest '%s': Neues Objective '%s' initialisiert mit 0." % [quest_id, obj.id],
				LOG_CAT
			)
			rec.objectives[obj.id] = 0

	# Veraltete Objective-IDs aus dem Save verwerfen (ohne Absturz)
	for saved_id in saved_obj.keys():
		var known := false
		for obj in definition.objectives:
			if obj.id == saved_id:
				known = true
				break
		if not known:
			AppLogger.log_warn(
				"Quest '%s': Objective '%s' nicht in Definition — verworfen." % [quest_id, saved_id],
				LOG_CAT
			)

	return rec

## Aktualisiert den Fortschritt eines Objectives.
## delta MUSS positiv sein — negativer Fortschritt ist kein unterstütztes Konzept.
## Gibt den neuen Wert zurück (nach Clamping).
## required: max. erlaubter Wert aus QuestDefinition.
func update_progress(objective_id: String, delta: int, required: int) -> int:
	if delta < 0:
		AppLogger.log_warn(
			"Quest '%s': Negatives delta (%d) für '%s' abgelehnt." % [quest_id, delta, objective_id],
			LOG_CAT
		)
		return objectives.get(objective_id, 0)

	if not objectives.has(objective_id):
		AppLogger.log_warn(
			"Quest '%s': Unbekannte Objective-ID '%s'." % [quest_id, objective_id],
			LOG_CAT
		)
		return 0

	var current: int    = objectives[objective_id]
	var clamped: int    = clamp(current + delta, 0, required)
	objectives[objective_id] = clamped
	return clamped

## Serialisiert für den Save-Block.
func to_save_dict() -> Dictionary:
	return {
		"status":     status,
		"level":      level,
		"started_at": started_at,
		"objectives": objectives.duplicate(),
	}

## Gibt true zurück wenn alle Objectives die required-Schwelle erreicht haben.
func is_complete(definition: QuestDefinition) -> bool:
	for obj in definition.objectives:
		if objectives.get(obj.id, 0) < obj.required:
			return false
	return true
