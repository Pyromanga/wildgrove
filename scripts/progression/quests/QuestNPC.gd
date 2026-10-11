extends StaticBody3D
class_name QuestNPC

## QuestNPC — Stationärer Quest-Geber. Koordinator-Klasse.
##
## EIN Dialog-System: DialogueTreeController (verzweigender Baum, liest den Quest-Zustand live
## aus dem QuestService). Subklassen überschreiben _build_dialogue_tree() für eigene Bäume; der
## Default baut aus den @export-Feldern unten einen Standard-Questgeber (offen → aktiv →
## erledigt, optional eine Folgequest) — das ersetzt das frühere Slot-System
## (QuestNPCDialogController, entfernt).
##
## Delegiert an:
##   NPCVisualBuilder          → 3D-Visuals aufbauen
##   DialogueTreeController    → Dialog + Quest-Start
##
## Pflicht-Deps (laut statt still, siehe on_spawn()): IEventBus, QuestService.
## NetworkBridge: für die Spieler-Identität (peer_id → player_id) und das TALK-Tracking.

const LOG_CAT := "QuestNPC"

@export var quest_id:         String = "quest_woodcutter_intro"
@export var quest_obj_id:     String = "obj_chop_trees"
@export var npc_display_name: String = "Waldläufer Erik"
## Stabile ID für TALK-Quest-Objectives (QuestObjective.target_id) — unabhängig
## von npc_display_name, damit Lokalisierung/Umbenennung Quest-Daten nicht bricht.
@export var npc_id:           String = "erik_woodcutter"

## Texte + Ziel-Menge für den Standard-Questgeber-Baum (nur der Default von
## _build_dialogue_tree() liest sie; Subklassen mit eigenem Baum ignorieren sie).
@export_multiline var dialog_offer_text: String = "Gut, dass du da bist!\nFälle 3 Eichen für mich.\nDas Holz wird gebraucht."
@export var dialog_encourage_format: String = "Gut! Du hast schon\n%d/%d Bäume gefällt."
@export_multiline var dialog_completed_text: String = "Danke! Das Holz werde\nich gut gebrauchen können."
## Ziel-Menge des über quest_obj_id getrackten Objectives — nur für die Anzeige (%d/%d),
## NICHT die Quelle der Wahrheit für den Quest-Fortschritt (das bleibt QuestService).
@export var quest_obj_required: int = 3

## Optionale Folgequest (2-stufige Kette). Leer = keine Kette.
@export var next_quest_id:          String = ""
@export var next_quest_obj_id:      String = ""
@export var next_quest_obj_required: int = 1
@export_multiline var next_dialog_offer_text: String = ""
@export var next_dialog_encourage_format: String = ""
@export_multiline var next_dialog_completed_text: String = ""

var _dialogue_tree: DialogueTreeController = null
var _dialog_label: Label3D
var _bus: IEventBus = null  ## Pflicht-Dep, injiziert via on_spawn(ctx). Für Tests: MockEventBus.
## Für die Spieler-Identität und das TALK-Objective-Tracking (ADR-021). Ohne sie bleibt der
## Dialog stumm (laut gemeldet), siehe _on_interacted().
var _network: NetworkBridge = null

func _ready() -> void:
	name = "QuestNPC_" + npc_display_name.replace(" ", "_")
	add_to_group("npcs")

	_dialog_label = NPCVisualBuilder.build(self, npc_display_name, _get_body_color())
	_build_collision()
	_setup_interactable()
	AppLogger.log_info("QuestNPC '%s' bereit." % npc_display_name, LOG_CAT)

## Hook für Subklassen: eigene Körperfarbe statt Erik-Standardblau.
func _get_body_color() -> Color:
	return Color(0.25, 0.40, 0.65)

## Hook für Subklassen: eigener Dialog-Baum. Default = Standard-Questgeber aus den
## @export-Feldern oben. Wird aus on_spawn() aufgerufen, NACHDEM _dialog_label/_bus/
## quest_service feststehen.
func _build_dialogue_tree(
	tree_label: Label3D, tree: SceneTree, tree_bus: IEventBus, quest_service: QuestService
) -> DialogueTreeController:
	return DialogueTreeController.build_quest_giver(
		tree_label, tree, tree_bus, quest_service,
		quest_id, quest_obj_id, quest_obj_required,
		dialog_offer_text, dialog_encourage_format, dialog_completed_text,
		next_quest_id, next_quest_obj_id, next_quest_obj_required,
		next_dialog_offer_text, next_dialog_encourage_format, next_dialog_completed_text
	)

# ─────────────────────────────────────────────
# Interaktion
# ─────────────────────────────────────────────

