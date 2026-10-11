extends QuestNPC
class_name MyrmexNPC

## MyrmexNPC — "Ameisenfrau Myrmex". Generiert von
## scripts/agent/build/quest_npc_scaffold.py (ADR-051 Stufe 3 —
## DialogueTreeController.build_quest_giver(), siehe dortiger
## Klassenkommentar für die generelle Begründung dieses Musters).

## Griechisch (Hybris-Lektion): Myrmex, laut Überlieferung von Athene in eine Ameise verwandelt, weil sie mit dem Pflug prahlte. Die Myrmidonen sind in der griechischen Sage aus Ameisen entstanden. Rolle: Hybris-Lektion, bescheidene Fleißarbeit. Gag: Nornen-Beschwerdeamt (Rückverwandlungsantrag).

func _init() -> void:
	quest_id         = ""  # kein Slot-System — dieser NPC nutzt ausschließlich den Dialogbaum.
	npc_display_name = "Ameisenfrau Myrmex"
	npc_id            = "myrmex_ant"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	return DialogueTreeController.build_quest_giver(
		tree_label, tree, tree_bus, quest_service,
		"quest_myrmex_acid",
		"obj_collect_formic_acid",
		3,
		"Man sagt, Athene machte mich\nzur Ameise – wegen Angeberei.\nBring mir 3 Ameisensäure.",
		"Ameisensäure: %d/%d.\nDie Nornen lehnen mich\nweiter ab (Formular 7b).",
		"Danke! Das Beschwerdeamt\nbleibt stur, aber du\nwarst eine große Hilfe.",
		"quest_myrmex_scholar",
		"obj_reach_entomology_3",
		3,
		"Wer viele Nester kennt, wird\nbescheiden. Erforsche\nweiter, ich notiere mit.",
		"Insektenkunde-Stufe %d/%d.\nBleib bescheiden!",
		"Du bist jetzt Kollegin!\nPrahlen verboten – ich\nkenne die Folgen."
	)

func _get_body_color() -> Color:
	return Color(0.4, 0.25, 0.15)
