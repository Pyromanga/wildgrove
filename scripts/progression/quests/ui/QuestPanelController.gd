class_name QuestPanelController
extends Node

var _visuals: QuestPanelVisuals
var _ctx: IUIContext

func setup(visuals: QuestPanelVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx     = ctx
	_ctx.bus().quest().quest_started.connect(_on_quest_started)
	_ctx.bus().quest().quest_completed.connect(_on_quest_completed)
	_ctx.bus().quest().quest_objective_updated.connect(_on_objective_updated)
	_refresh_active_quests()

func _refresh_active_quests() -> void:
	var qs := _ctx.get_quest()
	if not is_instance_valid(qs):
		return
	var player_id := _ctx.get_local_player_id()
	for quest_id in qs.get_active_quests(player_id):
		_show_quest(quest_id)
	# Bereits abgeschlossene Quests (z.B. nach Save/Reload) müssen ebenfalls im
	# Quest-Log erscheinen — sonst wirkt das Log nach dem Laden "leer", obwohl
	# der Fortschritt korrekt persistiert wurde (nur die UI-Wiederherstellung fehlte).
	for quest_id in qs.get_completed_quests(player_id):
		var def: QuestDefinition = qs.get_quest_definition(quest_id)
		_visuals.add_completed(quest_id, def.title if def else quest_id)

func _show_quest(quest_id: String) -> void:
	var qs := _ctx.get_quest()
	if not is_instance_valid(qs):
		return
	if not qs.get_active_quests(_ctx.get_local_player_id()).has(quest_id):
		return
	var def: QuestDefinition = qs.get_quest_definition(quest_id)
	_visuals.show_quest(quest_id, def.title if def else quest_id, _build_obj_data(quest_id, def))

## BUGFIX ("Questschritte werden alle sofort angezeigt obwohl der Schritt
## nicht erreicht ist"): vorher wurden hier UNCONDITIONAL alle def.objectives
## in die UI gereicht — ein Spieler sah also z.B. bei
## quest_talia_investigation sofort "TALK Talia", obwohl er den vorherigen
## Schritt "CUSTOM caught_fox" noch gar nicht erreicht hatte. Jetzt werden
## gesperrte zukünftige Schritte (siehe QuestObjectiveHandler.
## is_objective_unlocked(), dieselbe Logik die auch das Fortschreiten selbst
## gated) aus der Anzeige herausgefiltert, statt nur den Fortschrittsbalken
## bei 0 zu lassen — der Spieler soll einen noch nicht erreichten Schritt
## gar nicht erst sehen.
func _build_obj_data(quest_id: String, def: QuestDefinition) -> Array[Dictionary]:
	if not def:
		return []
	var qs := _ctx.get_quest()
	if not is_instance_valid(qs):
		return []
	var player_id := _ctx.get_local_player_id()
	var record: QuestProgressRecord = qs.get_quest_record(quest_id, player_id)
	var result: Array[Dictionary] = []
	for i in range(def.objectives.size()):
		var obj: QuestObjective = def.objectives[i]
		if not QuestObjectiveHandler.is_objective_unlocked(def, record, i):
			break
		result.append({
			"label":    obj.label,
			"current":  qs.get_objective_progress(quest_id, obj.id, player_id),
			"required": obj.required,
		})
	return result

func _on_quest_started(quest_id: String) -> void:
	_show_quest(quest_id)
	# Quest-Panel automatisch einblenden wenn eine neue Quest startet,
	# damit der Spieler das Quest-Log nicht manuell öffnen muss.
	_visuals.panel.visible = true

func _on_quest_completed(quest_id: String, _reward: QuestReward) -> void:
	var qs  := _ctx.get_quest()
	var def := qs.get_quest_definition(quest_id) if is_instance_valid(qs) else null
	_visuals.remove_quest(quest_id)
	_visuals.add_completed(quest_id, def.title if def else quest_id)

func _on_objective_updated(quest_id: String, _obj_id: String, _cur: int, _req: int) -> void:
	_show_quest(quest_id)
