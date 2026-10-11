extends SettlerNPC
class_name ProfessionNPC

## ProfessionNPC — Dorfbewohner mit Beruf (Katalog: ProfessionCatalog, Recherche: docs/professions.md).
##
## Baut auf SettlerNPC auf (Taschendiebstahl, Pet-Kampf, positionsbasierter Name) und ergänzt
## drei SKRIPTE, die alle aus dem Katalog kommen:
##   1. TAGESABLAUF  (WorkSchedule): Arbeit → Pause → Feierabend → Schlaf. Im Schlaf ist der NPC
##      unsichtbar, ohne Kollision und nicht ansprechbar (auch nicht beklaubar, Server prüft mit).
##   2. ARBEITSBEWEGUNG (WorkAnimator): bei der Arbeit kippt/wippt die Figur passend zum Beruf.
##   3. TAUSCH (ProfessionTrade): optional "Bring mir X → ich mache Y", serverseitig über StructureUse.
## Der "Untersuchen"-Text wechselt mit dem Zustand und streut alle ~15 s den "Wusstest du?"-Fakt ein.
##
## Alles Optische ist lokal wie NPCLook (nichts wird übertragen): jeder Peer liest die Uhrzeit aus
## seinem WorldService. Ohne Uhr (kein Kontext, Tests) arbeitet der NPC dauerhaft.
## Eigenes Skript je Beruf (XyzNPC.gd, nur _profession_id()), weil der MultiplayerSpawner
## Skriptpfad → type_id auflöst.

const ACTION_TRADE := "profession_trade"
const REFRESH_SEC: float = 1.0
const TEXT_ROTATE_MSEC: int = 15000

## Vornamen aus SettlerNPC.FIRST_NAMES, die weiblich gelesen werden → "Töpferin" statt "Töpfer".
const FEMALE_NAMES: Array[String] = [
	"Berta", "Dörte", "Frida", "Hanne", "Ida", "Katja", "Marta", "Olga", "Rike", "Tilda", "Vera", "Wiebke", "Zora",
]

var _profession: Dictionary = {}
var _female: bool = false
var _state: int = WorkSchedule.State.WORK
var _hour_override: float = -1.0
var _refresh_accum: float = 0.0
var _animator: WorkAnimator = null
var _trade_comp: InteractableComponent = null
var _trade_def: BuildPieceDefinition = null
var _last_trade_msec: Dictionary = {}
var _saved_layer: int = 1

signal state_changed(new_state: int)

## Pflicht-Override jeder Berufs-Subklasse.
func _profession_id() -> String:
	return ""

func _init() -> void:
	_profession = ProfessionCatalog.get_profession(_profession_id())

# ── SettlerNPC-Hooks ─────────────────────────

func _role_title() -> String:
	return String(_profession.get("title_m", "Handwerker"))

func _compose_name(first_name: String) -> String:
	_female = FEMALE_NAMES.has(first_name)
	var title: String = String(_profession.get("title_f" if _female else "title_m", "Handwerker"))
	return "%s %s" % [title, first_name]

func _role_gold() -> Vector2i:
	return _profession.get("gold", Vector2i(5, 40))

func _role_lines() -> Array[String]:
	var out: Array[String] = []
	for l in (_profession.get("lines", []) as Array):
		out.append(String(l))
	return out

func _get_body_color() -> Color:
	return _profession.get("body_color", NPCLook.DEFAULT_BODY_COLOR)

func _npc_look_overrides() -> Dictionary:
	return {"sex": "female" if _female else "male"}

func _battle_bias_type() -> int:
	match String(_profession.get("battle", "")):
		"hoofed": return PetBattleTypes.Type.HOOFED
		"aqua": return PetBattleTypes.Type.AQUA
		_: return -1

# ── Lebenszyklus ─────────────────────────────

func _ready() -> void:
	super._ready()
	_saved_layer = collision_layer
	_animator = WorkAnimator.new()
	_animator.name = "WorkAnimator"
	_animator.style = String(_profession.get("work", "stir"))
	_animator.phase_offset = float(absi(hash(name)) % 1000) / 100.0
	add_child(_animator)
	_setup_trade()
	_refresh_state(true)

func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_SEC:
		_refresh_accum = 0.0
		_refresh_state(false)

## Test-/Admin-Hook: feste Uhrzeit statt WorldService (-1 = zurück zur Weltuhr).
func set_hour_override(hour: float) -> void:
	_hour_override = hour
	_refresh_state(false)

func get_state() -> int:
	return _state

func get_profession() -> Dictionary:
	return _profession

## Aktuelle Spielstunde oder -1, wenn es keine Uhr gibt.
func _current_hour() -> float:
	if _hour_override >= 0.0:
		return _hour_override
	if is_instance_valid(_ctx):
		var world: WorldService = _ctx.get_world()
		if is_instance_valid(world):
			return world.day_time
	return -1.0

