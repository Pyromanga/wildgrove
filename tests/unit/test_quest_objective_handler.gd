# res://tests/unit/test_quest_objective_handler.gd
extends GutTest

## Unit-Tests für QuestObjectiveHandler — statische Logik-Klasse, kein SceneTree.
##
## Vorher ungetestet (Coverage-Lücke). Deckt jetzt alle 6 resolve_*-Methoden ab,
## inklusive resolve_talk() und resolve_custom() (Runde 6 — vorher nur Enum-
## Einträge ohne Handler).
##
## Abgedeckt:
##   - resolve_loot():       COLLECT-Match, kein Match, falscher Typ, mehrere Quests
##   - resolve_xp():         SKILL-Match mit erreichtem Level, nicht erreichtem Level
##   - resolve_interaction(): INTERACT-Match
##   - resolve_kill():       KILL-Match
##   - resolve_talk():       TALK-Match (neu)
##   - resolve_custom():     CUSTOM-Match (neu)
##   - is_completable():     alle Pflicht-Objectives erfüllt, optional ignoriert

class MockSkillSystem extends SkillSystem:
	var _levels: Dictionary = {}
	## Optional: { player_id: { skill_name: level } } — wenn gesetzt, hat Vorrang
	## vor _levels (für Tests die player_id-Differenzierung prüfen wollen).
	var _levels_by_player: Dictionary = {}
	func get_level(skill_name: String, player_id: String = "1") -> int:
		if _levels_by_player.has(player_id):
			return (_levels_by_player[player_id] as Dictionary).get(skill_name, 0)
		return _levels.get(skill_name, 0)

func _make_def(quest_id: String, objs: Array[QuestObjective]) -> QuestDefinition:
	var d := QuestDefinition.new()
	d.id = quest_id
	d.objectives = objs
	return d

func _make_obj(id: String, type: QuestObjective.Type, target_id: String, required: int = 1, optional: bool = false) -> QuestObjective:
	var o := QuestObjective.new()
	o.id        = id
	o.type      = type
	o.target_id = target_id
	o.required  = required
	o.optional  = optional
	return o

# ─────────────────────────────────────────────────────────────────────────────
# resolve_loot()
# ─────────────────────────────────────────────────────────────────────────────

func test_resolve_loot_matches_collect_objective() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.COLLECT, "iron_ore", 5)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_loot("iron_ore", 2, active, defs)
	assert_eq(updates.size(), 1)
	assert_eq(updates[0]["quest_id"], "q1")
	assert_eq(updates[0]["obj_id"], "obj1")
	assert_eq(updates[0]["delta"], 2)

func test_resolve_loot_no_match_different_item() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.COLLECT, "iron_ore", 5)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_loot("copper_ore", 2, active, defs)
	assert_eq(updates.size(), 0, "Falsche item_id darf kein Update erzeugen")

func test_resolve_loot_no_match_wrong_type() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.KILL, "iron_ore", 5)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_loot("iron_ore", 1, active, defs)
	assert_eq(updates.size(), 0, "KILL-Objective darf nicht auf COLLECT-Event matchen")

func test_resolve_loot_ignores_inactive_quest() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.COLLECT, "iron_ore", 5)
	var defs := {"q1": _make_def("q1", [obj]), "q2": _make_def("q2", [])}
	var active := {"q1": null}  # nur q1 aktiv
	var updates := QuestObjectiveHandler.resolve_loot("iron_ore", 1, active, defs)
	assert_eq(updates.size(), 1, "Nur aktive Quests werden geprüft")

func test_resolve_loot_multiple_quests_both_match() -> void:
	var obj1 := _make_obj("o1", QuestObjective.Type.COLLECT, "log_normal", 3)
	var obj2 := _make_obj("o2", QuestObjective.Type.COLLECT, "log_normal", 5)
	var defs := {"q1": _make_def("q1", [obj1]), "q2": _make_def("q2", [obj2])}
	var active := {"q1": null, "q2": null}
	var updates := QuestObjectiveHandler.resolve_loot("log_normal", 1, active, defs)
	assert_eq(updates.size(), 2, "Beide aktiven Quests mit passendem Objective müssen ein Update erhalten")

