extends ServiceNode
class_name QuestService

## QuestService — Verwaltet den Fortschritt aller Quests.
##
## Abhängigkeiten (deps): ["data", "savesystem"]
##
## REFACTOR (Session 4):
##   Quest-Definitionen kommen jetzt von DataService.get_all_quests() —
##   kein eigener DirAccess-Scan mehr. DataService ist der einzige Ladeort
##   für statische Ressourcen.
##
## ARCHITEKTUR:
##   - QuestService hält KEINE Referenz auf InventorySystem oder SkillSystem
##   - Lauscht auf EventBus.world.loot_collected und EventBus.player.xp_gained
##   - Reward-Auszahlung über RewardDispatcher (neu in Session 4)

const LOG_CAT  := "Quest"
const SAVE_KEY := "quest_progress"

var _data_service: DataService
var _save_system:  SaveSystem

## Quest-Definitionen: { quest_id: QuestDefinition } — von DataService
var _definitions: Dictionary = {}

## Aktive Quests: { quest_id: { "status": "started", "objectives": { obj_id: current } } }
var active_quests: Dictionary = {}
## Abgeschlossene Quest-IDs
var completed_quests: Array[String] = []
## Freigeschaltete aber noch nicht gestartete Quests
var available_quests: Array[String] = []


# ─────────────────────────────────────────────
# Phase 4: Configure (Injection)
# ─────────────────────────────────────────────


func configure(deps: Dictionary) -> void:
	var t := Logger.log_begin("QuestService.configure()", LOG_CAT)

	_data_service = deps.get("data") as DataService
	_save_system  = deps.get("savesystem") as SaveSystem

	if not is_instance_valid(_data_service):
		Logger.log_warn("DataService fehlt — Quest-Definitionen nicht geladen.", LOG_CAT)
	else:
		_definitions = _data_service.get_all_quests()
		Logger.log_debug("Quest-Definitionen geladen: %d" % _definitions.size(), LOG_CAT)

	if not is_instance_valid(_save_system):
		Logger.log_warn("SaveSystem fehlt — Quest-Fortschritt nicht gespeichert.", LOG_CAT)
	else:
		_save_system.register_save_provider(self)
		var saved: Dictionary = _save_system.get_state_for(SAVE_KEY)
		if not saved.is_empty():
			_restore_from_save(saved)

	Logger.log_end("QuestService.configure()", t, LOG_CAT)
	Logger.log_info(
		"Konfiguriert. Definitionen: %d, Aktiv: %d, Abgeschlossen: %d."
		% [_definitions.size(), active_quests.size(), completed_quests.size()],
		LOG_CAT
	)


# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────


func on_ready() -> void:
	EventBus.world.loot_collected.connect(_on_loot_collected)
	EventBus.player.xp_gained.connect(_on_xp_gained)
	EventBus.world.interaction_finished.connect(_on_interaction_finished)

	# Auto-start Quests (ohne Prerequisites) direkt bei Spielstart aktivieren
	if is_instance_valid(_data_service):
		for quest_id in _data_service.get_auto_start_quests():
			if not completed_quests.has(quest_id) and not active_quests.has(quest_id):
				start_quest(quest_id)

	Logger.log_info("QuestService aktiv. EventBus-Connections aufgebaut.", LOG_CAT)


# ─────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────


func get_save_key() -> String:
	return SAVE_KEY


func get_save_data() -> Dictionary:
	return {
		"active":    active_quests.duplicate(true),
		"completed": completed_quests.duplicate(),
		"available": available_quests.duplicate(),
	}


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func start_quest(quest_id: String) -> bool:
	if quest_id.is_empty():
		Logger.log_error("start_quest(): quest_id ist leer!", LOG_CAT)
		return false

	if completed_quests.has(quest_id):
		Logger.log_debug("Quest '%s' bereits abgeschlossen." % quest_id, LOG_CAT)
		return false

	if active_quests.has(quest_id):
		Logger.log_debug("Quest '%s' ist bereits aktiv." % quest_id, LOG_CAT)
		return false

	# Prerequisites prüfen
	var def: QuestDefinition = _definitions.get(quest_id)
	if def:
		for prereq in def.prerequisites:
			if not completed_quests.has(prereq):
				Logger.log_debug(
					"Quest '%s': Prerequisite '%s' nicht erfüllt." % [quest_id, prereq], LOG_CAT
				)
				return false

	# Objective-Startstand initialisieren
	var objectives: Dictionary = {}
	if def:
		for obj in def.objectives:
			objectives[obj.id] = 0

	active_quests[quest_id] = {"status": "started", "objectives": objectives}
	available_quests.erase(quest_id)

	EventBus.quest.emit_quest_started(quest_id)
	Logger.log_info("Quest gestartet: '%s'." % quest_id, LOG_CAT)
	return true


func complete_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		Logger.log_warn("complete_quest('%s'): Quest nicht aktiv." % quest_id, LOG_CAT)
		return

	active_quests.erase(quest_id)
	completed_quests.append(quest_id)

	# Reward über RewardDispatcher auszahlen wenn vorhanden
	var def: QuestDefinition = _definitions.get(quest_id)
	var reward: QuestReward   = def.reward if (def and def.reward) else null

	if reward and is_instance_valid(Services.reward_dispatcher):
		Services.reward_dispatcher.dispatch(reward)
	elif reward:
		Logger.log_warn("RewardDispatcher fehlt — Reward für '%s' nicht ausgezahlt!" % quest_id, LOG_CAT)

	EventBus.quest.emit_quest_completed(quest_id, reward)
	Logger.log_info("Quest abgeschlossen: '%s'." % quest_id, LOG_CAT)

	# Nachfolge-Quests freischalten
	_unlock_followup_quests(quest_id)


