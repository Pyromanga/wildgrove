# res://tests/unit/test_quest_objective.gd
extends GutTest

## Tests für QuestObjectiveHandler — pure static functions, kein SceneTree nötig.
##
## Abgedeckte Pfade:
##   resolve_loot:        COLLECT-Match, falsches Item, kein aktiver Quest
##   resolve_interaction: INTERACT-Match, falsche action_id
##   is_completable:      alle erfüllt, ein non-optional fehlt, nur optional fehlt
##   QuestProgressRecord: create_new, update_progress (positiv/negativ/clamp), to_save_dict

# ─────────────────────────────────────────────
# Helper — minimale QuestDefinition + Objectives ohne Resource-Editor
# ─────────────────────────────────────────────

func _make_objective(id: String, type: QuestObjective.Type, target_id: String, required: int = 1, optional: bool = false) -> QuestObjective:
	var obj := QuestObjective.new()
	obj.id        = id
	obj.type      = type
	obj.target_id = target_id
	obj.required  = required
	obj.optional  = optional
	return obj

func _make_definition(quest_id: String, objectives: Array[QuestObjective]) -> QuestDefinition:
	var def := QuestDefinition.new()
	def.id         = quest_id
	def.objectives = objectives
	return def

# ─────────────────────────────────────────────
# resolve_loot
# ─────────────────────────────────────────────

func test_resolve_loot_match() -> void:
	var obj := _make_objective("chop_5", QuestObjective.Type.COLLECT, "log_oak", 5)
	var def := _make_definition("quest_wood_01", [obj] as Array[QuestObjective])

	var active := { "quest_wood_01": {} }
	var defs   := { "quest_wood_01": def }

	var updates := QuestObjectiveHandler.resolve_loot("log_oak", 3, active, defs)

	assert_eq(updates.size(), 1,                   "Genau ein Update erwartet")
	assert_eq(updates[0]["quest_id"], "quest_wood_01")
	assert_eq(updates[0]["obj_id"],   "chop_5")
	assert_eq(updates[0]["delta"],    3)

func test_resolve_loot_wrong_item() -> void:
	var obj := _make_objective("chop_5", QuestObjective.Type.COLLECT, "log_oak", 5)
	var def := _make_definition("quest_wood_01", [obj] as Array[QuestObjective])

	var active := { "quest_wood_01": {} }
	var defs   := { "quest_wood_01": def }

	var updates := QuestObjectiveHandler.resolve_loot("iron_ore", 1, active, defs)
	assert_eq(updates.size(), 0, "Kein Match bei falschem Item")

func test_resolve_loot_no_active_quests() -> void:
	var updates := QuestObjectiveHandler.resolve_loot("log_oak", 1, {}, {})
	assert_eq(updates.size(), 0, "Leere active_quests → keine Updates")

func test_resolve_loot_multiple_quests_one_match() -> void:
	var obj1 := _make_objective("chop_5",   QuestObjective.Type.COLLECT, "log_oak",  5)
	var obj2 := _make_objective("mine_10",  QuestObjective.Type.COLLECT, "iron_ore", 10)
	var def1 := _make_definition("quest_wood",  [obj1] as Array[QuestObjective])
	var def2 := _make_definition("quest_mine",  [obj2] as Array[QuestObjective])

	var active := { "quest_wood": {}, "quest_mine": {} }
	var defs   := { "quest_wood": def1, "quest_mine": def2 }

	var updates := QuestObjectiveHandler.resolve_loot("log_oak", 2, active, defs)
	assert_eq(updates.size(), 1, "Nur quest_wood matcht")
	assert_eq(updates[0]["quest_id"], "quest_wood")

# ─────────────────────────────────────────────
# resolve_interaction
# ─────────────────────────────────────────────

func test_resolve_interaction_match() -> void:
	var obj := _make_objective("talk_elder", QuestObjective.Type.INTERACT, "npc_elder")
	var def := _make_definition("quest_intro", [obj] as Array[QuestObjective])

	var active := { "quest_intro": {} }
	var defs   := { "quest_intro": def }

	var updates := QuestObjectiveHandler.resolve_interaction("npc_elder", active, defs)
	assert_eq(updates.size(), 1)
	assert_eq(updates[0]["obj_id"], "talk_elder")
	assert_eq(updates[0]["delta"],  1)

func test_resolve_interaction_wrong_action() -> void:
	var obj := _make_objective("talk_elder", QuestObjective.Type.INTERACT, "npc_elder")
	var def := _make_definition("quest_intro", [obj] as Array[QuestObjective])

	var active := { "quest_intro": {} }
	var defs   := { "quest_intro": def }

	var updates := QuestObjectiveHandler.resolve_interaction("npc_blacksmith", active, defs)
	assert_eq(updates.size(), 0, "Falsche action_id → kein Match")

