extends StaticBody3D
class_name ShopNPC

## ShopNPC — Stationärer Händler-NPC (Round 88).
##
## Deutlich einfacher als QuestNPC: keine Dialog-State-Machine, kein
## Quest-Tracking über die Autorität nötig — "Shop öffnen" ist eine rein
## lokale UI-Aktion (jeder Client zeigt sein eigenes Shop-Panel; die
## eigentlichen Kauf-/Verkauf-Transaktionen laufen separat über
## ShopService.request_buy_item()/request_sell_item(), die selbst schon
## netzwerksicher sind — siehe dort). Deshalb reicht ein einfacher
## `_bus.ui().emit_shop_opened()`-Aufruf ohne Autoritäts-Guard, anders als
## QuestNPC._on_interacted() (vergleiche dortigen BUG-26-Kommentar).

const LOG_CAT := "ShopNPC"

@export var npc_display_name: String = "Händler Toma"

var _dialog_label: Label3D
var _bus: IEventBus = null  ## Pflicht-Dep, injiziert via on_spawn(ctx).

func _ready() -> void:
	name = "ShopNPC_" + npc_display_name.replace(" ", "_")
	add_to_group("npcs")

	_dialog_label = NPCVisualBuilder.build(self, npc_display_name, _get_body_color())
	_build_collision()
	_setup_interactable()
	AppLogger.log_info("ShopNPC '%s' bereit." % npc_display_name, LOG_CAT)

# ─────────────────────────────────────────────
# Interaktion
# ─────────────────────────────────────────────

func _setup_interactable() -> void:
	var d := InteractableData.new()
	d.id           = "talk_shop_npc"
	d.label        = "Mit %s handeln" % npc_display_name
	d.duration     = 0.3
	d.xp_type      = "none"
	d.xp_amount    = 0
	d.inspect_text = "%s. Ein fahrender Händler mit Werkzeug und offenem Ohr für Beute." % npc_display_name
	var comp := InteractableComponent.new()
	comp.data = d
	add_child(comp)
	comp.interacted.connect(_on_interacted)

## Analog zu QuestNPC._get_body_color(): overridebar für Subklassen (z.B.
## ForesterNPC), damit unterschiedliche Händler-Rollen sich optisch
## unterscheiden lassen, ohne _ready() zu duplizieren.
func _get_body_color() -> Color:
	return Color(0.25, 0.40, 0.65)  # Default: Toma-Blau, unverändert.

func _on_interacted(action_id: String, _peer_id: int) -> void:
	if action_id != "talk_shop_npc":
		return
	if _bus != null:
		_bus.ui().emit_shop_opened(npc_display_name)
	AppLogger.log_info("Shop-Panel angefordert (NPC '%s')." % npc_display_name, LOG_CAT)

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
			"ShopNPC.on_spawn(): kein IEventBus im EntityContext — Spawn ohne DI nicht unterstützt.",
			LOG_CAT
		)

func on_despawn() -> void:
	pass