func fail_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		Logger.log_warn("fail_quest('%s'): Quest nicht aktiv." % quest_id, LOG_CAT)
		return
	active_quests.erase(quest_id)
	EventBus.quest.emit_quest_failed(quest_id)
	Logger.log_warn("Quest fehlgeschlagen: '%s'." % quest_id, LOG_CAT)


func unlock_quest(quest_id: String) -> void:
	if completed_quests.has(quest_id) or active_quests.has(quest_id):
		return
	if not available_quests.has(quest_id):
		available_quests.append(quest_id)
		EventBus.quest.emit_quest_unlocked(quest_id)
		Logger.log_info("Quest freigeschaltet: '%s'." % quest_id, LOG_CAT)


func update_objective(quest_id: String, objective_id: String, delta: int) -> void:
	if not active_quests.has(quest_id):
		return

	var objectives: Dictionary = active_quests[quest_id]["objectives"]
	var current: int           = objectives.get(objective_id, 0)
	objectives[objective_id]   = current + delta

	Logger.log_debug(
		"Objective '%s/%s': %d (+%d)." % [quest_id, objective_id, objectives[objective_id], delta],
		LOG_CAT
	)

	# Abschluss-Check: Prüfen ob alle Objectives der Definition erfüllt sind
	var def: QuestDefinition = _definitions.get(quest_id)
	if def:
		_check_quest_completion(quest_id, def)


func is_quest_active(quest_id: String)    -> bool: return active_quests.has(quest_id)
func is_quest_completed(quest_id: String) -> bool: return completed_quests.has(quest_id)

func get_objective_progress(quest_id: String, objective_id: String) -> int:
	if not active_quests.has(quest_id):
		return 0
	return active_quests[quest_id]["objectives"].get(objective_id, 0)


# ─────────────────────────────────────────────
# Event-Handler (für Objective-Fortschritt)
# ─────────────────────────────────────────────


func _on_loot_collected(item_id: String, quantity: int) -> void:
	Logger.log_trace("Loot: %dx '%s' — prüfe COLLECT-Objectives." % [quantity, item_id], {}, LOG_CAT)
	for quest_id in active_quests.keys():
		var def: QuestDefinition = _definitions.get(quest_id)
		if not def:
			continue
		for obj in def.objectives:
			if obj.type == QuestObjective.Type.COLLECT and obj.target_id == item_id:
				update_objective(quest_id, obj.id, quantity)


func _on_xp_gained(skill_name: String, amount: int) -> void:
	Logger.log_trace("XP: +%d in '%s' — prüfe SKILL-Objectives." % [amount, skill_name], {}, LOG_CAT)
	for quest_id in active_quests.keys():
		var def: QuestDefinition = _definitions.get(quest_id)
		if not def:
			continue
		for obj in def.objectives:
			if obj.type == QuestObjective.Type.SKILL and obj.target_id == skill_name:
				# SKILL-Objectives tracken absoluten Level, nicht XP-Delta
				var req_level: int = obj.required_amount
				if is_instance_valid(Services.skill_system):
					var cur_level: int = Services.skill_system.get_level(skill_name)
					if cur_level >= req_level:
						update_objective(quest_id, obj.id, 1)


func _on_interaction_finished(action_id: String, _label: String) -> void:
	Logger.log_trace("Interaktion beendet: '%s' — prüfe INTERACT-Objectives." % action_id, {}, LOG_CAT)
	for quest_id in active_quests.keys():
		var def: QuestDefinition = _definitions.get(quest_id)
		if not def:
			continue
		for obj in def.objectives:
			if obj.type == QuestObjective.Type.INTERACT and obj.target_id == action_id:
				update_objective(quest_id, obj.id, 1)


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


## Prüft ob alle Pflicht-Objectives einer Quest erfüllt sind und schließt sie ab.
func _check_quest_completion(quest_id: String, def: QuestDefinition) -> void:
	var objectives_state: Dictionary = active_quests[quest_id]["objectives"]

	for obj in def.objectives:
		if obj.optional:
			continue
		var progress: int = objectives_state.get(obj.id, 0)
		if progress < obj.required_amount:
			return  # Noch nicht fertig

	# Alle Pflicht-Objectives erfüllt
	complete_quest(quest_id)


## Schaltet Quests frei deren Prerequisites jetzt erfüllt sind.
func _unlock_followup_quests(completed_id: String) -> void:
	for quest_id in _definitions:
		var def: QuestDefinition = _definitions[quest_id]
		if completed_quests.has(quest_id) or active_quests.has(quest_id):
			continue
		if not def.prerequisites.has(completed_id):
			continue
		# Alle Prerequisites dieser Quest prüfen
		var all_met := true
		for prereq in def.prerequisites:
			if not completed_quests.has(prereq):
				all_met = false
				break
		if all_met:
			unlock_quest(quest_id)
			if def.auto_start:
				start_quest(quest_id)


func _restore_from_save(saved_data: Dictionary) -> void:
	active_quests    = saved_data.get("active",    {})
	completed_quests = saved_data.get("completed", [])
	available_quests = saved_data.get("available", [])
	Logger.log_info(
		"Quest-State geladen: aktiv=%d, abgeschlossen=%d, verfügbar=%d."
		% [active_quests.size(), completed_quests.size(), available_quests.size()],
		LOG_CAT
	)