func _setup_interactable() -> void:
	var d := InteractableData.new()
	d.id          = "talk_quest_npc"
	d.label       = "Mit %s sprechen" % npc_display_name
	d.duration    = 0.3
	d.xp_type     = "none"
	d.xp_amount   = 0
	d.inspect_text = "%s. Er sieht aus als hätte er eine Aufgabe für dich." % npc_display_name
	var comp := InteractableComponent.new()
	comp.data = d
	add_child(comp)
	# InteractableComponent._handle_completion() feuert nur das 'interacted'-Signal.
	comp.interacted.connect(_on_interacted)

## Aufgerufen nach Abschluss der Rede-Interaktion. peer_id: Identität des Sprechenden.
##
## Spieler-Identität: genau EIN Weg — NetworkBridge.get_player_id_for_peer(peer_id). Kann sie
## nicht aufgelöst werden, ist das ein Fehler (kein stiller Ersatzwert): der Dialog bleibt
## stumm und es steht ein ERROR im Log.
##
## BUG-26: Lokales Feedback (Dialog) läuft für jeden Peer, Quest-Tracking (Bus-Emit +
## report_domain_event()) nur auf der Autorität — sonst zählen TALK-Objectives doppelt.
func _on_interacted(action_id: String, peer_id: int) -> void:
	if action_id != "talk_quest_npc":
		return
	if not is_instance_valid(_dialogue_tree):
		AppLogger.log_error("'%s': _on_interacted() ohne Dialog-Baum (on_spawn() fehlgeschlagen?)." % npc_id, LOG_CAT)
		return
	var player_id := _network.get_player_id_for_peer(peer_id) if is_instance_valid(_network) else ""
	if player_id.is_empty():
		AppLogger.log_error(
			"'%s': Spieler-ID für peer %d nicht auflösbar (NetworkBridge=%s) — Dialog abgebrochen." % [
				npc_id, peer_id, "ja" if is_instance_valid(_network) else "NEIN"],
			LOG_CAT
		)
		return
	_dialogue_tree.set_player_id(player_id)
	_dialogue_tree.on_interact()
	if not is_multiplayer_authority():
		return
	if _bus != null:
		_bus.quest().emit_npc_talked_to(npc_id)
	if is_instance_valid(_network):
		_network.report_domain_event("npc_talked_to", {"npc_id": npc_id}, peer_id)
	AppLogger.log_info("NPC interagiert (%s)." % npc_id, LOG_CAT)

# ─────────────────────────────────────────────
# Collision
# ─────────────────────────────────────────────

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var sh  := CapsuleShape3D.new()
	sh.radius = 0.35
	sh.height = 1.5
	col.shape = sh
	col.position.y = 0.75
	add_child(col)

# ─────────────────────────────────────────────
# EntityOrchestrator-Interface
# ─────────────────────────────────────────────

func on_spawn(_cfg: Dictionary, ctx: IEntityContext = null) -> void:
	if is_instance_valid(ctx) and ctx.has_method("get_event_bus"):
		_bus = ctx.get_event_bus() as IEventBus
	if _bus == null:
		AppLogger.log_error(
			"QuestNPC.on_spawn(): kein IEventBus im EntityContext — Spawn ohne DI nicht unterstützt.",
			LOG_CAT
		)
		return
	if is_instance_valid(ctx):
		_network = ctx.get_network_bridge()
	if _network == null:
		AppLogger.log_error(
			"QuestNPC '%s': keine NetworkBridge im EntityContext — keine Spieler-Identität, der Dialog bleibt stumm." % npc_id,
			LOG_CAT
		)
	var quest_service: QuestService = ctx.get_quest_service() if is_instance_valid(ctx) else null
	if quest_service == null:
		# Pflicht-Dep. Ohne sie könnte der Baum nie eine Bedingung auswerten oder eine Quest
		# starten — früher wurde das stillschweigend zum Fallback-Text (Quest-Bug).
		AppLogger.log_error(
			"QuestNPC '%s': kein QuestService im EntityContext — Quests können nicht gestartet werden. "
			% npc_id + "Ist 'quest' in den optional_deps des 'world'-Service (BootstrapConfig.tres) deklariert?",
			LOG_CAT
		)
	_dialogue_tree = _build_dialogue_tree(_dialog_label, get_tree(), _bus, quest_service)
	if not is_instance_valid(_dialogue_tree):
		AppLogger.log_error("QuestNPC '%s': _build_dialogue_tree() lieferte keinen Baum." % npc_id, LOG_CAT)
		return
	_dialogue_tree.set_choice_ui_factory(func() -> NPCDialogueChoiceUI: return NPCDialogueChoiceUI.new())

func on_despawn() -> void:
	pass