func _refresh_state(force: bool) -> void:
	var hour: float = _current_hour()
	var new_state: int = WorkSchedule.State.WORK if hour < 0.0 else WorkSchedule.state_at(hour, _profession["shift"])
	var changed: bool = new_state != _state
	if changed or force:
		_state = new_state
		_apply_state()
		if changed:
			state_changed.emit(_state)
	_refresh_texts()

func _apply_state() -> void:
	var asleep: bool = _state == WorkSchedule.State.SLEEP
	visible = not asleep
	collision_layer = 0 if asleep else _saved_layer
	for child in get_children():
		if child is InteractableComponent:
			(child as InteractableComponent).set_enabled(not asleep)
	if is_instance_valid(_animator):
		_animator.active = _state == WorkSchedule.State.WORK

# ── Texte ────────────────────────────────────

## Text für "Untersuchen": Alltagssatz (stabil je NPC) bzw. alle ~15 s der Fakt, plus Zustand.
func build_text(rotation_step: int) -> String:
	var lines: Array[String] = _role_lines()
	var fact: String = String(_profession.get("fact", ""))
	var h: int = absi(hash(Vector2i(roundi(position.x * 10.0), roundi(position.z * 10.0))))
	var pool: Array[String] = lines.duplicate()
	if not fact.is_empty():
		pool.append(fact)
	var line: String = pool[(h + rotation_step) % pool.size()] if not pool.is_empty() else ""
	var status: String
	match _state:
		WorkSchedule.State.WORK: status = String(_profession.get("work_verb", "arbeitet"))
		WorkSchedule.State.BREAK: status = "macht gerade Pause"
		_: status = "hat Feierabend"
	return "%s (%s): \"%s\"" % [npc_display_name, status, line]

func _refresh_texts() -> void:
	var text: String = build_text(int(Time.get_ticks_msec() / TEXT_ROTATE_MSEC))
	for child in get_children():
		if child is InteractableComponent and (child as InteractableComponent).data != null:
			if child != _trade_comp:
				(child as InteractableComponent).data.inspect_text = text

# ── Interaktion ──────────────────────────────

func _on_interacted(action_id: String, peer_id: int) -> void:
	if _state == WorkSchedule.State.SLEEP:
		return
	if action_id == ACTION_TRADE:
		_on_trade_interacted(peer_id)
		return
	super._on_interacted(action_id, peer_id)

func _setup_trade() -> void:
	var trade: Dictionary = _profession.get("trade", {})
	if trade.is_empty():
		return
	_trade_def = ProfessionTrade.make_def(trade, String(_profession["id"]))
	var d := InteractableData.new()
	d.id = ACTION_TRADE
	d.label = "%s (%s)" % [String(trade["label"]), npc_display_name]
	d.duration = float(trade.get("duration", 2.0))
	d.xp_type = "none"
	d.xp_amount = 0
	d.inspect_text = "%s: \"%s\"" % [npc_display_name, String(trade.get("offer", ""))]
	_trade_comp = InteractableComponent.new()
	_trade_comp.name = "ProfessionTradeInteractable"
	_trade_comp.data = d
	add_child(_trade_comp)
	_trade_comp.interacted.connect(_on_interacted)
	if is_instance_valid(_ctx):
		_trade_comp.inject_context(_ctx)

## Wie BuildPiece._on_structure_used(): Rückmeldung nur auf dem Peer des Spielers (Vorprüfung aus dem
## lokalen Inventar), Wirkung nur auf der Autorität (StructureUse inkl. Cooldown/Inventarplatz).
func _on_trade_interacted(peer_id: int) -> void:
	if _trade_def == null or not is_instance_valid(_ctx):
		return
	var network: NetworkBridge = _ctx.get_network_bridge()
	var player_id: String = network.get_player_id_for_peer(peer_id) if is_instance_valid(network) else ""
	var bus: IEventBus = _ctx.get_event_bus()
	var inventory: InventorySystem = _ctx.get_inventory()
	var is_local: bool = peer_id == _ctx.get_local_peer_id()
	if is_local:
		var hint := StructureUse.check(_trade_def, player_id, inventory)
		if not hint.is_empty() and bus != null:
			bus.ui().emit_notification_requested(StructureUse.reason_text(hint, _trade_def, _ctx.get_data()))
			return
	if not is_multiplayer_authority():
		return
	var now := Time.get_ticks_msec()
	var reason := StructureUse.use(_trade_def, player_id, inventory, int(_last_trade_msec.get(player_id, 0)), now)
	if reason.is_empty():
		_last_trade_msec[player_id] = now
		if is_local and bus != null:
			bus.ui().emit_floating_loot_text_requested("🛠 %s" % _trade_def.use_label)
	elif is_local and bus != null:
		bus.ui().emit_notification_requested(StructureUse.reason_text(reason, _trade_def, _ctx.get_data()))

func on_spawn(cfg: Dictionary = {}, ctx: IEntityContext = null) -> void:
	super.on_spawn(cfg, ctx)
	if is_instance_valid(ctx) and is_instance_valid(_trade_comp):
		_trade_comp.inject_context(ctx)
	_refresh_state(true)
