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
## Round 106 (ADR-049): Gegenstück zu quest_started(quest_id) MIT player_id —
## quest_started selbst bleibt unverändert (QuestPanelController braucht das
## Feld nicht, siehe dortiger Kommentar), aber ein session-weiter Konsument
## wie WikiService kann ohne player_id keinem Spieler-Bucket zuordnen. Wird
## an derselben Stelle wie quest_started emittiert (on_quest_start_confirmed(),
## läuft nur auf der Autorität), kein zusätzlicher Trigger-Pfad.
signal quest_started_for_player(player_id: String, quest_id: String)
## Von Quest-Gebern (z.B. QuestNPC) gesendet um eine Quest zu starten.
## QuestService lauscht hierauf.
signal quest_start_requested(quest_id: String)
## Von QuestService gesendet wenn ein start_request fehlschlägt (Prereq, schon aktiv, etc.)
signal quest_start_failed(quest_id: String, reason: String)
signal quest_objective_updated(quest_id: String, objective_id: String, current: int, required: int)
signal quest_completed(quest_id: String, reward: QuestReward)
signal quest_failed(quest_id: String)
signal quest_unlocked(quest_id: String)
## Von RewardDispatcher gesendet wenn ein Quest-Reward ein Quest freischalten soll.
## QuestService lauscht hierauf statt direkt von RewardDispatcher aufgerufen zu werden.
signal quest_unlock_requested(quest_id: String)
## Für custom_signals in QuestReward — beliebige Quest-Ereignisse ohne eigenes Signal.
signal reward_custom_signal(signal_key: String)

## Von QuestNPC (oder anderen Dialog-Trägern) gesendet wenn ein Spieler mit einem
## NPC gesprochen hat. npc_id ist der EntityRegistry-Key oder eine feste NPC-ID.
## Trägt TALK-Quest-Objectives (vgl. QuestObjectiveHandler.resolve_talk()).
signal npc_talked_to(npc_id: String)

## Generischer Trigger für CUSTOM-Quest-Objectives. signal_key ist frei definiert
## vom jeweiligen Gameplay-System (z.B. "found_secret_cave", "defeated_boss_x").
## Jedes System das ein CUSTOM-Objective erfüllen will emittiert dieses Signal
## mit seinem eigenen Key. Trägt CUSTOM-Quest-Objectives
## (vgl. QuestObjectiveHandler.resolve_custom()).
signal custom_objective_triggered(signal_key: String)

func _init() -> void:
	super._init("Events/Quest")

func emit_quest_start_failed(quest_id: String, reason: String) -> void:
	_log_warn("Quest-Start fehlgeschlagen '%s': %s" % [quest_id, reason])
	quest_start_failed.emit(quest_id, reason)

func emit_quest_start_requested(quest_id: String) -> void:
	_log("Quest-Start angefordert: '%s'" % quest_id)
	quest_start_requested.emit(quest_id)

func emit_quest_started(quest_id: String) -> void:
	_log_info("Quest gestartet: '%s'" % quest_id)
	quest_started.emit(quest_id)

func emit_quest_started_for_player(player_id: String, quest_id: String) -> void:
	quest_started_for_player.emit(player_id, quest_id)

func emit_quest_objective_updated(
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

func emit_quest_unlock_requested(quest_id: String) -> void:
	_log("Quest-Unlock angefordert (von RewardDispatcher): '%s'" % quest_id)
	quest_unlock_requested.emit(quest_id)

func emit_reward_custom_signal(signal_key: String) -> void:
	_log("Custom-Reward-Signal: '%s'" % signal_key)
	reward_custom_signal.emit(signal_key)

func emit_npc_talked_to(npc_id: String) -> void:
	_log("NPC angesprochen: '%s'" % npc_id)
	npc_talked_to.emit(npc_id)

func emit_custom_objective_triggered(signal_key: String) -> void:
	_log("Custom-Objective getriggert: '%s'" % signal_key)
	custom_objective_triggered.emit(signal_key)
