class_name QuestObjectiveHandler
extends RefCounted

## QuestObjectiveHandler — Prüft EventBus-Events gegen aktive Quest-Objectives.
##
## Extrahiert aus QuestService._on_loot_collected(), _on_xp_gained(), _on_interaction_finished().
## Kein Node, kein Service — reine Logik-Klasse.
##
## Verantwortung:
##   - Für jeden eingehenden Event-Wert berechnen welche Objectives betroffen sind
##   - Gibt Array[{ quest_id, objective_id, delta }] zurück → QuestService führt update_objective() aus
##
## Was QuestObjectiveHandler NICHT tut:
##   - Kein EventBus-Connect (bleibt bei QuestService)
##   - Kein state-Zugriff (active_quests, definitions bleiben bei QuestService)

const LOG_CAT := "QuestObjectiveHandler"

## BUGFIX ("Questschritte werden alle sofort angezeigt" / "spätere Schritte
## lassen sich vor früheren abschließen", siehe QuestDefinition.sequential):
## Gibt zurück ob def.objectives[index] für dieses Record überhaupt
## Fortschritt annehmen darf. Bei sequential == false (oder index <= 0)
## immer true — sonst nur wenn ALLE vorherigen non-optional Objectives
## (Array-Reihenfolge) bereits ihr required erreicht haben. Optionale
## Objectives blockieren die Kette nicht (sie sind laut Definition sowieso
## nicht zwingend), zählen aber selbst auch nur, wenn sie an der Reihe sind —
## das hält sie konsistent mit is_completable()/is_complete(), die optionale
## Objectives beim Abschluss-Check ebenfalls ignorieren.
## REGRESSION-FIX beim Schreiben dieses Codes: die bestehenden GUT-Tests in
## test_quest_objective_handler.gd rufen resolve_*() ausschließlich mit
## Ein-Objective-Quests und active_quests = {"q1": null} auf (record wird dort
## absichtlich nicht gebraucht, weil nur resolve_xp() ihn je las). Index 0 hat
## per Definition KEIN vorheriges Objective zu prüfen, muss also unabhängig
## vom Record-Zustand immer entsperrt sein — sonst würde dieser Fix jeden
## bestehenden Test (und jede frisch gestartete Quest, bevor active_quests
## überhaupt befüllt ist) fälschlich blockieren. Erst ab index > 0 wird der
## echte Record gebraucht (in der echten App immer vorhanden, siehe
## QuestService.bucket["active"]), und nur dann bedeutet record == null
## "kann nicht geprüft werden" → konservativ gesperrt.
static func is_objective_unlocked(
	def:     QuestDefinition,
	record:  QuestProgressRecord,
	index:   int
) -> bool:
	if not def.sequential or index <= 0:
		return true
	if record == null:
		return false
	for i in range(index):
		var prior: QuestObjective = def.objectives[i]
		if prior.optional:
			continue
		if record.objectives.get(prior.id, 0) < prior.required:
			return false
	return true

## Gibt alle Objective-Updates zurück die durch ein COLLECT-Event ausgelöst werden.
## { quest_id, obj_id, delta }
static func resolve_loot(
	item_id:       String,
	quantity:      int,
	active_quests: Dictionary,
	definitions:   Dictionary
) -> Array[Dictionary]:
	var updates: Array[Dictionary] = []
	for quest_id in active_quests.keys():
		var def: QuestDefinition = definitions.get(quest_id)
		if not def:
			continue
		var record: QuestProgressRecord = active_quests[quest_id]
		for i in range(def.objectives.size()):
			var obj: QuestObjective = def.objectives[i]
			if obj.type == QuestObjective.Type.COLLECT and obj.target_id == item_id:
				if is_objective_unlocked(def, record, i):
					updates.append({"quest_id": quest_id, "obj_id": obj.id, "delta": quantity})
	return updates

