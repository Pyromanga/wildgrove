extends QuestNPC
class_name HerbalistNPC

## HerbalistNPC — "Kräuterkundige Senna". Quest-Geberin für den
## Foraging-Questchain quest_herbalist_request → quest_herbalist_secret.
##
## ADR-051 Stufe 3 (umgestellt 2026-09-27): nutzt DialogueTreeController.
## build_quest_giver() — siehe MinerNPC.gd Klassenkommentar für die volle
## Begründung, gilt hier identisch.

func _init() -> void:
	quest_id         = ""  # kein Slot-System mehr — siehe MinerNPC.gd.
	npc_display_name = "Kräuterkundige Senna"
	npc_id            = "senna_herbalist"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	return DialogueTreeController.build_quest_giver(
		tree_label, tree, tree_bus, quest_service,
		"quest_herbalist_request", "obj_collect_mushroom", 4,
		"Ah, ein Sammler! Ich brauche\n4 wilde Pilze und 3 Farnfasern\nfür meine Tinkturen.",
		"Pilze bisher: %d/%d.\nDie Fasern nicht vergessen!",
		"Wunderbar, genau was ich\nbrauchte. Danke dir!",
		"quest_herbalist_secret", "obj_collect_cactus_fiber", 2,
		"Weil du so zuverlässig bist,\nverrate ich dir mein geheimes\nRezept — bring mir 2 Kaktusfasern.",
		"Kaktusfasern: %d/%d.\nDie Wüste ist im Osten.",
		"Perfekt. Das Rezept gehört\njetzt auch dir, Freund/in."
	)

func _get_body_color() -> Color:
	# Kräuter-Grün statt Eriks Blau — passt zur Kräuterkunde-Rolle.
	return Color(0.30, 0.55, 0.28)
