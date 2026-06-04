class_name QuestEvents
extends BaseEvents

## QuestEvents — EventBus-Namespace für alle Quest-Signale.
##
## Einbinden in EventBus.gd:
##   var quest: QuestEvents
##   # in _ready():
##   quest = QuestEvents.new()
##
## Verwendung:
##   EventBus.quest.quest_started.connect(_on_quest_started)
##   EventBus.quest.emit_quest_completed("quest_tutorial")

signal quest_started(quest_id: String)
signal quest_objective_updated(quest_id: String, objective_id: String, current: int, required: int)
signal quest_completed(quest_id: String, reward: QuestReward)
signal quest_failed(quest_id: String)
signal quest_unlocked(quest_id: String)


func _init() -> void:
	super._init("Events/Quest")


func emit_quest_started(quest_id: String) -> void:
	_log_info("Quest gestartet: '%s'" % quest_id)
	quest_started.emit(quest_id)


func emit_objective_updated(
	quest_id: String, objective_id: String, current: int, required: int
) -> void:
	_log("Objective '%s/%s': %d/%d" % [quest_id, objective_id, current, required])
	quest_objective_updated.emit(quest_id, objective_id, current, required)


func emit_quest_completed(quest_id: String, reward: QuestReward) -> void:
	_log_info("Quest abgeschlossen: '%s'" % quest_id)
	quest_completed.emit(quest_id, reward)


func emit_quest_failed(quest_id: String) -> void:
	_log_warn("Quest fehlgeschlagen: '%s'" % quest_id)
	quest_failed.emit(quest_id)


func emit_quest_unlocked(quest_id: String) -> void:
	_log_info("Quest freigeschalten: '%s'" % quest_id)
	quest_unlocked.emit(quest_id)