## Gibt alle Objective-Updates zurück die durch ein XP/SKILL-Event ausgelöst werden.
## Prüft ob skill_system.get_level() den Required-Level erreicht.
## player_id: Pflichtparameter (Round 45/R-5) — vorher stiller Default-1 in
## skill_system.get_level(), obwohl active_quests/definitions längst pro Spieler
## aufgelöst wurden. Sonst würde Spieler 2's SKILL-Objective gegen Spieler 1's
## Skill-Level geprüft.
## Round 67 (Bug-Fund während der peer_id/player_id-Namensbereinigung, siehe
## TODO-offene-probleme.md): player_id ist HIER String, nicht int — SkillSystem.
## get_level() verlangt seit Round 65 player_id: String (SkillSystem-Migration,
## ADR-029 Plan-Schritt 4). Der Aufrufer (QuestService._on_xp_gained()) reichte
## bis Round 66 den rohen int-peer_id durch statt der bereits an seiner eigenen
## Empfangsgrenze übersetzten String-player_id — ein Typkonflikt gegen die reale
## SkillSystem-Signatur, der nur deshalb nie auffiel, weil Tests hier ausschließlich
## gegen ein Double mit eigener (ebenfalls veralteter) int-Signatur laufen und nie
## gegen die echte Godot/GUT-Runtime (siehe offener Punkt "Tests gegen die echte
## Godot-Runtime" in TODO-offene-probleme.md).
## BUGFIX (Bug #5, "Mining-Quest zeigt 0/3 statt tatsächlichem Fortschritt"):
## vorher wurde bei erreichtem Ziel-Level ein fixes delta=1 vergeben — die
## Anzeige sprang also nie auf den tatsächlichen Level (z.B. 2/3 bei Level 2),
## sondern blieb bei 0/3 bis Level >= required erreicht war, und selbst dann
## nur +1 statt des vollen Fortschritts. update_objective() arbeitet rein
## additiv (record.objectives[id] + delta, siehe QuestProgressRecord.
## update_progress()) — SKILL-Objectives sollen aber den ABSOLUTEN Skill-Level
## widerspiegeln, kein Zähler von Events. Fix: delta = aktueller Level minus
## bereits gespeicherter Fortschritt, sodass objectives[id] nach dem Update
## exakt dem Skill-Level entspricht (geclamped auf required, siehe
## update_progress()). Setzt voraus, dass active_quests[quest_id] das
## QuestProgressRecord-Objekt ist (nicht nur die ID) — siehe QuestService.
## _on_xp_gained(), das bucket["active"] unverändert durchreicht.
static func resolve_xp(
	skill_name:    String,
	active_quests: Dictionary,
	definitions:   Dictionary,
	skill_system:  SkillSystem,
	player_id:     String
) -> Array[Dictionary]:
	var updates: Array[Dictionary] = []
	if not is_instance_valid(skill_system):
		return updates
	for quest_id in active_quests.keys():
		var def: QuestDefinition = definitions.get(quest_id)
		if not def:
			continue
		var record: QuestProgressRecord = active_quests[quest_id]
		for i in range(def.objectives.size()):
			var obj: QuestObjective = def.objectives[i]
			if obj.type == QuestObjective.Type.SKILL and obj.target_id == skill_name:
				if not is_objective_unlocked(def, record, i):
					continue
				var cur_level: int = skill_system.get_level(skill_name, player_id)
				var current_progress: int = record.objectives.get(obj.id, 0) if record != null else 0
				var delta: int = cur_level - current_progress
				if delta > 0:
					updates.append({"quest_id": quest_id, "obj_id": obj.id, "delta": delta})
	return updates

