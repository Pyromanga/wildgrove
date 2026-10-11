extends StaticBody3D
class_name BankNPC

## BankNPC — Stationärer Bankier-NPC (ADR-034). Exaktes Gegenstück zu
## ShopNPC (Round 88) — "Bank öffnen" ist wie "Shop öffnen" eine rein lokale
## UI-Aktion, die eigentlichen Ein-/Auszahlungen laufen netzwerksicher über
## BankService.request_*() (siehe dort).

const LOG_CAT := "BankNPC"

@export var npc_display_name: String = "Bankier Aurelius"

var _dialog_label: Label3D
var _bus: IEventBus = null

func _ready() -> void:
	name = "BankNPC_" + npc_display_name.replace(" ", "_")
	add_to_group("npcs")

	_dialog_label = NPCVisualBuilder.build(self, npc_display_name)
	_build_collision()
	_setup_interactable()
	AppLogger.log_info("BankNPC '%s' bereit." % npc_display_name, LOG_CAT)

func _setup_interactable() -> void:
	var d := InteractableData.new()
	d.id           = "talk_bank_npc"
	d.label        = "Bank öffnen (%s)" % npc_display_name
	d.duration     = 0.3
	d.xp_type      = "none"
	d.xp_amount    = 0
	d.inspect_text = "%s. Verwahrt Gold und Wertsachen sicher — was hier liegt, ist vor allem sicher." % npc_display_name
	var comp := InteractableComponent.new()
	comp.data = d
	add_child(comp)
	comp.interacted.connect(_on_interacted)

func _on_interacted(action_id: String, _peer_id: int) -> void:
	if action_id != "talk_bank_npc":
		return
	if _bus != null:
		_bus.ui().emit_bank_opened(npc_display_name)
	AppLogger.log_info("Bank-Panel angefordert (NPC '%s')." % npc_display_name, LOG_CAT)

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var sh  := CapsuleShape3D.new()
	sh.radius = 0.35
	sh.height = 1.5
	col.shape = sh
	col.position.y = 0.75
	add_child(col)

func on_spawn(_cfg: Dictionary, ctx: IEntityContext = null) -> void:
	if is_instance_valid(ctx) and ctx.has_method("get_event_bus"):
		_bus = ctx.get_event_bus() as IEventBus
	if _bus == null:
		AppLogger.log_error(
			"BankNPC.on_spawn(): kein IEventBus im EntityContext — Spawn ohne DI nicht unterstützt.",
			LOG_CAT
		)

func on_despawn() -> void:
	pass
