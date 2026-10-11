extends StaticBody3D
class_name TutorialGuideNPC

## TutorialGuideNPC — Tutorial-Teil 2 (ADR-048 Round 106).
##
## Erfüllt die ursprüngliche Vorgabe aus ADR-048 ("...danach Spawn in der
## Welt + erklärender NPC"): ein stationärer NPC nahe dem Player-Spawnpunkt
## (siehe WorldSpawner.gd), der bei jedem Gespräch einen von mehreren
## UI/UX-Tipps zeigt (siehe TutorialGuideDialogController). Strukturell
## exakt `BankNPC`/`ShopNPC`-Muster (Koordinator-Klasse, delegiert Visuals
## an `NPCVisualBuilder`, Dialog-Logik an einen eigenen Controller) — die
## bewusst schlankste Variante der vier NPCs, weil hier (anders als
## `QuestNPC`) kein Quest-Bus-Zugriff und (anders als `BankNPC`/`ShopNPC`)
## kein Panel-Open-Event nötig ist, nur reiner Anzeige-Text.
##
## BEWUSST NICHT TEIL DIESER RUNDE:
##   - Kein automatisches Ansprechen direkt nach dem Spawn (kein
##     erzwungener Dialog-Popup) — der NPC steht sichtbar in der Nähe,
##     Interaktion bleibt wie bei jedem anderen NPC freiwillig über
##     `InteractableComponent`. Ein "läuft aktiv auf den Spieler zu und
##     spricht ihn an"-Verhalten wäre eigene Bewegungslogik (siehe
##     `EnemyNPC`/`AnimalBase` für vorhandene Bewegungsmuster) und damit
##     eine deutlich größere Änderung als in dieser Runde gerechtfertigt.
##   - Kein Fortschritts-Tracking, ob ein Spieler den Guide schon
##     gesprochen hat — die Tipps sind bewusst wiederholbar (siehe
##     `TutorialGuideDialogController`), kein einmaliges Gate wie
##     `CharacterCreationService.has_seen_creation()`.
##   - Kein `NetworkBridge`-Dep (anders als `QuestNPC`, das ihn für das
##     TALK-Quest-Objective-Tracking über `report_domain_event()` braucht)
##     — hier gibt es kein Quest-Objective, das getrackt werden müsste, nur
##     lokal angezeigten Text.

const LOG_CAT := "TutorialGuideNPC"

@export var npc_display_name: String = "Wegweiser Mira"

var _dialog: TutorialGuideDialogController
var _dialog_label: Label3D
var _bus: IEventBus = null  ## Pflicht-Dep, injiziert via on_spawn(ctx) — für Tests: MockEventBus.

func _ready() -> void:
	name = "TutorialGuideNPC_" + npc_display_name.replace(" ", "_")
	add_to_group("npcs")

	_dialog_label = NPCVisualBuilder.build(self, npc_display_name)
	# TutorialGuideDialogController braucht IEventBus — wird in on_spawn()
	# erzeugt, da _bus erst dort garantiert gesetzt ist (analog QuestNPC).

	_build_collision()
	_setup_interactable()
	AppLogger.log_info("TutorialGuideNPC '%s' bereit." % npc_display_name, LOG_CAT)

# ─────────────────────────────────────────────
# Interaktion
# ─────────────────────────────────────────────

func _setup_interactable() -> void:
	var d := InteractableData.new()
	d.id           = "talk_tutorial_guide"
	d.label        = "Mit %s sprechen" % npc_display_name
	d.duration     = 0.3
	d.xp_type      = "none"
	d.xp_amount    = 0
	d.inspect_text = "%s. Kennt sich in Wildgrove aus und erklärt dir gerne, wie hier alles funktioniert." % npc_display_name
	var comp := InteractableComponent.new()
	comp.data = d
	add_child(comp)
	comp.interacted.connect(_on_interacted)

## Aufgerufen von InteractableComponent nach Abschluss der Rede-Interaktion.
## Kein Autoritäts-Guard nötig (anders als QuestNPC._on_interacted(), siehe
## dortiger BUG-26-Kommentar) — hier gibt es kein serverseitiges Tracking,
## das doppelt zählen könnte, nur lokal angezeigter Text. Läuft deshalb
## unverändert für JEDEN Peer, der interagiert (Host wie Client).
func _on_interacted(action_id: String, _peer_id: int) -> void:
	if action_id != "talk_tutorial_guide":
		return
	if not is_instance_valid(_dialog):
		AppLogger.log_warn("_on_interacted vor on_spawn() — _dialog nicht initialisiert.", LOG_CAT)
		return
	_dialog.on_interact()

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
			"TutorialGuideNPC.on_spawn(): kein IEventBus im EntityContext — Spawn ohne DI nicht unterstützt.",
			LOG_CAT
		)
		return
	_dialog = TutorialGuideDialogController.new(_dialog_label, get_tree(), _bus)

func on_despawn() -> void:
	pass
