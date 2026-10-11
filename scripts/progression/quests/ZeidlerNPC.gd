extends QuestNPC
class_name ZeidlerNPC

## ZeidlerNPC — "Zeidlerin Gerlinde". Generiert von
## scripts/agent/build/quest_npc_scaffold.py (ADR-051 Stufe 3 —
## DialogueTreeController.build_quest_giver(), siehe dortiger
## Klassenkommentar für die generelle Begründung dieses Musters).

## Fränkisch-germanisch (mittelalterliche Zeidlerei: Waldimkerei in Baumhöhlen, z. B. im Nürnberger Reichswald). Rolle: Wald/Handwerk. Gag: Zuständigkeits-Verweis – Wespen und Hornissen sind nicht ihre Abteilung.

func _init() -> void:
	quest_id         = ""  # kein Slot-System — dieser NPC nutzt ausschließlich den Dialogbaum.
	npc_display_name = "Zeidlerin Gerlinde"
	npc_id            = "gerlinde_zeidler"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	return DialogueTreeController.build_quest_giver(
		tree_label, tree, tree_bus, quest_service,
		"quest_gerlinde_combs",
		"obj_collect_honeycomb_zeidler",
		3,
		"Zeidler holten Honig aus\nBaumhöhlen. Alter Beruf!\nBring mir 3 Honigwaben.",
		"Honigwaben: %d/%d.\nGrüß die Bienen!",
		"Süß! Und Wespen? Nicht\nmeine Abteilung – frag\nPapiermeisterin Lian.",
		"quest_gerlinde_master",
		"obj_reach_beekeeping_3",
		3,
		"Zeig mir, dass du den\nTanz der Bienen lesen\nkannst. Imkerei-Stufe 3!",
		"Imkerei-Stufe %d/%d.\nGeduld gehört dazu.",
		"Du liest den Schwänzeltanz\nbesser als ich. Ich tanze\nnur schlecht."
	)

func _get_body_color() -> Color:
	return Color(0.85, 0.68, 0.2)