# ─────────────────────────────────────────────────────────────────────────────
# resolve_xp()
# ─────────────────────────────────────────────────────────────────────────────

func test_resolve_xp_matches_when_level_reached() -> void:
	var skill := MockSkillSystem.new()
	skill._levels["woodcutting"] = 10
	var obj := _make_obj("obj1", QuestObjective.Type.SKILL, "woodcutting", 10)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_xp("woodcutting", active, defs, skill, "1")
	assert_eq(updates.size(), 1, "Level erreicht → Update muss erzeugt werden")

func test_resolve_xp_no_match_when_level_not_reached() -> void:
	var skill := MockSkillSystem.new()
	skill._levels["woodcutting"] = 5
	var obj := _make_obj("obj1", QuestObjective.Type.SKILL, "woodcutting", 10)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_xp("woodcutting", active, defs, skill, "1")
	assert_eq(updates.size(), 0, "Level nicht erreicht → kein Update")

func test_resolve_xp_no_crash_without_skill_system() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.SKILL, "woodcutting", 10)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_xp("woodcutting", active, defs, null, "1")
	assert_eq(updates.size(), 0, "Ohne SkillSystem darf kein Update erzeugt werden, kein Crash")

func test_resolve_xp_checks_level_for_given_player_not_player_one() -> void:
	# Round 45/R-5-Regression: player_id ist Pflichtparameter, weil skill_system.get_level()
	# sonst leise auf Spieler 1 default. Spieler 1 hat hier NICHT das Level, Spieler 2 hat es.
	# Round 67: player_id ist String (stabile Identität), nicht int — siehe Bug-Fund in
	# QuestObjectiveHandler.resolve_xp() / TODO-offene-probleme.md.
	var skill := MockSkillSystem.new()
	skill._levels_by_player = {"1": {"woodcutting": 2}, "2": {"woodcutting": 10}}
	var obj := _make_obj("obj1", QuestObjective.Type.SKILL, "woodcutting", 10)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates_p2 := QuestObjectiveHandler.resolve_xp("woodcutting", active, defs, skill, "2")
	assert_eq(updates_p2.size(), 1, "Spieler 2 hat Level 10 erreicht → Update muss erzeugt werden")
	var updates_p1 := QuestObjectiveHandler.resolve_xp("woodcutting", active, defs, skill, "1")
	assert_eq(updates_p1.size(), 0, "Spieler 1 hat Level 10 NICHT erreicht → kein Update")

# ─────────────────────────────────────────────────────────────────────────────
# resolve_interaction()
# ─────────────────────────────────────────────────────────────────────────────

func test_resolve_interaction_matches() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.INTERACT, "chop", 3)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_interaction("chop", active, defs)
	assert_eq(updates.size(), 1)
	assert_eq(updates[0]["delta"], 1, "INTERACT-Updates sind immer delta=1")

func test_resolve_interaction_no_match() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.INTERACT, "chop", 3)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_interaction("mine", active, defs)
	assert_eq(updates.size(), 0)

# ─────────────────────────────────────────────────────────────────────────────
# resolve_kill()
# ─────────────────────────────────────────────────────────────────────────────

func test_resolve_kill_matches() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.KILL, "goblin", 3)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_kill("goblin", active, defs)
	assert_eq(updates.size(), 1)

func test_resolve_kill_no_match_different_enemy() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.KILL, "goblin", 3)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_kill("skeleton", active, defs)
	assert_eq(updates.size(), 0)

# ─────────────────────────────────────────────────────────────────────────────
# resolve_talk() — neu (Runde 6)
# ─────────────────────────────────────────────────────────────────────────────

func test_resolve_talk_matches() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.TALK, "erik_woodcutter", 1)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_talk("erik_woodcutter", active, defs)
	assert_eq(updates.size(), 1)
	assert_eq(updates[0]["obj_id"], "obj1")

