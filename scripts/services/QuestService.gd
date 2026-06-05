extends ServiceNode
class_name QuestService

## QuestService — Verwaltet den Fortschritt aller Quests.
## Abhängigkeiten (deps): ["data", "savesystem"]

const LOG_CAT := "Quest"
const SAVE_KEY := "quest_progress"

var _data_service: DataService
var _save_system: SaveSystem

var active_quests: Dictionary = {}
var completed_quests: Array[String] = []

# ─────────────────────────────────────────────
# Phase 4: Configure (Injection)
# ─────────────────────────────────────────────


func configure(deps: Dictionary) -> void:
	_data_service = deps.get("data") as DataService
	_save_system = deps.get("savesystem") as SaveSystem

	if _save_system:
		_save_system.register_save_provider(self)
		var saved = _save_system.get_state_for(SAVE_KEY)
		if not saved.is_empty():
			_restore_from_save(saved)

	Logger.log_info("QuestService konfiguriert.", LOG_CAT)


# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────


func on_ready() -> void:
	# Früher: Services.inventory.inventory_changed.connect(...)
	# Das ist ein Anti-Pattern in on_ready() — Services.inventory könnte null sein,
	# und QuestService koppelt sich direkt an einen anderen Service statt an den Bus.
	# Jetzt: auf EventBus.world.loot_collected lauschen — gleiche Information,
	# aber entkoppelt. Quests können so auf Item-Picks reagieren ohne InventorySystem zu kennen.
	EventBus.world.loot_collected.connect(_on_loot_collected)
	EventBus.player.xp_gained.connect(_on_xp_gained)
	Logger.log_info("QuestService aktiv.", LOG_CAT)


# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────


func get_save_key() -> String:
	return SAVE_KEY


func get_save_data() -> Dictionary:
	return {"active": active_quests, "completed": completed_quests}


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func start_quest(quest_id: String) -> void:
	if completed_quests.has(quest_id) or active_quests.has(quest_id):
		return
	Logger.log_info("Quest gestartet: %s" % quest_id, LOG_CAT)
	active_quests[quest_id] = {"status": "started", "objectives": {}}
	EventBus.quest.quest_started.emit(quest_id)


func complete_quest(quest_id: String) -> void:
	if active_quests.has(quest_id):
		active_quests.erase(quest_id)
		completed_quests.append(quest_id)
		Logger.log_info("Quest abgeschlossen: %s" % quest_id, LOG_CAT)
		# Fix: Signal erwartet (quest_id, reward) — null als leeren Reward übergeben
		EventBus.quest.quest_completed.emit(quest_id, null)


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _on_loot_collected(item_id: String, quantity: int) -> void:
	Logger.log_trace("Loot aufgenommen: %dx '%s' — prüfe Quest-Ziele" % [quantity, item_id], {}, LOG_CAT)
	## [STUB] Quest-Ziel-Fortschritt für Item-Sammlung hier implementieren.
	## Beispiel: _check_collection_objectives(item_id, quantity)


func _on_xp_gained(skill_name: String, _amount: int) -> void:
	Logger.log_trace("XP gewonnen: '%s' — prüfe Quest-Ziele" % skill_name, {}, LOG_CAT)
	## [STUB] Quest-Ziel-Fortschritt für Skill-Nutzung hier implementieren.
	## Beispiel: _check_skill_objectives(skill_name)


func _restore_from_save(saved_data: Dictionary) -> void:
	active_quests = saved_data.get("active", {})
	completed_quests = saved_data.get("completed", [])
