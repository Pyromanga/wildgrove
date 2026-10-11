extends StaticBody3D
class_name Gravestone

## Gravestone — Welt-Entität für ADR-037 (PvE-Tod-Loot, Grab-Hybrid-Timer).
## Serverautoritativ gespawnt über WorldService (analog BankNPC/ShopNPC-
## Spawn-Konvention), von DeathLootService.handle_pve_death() befüllt.
##
## PHASE OHNE EIGENES ENUM/FLAG (siehe ADR-037 "Mitigationen"): die aktuelle
## Phase (Personal Loot / Free-for-all / bereits despawnt) wird ausschließlich
## aus dem Vergleich `now` gegen `_personal_loot_until`/`_despawn_at` berechnet
## — kein separater State, der aus dem Gleichschritt geraten könnte.
##
## EINE INTERAKTION = ALLES PLÜNDERN: anders als z.B. eine Bank (viele
## Ein-/Auszahlungen über die Zeit) wird ein Grab in EINEM Zug komplett
## geplündert (Gold + alle Items) und despawnt danach sofort — bewusst
## einfach gehalten, keine Teil-Plünderung/Item-Auswahl-UI nötig.
##
## AUTORITÄTS-MUSTER: identisch zu HarvestableEntity._on_interacted() — läuft
## über InteractableComponent._handle_completion()'s RPC-Weiterleitung, die
## eigentliche Wirkung ausschließlich auf der Autorität (is_multiplayer_authority()-
## Guard). Kein request_*()/on_*_confirmed()-Split nötig, weil es (wie bei
## HarvestableEntity) bereits über das bestehende Interaktionssystem (ADR-020)
## netzwerksicher geroutet wird.

const LOG_CAT := "Gravestone"

var owner_player_id: String = ""
var _gold: int = 0
var _items: Array = []  ## [{item_id: String, quantity: int}]
var _personal_loot_until: float = 0.0
var _despawn_at: float = 0.0

var _interactable_comp: InteractableComponent = null
var _ctx: IEntityContext = null
var _despawn_timer: SceneTreeTimer = null
var _looted: bool = false  ## verhindert doppeltes Plündern in derselben Frame-Lücke

func _ready() -> void:
	# BUGFIX (2026-09-17, "Dinge werden nicht gesynct"): unconditional
	# überschrieben — exakt derselbe Bug wie bei AnimalBase (siehe dortiger
	# Kommentar). Gravestone wird über EntityOrchestrator.spawn_entity()
	# gespawnt und bekommt dort bereits einen deterministischen, positions-
	# basierten Namen — der wurde hier bisher IMMER durch einen pro Prozess
	# unterschiedlichen get_instance_id()-Namen ersetzt.
	if name == get_class() or name.begins_with("@"):
		name = "Gravestone_%d" % (get_instance_id() % 9999)
	set_multiplayer_authority(1)
	add_to_group("interactable")
	_build_collision()
	_setup_interactable()

## Aufgerufen von EntityOrchestrator NACH add_child() und NACH _ready().
## config: siehe DeathLootService.handle_pve_death() für die genaue Form.
func on_spawn(config: Dictionary = {}, ctx: IEntityContext = null) -> void:
	_ctx = ctx
	owner_player_id      = config.get("owner_player_id", "")
	_gold                = int(config.get("gold", 0))
	_items                = config.get("items", [])
	_personal_loot_until = float(config.get("personal_loot_until", 0.0))
	_despawn_at          = float(config.get("despawn_at", 0.0))
	_looted              = false

	if is_instance_valid(_interactable_comp):
		_interactable_comp.inject_context(_ctx)

	_clear_visuals()
	_build_visuals()

	# Despawn-Timer nur auf der Autorität — auf Clients existiert das Grab nur
	# als repliziertes Darstellungsobjekt, kein eigener Despawn-Auslöser.
	if is_multiplayer_authority():
		_schedule_despawn()

	AppLogger.log_info(
		"Gravestone gespawnt für '%s' (%d Gold, %d Item-Stacks)." % [owner_player_id, _gold, _items.size()],
		LOG_CAT
	)

func on_despawn() -> void:
	if is_instance_valid(_interactable_comp):
		_interactable_comp.disconnect_world_events()
	if is_instance_valid(_despawn_timer) and _despawn_timer.timeout.is_connected(_request_despawn):
		_despawn_timer.timeout.disconnect(_request_despawn)
	_despawn_timer = null

# ─────────────────────────────────────────────
# Despawn-Timer (ADR-037: Phase 3)
# ─────────────────────────────────────────────

func _schedule_despawn() -> void:
	var remaining := _despawn_at - Time.get_unix_time_from_system()
	if remaining <= 0.0:
		# Grab wurde mit bereits abgelaufenem despawn_at gespawnt (z.B. nach
		# einem Server-Neustart mit altem Save-Stand, falls Gräber jemals
		# persistiert würden — aktuell nicht der Fall, siehe DeathLootService
		# Klassenkommentar "NICHT PERSISTIERT"). Sofort despawnen statt mit
		# einem negativen/0-Timer zu warten.
		_request_despawn()
		return
	_despawn_timer = get_tree().create_timer(remaining)
	_despawn_timer.timeout.connect(_request_despawn)

