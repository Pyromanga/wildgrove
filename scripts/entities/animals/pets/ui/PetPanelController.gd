class_name PetPanelController
extends Node

## PetPanelController — verbindet PetPanelVisuals mit WorldService.get_pets_for_peer()
## (Lesen) und PetComponent.set_abilities() (Schreiben, siehe dortiger Kommentar
## zum Autoritäts-Guard). Kein eigener Zustand über eine Refresh-Runde hinaus —
## die "Wahrheit" bleibt immer bei den PetComponent-Instanzen selbst.
##
## REFRESH-STRATEGIE (zwei Ebenen):
##
## 1. STRUKTUR (welche Pets gibt es): Refresh bei jedem Öffnen des Panels UND
##    sofort, wenn ein Pet entsteht/verschwindet. BUGFIX ("Wenn ich neue Pets
##    fange, updatet sich das Menü nicht sofort, ich muss es erst zu- und wieder
##    aufmachen"): vorher gab es NUR den Refresh beim Öffnen — ein bei offenem
##    Panel gefangenes Pet tauchte erst beim nächsten Öffnen auf. Jetzt hört der
##    Controller über IEventBus.world() auf entity_spawned/entity_despawned
##    (type_id == "pet"). Diese Events laufen für JEDEN Spawn-Pfad durch
##    EntityOrchestrator.spawn_entity()/despawn_entity(): frisch gefangenes Tier
##    (AnimalCatcher), Save-Wiederherstellung (PetRestorer) und Netzwerk-Kopie
##    (NetworkBridge._rpc_spawn_remote_pet). Der Refresh läuft per call_deferred()
##    und ist entprellt (mehrere Events im selben Frame → ein Refresh):
##    spawn_entity() emittiert zwar NACH on_spawn(), despawn_entity() aber nach
##    queue_free() — das Pet hängt dann noch bis Frame-Ende in der Gruppe "pets"
##    und wird deshalb zusätzlich über is_queued_for_deletion() ausgefiltert.
##
## 2. STATUS (was tut ein Pet gerade): kein Event dafür — ein Timer (STATUS_INTERVAL)
##    fragt, solange das Panel sichtbar ist, PetComponent.get_current_activity()
##    ab und reicht nur Status/Filter an die Visuals weiter (refresh_status()),
##    ohne die Kacheln neu zu bauen.

## Wie oft der "was tut es gerade"-Status aktualisiert wird, solange das Panel
## offen ist (Sekunden).
const STATUS_INTERVAL := 1.0

var _visuals: PetPanelVisuals
var _ctx: IUIContext
var _world_events: WorldEvents = null
var _status_timer: Timer
var _refresh_pending: bool = false

func setup(visuals: PetPanelVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx     = ctx
	_visuals.ability_toggled.connect(_on_ability_toggled)
	_visuals.panel.visibility_changed.connect(_on_visibility_changed)

	_status_timer = Timer.new()
	_status_timer.name = "PetStatusTimer"
	_status_timer.wait_time = STATUS_INTERVAL
	_status_timer.one_shot = false
	_status_timer.timeout.connect(_on_status_tick)
	add_child(_status_timer)

	# Kein Bus (z.B. Tests ohne Event-Bus) → nur Refresh beim Öffnen, wie bisher.
	var bus: IEventBus = _ctx.bus() if is_instance_valid(_ctx) else null
	if is_instance_valid(bus):
		_world_events = bus.world()
		_world_events.entity_spawned.connect(_on_entity_spawned)
		_world_events.entity_despawned.connect(_on_entity_despawned)

	refresh()

func _exit_tree() -> void:
	if is_instance_valid(_world_events):
		if _world_events.entity_spawned.is_connected(_on_entity_spawned):
			_world_events.entity_spawned.disconnect(_on_entity_spawned)
		if _world_events.entity_despawned.is_connected(_on_entity_despawned):
			_world_events.entity_despawned.disconnect(_on_entity_despawned)

func _on_visibility_changed() -> void:
	if _visuals.panel.visible:
		refresh()
		if is_instance_valid(_status_timer) and _status_timer.is_inside_tree():
			_status_timer.start()
	elif is_instance_valid(_status_timer) and not _status_timer.is_stopped():
		_status_timer.stop()

func _on_entity_spawned(type_id: String, _entity: Node3D, _position: Vector3) -> void:
	if type_id == "pet":
		_schedule_refresh()

func _on_entity_despawned(type_id: String, _uuid: String, _position: Vector3) -> void:
	if type_id == "pet":
		_schedule_refresh()

## Entprellt: beliebig viele Aufrufe im selben Frame → genau ein refresh().
func _schedule_refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	_run_scheduled_refresh.call_deferred()

func _run_scheduled_refresh() -> void:
	_refresh_pending = false
	refresh()

func _on_status_tick() -> void:
	if not is_instance_valid(_visuals) or not _visuals.panel.visible:
		return
	_visuals.refresh_status(_collect_pet_rows())

## Öffentlich (wie InventoryUIController.refresh()) — HUDBuilder ruft das einmal
## direkt nach dem Bauen auf, damit das Panel auch ohne vorheriges Öffnen/
## Schließen einen korrekten Erststand hätte, falls es je initial sichtbar wäre.
func refresh() -> void:
	if not is_instance_valid(_visuals):
		return
	_visuals.set_pets(_collect_pet_rows())

func _collect_pet_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var world: WorldService = _ctx.get_world() if is_instance_valid(_ctx) else null
	if not is_instance_valid(world):
		return rows
	var peer_id := _ctx.get_local_peer_id()
	for pet in world.get_pets_for_peer(peer_id):
		# Gerade despawnte Pets hängen bis Frame-Ende noch in der Gruppe "pets"
		# (siehe Klassenkommentar) — nicht mehr anzeigen.
		if not is_instance_valid(pet) or pet.is_queued_for_deletion():
			continue
		var activity: Dictionary = pet.get_current_activity()
		var progress: Dictionary = pet.get_level_progress()
		rows.append({
			"id":         pet.get_instance_id(),
			"name":       pet.get_pet_name(),
			"abilities":  pet.get_abilities(),
			"appearance": pet.get_appearance(),
			"activity":   String(activity.get("ability", "")),
			"acting":     bool(activity.get("acting", false)),
			# FEATURE (Pet-XP/Level, siehe PetLeveling):
			"level":          pet.get_level(),
			"xp_into_level":  int(progress.get("xp_into_level", 0)),
			"xp_for_next":    int(progress.get("xp_for_next", -1)),
		})
	return rows

func _on_ability_toggled(pet_instance_id: int, ability_id: String, enabled: bool) -> void:
	var pet := instance_from_id(pet_instance_id)
	if not is_instance_valid(pet) or not (pet is PetComponent):
		# Pet wurde zwischen Panel-Öffnen und Tap despawnt (gestorben/entfernt) —
		# kein Fehlerfall, nur zu spät. Der despawn-Event-Refresh räumt die Kachel
		# automatisch weg.
		AppLogger.log_warn(
			"Pet-Menü: Toggle auf nicht mehr existentes Pet (instance_id %d) ignoriert." % pet_instance_id,
			"PetPanel"
		)
		return
	var current := (pet as PetComponent).get_abilities()
	if enabled and not current.has(ability_id):
		current.append(ability_id)
	elif not enabled:
		current.erase(ability_id)
	(pet as PetComponent).set_abilities(current)