func test_resolve_talk_no_match_different_npc() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.TALK, "erik_woodcutter", 1)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_talk("some_other_npc", active, defs)
	assert_eq(updates.size(), 0)

func test_resolve_talk_no_match_wrong_type() -> void:
	## INTERACT-Objective mit gleichem target_id darf nicht auf TALK matchen
	var obj := _make_obj("obj1", QuestObjective.Type.INTERACT, "erik_woodcutter", 1)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_talk("erik_woodcutter", active, defs)
	assert_eq(updates.size(), 0, "INTERACT-Objective darf nicht auf resolve_talk() matchen")

func test_resolve_talk_ignores_inactive_quest() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.TALK, "erik_woodcutter", 1)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {}  # keine aktive Quest
	var updates := QuestObjectiveHandler.resolve_talk("erik_woodcutter", active, defs)
	assert_eq(updates.size(), 0)

# ─────────────────────────────────────────────────────────────────────────────
# resolve_custom() — neu (Runde 6)
# ─────────────────────────────────────────────────────────────────────────────

func test_resolve_custom_matches() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.CUSTOM, "erik_camp_explored", 1)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_custom("erik_camp_explored", active, defs)
	assert_eq(updates.size(), 1)

func test_resolve_custom_no_match_different_key() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.CUSTOM, "erik_camp_explored", 1)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_custom("wrong_key", active, defs)
	assert_eq(updates.size(), 0)

func test_resolve_custom_no_match_wrong_type() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.TALK, "erik_camp_explored", 1)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_custom("erik_camp_explored", active, defs)
	assert_eq(updates.size(), 0, "TALK-Objective darf nicht auf resolve_custom() matchen")

func test_resolve_custom_case_sensitive_key_match() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.CUSTOM, "erik_camp_explored", 1)
	var defs := {"q1": _make_def("q1", [obj])}
	var active := {"q1": null}
	var updates := QuestObjectiveHandler.resolve_custom("Erik_Camp_Explored", active, defs)
	assert_eq(updates.size(), 0, "signal_key-Match muss exakt (case-sensitive) sein")

# ─────────────────────────────────────────────────────────────────────────────
# Alle 6 Typen — Cross-Type-Isolation in einer gemischten Quest
# ─────────────────────────────────────────────────────────────────────────────

func test_mixed_quest_each_resolver_only_matches_its_own_type() -> void:
	## Eine Quest mit allen 6 Objective-Typen — jeder resolve_*() darf nur
	## sein eigenes Objective treffen, nie die der anderen 5 Typen.
	var o_collect  := _make_obj("o_collect",  QuestObjective.Type.COLLECT,  "shared_id", 1)
	var o_skill    := _make_obj("o_skill",    QuestObjective.Type.SKILL,    "shared_id", 1)
	var o_interact := _make_obj("o_interact", QuestObjective.Type.INTERACT, "shared_id", 1)
	var o_kill     := _make_obj("o_kill",     QuestObjective.Type.KILL,     "shared_id", 1)
	var o_talk     := _make_obj("o_talk",     QuestObjective.Type.TALK,     "shared_id", 1)
	var o_custom   := _make_obj("o_custom",   QuestObjective.Type.CUSTOM,   "shared_id", 1)
	var qmix_def := _make_def("qmix", [o_collect, o_skill, o_interact, o_kill, o_talk, o_custom])
	# Dieser Test prüft Cross-Type-Isolation an EINEM Zeitpunkt, nicht Reihenfolge
	# (siehe QuestDefinition.sequential / QuestObjectiveHandler.is_objective_unlocked()).
	# Ohne sequential = false würden o_interact/o_kill/o_talk/o_custom (Index > 0)
	# fälschlich als "noch nicht erreicht" gesperrt, weil active_quests hier
	# bewusst kein QuestProgressRecord mitführt.
	qmix_def.sequential = false
	var defs := {"qmix": qmix_def}
	var active := {"qmix": null}

	var loot_updates   := QuestObjectiveHandler.resolve_loot("shared_id", 1, active, defs)
	var interact_updates := QuestObjectiveHandler.resolve_interaction("shared_id", active, defs)
	var kill_updates    := QuestObjectiveHandler.resolve_kill("shared_id", active, defs)
	var talk_updates    := QuestObjectiveHandler.resolve_talk("shared_id", active, defs)
	var custom_updates  := QuestObjectiveHandler.resolve_custom("shared_id", active, defs)

	assert_eq(loot_updates.size(), 1, "resolve_loot() darf nur o_collect treffen")
	assert_eq(loot_updates[0]["obj_id"], "o_collect")
	assert_eq(interact_updates.size(), 1, "resolve_interaction() darf nur o_interact treffen")
	assert_eq(interact_updates[0]["obj_id"], "o_interact")
	assert_eq(kill_updates.size(), 1, "resolve_kill() darf nur o_kill treffen")
	assert_eq(kill_updates[0]["obj_id"], "o_kill")
	assert_eq(talk_updates.size(), 1, "resolve_talk() darf nur o_talk treffen")
	assert_eq(talk_updates[0]["obj_id"], "o_talk")
	assert_eq(custom_updates.size(), 1, "resolve_custom() darf nur o_custom treffen")
	assert_eq(custom_updates[0]["obj_id"], "o_custom")

