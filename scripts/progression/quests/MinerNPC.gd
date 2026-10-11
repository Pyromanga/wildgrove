extends QuestNPC
class_name MinerNPC

## MinerNPC — "Bergarbeiterin Mira". Quest-Geberin für
## quest_miner_defense → quest_miner_gratitude.
##
## ADR-051 Stufe 3 (umgestellt 2026-09-27, vorher Slot-System siehe Git-
## Historie dieser Datei): nutzt jetzt DialogueTreeController.build_quest_giver()
## statt der QuestNPC-Slot-Felder (quest_id/next_quest_id usw.) — reproduziert
## exakt dasselbe Verhalten (offen → annehmen → Live-Fortschritt → erledigt,
## dann Kettenstufe 2), nur über die generische Baum-Engine statt des
## Spezialfall-Code des (entfernten) Slot-Systems.
##
## Folgequest quest_miner_gratitude (prerequisites=[quest_miner_defense],
## auto_start=false) wird über die "entry"-Router-Bedingungen von
## build_quest_giver() automatisch angeboten, sobald quest_miner_defense
## abgeschlossen ist — kein manuelles Kettenmanagement mehr nötig.

func _init() -> void:
	quest_id         = ""  # kein Slot-System mehr — siehe Klassenkommentar oben.
	npc_display_name = "Bergarbeiterin Mira"
	npc_id            = "mira_miner"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	return DialogueTreeController.build_quest_giver(
		tree_label, tree, tree_bus, quest_service,
		"quest_miner_defense", "obj_collect_iron", 5,
		"Goblins haben unsere Mine\nüberfallen! Bring mir 5 Eisenerz\nund vertreib die Kerle.",
		"Weiter so! Schon\n%d/%d Eisenerz.",
		"Die Mine ist wieder sicher.\nIch schulde dir was, Freund.",
		"quest_miner_gratitude", "obj_reach_mining_3", 3,
		"Weißt du was — bleib dran\nmit dem Bergbau. Zeig mir,\ndass du's wirklich drauf hast.",
		"Bergbau-Stufe %d/%d.\nWeiter üben!",
		"Respekt! Du bist jetzt\neine von uns Bergleuten."
	)

func _get_body_color() -> Color:
	# Erdiges Ocker/Braun statt Eriks Blau — passt zur Bergbau-Rolle.
	return Color(0.55, 0.42, 0.20)
