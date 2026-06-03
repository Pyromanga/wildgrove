class_name QuestService
extends Service

## QuestService — Verwaltet den Fortschritt aller Quests.
##
## Zuständigkeit:
## - Hält die Liste der aktiven/abgeschlossenen Quests.
## - Prüft Objectives gegen EventBus-Signale.
## - Schaltet Belohnungen via EventBus frei.

var active_quests: Dictionary = {}
var completed_quests: Array[String] = []

func init() -> void:
	# Hier später: Abhängigkeiten via Services.data holen
	Logger.log_info("QuestService initialisiert.", _log_cat())

func on_ready() -> void:
	# Hier später: Signale vom EventBus connecten (z.B. Item gesammelt)
	Logger.log_info("QuestService bereit.", _log_cat())

func start_quest(quest_id: String) -> void:
	if completed_quests.has(quest_id): return
	# Logik folgt...
	EventBus.quest.emit_quest_started(quest_id)