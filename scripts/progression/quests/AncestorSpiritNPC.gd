extends QuestNPC
class_name AncestorSpiritNPC

## AncestorSpiritNPC — "Ahnengeist Babatunde". Quest-Geber für den Questchain
## quest_babatunde_tale → quest_babatunde_legacy.
##
## Kulturkreis: Yoruba-Egungun-Tradition (siehe docs/quest-writing-guide.md
## Abschnitt 1/4). Running Gag (Abschnitt 3, "Der Ahnengeist mit
## Nachrichten-Rückstand"): siehe completed_text/next_offer_text unten.
##
## Design-Entscheidung gegen CUSTOM-Objective: QuestCustomTrigger ist im
## World-Setup nirgends instanziiert (dasselbe Problem wie
## quest_erik_friendship.obj_explore_camp, siehe WoodcutterNPC.gd). Diese
## Kette nutzt stattdessen zwei TALK-Objectives auf Erik/Mira.
##
## ADR-051 Stufe 3 (umgestellt 2026-09-27): nutzt DialogueTreeController.
## build_quest_giver() — siehe MinerNPC.gd Klassenkommentar für die
## allgemeine Begründung. quest_babatunde_tale.obj_talk_erik_tale ist ein
## TALK-Objective ohne numerische Anzeige im Text — with_progress() wird
## trotzdem angewendet (exakt wie im alten Slot-System: _encourage_format %
## [progress, required] lief dort unconditional, auch ohne %d-Platzhalter im
## Text — reine Verhaltens-Beibehaltung, kein neues Risiko).

func _init() -> void:
	quest_id         = ""  # kein Slot-System mehr — siehe MinerNPC.gd.
	npc_display_name = "Ahnengeist Babatunde"
	npc_id            = "babatunde_spirit"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	return DialogueTreeController.build_quest_giver(
		tree_label, tree, tree_bus, quest_service,
		"quest_babatunde_tale", "obj_talk_erik_tale", 1,
		"Endlich! Wie steht's um\nden Streit mit dem Nachbar-\ndorf? Erzähl's Erik und Mira.",
		"Noch nicht überall erzählt?\nDie Geschichte wartet\nseit Generationen. Sie kann warten.",
		"Ein Streit? Der ist doch...\nmoment, seit wann ist der\nvorbei? Wir müssen reden.",
		"quest_babatunde_legacy", "obj_reach_forestry_2", 2,
		"Vorbei seit drei Generationen.\nPeinlich. Zeig mir, dass du\ndas Wissen des Waldes wert bist.",
		"Forstwissen-Stufe %d/%d.\nDie Bäume erinnern sich\nan mehr als ich.",
		"Gut. Nimm dieses Wissen —\nkein Schatz, nur Erinnerung,\nweitergereicht."
	)

func _get_body_color() -> Color:
	# Blasses Violett-Grau — geisterhaft, statt Eriks kräftigem Blau.
	return Color(0.52, 0.48, 0.60)

## TODO (Folge-Ticket, kein Teil dieser Quest-Runde): QuestCustomTrigger in
## World.tscn/WorldSpawner verdrahten (aktuell nirgends instanziiert) — würde
## auch quest_erik_friendship.obj_explore_camp reparieren.