# ─────────────────────────────────────────────────────────────────────────────
# is_completable()
# ─────────────────────────────────────────────────────────────────────────────

func test_is_completable_true_when_all_required_met() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.COLLECT, "x", 5)
	var def := _make_def("q1", [obj])
	var state := {"obj1": 5}
	assert_true(QuestObjectiveHandler.is_completable("q1", state, def))

func test_is_completable_false_when_not_met() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.COLLECT, "x", 5)
	var def := _make_def("q1", [obj])
	var state := {"obj1": 3}
	assert_false(QuestObjectiveHandler.is_completable("q1", state, def))

func test_is_completable_ignores_optional() -> void:
	var required_obj := _make_obj("o_req", QuestObjective.Type.COLLECT, "x", 5)
	var optional_obj  := _make_obj("o_opt", QuestObjective.Type.TALK, "y", 1, true)
	var def := _make_def("q1", [required_obj, optional_obj])
	var state := {"o_req": 5}  # optional nicht erfüllt
	assert_true(QuestObjectiveHandler.is_completable("q1", state, def),
		"Optionale Objectives dürfen Completion nicht blockieren")

func test_is_completable_false_when_missing_progress_entry() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.COLLECT, "x", 5)
	var def := _make_def("q1", [obj])
	var state := {}  # kein Eintrag für obj1
	assert_false(QuestObjectiveHandler.is_completable("q1", state, def),
		"Fehlender Progress-Eintrag muss als 0 behandelt werden")

# ─────────────────────────────────────────────────────────────────────────────
# is_objective_unlocked() / sequentielle Gating-Logik (Issues #3 + #4)
# ─────────────────────────────────────────────────────────────────────────────

func _make_record(quest_id: String, objective_progress: Dictionary) -> QuestProgressRecord:
	var rec := QuestProgressRecord.new()
	rec.quest_id = quest_id
	rec.objectives = objective_progress.duplicate()
	return rec

func test_first_objective_always_unlocked_even_without_record() -> void:
	var obj := _make_obj("obj1", QuestObjective.Type.KILL, "skeleton", 5)
	var def := _make_def("q1", [obj])
	assert_true(QuestObjectiveHandler.is_objective_unlocked(def, null, 0),
		"Index 0 hat kein Vorgänger-Objective und muss immer entsperrt sein")

func test_second_objective_locked_while_first_incomplete() -> void:
	var obj1 := _make_obj("obj1", QuestObjective.Type.TALK, "mira", 1)
	var obj2 := _make_obj("obj2", QuestObjective.Type.CUSTOM, "caught_fox", 1)
	var def := _make_def("q1", [obj1, obj2])
	var rec := _make_record("q1", {"obj1": 0, "obj2": 0})
	assert_false(QuestObjectiveHandler.is_objective_unlocked(def, rec, 1),
		"obj2 darf nicht freigeschaltet sein solange obj1 nicht erfüllt ist")

