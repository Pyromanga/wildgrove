extends QuestNPC
class_name PapermakerNPC

## PapermakerNPC — "Papiermeisterin Lian". Generiert von
## scripts/agent/build/quest_npc_scaffold.py (ADR-051 Stufe 3 —
## DialogueTreeController.build_quest_giver(), siehe dortiger
## Klassenkommentar für die generelle Begründung dieses Musters).

## Chinesische Papiermacher-Tradition (Han-Zeit, Papier aus Pflanzenfasern). Rolle: Meisterschaft, ruhig und sentenzhaft. Gag: Zuständigkeits-Verweis – Hornissen sind Sigruns Abteilung.

func _init() -> void:
	quest_id         = ""  # kein Slot-System — dieser NPC nutzt ausschließlich den Dialogbaum.
	npc_display_name = "Papiermeisterin Lian"
	npc_id            = "lian_paper"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	return DialogueTreeController.build_quest_giver(
		tree_label, tree, tree_bus, quest_service,
		"quest_lian_wasp_paper",
		"obj_collect_wasp_paper",
		3,
		"Die Wespe macht Papier aus\nHolz, ohne Meister. Bring\nmir 3 Wespenpapier.",
		"Wespenpapier: %d/%d.\nGeduld, Schüler.",
		"Wir fertigen seit 1900\nJahren Papier, die Wespe\nlänger. Sie prahlt nicht.",
		"quest_lian_fibre",
		"obj_collect_fern_fiber_paper",
		4,
		"Papier braucht gute Faser.\nBring mir 4 Farnfasern,\nwir vergleichen.",
		"Farnfasern: %d/%d.\nDie Faser lügt nicht.",
		"Gutes Blatt! Hornissen?\nNicht meine Abteilung –\nfrag Orakel Sigrun."
	)

func _get_body_color() -> Color:
	return Color(0.78, 0.74, 0.62)
