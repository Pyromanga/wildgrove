extends QuestNPC
class_name HornetOracleNPC

## HornetOracleNPC — "Orakel Sigrun". Generiert von
## scripts/agent/build/quest_npc_scaffold.py (ADR-051 Stufe 3 —
## DialogueTreeController.build_quest_giver(), siehe dortiger
## Klassenkommentar für die generelle Begründung dieses Musters).

## Nordisch-germanisch (Runen-Orakel): Sigrun prophezeit "Drei Hornissenstiche töten einen Mann" – ein Volksmythos, den die Quest widerlegt. Rolle: Orakel/Mythos-Check. Schutz-Hinweis: bewohnte Nester in Ruhe lassen. Gag: Nornen-Beschwerdeamt (falsche Prophezeiung wird dort gemeldet).

func _init() -> void:
	quest_id         = ""  # kein Slot-System — dieser NPC nutzt ausschließlich den Dialogbaum.
	npc_display_name = "Orakel Sigrun"
	npc_id            = "sigrun_oracle"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	return DialogueTreeController.build_quest_giver(
		tree_label, tree, tree_bus, quest_service,
		"quest_sigrun_myth",
		"obj_collect_hornet_paper",
		2,
		"Die Runen sagen: drei Stiche\ntöten einen Mann! Bring 2\nHornissenpapier zum Prüfen.",
		"Hornissenpapier: %d/%d.\nNur leere Nester!",
		"Die Runen irrten: ein Mythos.\nIch melde es den Nornen.\nBewohnte Nester: Abstand!",
		"quest_sigrun_scholar",
		"obj_reach_entomology_4",
		4,
		"Wahrheit schlägt Runen.\nErreiche Insektenkunde-\nStufe 4.",
		"Insektenkunde-Stufe %d/%d.\nDie Wahrheit wartet.",
		"Du siehst klarer als\nmeine Runen. Ich\nschreibe das auf."
	)

func _get_body_color() -> Color:
	return Color(0.3, 0.3, 0.45)