func test_second_objective_unlocked_once_first_complete() -> void:
	var obj1 := _make_obj("obj1", QuestObjective.Type.TALK, "mira", 1)
	var obj2 := _make_obj("obj2", QuestObjective.Type.CUSTOM, "caught_fox", 1)
	var def := _make_def("q1", [obj1, obj2])
	var rec := _make_record("q1", {"obj1": 1, "obj2": 0})
	assert_true(QuestObjectiveHandler.is_objective_unlocked(def, rec, 1),
		"obj2 muss freigeschaltet sein sobald obj1 sein required erreicht hat")

func test_optional_prior_objective_does_not_block_chain() -> void:
	var obj1 := _make_obj("obj1", QuestObjective.Type.TALK, "mira", 1, true)  # optional
	var obj2 := _make_obj("obj2", QuestObjective.Type.CUSTOM, "caught_fox", 1)
	var def := _make_def("q1", [obj1, obj2])
	var rec := _make_record("q1", {"obj1": 0, "obj2": 0})
	assert_true(QuestObjectiveHandler.is_objective_unlocked(def, rec, 1),
		"Ein optionales, unerfülltes Vorgänger-Objective darf die Kette nicht blockieren")

func test_non_sequential_quest_unlocks_everything_regardless_of_order() -> void:
	var obj1 := _make_obj("obj1", QuestObjective.Type.COLLECT, "wood", 5)
	var obj2 := _make_obj("obj2", QuestObjective.Type.COLLECT, "stone", 5)
	var def := _make_def("q1", [obj1, obj2])
	def.sequential = false
	var rec := _make_record("q1", {"obj1": 0, "obj2": 0})
	assert_true(QuestObjectiveHandler.is_objective_unlocked(def, rec, 1),
		"sequential = false muss alle Objectives unabhängig von der Reihenfolge freischalten")

func test_resolve_kill_does_not_advance_later_step_before_earlier_one() -> void:
	# Regressionstest für Issue #4 ("Die letzten Questschritte können beendet
	# werden obwohl vorherige nicht abgeschlossen sind"): ein Spieler, der den
	# "Verbrecher" (hier: Skelett) tötet bevor er mit der NPC gesprochen hat,
	# darf den KILL-Schritt noch nicht gutgeschrieben bekommen.
	var obj_talk := _make_obj("obj_talk", QuestObjective.Type.TALK, "talia", 1)
	var obj_kill := _make_obj("obj_kill", QuestObjective.Type.KILL, "skeleton", 5)
	var def := _make_def("q1", [obj_talk, obj_kill])
	var rec := _make_record("q1", {"obj_talk": 0, "obj_kill": 0})
	var active := {"q1": rec}
	var defs := {"q1": def}
	var updates := QuestObjectiveHandler.resolve_kill("skeleton", active, defs)
	assert_eq(updates.size(), 0,
		"KILL-Objective darf keinen Fortschritt erhalten solange der vorherige TALK-Schritt offen ist")

func test_resolve_kill_advances_once_prior_talk_step_done() -> void:
	var obj_talk := _make_obj("obj_talk", QuestObjective.Type.TALK, "talia", 1)
	var obj_kill := _make_obj("obj_kill", QuestObjective.Type.KILL, "skeleton", 5)
	var def := _make_def("q1", [obj_talk, obj_kill])
	var rec := _make_record("q1", {"obj_talk": 1, "obj_kill": 0})
	var active := {"q1": rec}
	var defs := {"q1": def}
	var updates := QuestObjectiveHandler.resolve_kill("skeleton", active, defs)
	assert_eq(updates.size(), 1,
		"KILL-Objective muss Fortschritt erhalten sobald der vorherige TALK-Schritt erfüllt ist")