## Gibt alle Objective-Updates zurück die durch ein INTERACT-Event ausgelöst werden.
static func resolve_interaction(
	action_id:     String,
	active_quests: Dictionary,
	definitions:   Dictionary
) -> Array[Dictionary]:
	var updates: Array[Dictionary] = []
	for quest_id in active_quests.keys():
		var def: QuestDefinition = definitions.get(quest_id)
		if not def:
			continue
		var record: QuestProgressRecord = active_quests[quest_id]
		for i in range(def.objectives.size()):
			var obj: QuestObjective = def.objectives[i]
			if obj.type == QuestObjective.Type.INTERACT and obj.target_id == action_id:
				if is_objective_unlocked(def, record, i):
					updates.append({"quest_id": quest_id, "obj_id": obj.id, "delta": 1})
	return updates

## Gibt alle Objective-Updates zurück die durch ein KILL-Event ausgelöst werden.
## enemy_type_id: EntityRegistry-Key des besiegten Feindes (z.B. "goblin").
## Wird von QuestService._on_enemy_killed() aufgerufen.
static func resolve_kill(
	enemy_type_id: String,
	active_quests: Dictionary,
	definitions:   Dictionary
) -> Array[Dictionary]:
	var updates: Array[Dictionary] = []
	for quest_id in active_quests.keys():
		var def: QuestDefinition = definitions.get(quest_id)
		if not def:
			continue
		var record: QuestProgressRecord = active_quests[quest_id]
		for i in range(def.objectives.size()):
			var obj: QuestObjective = def.objectives[i]
			if obj.type == QuestObjective.Type.KILL and obj.target_id == enemy_type_id:
				if is_objective_unlocked(def, record, i):
					updates.append({"quest_id": quest_id, "obj_id": obj.id, "delta": 1})
	return updates

## Gibt alle Objective-Updates zurück die durch ein TALK-Event ausgelöst werden.
## npc_id: feste NPC-ID oder EntityRegistry-Key des angesprochenen NPCs.
## Wird von QuestService._on_npc_talked_to() aufgerufen.
static func resolve_talk(
	npc_id:        String,
	active_quests: Dictionary,
	definitions:   Dictionary
) -> Array[Dictionary]:
	var updates: Array[Dictionary] = []
	for quest_id in active_quests.keys():
		var def: QuestDefinition = definitions.get(quest_id)
		if not def:
			continue
		var record: QuestProgressRecord = active_quests[quest_id]
		for i in range(def.objectives.size()):
			var obj: QuestObjective = def.objectives[i]
			if obj.type == QuestObjective.Type.TALK and obj.target_id == npc_id:
				if is_objective_unlocked(def, record, i):
					updates.append({"quest_id": quest_id, "obj_id": obj.id, "delta": 1})
	return updates

## Gibt alle Objective-Updates zurück die durch ein CUSTOM-Event ausgelöst werden.
## signal_key: frei definierter Schlüssel — muss exakt obj.target_id entsprechen.
## Wird von QuestService._on_custom_objective_triggered() aufgerufen.
static func resolve_custom(
	signal_key:    String,
	active_quests: Dictionary,
	definitions:   Dictionary
) -> Array[Dictionary]:
	var updates: Array[Dictionary] = []
	for quest_id in active_quests.keys():
		var def: QuestDefinition = definitions.get(quest_id)
		if not def:
			continue
		var record: QuestProgressRecord = active_quests[quest_id]
		for i in range(def.objectives.size()):
			var obj: QuestObjective = def.objectives[i]
			if obj.type == QuestObjective.Type.CUSTOM and obj.target_id == signal_key:
				if is_objective_unlocked(def, record, i):
					updates.append({"quest_id": quest_id, "obj_id": obj.id, "delta": 1})
	return updates

## Prüft ob alle Pflicht-Objectives einer Quest erfüllt sind.
## Gibt true zurück wenn die Quest abgeschlossen werden kann.
static func is_completable(
	quest_id:        String,
	objectives_state: Dictionary,
	def:             QuestDefinition
) -> bool:
	for obj in def.objectives:
		if obj.optional:
			continue
		var progress: int = objectives_state.get(obj.id, 0)
		if progress < obj.required:
			return false
	return true