# ─────────────────────────────────────────────
# is_completable
# ─────────────────────────────────────────────

func test_is_completable_all_done() -> void:
	var obj := _make_objective("chop_5", QuestObjective.Type.COLLECT, "log_oak", 5)
	var def := _make_definition("quest_wood_01", [obj] as Array[QuestObjective])

	var state := { "chop_5": 5 }
	assert_true(QuestObjectiveHandler.is_completable("quest_wood_01", state, def))

func test_is_completable_not_enough_progress() -> void:
	var obj := _make_objective("chop_5", QuestObjective.Type.COLLECT, "log_oak", 5)
	var def := _make_definition("quest_wood_01", [obj] as Array[QuestObjective])

	var state := { "chop_5": 3 }
	assert_false(QuestObjectiveHandler.is_completable("quest_wood_01", state, def))

func test_is_completable_optional_objective_missing_is_ok() -> void:
	var required_obj := _make_objective("chop_5", QuestObjective.Type.COLLECT, "log_oak",   5, false)
	var optional_obj := _make_objective("chop_10", QuestObjective.Type.COLLECT, "log_willow", 10, true)
	var def := _make_definition("quest_wood_01", [required_obj, optional_obj] as Array[QuestObjective])

	# optional_obj nicht erfüllt → Quest trotzdem completable
	var state := { "chop_5": 5, "chop_10": 0 }
	assert_true(QuestObjectiveHandler.is_completable("quest_wood_01", state, def))

# ─────────────────────────────────────────────
# QuestProgressRecord
# ─────────────────────────────────────────────

func test_create_new_initializes_objectives_to_zero() -> void:
	var obj1 := _make_objective("chop_5",  QuestObjective.Type.COLLECT, "log_oak",  5)
	var obj2 := _make_objective("mine_3",  QuestObjective.Type.COLLECT, "iron_ore", 3)
	var def  := _make_definition("quest_combo", [obj1, obj2] as Array[QuestObjective])

	var rec := QuestProgressRecord.create_new(def)
	assert_eq(rec.quest_id, "quest_combo")
	assert_eq(rec.status,   "started")
	assert_eq(rec.objectives["chop_5"],  0, "chop_5 startet bei 0")
	assert_eq(rec.objectives["mine_3"],  0, "mine_3 startet bei 0")

func test_update_progress_clamps_at_required() -> void:
	var obj := _make_objective("chop_5", QuestObjective.Type.COLLECT, "log_oak", 5)
	var def := _make_definition("quest_wood_01", [obj] as Array[QuestObjective])
	var rec := QuestProgressRecord.create_new(def)

	# Delta größer als required → auf required gedeckelt
	var result := rec.update_progress("chop_5", 100, 5)
	assert_eq(result, 5, "update_progress muss auf required=5 decken")
	assert_eq(rec.objectives["chop_5"], 5)

func test_update_progress_rejects_negative_delta() -> void:
	var obj := _make_objective("chop_5", QuestObjective.Type.COLLECT, "log_oak", 5)
	var def := _make_definition("quest_wood_01", [obj] as Array[QuestObjective])
	var rec := QuestProgressRecord.create_new(def)
	rec.objectives["chop_5"] = 3

	# Negatives delta wird abgelehnt — Wert bleibt bei 3
	var result := rec.update_progress("chop_5", -2, 5)
	assert_eq(result,                   3, "Rückgabewert nach negativem delta ist unveränderter Wert")
	assert_eq(rec.objectives["chop_5"], 3, "Interner Wert bleibt bei 3")

func test_update_progress_unknown_id_returns_zero() -> void:
	var obj := _make_objective("chop_5", QuestObjective.Type.COLLECT, "log_oak", 5)
	var def := _make_definition("quest_wood_01", [obj] as Array[QuestObjective])
	var rec := QuestProgressRecord.create_new(def)

	var result := rec.update_progress("nonexistent_obj", 1, 1)
	assert_eq(result, 0, "Unbekannte Objective-ID → 0 zurückgeben")

func test_to_save_dict_roundtrip() -> void:
	var obj := _make_objective("chop_5", QuestObjective.Type.COLLECT, "log_oak", 5)
	var def := _make_definition("quest_wood_01", [obj] as Array[QuestObjective])
	var rec := QuestProgressRecord.create_new(def)
	rec.update_progress("chop_5", 3, 5)

	var saved := rec.to_save_dict()
	assert_eq(saved["status"],               "started")
	assert_eq(saved["objectives"]["chop_5"], 3)
	assert_true(saved.has("level"),           "level muss serialisiert werden")
	assert_true(saved.has("started_at"),      "started_at muss serialisiert werden")
