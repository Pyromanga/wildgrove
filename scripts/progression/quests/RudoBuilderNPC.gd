extends QuestNPC
class_name RudoBuilderNPC

## RudoBuilderNPC — "Baumeisterin Rudo". Generiert von
## scripts/agent/build/quest_npc_scaffold.py (ADR-051 Stufe 3 —
## DialogueTreeController.build_quest_giver(), siehe dortiger
## Klassenkommentar für die generelle Begründung dieses Musters).

## Shona-Handwerkstradition (Simbabwe, Trockenmauerbau wie in Great Zimbabwe). Rolle: Baukunst/Handwerk. Gag: Ein römisches Bauamt wäre beim Anblick eines Termitenturms ohne Genehmigung entsetzt.

func _init() -> void:
	quest_id         = ""  # kein Slot-System — dieser NPC nutzt ausschließlich den Dialogbaum.
	npc_display_name = "Baumeisterin Rudo"
	npc_id            = "rudo_builder"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	return DialogueTreeController.build_quest_giver(
		tree_label, tree, tree_bus, quest_service,
		"quest_rudo_clay",
		"obj_collect_termite_clay",
		3,
		"Termiten bauen ohne Gerüst\nund ohne Genehmigung. Bring\nmir 3 Termitenlehm!",
		"Termitenlehm: %d/%d.\nIch knete schon vor.",
		"Gut geknetet! Rom würde\nein Formular verlangen,\ndie Termiten tun's einfach.",
		"quest_rudo_wall",
		"obj_collect_stone_wall",
		6,
		"Trockenmauer, ohne Mörtel,\nso baute man in Simbabwe.\nBring mir 6 Steine!",
		"Steine: %d/%d.\nJeder Stein muss passen.",
		"Sie hält! Ganz ohne\nMörtel – wie ein\nTermitenturm."
	)

func _get_body_color() -> Color:
	return Color(0.62, 0.42, 0.22)