func _request_despawn() -> void:
	var uuid: String = get_meta("entity_uuid", "")
	var bus: IEventBus = _ctx.get_event_bus() if is_instance_valid(_ctx) else null
	# BUGFIX (2026-09-17, "Dinge werden nicht gesynct"): dieselbe Lücke wie bei
	# EnemyNPC._die() und HarvestableEntity._on_interacted() — despawnte bisher
	# nur lokal auf der Autorität über den EventBus, kein anderer Peer erfuhr
	# je davon (gilt für BEIDE Auslöser von _request_despawn(): Timer-Ablauf
	# UND fertig geplündert).
	var network: NetworkBridge = _ctx.get_network_bridge() if is_instance_valid(_ctx) else null
	if is_instance_valid(network):
		network.broadcast_to_all_peers("entity_despawned", {"name": name})
	else:
		AppLogger.log_warn(
			"_request_despawn(): kein NetworkBridge verfügbar — Despawn von '%s' wird anderen Peers nicht gemeldet." % name,
			LOG_CAT
		)
	if not uuid.is_empty() and bus != null:
		bus.world().emit_entity_despawn_requested(uuid)
	else:
		AppLogger.log_warn("Kein IEventBus im Context — direkte queue_free() statt Despawn-Request.", LOG_CAT)
		on_despawn()
		queue_free()

# ─────────────────────────────────────────────
# Interaktion (ADR-037: Phase 1/2 — Plündern)
# ─────────────────────────────────────────────

func _setup_interactable() -> void:
	var d := InteractableData.new()
	d.id           = "loot_gravestone"
	d.label        = "Grab plündern"
	d.duration     = 0.5
	d.xp_type      = "none"
	d.xp_amount    = 0
	d.inspect_text = "Ein frisches Grab. Was hier liegt, wartet auf jemanden, der es findet."
	_interactable_comp = InteractableComponent.new()
	_interactable_comp.data = d
	add_child(_interactable_comp)
	_interactable_comp.interacted.connect(_on_interacted)

## Autoritäts-Gate + Phase-Check identisch im Prinzip zu
## HarvestableEntity._on_interacted() — läuft ausschließlich auf der
## Autorität (siehe dortiger Kommentar für die volle Begründung des
## RPC-Weiterleitungswegs).
func _on_interacted(action_id: String, peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	if action_id != "loot_gravestone" or _looted:
		return

	var network: NetworkBridge = _ctx.get_network_bridge() if is_instance_valid(_ctx) else null
	var looter_player_id := network.get_player_id_for_peer(peer_id) if is_instance_valid(network) else ""
	if looter_player_id.is_empty():
		AppLogger.log_warn("_on_interacted(): player_id-Übersetzung fehlgeschlagen — Plündern verweigert.", LOG_CAT)
		return

	# ADR-037 Phase-Check: rein aus den beiden Timestamps abgeleitet, kein
	# separates Enum. Vor personal_loot_until darf NUR der Besitzer plündern.
	var now := Time.get_unix_time_from_system()
	if now < _personal_loot_until and looter_player_id != owner_player_id:
		AppLogger.log_info(
			"'%s' versucht Personal-Loot-Grab von '%s' zu plündern — verweigert (noch %.0fs)."
			% [looter_player_id, owner_player_id, _personal_loot_until - now],
			LOG_CAT
		)
		return

	_looted = true
	var currency: CurrencyService  = _ctx.get_currency()  if is_instance_valid(_ctx) else null
	var inventory: InventorySystem = _ctx.get_inventory() if is_instance_valid(_ctx) else null

	if _gold > 0 and is_instance_valid(currency):
		currency.request_add_gold(looter_player_id, _gold)
	if is_instance_valid(inventory):
		for entry in _items:
			var item_id: String = entry.get("item_id", "")
			var qty: int         = entry.get("quantity", 0)
			if not item_id.is_empty() and qty > 0:
				inventory.on_item_add_confirmed(item_id, qty, looter_player_id)

	AppLogger.log_info(
		"Grab von '%s' geplündert durch '%s' (%d Gold, %d Item-Stacks)."
		% [owner_player_id, looter_player_id, _gold, _items.size()],
		LOG_CAT
	)
	_request_despawn()

# ─────────────────────────────────────────────
# Visuals — einfacher Platzhalter (analog HarvestableEntity._add_placeholder_box())
# ─────────────────────────────────────────────

## Pool-Reuse-Guard (siehe HarvestableEntity._clear_visuals()-Kommentar für
## dasselbe Muster): sowohl _interactable_comp ALS AUCH die CollisionShape3D
## werden übersprungen. _ready() feuert bei einem aus dem EntityPool
## wiederverwendeten Node NICHT erneut (Godot ruft _ready() nur beim ersten
## Tree-Eintritt) — die in _ready() einmalig gebaute Kollision würde sonst
## beim zweiten on_spawn() gelöscht und nie wieder aufgebaut.
func _clear_visuals() -> void:
	for child in get_children():
		if child == _interactable_comp or child is CollisionShape3D:
			continue
		remove_child(child)
		child.free()

func _build_visuals() -> void:
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.55, 0.55, 0.58)
	var stone_mesh := BoxMesh.new()
	stone_mesh.size = Vector3(0.6, 0.9, 0.15)
	var stone_mi := MeshInstance3D.new()
	stone_mi.mesh = stone_mesh
	stone_mi.material_override = stone_mat
	stone_mi.position.y = 0.45
	add_child(stone_mi)

	var label := Label3D.new()
	label.text      = "Grab"
	label.font_size = 40
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate  = Color(0.85, 0.85, 0.9)
	label.position.y = 1.1
	add_child(label)

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var sh  := BoxShape3D.new()
	sh.size = Vector3(0.6, 0.9, 0.15)
	col.shape = sh
	col.position.y = 0.45
	add_child(col)
