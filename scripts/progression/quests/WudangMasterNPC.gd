extends QuestNPC
class_name WudangMasterNPC

## WudangMasterNPC — "Kampfmeisterin Wei". Quest-Geberin für den Questchain
## quest_wei_patience → quest_wei_mastery.
##
## Kulturkreis: chinesische Wudang-Tradition (innere Kampfkunst/Qi-Kultivierung,
## siehe docs/quest-writing-guide.md Abschnitt 1/4). Bewusst KEIN KILL-
## Objective: Wei prüft `combat`-Skill-Level statt Kill-Counts.
##
## Running Gag (Abschnitt 3, "Der Schüler, der schneller sein will als die
## Prüfung erlaubt"): siehe next_offer_text unten.
##
## ADR-051 Stufe 3 (umgestellt 2026-09-27): nutzt DialogueTreeController.
## build_quest_giver() — siehe MinerNPC.gd Klassenkommentar für die
## allgemeine Begründung.

func _init() -> void:
	quest_id         = ""  # kein Slot-System mehr — siehe MinerNPC.gd.
	npc_display_name = "Kampfmeisterin Wei"
	npc_id            = "wei_master"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	return DialogueTreeController.build_quest_giver(
		tree_label, tree, tree_bus, quest_service,
		"quest_wei_patience", "obj_reach_combat_2", 2,
		"Ich zähle keine Kills.\nErreiche Kampf-Stufe 2 —\ndann reden wir weiter.",
		"Kampf-Stufe %d/%d.\nGeduld schlägt Tempo.",
		"Gut. Du lernst, nicht\nzu zählen. Das ist der\nerste Schritt.",
		"quest_wei_mastery", "obj_reach_combat_4", 4,
		"Stufe 2 in halber Zeit?\nKein Kompliment. Zeig mir\nStufe 4 — richtig geübt.",
		"Kampf-Stufe %d/%d.\nImmer noch kein Rennen.",
		"Jetzt verstehst du Wudang.\nOder zumindest die Hälfte\ndavon. Genug für heute."
	)

func _get_body_color() -> Color:
	# Gedecktes Rot (Kampfkunst-Gewand) statt Eriks Blau — passt zur Rolle.
	return Color(0.50, 0.12, 0.12)
