extends QuestNPC
class_name GuardNPC

## GuardNPC — "Wächterin Talia". Quest-Geberin für ZWEI unabhängige Themen:
##   1. "Der Dieb im Pelz" — quest_talia_investigation → quest_talia_verdict
##      (4 bzw. 2 Objectives, siehe Git-Historie dieser Datei für die volle
##      Erzählung — Fuchs-Dieb-Pointe, fox_tail_talisman-Reward).
##   2. "Friedhofswache" — quest_talia_graveyard_watch (einstufig, schaltet
##      über BuildPieceDefinition.requires_quest_id einen Wach-Grabstein frei).
##
## ADR-051 Stufe 3 (umgestellt 2026-09-27, vorher Stufe-1-Extra-Slot auf dem
## Slot-System): DAS hier ist der Fall, für den Stufe 2/3 ("mehrere
## Sprachmöglichkeiten") eigentlich gebaut wurden — Talia hat jetzt ECHT zwei
## unabhängige Anliegen, die beide gleichzeitig offen sein können. Der
## Root-Knoten zeigt deshalb IMMER ein 2-Themen-Menü (nicht nur bei
## Mehrdeutigkeit wie bei anderen NPCs) — der einzige NPC in diesem Projekt,
## bei dem das Gesprächsmenü dauerhaft sichtbar bleibt, weil es hier
## inhaltlich gerechtfertigt ist (zwei echte Themen, nicht nur ein
## Übergangszustand).
##
## Jedes Thema ist intern derselbe 3-Wege-Router wie
## DialogueTreeController.build_quest_giver() (offen/aktiv/erledigt, Thema 1
## zusätzlich mit Kettenstufe 2) — hier von Hand gebaut statt über die
## Factory, weil zwei Factory-Aufrufe in DENSELBEN Controller kollidierende
## Knoten-IDs ("entry", "offer1", ...) erzeugen würden. Node-IDs deshalb mit
## "theft_"/"grave_" präfixiert.

func _init() -> void:
	quest_id         = ""  # kein Slot-System mehr.
	npc_display_name = "Wächterin Talia"
	npc_id            = "talia_guard"

func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	var dt := DialogueTreeController.new(tree_label, tree, tree_bus, quest_service)

	# ── Thema 1: "Der Dieb im Pelz" (2 Stufen) ──────────────────────────────
	dt.add_node("theft_offer1",
		"Seit Tagen fehlt Mira\nallerhand Glänzendes. Frag sie,\nfolge der Spur, fang den Dieb."
	).add_choice("(annehmen)", "theft_active1", "start_quest:quest_talia_investigation")
	dt.add_node("theft_active1", "Spur verfolgt: Stufe %d/%d.\nDu kommst näher ran.") \
		.with_progress("quest_talia_investigation", "obj_track_forestry_3", 3)
	dt.add_node("theft_offer2",
		"Frag Mira nochmal genau,\nwo sie das Nugget zuletzt\ngesehen hat. Irgendwas passt nicht."
	).add_choice("(annehmen)", "theft_active2", "start_quest:quest_talia_verdict")
	dt.add_node("theft_active2", "Schon mit Mira gesprochen?\nIch warte auf deinen Bericht.") \
		.with_progress("quest_talia_verdict", "obj_talk_mira_confront", 1)
	dt.add_node("theft_done",
		"Sie hat's selbst verlegt, was?\nTypisch. Der Fuchs kriegt eine\nEntschuldigung. Von mir aus reicht's."
	)
	dt.add_node("theft_entry", "Ein Fuchs war's? Na sowas.\nGut gemacht — aber irgendwas\nan der Sache stinkt noch.") \
		.add_choice("", "theft_active1", "", "quest_active:quest_talia_investigation") \
		.add_choice("", "theft_offer1", "", "quest_not_active:quest_talia_investigation,quest_not_completed:quest_talia_investigation") \
		.add_choice("", "theft_active2", "", "quest_active:quest_talia_verdict") \
		.add_choice("", "theft_offer2", "", "quest_completed:quest_talia_investigation,quest_not_active:quest_talia_verdict,quest_not_completed:quest_talia_verdict") \
		.add_choice("", "theft_done", "", "quest_completed:quest_talia_verdict")

	# ── Thema 2: "Friedhofswache" (einstufig) ───────────────────────────────
	dt.add_node("grave_offer",
		"Die Friedhöfe im Land werden\nmehr, und die Skelette mit\nihnen. Erledige 5 davon."
	).add_choice("(annehmen)", "grave_active", "start_quest:quest_talia_graveyard_watch")
	dt.add_node("grave_active", "Erledigte Skelette: %d/%d.\nDie Gräber ruhen nicht von selbst.") \
		.with_progress("quest_talia_graveyard_watch", "obj_kill_graveyard_skeletons", 5)
	dt.add_node("grave_done",
		"Ordentliche Arbeit. Du hast dir\nverdient, selbst einen Wach-\nGrabstein aufstellen zu dürfen."
	)
	dt.add_node("grave_entry", "Die Friedhöfe im Land werden\nmehr, und die Skelette mit\nihnen. Erledige 5 davon.") \
		.add_choice("", "grave_active", "", "quest_active:quest_talia_graveyard_watch") \
		.add_choice("", "grave_offer", "", "quest_not_active:quest_talia_graveyard_watch,quest_not_completed:quest_talia_graveyard_watch") \
		.add_choice("", "grave_done", "", "quest_completed:quest_talia_graveyard_watch")

	# ── Root: IMMER beide Themen zur Auswahl (siehe Klassenkommentar oben) ──
	dt.add_node("entry", "Was gibt's?") \
		.add_choice("Über den Diebstahl reden", "theft_entry") \
		.add_choice("Über die Friedhöfe reden", "grave_entry")
	dt.set_start_node("entry")
	return dt

func _get_body_color() -> Color:
	# Gedecktes Grün (Wächter-Uniform) — unterscheidet sie von Eriks Blau
	# und Weis Rot.
	return Color(0.20, 0.40, 0.25)
