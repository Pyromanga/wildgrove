extends Node3D
class_name InteractableComponent

## InteractableComponent — Koppelt ein World-Objekt an das Interaktions-System.
##
## Verantwortung:
##   - Gruppe "interactable" + Meta "interactable_components" (Array, ADR-035)
##     auf Parent setzen
##   - Label3D + 3D-Fortschrittsbar verwalten
##   - Interaktion via InteractionExecutor ausführen
##   - Completion-Ergebnisse nur via EventBus weitergeben
##
## Delegiert Nähe-Erkennung → ProximityDetector (eigenes Signal-basiertes Node)
##
##   inject_context() empfängt IEntityContext von der Parent-Entity.
##   Falls inject_context() nie aufgerufen wird, bricht start_default_interaction()
##   mit einem log_error() hart ab (kein stiller Fallback, keine Interaktion ohne DI).
##
##   Emittiert NUR via EventBus — keine direkten Service-Calls.
##
## G-02: ProximityDetector übergibt jetzt den Player-Node in player_entered/exited.
##   _is_player_target() nutzt den nächsten Spieler relativ zu dieser Interactable
##   statt get_first_node_in_group("player") — korrekt bei zwei Spielern.

@export var data: InteractableData
@export var detection_radius: float = 3.0

## Emitted when an interaction completes. The parent entity connects to this
## in _ready() — the component never calls get_parent() directly.
## ADR-015 / MIGRATION-015 Phase 4: peer_id ist Pflichtparameter, kein
## Default — jeder Consumer muss sich bewusst entscheiden, was er damit tut
## (verwenden oder mit _peer_id-Konvention explizit als ungenutzt markieren),
## statt sich hinter einem stillen Fallback zu verstecken.
signal interacted(action_id: String, peer_id: int)

## Emittiert, wenn die Aktion dieser Komponente für den Spieler beginnt, der sie als Ziel hat
## (gleiche Bedingung wie die 3D-Fortschrittsbar) — Haken für Animationen, die zur Dauer der
## Interaktion passen sollen (z.B. Brunnen-Eimer). Rein visuell, nur auf dem handelnden Peer.
signal progress_started(action_id: String, duration: float)

## Abschaltbar (z.B. "Abreißen" nur im Bau-Modus, siehe BuildPiece): aus → keine Aktionen, kein
## Label. Standard an, alle bisherigen Komponenten unverändert.
var enabled: bool = true

const LOG_CAT := "Interactable"

var _bar_3d:  Factory3D.Bar3D = null
var _label:   Label3D         = null
var _ctx:     IEntityContext   = null   ## injiziert von Parent via inject_context()
var _world_events_connected: bool = false

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	assert(data != null, "InteractableComponent braucht InteractableData! (data == null)")

	get_parent().add_to_group("interactable")
	# ADR-035: mehrere InteractableComponents pro Parent-Node möglich (z.B.
	# Player: "attack_player" + "trade_request", siehe PlayerAttack.gd/
	# PlayerTrade.gd) — Meta ist deshalb eine Liste, kein Einzel-Slot mehr
	# (der bis Round 88 pro Node genau EINE InteractableComponent annahm und
	# eine zweite stillschweigend überschrieben hätte, siehe get_actions()-
	# Konsumenten Player.get_context_actions()/WorldService._max_interaction_range_for(),
	# die jetzt beide über die volle Liste iterieren).
	var siblings: Array = get_parent().get_meta("interactable_components", [])
	siblings = siblings.duplicate()
	siblings.append(self)
	get_parent().set_meta("interactable_components", siblings)

	_setup_label()
	# Bar-Setup + World-Events erfolgen in inject_context() sobald _ctx verfügbar ist;
	# hier nur wenn _ctx bereits gesetzt (Szenen-Init-Reihenfolge-Workaround).
	if is_instance_valid(_ctx):
		_setup_bar()
		_connect_world_events()
	_setup_proximity()
	# _connect_world_events() läuft in inject_context() — _ctx (und damit der
	# injizierte IEventBus) ist erst dort garantiert gesetzt.

	AppLogger.log_info(
		"Bereit: '%s' | Parent: '%s' | Radius: %.1fm"
		% [data.label, get_parent().name, detection_radius],
		LOG_CAT
	)

