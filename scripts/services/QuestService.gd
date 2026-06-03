extends ServiceNode
class_name QuestService

## QuestService — Verwaltet den Fortschritt aller Quests.
## Abhängigkeiten (deps): ["data", "savesystem"]

const LOG_CAT := "Quest"
const SAVE_KEY := "quest_progress"

# Lokale Referenzen via DI
var _data_service: DataService
var _save_system:  SaveSystem

var active_quests: Dictionary = {} # { "quest_id": QuestProgressObject }
var completed_quests: Array[String] = []

# ─────────────────────────────────────────────
# Phase 4: Configure (Injection)
# ─────────────────────────────────────────────

func configure(deps: Dictionary) -> void:
	_data_service = deps.get("data") as DataService
	_save_system = deps.get("savesystem") as SaveSystem

	if _save_system:
		_save_system.register_save_provider(self)
		
		# Fortschritt aus dem Cache laden
		var saved = _save_system.get_state_for(SAVE_KEY)
		if not saved.is_empty():
			_restore_from_save(saved)
			
	Logger.log_info("QuestService konfiguriert.", LOG_CAT)

# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────

func on_ready() -> void:
	# Hier verbinden wir uns mit dem globalen EventBus
	# Beispiel: Wenn ein Item gesammelt wird, prüfen wir Quest-Ziele
	EventBus.inventory.item_added.connect(_on_item_collected)
	Logger.log_info("QuestService aktiv und lauscht auf Events.", LOG_CAT)

# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	return {
		"active": active_quests,
		"completed": completed_quests
	}

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func start_quest(quest_id: String) -> void:
	if completed_quests.has(quest_id) or active_quests.has(quest_id):
		return
		
	Logger.log_info("Quest gestartet: %s" % quest_id, LOG_CAT)
	# Hier würde man die Quest-Daten aus dem DataService holen
	active_quests[quest_id] = {"status": "started", "objectives": {}}
	
	EventBus.quest.quest_started.emit(quest_id)

func complete_quest(quest_id: String) -> void:
	if active_quests.has(quest_id):
		active_quests.erase(quest_id)
		completed_quests.append(quest_id)
		
		Logger.log_info("Quest abgeschlossen: %s" % quest_id, LOG_CAT)
		EventBus.quest.quest_completed.emit(quest_id)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _on_item_collected(item_id: String, _amount: int) -> void:
	# Logik zum Prüfen, ob dieses Item für eine aktive Quest gebraucht wird
	Logger.log_trace("Prüfe Quest-Ziele für Item: %s" % item_id, {"item_id": item_id}, LOG_CAT)

func _restore_from_save(data: Dictionary) -> void:
	active_quests = data.get("active", {})
	completed_quests = data.get("completed", [])