## Wird von der Parent-Entity in on_spawn() aufgerufen sobald der IEntityContext vorliegt.
## Ermöglicht Factory3D-Zugriff ohne Services-Locator.
func inject_context(ctx: IEntityContext) -> void:
	_ctx = ctx
	# Bar jetzt erst erstellen — Factory3D ist über ctx verfügbar.
	if not is_instance_valid(_bar_3d):
		_setup_bar()
	if not _world_events_connected:
		_connect_world_events()

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Gibt alle verfügbaren Aktionen zurück. Aufgerufen von Player.get_context_actions().
func get_actions() -> Array[InteractableAction]:
	var actions: Array[InteractableAction] = []
	if not enabled:
		return actions

	var action := InteractableAction.new(data.id, data.label)
	action.duration     = data.duration
	action.xp_type      = data.xp_type
	action.xp_amount    = data.xp_amount
	action.loot_table   = data.loot_table
	action.yield_stat_id = data.yield_stat_id
	action.speed_stat_id = data.speed_stat_id
	action.inspect_text = data.inspect_text
	action.on_complete  = _handle_completion
	actions.append(action)

	var inspect_text := data.inspect_text if not data.inspect_text.is_empty() \
		else "%s — nichts Besonderes fällt auf." % data.label
	var inspect := InteractableAction.new(data.id + "_inspect", "Untersuchen")
	inspect.duration    = 0.0
	inspect.xp_type     = "none"
	inspect.xp_amount   = 0
	inspect.inspect_text = inspect_text
	inspect.on_complete  = func(_peer_id: int) -> void:
		if is_instance_valid(_ctx) and _ctx.get_event_bus() != null:
			_ctx.get_event_bus().world().emit_interaction_reward_text(inspect_text)
		else:
			AppLogger.log_warn("get_actions(): kein IEventBus — inspect_text nicht emittiert.", LOG_CAT)
	actions.append(inspect)

	AppLogger.log_debug(
		"get_actions(): '%s' — %d Aktionen." % [data.label, actions.size()], LOG_CAT
	)
	return actions

## Startet die erste verfügbare Aktion via InteractionExecutor.
## Nutzt ctx.get_interaction_executor() — setzt inject_context() voraus.
## In Produktion immer erfüllt (EntityOrchestrator ruft inject_context() immer auf).
## Ohne ctx wird ein klarer Fehler geloggt statt auf Services-Locator zurückzufallen.
func start_default_interaction() -> void:
	if not is_instance_valid(_ctx):
		AppLogger.log_error(
			"start_default_interaction: inject_context() wurde nie aufgerufen — "
			+ "Entity ohne Orchestrator gespawnt? Interaktion abgebrochen.",
			LOG_CAT
		)
		return

	var executor := _ctx.get_interaction_executor()

	if not is_instance_valid(executor):
		AppLogger.log_error("InteractionExecutor-Service fehlt!", LOG_CAT)
		return

	var actions := get_actions()
	if actions.is_empty():
		return
	executor.execute_action(actions[0])

# ─────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────

## Aktualisiert das 3D-Label nach einem Wechsel von `data` (z.B. DigFind: Art erst beim Spawn bekannt).
func set_enabled(on: bool) -> void:
	enabled = on
	if not on and is_instance_valid(_label):
		_label.visible = false

func refresh_label() -> void:
	if is_instance_valid(_label):
		_label.text = data.label

func _setup_label() -> void:
	_label           = Label3D.new()
	_label.text      = data.label
	_label.position  = Vector3(0.0, 2.5, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.visible   = false
	add_child(_label)

func _setup_bar() -> void:
	# Factory3D über IEntityContext.
	var factory: Factory3D = _ctx.get_factory3d() if is_instance_valid(_ctx) else null
	if is_instance_valid(factory):
		_bar_3d = factory.create_3d_bar(self)
	else:
		AppLogger.log_warn("Factory3D nicht verfügbar — 3D-Fortschrittsbar fehlt.", LOG_CAT)

func _setup_proximity() -> void:
	var detector := ProximityDetector.new(detection_radius)
	add_child(detector)
	detector.player_entered.connect(_on_player_entered)
	detector.player_exited.connect(_on_player_exited)
	AppLogger.log_debug("ProximityDetector erstellt (Radius: %.1fm)." % detection_radius, LOG_CAT)

func _connect_world_events() -> void:
	if not is_instance_valid(_ctx):
		AppLogger.log_error(
			"_connect_world_events: kein _ctx — inject_context() wurde nicht aufgerufen.",
			LOG_CAT
		)
		return
	var bus: IEventBus = _ctx.get_event_bus()
	if bus == null:
		AppLogger.log_error("_connect_world_events: kein IEventBus im Context.", LOG_CAT)
		return
	bus.world().interaction_started.connect(_on_interaction_started)
	bus.world().interaction_finished.connect(_on_interaction_ended)
	bus.world().interaction_cancelled.connect(_on_interaction_ended)
	_world_events_connected = true

## Aufgerufen von HarvestableEntity.on_despawn() (Pool-Rückgabe). Trennt die
## globalen EventBus-Connections — ohne dies bleibt eine gepoolte, nicht mehr
## im Tree befindliche Instanz für IMMER an interaction_started/finished/
## cancelled angehängt und reagiert (fehlerhaft) auf Interaktionen anderer
## Entities. inject_context() beim nächsten Pool-Reuse verbindet sauber neu,
## da _world_events_connected hier zurückgesetzt wird.
func disconnect_world_events() -> void:
	if not is_instance_valid(_ctx):
		return
	var bus: IEventBus = _ctx.get_event_bus()
	if bus == null:
		return
	if bus.world().interaction_started.is_connected(_on_interaction_started):
		bus.world().interaction_started.disconnect(_on_interaction_started)
	if bus.world().interaction_finished.is_connected(_on_interaction_ended):
		bus.world().interaction_finished.disconnect(_on_interaction_ended)
	if bus.world().interaction_cancelled.is_connected(_on_interaction_ended):
		bus.world().interaction_cancelled.disconnect(_on_interaction_ended)
	_world_events_connected = false

# ─────────────────────────────────────────────
# Proximity
# ─────────────────────────────────────────────

## G-02: player-Parameter von ProximityDetector — welcher Spieler nah ist.
func _on_player_entered(_player: Node3D) -> void:
	if enabled and is_instance_valid(_label):
		_label.visible = true
	AppLogger.log_info(
		"Spieler in Reichweite: '%s' (%.1fm)." % [data.label, detection_radius], LOG_CAT
	)

## G-02: player-Parameter von ProximityDetector.
func _on_player_exited(_player: Node3D) -> void:
	if is_instance_valid(_label):
		_label.visible = false
	AppLogger.log_info("Spieler außer Reichweite: '%s'." % data.label, LOG_CAT)

# ─────────────────────────────────────────────
# Completion
# ─────────────────────────────────────────────

## peer_id: Pflichtparameter, kommt von InteractionExecutor über
## InteractableAction.peer_id (die Identität des ausführenden Spielers,
## nicht die des Interactables selbst). Keine Default — InteractionExecutor
## ist der einzige Aufrufer und liefert ihn immer aus einem realen Kontext.
##
## ADR-020: InteractionExecutor läuft PRO PEER lokal (siehe dortige Doku) — auf
## einem Nicht-Host-Client lief dieser Hook bisher NUR lokal und erreichte die
## Autorität nie (R-1/R-2/R-3/R-6 aus TODO-offene-probleme.md sind dieselbe
## strukturelle Lücke). Fix: der lokale Emit bleibt bestehen (Autorität wirkt
## darüber direkt; Nicht-Autorität bekommt darüber höchstens ein wirkungsloses,
## instantanes Feedback — siehe EnemyNPC._on_interacted()'s Guard, das genau
## dieses Muster bereits vorexerziert). Zusätzlich, NUR wenn die Entity nicht
## die Autorität ist, wird dieselbe Absicht per RPC an die Autorität gemeldet
## (WorldService.request_entity_interaction() → NetworkBridge → dort läuft
## derselbe _on_interacted()-Hook noch einmal, diesmal mit echter Wirkung).
func _handle_completion(peer_id: int) -> void:
	var parent := get_parent()
	if not parent.has_method("_on_interacted"):
		AppLogger.log_warn(
			"Interaktion abgeschlossen: '%s'. Parent hat KEINE _on_interacted() — kein Hook aufgerufen." % data.label,
			LOG_CAT
		)
		return

	AppLogger.log_info("Interaktion abgeschlossen: '%s'. Entity-Hook aufgerufen." % data.label, LOG_CAT)
	interacted.emit(data.id, peer_id)  # Parent connects to this signal in _ready() — no direct call

	# BUGFIX (2026-09-21, "Condition '!is_inside_tree()' is true" beim Harvest):
	# Für Harvestables (oak_tree, rock_boulder, ...) ruft genau dieser Emit
	# synchron den Despawn-Pfad auf (_on_interacted() -> Pool-Rückgabe ->
	# Entity verlässt sofort den Tree). Der anschließende Zugriff auf
	# is_multiplayer_authority() lief danach auf einem bereits aus dem Tree
	# entfernten (ggf. sogar wiederverwendeten) Node und schlug im Engine-Core
	# fehl. Der lokale Emit hat seine Wirkung so oder so schon ausgelöst,
	# also gibt es hier nichts mehr an die Autorität zu melden.
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return

	if parent.is_multiplayer_authority():
		return  # Wir SIND die Autorität — der Emit oben hat die Wirkung bereits ausgelöst.

	var world: WorldService = _ctx.get_world() if is_instance_valid(_ctx) else null
	if not is_instance_valid(world):
		AppLogger.log_warn(
			"'%s': kein WorldService im Context — Interaktion erreicht die Autorität nicht." % data.label,
			LOG_CAT
		)
		return

	# BUGFIX (2026-09-15, "Guest kann nichts abbauen"): direkter Meta-Read
	# (parent.get_meta("entity_uuid", "")) lieferte im Feld-Test bei manchen
	# Entities einen leeren String, obwohl er beim Spawn unconditional gesetzt
	# wird — siehe WorldService.resolve_entity_uuid() für Details/Fallback.
	var uuid: String = world.resolve_entity_uuid(parent)
	if uuid.is_empty():
		AppLogger.log_warn(
			"'%s': keine entity_uuid (auch nicht über Namensauflösung) — Interaktion erreicht die Autorität nicht (nur lokales Feedback)." % data.label,
			LOG_CAT
		)
		return

	world.request_entity_interaction(uuid, data.id, peer_id)

# ─────────────────────────────────────────────
# 3D-Bar (World-Events)
# ─────────────────────────────────────────────

func _on_interaction_started(action_id: String, _label: String, duration: float) -> void:
	if action_id != data.id or not enabled:
		return
	if not _is_player_target():
		return
	progress_started.emit(action_id, duration)
	if not is_instance_valid(_bar_3d):
		return
	_bar_3d.visible = true
	var t := create_tween()
	# BUG-FIX: Lambda griff auf '_bar_3d' über 'self' zu -> GDScript fängt dabei
	# implizit 'self' (die InteractableComponent) als Capture ein. Wird die
	# Komponente (Entity-Despawn/Pool-Reuse) freigegeben während der Tween noch
	# läuft, crasht der Callable-Aufruf mit "Lambda capture at index 0 was
	# freed." Fix: lokale Kopie der Node-Referenz capturen statt 'self', plus
	# Validity-Guard im Lambda-Body.
	var bar := _bar_3d
	t.tween_method(func(v: float) -> void:
		if is_instance_valid(bar):
			bar.update(v)
	, 0.0, 1.0, duration)

func _on_interaction_ended(action_id: String, _label: String) -> void:
	if action_id == data.id and is_instance_valid(_bar_3d):
		_bar_3d.visible = false

func _is_player_target() -> bool:
	# G-02: Alle Spieler prüfen — true wenn IRGENDEINER dieser Interactable als Ziel hat.
	# Verhindert dass Spieler 2 das Fortschrittsbalken-Feedback von Spieler 1 sieht
	# (und umgekehrt), wenn beide in Reichweite derselben Interactable sind.
	#
	# BUG-FIX: interaction_started ist ein globales EventBus-Signal — JEDE
	# InteractableComponent im Spiel empfängt es, auch despawnte/gepoolte
	# Instanzen (EntityPool.release() entfernt die Entity aus dem Tree, aber
	# die InteractableComponent bleibt als Child bestehen und ihre
	# world_events-Connection bleibt aktiv). get_tree() auf einer Nicht-im-
	# Baum-Node crasht dann mit "data.tree is null". Guard davor.
	if not is_inside_tree():
		return false
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return true  # Kein Spieler vorhanden — sicherer Default
	var parent: Node = get_parent()
	for player_node in players:
		if not is_instance_valid(player_node):
			continue
		if not player_node.has_method("get_closest_interactable"):
			continue
		var target: Node3D = player_node.get_closest_interactable()
		if not is_instance_valid(target):
			continue
		if parent == target or target.is_ancestor_of(self):
			return true
	return false
