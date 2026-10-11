extends CharacterBody3D
class_name Player

## Player.gd — Gameplay-Loop, State-Machine, Death/Respawn.
## Setup-Logik (Subsystem-Bau) → PlayerSetup.gd
##
## Player wird via EntityOrchestrator.spawn_entity("player", pos) gespawnt.
## on_spawn(config, ctx) übernimmt Initialisierung — identisch zu allen anderen Entities.
## Initialer State kommt via EventBus.player.player_state_changed (PlayerStateService
## emittiert beim ersten set_state()). Kein einmaliges Polling mehr nötig.

const LOG_CAT       := "Player"
## ADR-032/PvP: identischer Wert wie EnemyNPC.PLAYER_COMBAT_PROFILE_ID — die
## Resistenz eines Spielers als PvP-Ziel, nicht dupliziert als eigene Konstante
## der beiden Klassen möglich (kein gemeinsames Basis-Skript für Combat-Profile-IDs).
const PLAYER_COMBAT_PROFILE_ID := "player"
const JUMP_VELOCITY := 6.0

var _mover:  PlayerMover
## Klettern an Leitern (Graben in die Tiefe) — siehe PlayerLadder.
var _ladder: PlayerLadder = PlayerLadder.new()
## Reiten (Pferd/Esel) — siehe PlayerMount; nur im Solo-Spiel nutzbar.
var _mount: PlayerMount = PlayerMount.new()
var visuals: PlayerVisuals
var camera:  PlayerCamera
var input:   TouchInput
var sensor:  InteractionSensor
var picker:  InteractionTargetPicker
var health:  HealthComponent

var _jump_requested: bool    = false
var _spawn_position: Vector3 = Vector3.ZERO
var _is_dead:        bool    = false
var _respawn_timer:  SceneTreeTimer = null  ## Referenz zum Canceln bei Session-Ende

## Lokaler State-Cache — wird via EventBus aktualisiert, nie per Polling.
var _player_state: PlayerStateService.State = PlayerStateService.State.FREE
var _bus: IEventBus = null

## "Wem gehört dieser Player-Node" — gesetzt in on_spawn() aus ctx.get_owner_peer_id().
## Bewusst NICHT get_multiplayer_authority(): das beantwortet "wer ist
## Netzwerk-Autorität", eine andere Frage. Seit ADR-025 ist die Netzwerk-Autorität
## für JEDES Player-Node einheitlich der Server (siehe _ready()) — Ownership
## (wem "gehört" der Node, für Eingabe/UI/Filter) bleibt weiterhin pro Peer.
var _owner_peer_id: int = 1

## Peer-ID DIESES laufenden Prozesses — von ctx.get_local_peer_id() in on_spawn().
## "Ist das MEIN Player-Node" = _owner_peer_id == _local_peer_id.
var _local_peer_id: int = 1

## NetworkBridge — für submit_movement_input() (ADR-025). Null in reinen
## Test-Kontexten ohne Netz (nil-safe geprüft vor jeder Nutzung).
var _network: NetworkBridge = null

## Round 103 (ADR-047): Bewegungs-Statistik-Akkumulation — NUR in
## _loop_free_authoritative() gefüllt (autoritative Position, siehe
## Klassenkommentar dort), NIE in _loop_free_predicted()/_resimulate_from()
## (das wäre Client-Position, potenziell manipulierbar, und würde bei
## Reconciliation-Replays sonst doppelt zählen). Alle STAT_FLUSH_INTERVAL_SEC
## als EIN gebündeltes Signal geflusht statt pro Tick (~60/Sekunde) — rein
## additiv, berührt keinen bestehenden Reconciliation-/Prediction-Zustand.
const STAT_FLUSH_INTERVAL_SEC := 5.0
var _stat_walked_accum: float = 0.0
var _stat_jumped_accum: float = 0.0
var _stat_fallen_accum: float = 0.0
var _stat_flush_elapsed: float = 0.0

## ADR-032/PvP: gespeicherter EntityContext für spätere Service-Zugriffe in
## _on_interacted() (CombatSystem/DataService) — bisher hatte Player() keinen
## Grund, ctx über on_spawn() hinaus zu behalten, EnemyNPC tut das schon
## länger aus demselben Grund.
var _ctx: IEntityContext = null

# ─────────────────────────────────────────────
# ADR-025/026: Server-autoritatives Movement + Client-Side Prediction
# ─────────────────────────────────────────────

## Monoton steigende Eingabe-Sequenznummer — Grundlage für Prediction-Matching
## und Reconciliation. Nur auf dem vorhersagenden Client relevant (eigener Spieler,
## nicht Autorität).
var _input_seq: int = 0

## Ringpuffer vorhergesagter Zustände: [{seq, position, rotation, velocity}, ...].
## Größe: 180 Einträge = 3s bei 60Hz Physics-Tickrate. Bewusst nicht "unbegrenzt"
## (ADR-026-Mitigation) — an eine großzügig bemessene Round-Trip-Time gebunden:
## selbst ein für Mobilfunk/Hosted-Coop untypisch schlechtes RTT (500-800ms) passt
## mit deutlichem Puffer hinein. Kein geschätzter Platzhalter, sondern explizit aus
## Tickrate * erwarteter-Latenz-mit-Sicherheitsfaktor hergeleitet.
const PREDICTION_BUFFER_SIZE := 180
var _predicted_states: Array[Dictionary] = []

## Divergenz-Toleranz für Reconciliation, in Metern. Herleitung (ADR-026 verlangt
## explizit KEINEN geschätzten Platzhalter): bei 20Hz Sync-Rate liegen zwischen zwei
## Server-Bestätigungen bis zu 0.05s Physik ohne neue Bestätigung. Ein plausibler
## Ober-Wert für move_speed (Basis 6.0, großzügig x3 für Buffs/Ausrüstung = 18 m/s)
## ergibt eine erwartbare Positions-Drift durch reine Physik-/Lerp-Ungenauigkeit
## (ACCEL-Lerp konvergiert nicht sprunghaft) von deutlich unter 10cm pro Tick.
## 0.15m liegt darüber — Überschreitung bedeutet also echten Input- oder
## Zustands-Unterschied (verlorenes Paket, State-Divergenz, Manipulationsversuch),
## nicht Float-Rauschen.
const RECONCILE_TOLERANCE_M := 0.15

## Letzte vom Client bereits reconcilierte input_seq — verhindert wiederholtes
## Reconcilieren derselben Server-Antwort (die repliced Property ändert sich nur
## bei jedem NEUEN Sync-Tick, aber _physics_process läuft öfter als 20Hz).
var _last_reconciled_seq: int = -1

## Replizierte Server-Antwort: welche input_seq hat die Autorität zuletzt verarbeitet.
## Teil der SceneReplicationConfig in _setup_multiplayer_sync() — läuft (wie
## position/rotation/velocity) von der Autorität (Server) zu allen Clients.
var _last_processed_input_seq: int = 0

## AUTORITÄTS-SEITIGER Eingabe-Puffer für ein FREMDES (nicht-eigenes) Player-Node —
## z.B. der Server, der die Bewegung eines Mitspielers simuliert. FIFO, klein und
## hart begrenzt (MAX_PENDING_INPUTS): das ist bewusst KEIN Rate-Limiting (siehe
## offener TODO-Punkt "Kein Rate-Limiting auf any_peer-RPCs") — nur ein Schutz
## gegen unbegrenztes Array-Wachstum, falls ein Client schneller sendet als die
## Autorität pro Tick konsumiert.
const MAX_PENDING_INPUTS := 12
var _pending_remote_inputs: Array[Dictionary] = []

## Letzter bekannter Input eines Fremd-Spielers auf der Autorität — wird
## weiterverwendet, wenn zwischen zwei Physik-Ticks kein neuer Input eintraf
## (unreliable RPC: Paketverlust ist normal, siehe ADR-025 "Konsequenzen").
## jump_requested wird hier NIE gehalten (One-Shot, s. _consume_next_remote_input()),
## sonst würde ein wiederholt verwendeter Input Dauer-Sprünge auslösen.
var _last_remote_move_vec: Vector2 = Vector2.ZERO
var _last_remote_camera_yaw: float = 0.0

func _ready() -> void:
	add_to_group("player")
	set_physics_process(false)
	# ADR-025: Autorität = Server für JEDES Player-Node, exakt wie EnemyNPC/
	# AnimalBase/HarvestableEntity das bereits in ihrer eigenen _ready() tun —
	# kein Sonderfall mehr für Player. EntityOrchestrator.spawn_entity() setzt
	# das NICHT mehr selbst (siehe dortiger Kommentar) — die Entity ist jetzt
	# überall für ihre eigene Netzwerk-Autorität zuständig, kein zentraler
	# Override mehr nötig oder erlaubt.
	set_multiplayer_authority(1)
	# Signal-Connects laufen in on_spawn() — _bus ist erst dort garantiert gesetzt
	# (Pflicht-Dep via EntityContext, kein AutoLoad-Fallback, vgl. ADR-014).
	AppLogger.log_debug("Player _ready(). Warte auf on_spawn().", LOG_CAT)

## on_spawn() — Einstiegspunkt via EntityOrchestrator.
## ctx liefert alle benötigten Services. config kann spawn_position enthalten.
func on_spawn(config: Dictionary, ctx: IEntityContext) -> void:
	AppLogger.log_info("Player on_spawn() — initialisiere Subsysteme.", LOG_CAT)

	_bus = ctx.get_event_bus() if is_instance_valid(ctx) else null
	_ctx = ctx
	_owner_peer_id = ctx.get_owner_peer_id() if is_instance_valid(ctx) else 1
	_local_peer_id = ctx.get_local_peer_id() if is_instance_valid(ctx) else 1
	_network = ctx.get_network_bridge() if is_instance_valid(ctx) else null
	if _bus == null:
		AppLogger.log_error(
			"Player.on_spawn(): kein IEventBus im EntityContext — Spawn ohne DI nicht unterstützt.",
			LOG_CAT
		)
		return
	_bus.player().movement_interrupted.connect(_on_action_interrupted)
	_bus.player().player_state_changed.connect(_on_player_state_changed)

	var subs := PlayerSetup.build(self)
	_mover  = subs["mover"]
	visuals = subs["visuals"]
	camera  = subs["camera"]
	input   = subs["input"]
	sensor  = subs["sensor"]
	picker  = subs["picker"]
	health  = subs["health"]

	# Round 114 (ADR-048 Broadcast-Lücke): der Spawn-Payload eines Remote-
	# Player-Entities trägt jetzt den Look des Spielers mit (siehe
	# NetworkBridge._register_and_broadcast_player_spawn()) — hier direkt
	# angewendet, bevor irgendetwas anderes das Mesh sieht. Für das lokale
	# Player-Entity kommt kein "look" im config mit (der lokale Spieler
	# bekommt seinen eigenen Look über die Aussehens-UI, siehe
	# AppearancePanelController/CharacterCreationController), daher hier
	# kein Sonderfall nötig — is_instance_valid(visuals) reicht als Guard.
	if config.get("look") is Dictionary and is_instance_valid(visuals):
		visuals.apply_look(config["look"])

	# Blick (rein kosmetisch, siehe CharacterGaze): nie sich selbst anschauen. Der lokale
	# Spieler schaut sein aktuelles Interaktionsziel an; Remote-Spieler wählen automatisch
	# das nächste Wesen in Reichweite (Spieler/NPCs) bzw. schauen sich im Idle um.
	if is_instance_valid(visuals):
		var gaze_provider := Callable()
		if _owner_peer_id == _local_peer_id:
			gaze_provider = Callable(self, "get_closest_interactable")
		visuals.configure_gaze(self, gaze_provider)

	# BUGFIX (2026-09-16, "Kamera springt zum Gast-Charakter"): PlayerCamera.
	# _build_camera() setzt camera.current = true UNCONDITIONAL für JEDES
	# Player-Entity. Vor der Mitspieler-Sichtbarkeit (NetworkBridge) existierte
	# pro Prozess nie mehr als ein Player-Entity — dieser Pfad wurde nie
	# getriggert. Jetzt wird auch für JEDEN Remote-Peer ein vollwertiges
	# Player-Entity inkl. eigener Kamera gespawnt (siehe
	# NetworkBridge._rpc_spawn_remote_player()) — dessen Kamera "klaute" beim
	# Spawn automatisch den Fokus (Godot erlaubt nur eine current=true Camera3D
	# pro Viewport), das war exakt der Sprung zum Gast. Nur die eigene
	# (lokale) Kamera darf aktiv bleiben.
	if _owner_peer_id != _local_peer_id and is_instance_valid(camera) and is_instance_valid(camera.camera):
		camera.camera.current = false

	# FEATURE (First-Person-Zoom, siehe PlayerCamera-Klassenkommentar): eigenes
	# Mesh ausblenden, sobald die Kamera nah genug heranzoomt — sonst stünde das
	# Modell zwischen Kamera und Blickrichtung. Nur für den lokal gesteuerten
	# Spieler relevant (Remote-Spieler sollen für andere weiterhin sichtbar
	# bleiben, unabhängig davon, wie deren eigene Kamera gerade steht).
	if _owner_peer_id == _local_peer_id and is_instance_valid(camera) and is_instance_valid(visuals):
		camera.first_person_changed.connect(
			func(active: bool) -> void: visuals.visible = not active
		)

	# Easter Egg "sun_gazer" (siehe SunGazeWatcher.gd/AchievementService.gd
	# Klassenkommentar "EASTER EGGS") — dieselbe "nur lokaler Spieler"-
	# Bedingung wie der First-Person-Mesh-Block direkt darüber, aus demselben
	# Grund: Kamera-Ausrichtung/-Zoom ist rein lokaler Client-Zustand, für
	# einen Remote-Player-Node hier nicht einsehbar.
	if _owner_peer_id == _local_peer_id and is_instance_valid(camera):
		var world_for_sun: WorldService = ctx.get_world() if is_instance_valid(ctx) else null
		var sun_gaze_watcher := SunGazeWatcher.new()
		sun_gaze_watcher.name = "SunGazeWatcher"
		add_child(sun_gaze_watcher)
		sun_gaze_watcher.configure(
			camera,
			world_for_sun.get_sun_light() if is_instance_valid(world_for_sun) else null,
			_network,
			self
		)

	# FEATURE (Vogelperspektive + Karte, siehe PlayerCamera-Klassenkommentar/WorldMapView): ganz
	# weit herauszoomen blendet die Weltkarte ein. Rein lokale Ansicht → nur für den lokal
	# gesteuerten Spieler. Das Gelände kommt aus dem WorldService (TerrainField); fehlt es (Tests,
	# Welt noch nicht bereit), bleibt die Karte dunkel, Marker/Kompass funktionieren trotzdem.
	if _owner_peer_id == _local_peer_id and is_instance_valid(camera):
		var world_for_map: WorldService = ctx.get_world() if is_instance_valid(ctx) else null
		var map_view := WorldMapView.new()
		add_child(map_view)
		map_view.setup(
			camera, self, visuals,
			world_for_map.get_terrain() if is_instance_valid(world_for_map) else null
		)

	health.died.connect(_on_player_died)
	health.health_changed.connect(
		func(cur: int, mx: int) -> void: _bus.player().emit_player_health_changed(cur, mx)
	)
	# BUG-C-FIX (HP wird nicht gespeichert): gespeicherten HP-Wert anwenden,
	# BEVOR der erste health_changed-Emit unten läuft — sonst würde die UI
	# kurz den vollen Default-Wert zeigen. WorldSaveHandler.restore_world()
	# läuft laut WorldService.on_world_scene_ready() immer VOR spawn_all()
	# (analog zum Pet-Restore-Timing), data.player_health ist hier also schon
	# der wiederhergestellte Stand, falls einer existiert. player_id via
	# denselben _resolve_player_uuid()-Mechanismus wie überall sonst in dieser
	# Klasse — kein neuer Auflösungspfad.
	var world: WorldService = ctx.get_world() if is_instance_valid(ctx) else null
	if is_instance_valid(world):
		var player_id := _resolve_player_uuid(_owner_peer_id)
		var saved: Variant = world.data.player_health.get(player_id) if not player_id.is_empty() else null
		if saved is Dictionary and saved.has("current") and saved.has("max"):
			health.max_health = int(saved["max"])
			health.current_health = clampi(int(saved["current"]), 0, health.max_health)
			if health.current_health <= 0:
				health.is_dead = true
	_bus.player().emit_player_health_changed(health.current_health, health.max_health)

	# ADR-032/PvP: macht diesen Player-Node für InteractionSensor.get_closest()
	# sichtbar (identischer Mechanismus wie EnemyNPC — siehe PlayerAttack.gd-
	# Klassenkommentar) UND hängt die "attack_player"-Interaktion an, über die
	# ein anderer Spieler überhaupt erst angreifen kann.
	# ADR-035: PlayerTrade hängt zusätzlich "trade_request" an denselben Node —
	# zwei koexistierende InteractableComponents (siehe PlayerTrade.gd).
	# ADR-036: PlayerThank hängt zusätzlich "thank_player" an denselben Node —
	# dritte koexistierende InteractableComponent (siehe PlayerThank.gd).
	# ADR-039: PlayerPickpocket hängt zusätzlich drei "pickpocket_*"-Aktionen
	# an denselben Node — vierte koexistierende InteractableComponent-Gruppe
	# (siehe PlayerPickpocket.gd).
	add_to_group("interactable")
	PlayerAttack.setup_interactable(self, ctx)
	PlayerTrade.setup_interactable(self, ctx)
	PlayerThank.setup_interactable(self, ctx)
	PlayerPickpocket.setup_interactable(self, ctx)

	if is_instance_valid(sensor):
		sensor.inject_bus(_bus)
	# Nur der lokal gesteuerte Spieler soll auf Welt-Taps reagieren — world_tap_requested
	# ist ein geteiltes Input-Signal auf dem EventBus (kommt von TouchInput, das nur für
	# den lokalen Spieler echte Bildschirm-Eingaben verarbeitet). Ohne dieses Gate würde
	# JEDER sichtbare Remote-Spieler (jeweils mit eigener, nicht gerenderter Kamera) beim
	# Antippen ebenfalls einen Raycast von SEINER Kamera aus feuern und sein eigenes Ziel
	# markieren — sichtbar als zufällige Umrandungen bei anderen Spielern.
	if is_instance_valid(picker) and _owner_peer_id == _local_peer_id:
		picker.inject_bus(_bus)
	if is_instance_valid(input):
		input.inject_bus(_bus)
		input.inject_settings(ctx.get_settings() if is_instance_valid(ctx) else null)

	PlayerSetup.apply_stats(_mover, ctx)

	# StatModifierService in PlayerMover injizieren (Ablösung des internen Modifier-Dicts).
	# P1-Fix: ctx.get_service() existiert nicht in IEntityContext — korrekter Aufruf ist get_stat_modifiers().
	var stat_svc := ctx.get_stat_modifiers()
	if is_instance_valid(stat_svc):
		_mover.inject_stat_modifiers(stat_svc)

	# Spawn-Position aus config falls vorhanden, sonst aktuelle Position.
	if config.has("spawn_position"):
		global_position = config["spawn_position"]
	_spawn_position = global_position

	set_physics_process(true)
	_setup_multiplayer_sync()

	# G-04: Für Remote-Spieler (nicht der lokale Peer) Snapshot-Interpolation aktivieren.
	# Ohne Interpolation springen Remote-Spieler alle 50ms (20 Hz Sync-Rate).
	# Der lokale Spieler braucht keine Interpolation — er bewegt sich per Prediction
	# (ADR-026) sofort selbst, unabhängig von der Sync-Rate.
	# Owner-Abgleich statt Authority-Abgleich: Authority ist seit ADR-025 für ALLE
	# Player-Nodes einheitlich der Server — "ist das MEIN Spieler" wird deshalb über
	# _owner_peer_id/_local_peer_id beantwortet, nicht über get_multiplayer_authority().
	if multiplayer.has_multiplayer_peer() \
			and _owner_peer_id != _local_peer_id:
		var interpolator := RemotePlayerInterpolator.new()
		interpolator.name = "RemoteInterpolator"
		add_child(interpolator)
		AppLogger.log_debug("Remote-Spieler: Snapshot-Interpolation aktiviert.", LOG_CAT)

	AppLogger.log_info("Player online. Position: %s." % str(global_position), LOG_CAT)

func on_despawn() -> void:
	set_physics_process(false)
	if is_instance_valid(_respawn_timer):
		if _respawn_timer.timeout.is_connected(_respawn):
			_respawn_timer.timeout.disconnect(_respawn)
		_respawn_timer = null
	_is_dead = false
	AppLogger.log_info("Player despawned.", LOG_CAT)

## Empfängt PlayerStateService von EntityOrchestrator nach on_spawn() — kein Services-Locator.
## EntityOrchestrator.spawn_entity() ruft dies auf wenn _entity_player_states gesetzt ist.
func inject_player_states(svc: PlayerStateService) -> void:
	if is_instance_valid(input):
		input.inject_player_states(svc)

# ─────────────────────────────────────────────
# Physics-Loop
# ─────────────────────────────────────────────

## ADR-025/026: drei sich gegenseitig ausschließende Rollen pro Player-Node,
## abhängig davon WO dieser Code gerade läuft (Server oder Client) und WESSEN
## Node es ist — kein Tier-Sonderfall, dieselbe Fallunterscheidung für Solo/
## Hosted-Coop/Dedicated-Server (siehe ADR-025 "Tier-Kollaps"):
##
##   1. is_multiplayer_authority() → Server (oder Solo/Host, da unique_id=1).
##      Führt die EINZIGE echte Simulation aus — für den eigenen Spieler
##      (falls Host selbst spielt) aus lokalem Input, für jeden anderen
##      Spieler aus dessen zuletzt empfangenem Input (_pending_remote_inputs).
##   2. NICHT Autorität, aber MEIN Node (_owner_peer_id == _local_peer_id) →
##      Client-Side Prediction: simuliert sofort lokal (kein Warten auf
##      Server-Roundtrip), sendet den Input zusätzlich an die Autorität,
##      merkt sich das Ergebnis im Ringpuffer für spätere Reconciliation.
##   3. NICHT Autorität, NICHT mein Node → fremder Spieler auf meinem Client.
##      Keine lokale Simulation — MultiplayerSynchronizer + RemotePlayerInterpolator
##      übernehmen Position/Glättung vollständig (siehe RemotePlayerInterpolator.gd).
func _physics_process(delta: float) -> void:
	_physics_process_state(delta)
	_update_mount()

func _physics_process_state(delta: float) -> void:
	match _player_state:
		PlayerStateService.State.FREE:
			_loop_free(delta)
		PlayerStateService.State.BUSY:
			_loop_busy(delta)
		_:
			if is_multiplayer_authority() or _owner_peer_id == _local_peer_id:
				velocity = Vector3.ZERO
				move_and_slide()

func _loop_free(delta: float) -> void:
	if is_multiplayer_authority():
		_loop_free_authoritative(delta)
	elif _owner_peer_id == _local_peer_id:
		_loop_free_predicted(delta)
	# else: fremder Spieler auf meinem Client — nichts zu tun, siehe Klassen-Kommentar.

func _loop_busy(delta: float) -> void:
	if not (is_multiplayer_authority() or _owner_peer_id == _local_peer_id):
		return  # fremder Spieler — Sync/Interpolator übernehmen die Darstellung.
	if input.js_vec.length() > 0.5:
		# ADR-015: eigene peer_id mitgeben, damit InteractionExecutor gezielt
		# NUR diesen Spieler abbricht, nicht versehentlich einen anderen.
		_bus.player().emit_movement_interrupted(_owner_peer_id)
	velocity = velocity.move_toward(Vector3.ZERO, 15.0 * delta)
	move_and_slide()
	if _owner_peer_id == _local_peer_id:
		camera.handle_input(input, delta)

# ─────────────────────────────────────────────
# Fall 1: Autoritative Simulation (läuft auf dem Server für JEDEN Spieler)
# ─────────────────────────────────────────────

## Simuliert diesen Spieler autoritativ. Für den Host selbst (eigener lokaler
## Input) ODER für einen entfernten Spieler (letzter empfangener Input aus
## _pending_remote_inputs) — dieselbe Funktion, kein Sonderfall, weil beide
## Zweige am Ende exakt denselben _apply_movement()-Aufruf machen.
func _loop_free_authoritative(delta: float) -> void:
	var _tier2_t0 := Time.get_ticks_usec()
	var move_vec: Vector2
	var camera_yaw: float
	var jump: bool
	var seq: int

	if _owner_peer_id == _local_peer_id:
		# Host spielt selbst mit (Tier 1 Solo oder Tier 2 Host) — Input kommt
		# direkt aus dem lokalen TouchInput/PlayerCamera, kein RPC-Umweg
		# (ADR-025 "Tier-Kollaps": derselbe Codepfad, nur ohne Netzwerk-Zwischenschritt).
		move_vec = input.js_vec
		camera_yaw = camera.global_rotation.y
		jump = _jump_requested
		_jump_requested = false
		_input_seq += 1
		seq = _input_seq
		camera.handle_input(input, delta)
	else:
		var consumed := _consume_next_remote_input()
		move_vec = consumed["move_vec"]
		camera_yaw = consumed["camera_yaw"]
		jump = consumed["jump_requested"]
		seq = consumed["seq"]

	var move_dir := MathHelper.calculate_move_direction_from_yaw(camera_yaw, move_vec)
	var _stat_was_on_floor := is_on_floor()
	var _stat_pos_before := global_position
	_apply_movement(move_dir, delta, jump)
	_track_movement_stats(_stat_pos_before, _stat_was_on_floor, delta)
	visuals.handle_rotation(move_dir, delta)
	_last_processed_input_seq = seq
	_tier2_record_sample(Time.get_ticks_usec() - _tier2_t0)

## Nimmt den nächsten gepufferten Fremd-Input ab (FIFO) oder hält den letzten
## bekannten Bewegungs-Input, falls seit dem letzten Tick nichts Neues eintraf
## (Paketverlust bei unreliable RPC ist normal, s. ADR-025). jump_requested wird
## dabei NIE gehalten — sonst würde ein wiederverwendeter Input Dauer-Sprünge
## auslösen, siehe Feld-Kommentar oben.
func _consume_next_remote_input() -> Dictionary:
	if not _pending_remote_inputs.is_empty():
		var next: Dictionary = _pending_remote_inputs.pop_front()
		_last_remote_move_vec = next["move_vec"]
		_last_remote_camera_yaw = next["camera_yaw"]
		return next
	return {
		"seq": _last_processed_input_seq,
		"move_vec": _last_remote_move_vec,
		"camera_yaw": _last_remote_camera_yaw,
		"jump_requested": false,
	}

## Empfangs-Einstiegspunkt für die Autorität — aufgerufen von
## WorldService.route_movement_input() (selbst aufgerufen aus
## NetworkBridge._rpc_submit_movement_input(), peer_id fälschungssicher aus
## multiplayer.get_remote_sender_id()). NIEMALS direkt von einem Client-Peer
## aufrufbar — dieser Node hat auf Nicht-Autoritäts-Peers ohnehin keine
## Wirkung, weil nur die Autorität hier _loop_free_authoritative() ausführt.
func receive_authoritative_input(input_snapshot: Dictionary) -> void:
	if not is_multiplayer_authority():
		AppLogger.log_warn(
			"receive_authoritative_input() auf Nicht-Autorität aufgerufen — ignoriert.", LOG_CAT
		)
		return
	_pending_remote_inputs.append(input_snapshot)
	if _pending_remote_inputs.size() > MAX_PENDING_INPUTS:
		# Defensiver Deckel gegen unbegrenztes Wachstum bei Flood — KEIN
		# Rate-Limiting (siehe TODO "Kein Rate-Limiting auf any_peer-RPCs",
		# weiterhin offen). Verwirft den ältesten, noch nicht simulierten Input.
		_pending_remote_inputs.pop_front()

# ─────────────────────────────────────────────
# Fall 2: Client-Side Prediction (läuft auf dem eigenen, nicht-autoritativen Client)
# ─────────────────────────────────────────────

func _loop_free_predicted(delta: float) -> void:
	_reconcile_if_needed()

	var move_vec := input.js_vec
	var camera_yaw := camera.global_rotation.y
	var jump := _jump_requested
	_jump_requested = false
	_input_seq += 1
	var seq := _input_seq

	var move_dir := MathHelper.calculate_move_direction_from_yaw(camera_yaw, move_vec)
	_apply_movement(move_dir, delta, jump)
	visuals.handle_rotation(move_dir, delta)
	camera.handle_input(input, delta)

	# WICHTIG: der Eintrag speichert sowohl das ERGEBNIS (position/rotation/velocity,
	# für den Drift-Vergleich in _reconcile_if_needed()) als auch den ORIGINAL-INPUT
	# (move_vec/camera_yaw/jump_requested/delta, für die tatsächliche Resimulation in
	# _resimulate_from()) — ohne den Input wäre keine echte Resimulation möglich,
	# nur eine Wiederholung des Ergebnisses.
	_predicted_states.append({
		"seq": seq,
		"position": global_position,
		"rotation": rotation,
		"velocity": velocity,
		"move_vec": move_vec,
		"camera_yaw": camera_yaw,
		"jump_requested": jump,
		"delta": delta,
	})
	if _predicted_states.size() > PREDICTION_BUFFER_SIZE:
		_predicted_states.pop_front()

	if is_instance_valid(_network):
		_network.submit_movement_input({
			"seq": seq,
			"move_vec": move_vec,
			"camera_yaw": camera_yaw,
			"jump_requested": jump,
			"delta": delta,
		})

## Prüft, ob eine neue Server-Bestätigung (_last_processed_input_seq, per
## MultiplayerSynchronizer repliziert) eingetroffen ist, seit zuletzt reconciliert
## wurde. Kein Signal/Setter-Callback nötig — die Property wird von Godots
## MultiplayerSynchronizer direkt geschrieben; Polling einmal pro Physik-Tick ist
## günstig genug und hält den Code frei von zusätzlicher Sync-Infrastruktur.
func _reconcile_if_needed() -> void:
	if _last_processed_input_seq == _last_reconciled_seq:
		return
	_last_reconciled_seq = _last_processed_input_seq

	var matching_index := -1
	for i in range(_predicted_states.size()):
		if _predicted_states[i]["seq"] == _last_processed_input_seq:
			matching_index = i
			break

	if matching_index == -1:
		# Server bestätigt eine seq, die außerhalb unseres Ringpuffer-Horizonts liegt
		# (z.B. nach einer Reconnect-Pause) — kein Vergleich möglich, akzeptiere die
		# Server-Position hart als neue Wahrheit. Kein stiller Fall: geloggt, weil das
		# strukturell selten sein sollte (Puffer ist auf 3s RTT ausgelegt).
		AppLogger.log_warn(
			"Reconciliation: seq %d nicht im Ringpuffer — harter Snap." % _last_processed_input_seq,
			LOG_CAT
		)
		_predicted_states.clear()
		return

	var predicted: Dictionary = _predicted_states[matching_index]
	var server_position: Vector3 = global_position  # bereits per Sync auf Server-Wert gesetzt
	var drift: float = predicted["position"].distance_to(server_position)

	# Bestätigte und ältere Einträge aus dem Puffer entfernen — unabhängig davon,
	# ob reconciliert wird: sie sind ab jetzt Geschichte.
	_predicted_states = _predicted_states.slice(matching_index + 1)

	if drift <= RECONCILE_TOLERANCE_M:
		return  # Normalfall: Vorhersage war richtig genug, keine Korrektur nötig.

	AppLogger.log_debug(
		"Reconciliation: Drift %.3fm > Toleranz %.3fm bei seq %d — Resimulation von %d Inputs."
		% [drift, RECONCILE_TOLERANCE_M, _last_processed_input_seq, _predicted_states.size()],
		LOG_CAT
	)
	_resimulate_from(server_position, rotation, velocity)

## Setzt den Client hart auf die Server-Position zurück und führt jeden seither
## lokal vorhergesagten, noch unbestätigten Input erneut aus — nicht nur ein
## harter Snap (der würde bei jeder kleinen Korrektur sichtbar ruckeln).
## Nutzt denselben PlayerMover.calculate_velocity()-Code wie die Echtzeit-
## Simulation, mit demselben effective_speed, der auch beim Originaldurchlauf
## gegolten hätte (siehe PlayerMover-Kommentar zum Determinismus-Vertrag) —
## move_speed wird hier bewusst NEU über get_current_speed() gezogen (nicht
## aus dem Ringpuffer-Eintrag), weil move_speed niemals vom Client übertragen
## wird (Sicherheitsanforderung, ADR-025) und Resimulation innerhalb desselben
## Reconciliation-Fensters (Millisekunden) praktisch nie einen Buff-Wechsel
## überstreicht — anders als eine über Sekunden verzögerte Neuabfrage.
func _resimulate_from(start_pos: Vector3, start_rot: Vector3, start_vel: Vector3) -> void:
	global_position = start_pos
	rotation = start_rot
	velocity = start_vel

	var remaining := _predicted_states.duplicate()
	_predicted_states.clear()

	for entry in remaining:
		var move_dir := MathHelper.calculate_move_direction_from_yaw(
			entry["camera_yaw"], entry["move_vec"]
		)
		# jump_requested wird TREU wiederholt (nicht unterdrückt): _apply_movement()
		# hat keine Seiteneffekte außer Velocity-Mutation, ein Sprung im Original-Tick
		# muss auch bei der Resimulation dieselbe vel.y-Änderung erzeugen — sonst würde
		# jede Reconciliation nach einem Sprung eine neue, künstliche Divergenz erzeugen.
		_apply_movement(move_dir, entry["delta"], entry["jump_requested"])
		_predicted_states.append({
			"seq": entry["seq"],
			"position": global_position,
			"rotation": rotation,
			"velocity": velocity,
			"move_vec": entry["move_vec"],
			"camera_yaw": entry["camera_yaw"],
			"jump_requested": entry["jump_requested"],
			"delta": entry["delta"],
		})

## Gemeinsamer Simulationskern für Autorität, Prediction UND Resimulation —
## genau EINE Stelle, die PlayerMover.calculate_velocity() + move_and_slide()
## aufruft, damit "gleicher Code, gleiche Regeln" (ADR-025) nicht durch drei
## leicht unterschiedliche Kopien unterlaufen wird.
func _apply_movement(move_dir: Vector3, delta: float, jump_requested: bool) -> void:
	# ADR-029 Round 69: PlayerMover.get_current_speed() verlangt jetzt
	# player_id: String (StatModifierService ist migriert, siehe
	# TODO-offene-probleme.md) — PlayerMover selbst bleibt dep-frei (kein
	# NetworkBridge-Zugriff), Übersetzung passiert hier am Aufrufer, der
	# _network bereits als eigenes Feld hält.
	# Leiter hat Vorrang: positionsbasiert, ohne Physik (siehe PlayerLadder).
	var ladder_step: Dictionary = _ladder.step(global_position, move_dir, delta, jump_requested, _get_ladder_registry())
	if not ladder_step.is_empty():
		global_position = ladder_step["position"]
		velocity = ladder_step["velocity"]
		return
	var effective_speed := _mover.get_current_speed(_resolve_player_uuid(_owner_peer_id)) * _mount.speed_multiplier()
	velocity = _mover.calculate_velocity(velocity, move_dir, delta, is_on_floor(), effective_speed)
	if jump_requested and is_on_floor():
		velocity.y = JUMP_VELOCITY
	move_and_slide()

## Leiter-Registry der Welt (null ohne Kontext/Welt und in Mehrspieler-Sitzungen).
func _get_ladder_registry() -> LadderRegistry:
	if not is_instance_valid(_ctx):
		return null
	var world: WorldService = _ctx.get_world()
	if not is_instance_valid(world):
		return null
	return world.get_ladder_registry()

## Round 103 (ADR-047): reine Zusatz-Buchführung für StatsService — NULL
## Einfluss auf Bewegung/Physik/Reconciliation selbst, liest nur
## global_position/is_on_floor() VOR bzw. NACH _apply_movement() (vom
## Aufrufer übergeben), verändert keinen bestehenden State außer den neuen
## _stat_*_accum-Feldern. Nur im _loop_free_authoritative()-Zweig
## aufgerufen — NIE in _loop_free_predicted()/_resimulate_from() (siehe
## Feld-Kommentar bei _stat_walked_accum).
##
## Approximation (siehe ADR-047 "Bewusst nicht Teil dieser Runde" für die
## Einschränkung): horizontale Distanz während "auf dem Boden VOR diesem
## Tick" = "gelaufen", vertikaler Aufstieg während in der Luft =
## "gesprungen", vertikaler Abstieg während in der Luft = "gefallen". Kein
## Unterschied zwischen einem kurzen Hüpfer und echtem Fallschaden-Sturz —
## beides zählt hier als "gefallen".
func _track_movement_stats(pos_before: Vector3, was_on_floor: bool, delta: float) -> void:
	var pos_delta := global_position - pos_before
	if was_on_floor:
		_stat_walked_accum += Vector2(pos_delta.x, pos_delta.z).length()
	elif pos_delta.y > 0.0:
		_stat_jumped_accum += pos_delta.y
	elif pos_delta.y < 0.0:
		_stat_fallen_accum += -pos_delta.y

	_stat_flush_elapsed += delta
	if _stat_flush_elapsed < STAT_FLUSH_INTERVAL_SEC:
		return
	_stat_flush_elapsed = 0.0
	if _stat_walked_accum > 0.0 or _stat_jumped_accum > 0.0 or _stat_fallen_accum > 0.0:
		_bus.player().emit_movement_stats_batch(_owner_peer_id, _stat_walked_accum, _stat_jumped_accum, _stat_fallen_accum)
	_stat_walked_accum = 0.0
	_stat_jumped_accum = 0.0
	_stat_fallen_accum = 0.0

## Übersetzt peer_id → die stabile player_id, für den
## PlayerMover.get_current_speed()-Aufruf oben (StatModifierService ist seit
## Round 69 auf player_id: String migriert). Identisches 5-Zeilen-Muster wie
## RewardDispatcher/EquipmentService/CombatSystem._resolve_player_uuid() —
## bewusst keine gemeinsame Utility-Funktion für eine fünfte Call-Site, siehe
## Round-63-Diskussion. Leerer String bei fehlendem NetworkBridge oder
## unauflösbarer peer_id — kein stiller Fallback auf Spieler 1.
func _resolve_player_uuid(peer_id: int) -> String:
	if not is_instance_valid(_network):
		AppLogger.log_warn(
			"_resolve_player_uuid(%d): kein NetworkBridge injiziert — Übersetzung nicht möglich." % peer_id,
			LOG_CAT
		)
		return ""
	return _network.get_player_id_for_peer(peer_id)

## BUG-C-FIX (HP wird nicht gespeichert): öffentlicher Zugriff auf _owner_peer_id
## für WorldService.collect_and_store_player_health() — analog zu
## get_player_by_id() auf der Aufrufer-Seite, das intern dasselbe Feld nutzt.
func get_owner_peer_id() -> int:
	return _owner_peer_id

## Für SunGazeWatcher (und potenzielle künftige rein-lokale Beobachter,
## siehe dort): lazy statt einmalig bei on_spawn() aufgelöst und
## zwischengespeichert, weil _resolve_player_uuid() ohnehin nur ein billiger
## Dictionary-Lookup über NetworkBridge ist — kein Grund, einen möglicherweise
## veralteten Wert zu cachen.
func get_local_player_uuid() -> String:
	return _resolve_player_uuid(_owner_peer_id)

# ─────────────────────────────────────────────
# Fall 3: Fremder Spieler auf meinem Client — siehe Klassen-Kommentar oben
# an _physics_process(). Kein eigener Codeblock nötig: die match-Fälle in
# _loop_free()/_loop_busy() überspringen diesen Fall bereits vollständig.
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# PvP-Kampf (ADR-032 Folge) — spiegelbildlich zu EnemyNPC._on_interacted().
# ─────────────────────────────────────────────

## Wird über PlayerAttack.setup_interactable() an das 'interacted'-Signal der
## "attack_player"-InteractableComponent gebunden. attacker_peer_id ist der
## Peer, der interagiert hat — NICHT dieser Player selbst (siehe
## InteractableComponent._handle_completion() für die Herkunft).
func _on_interacted(action_id: String, attacker_peer_id: int) -> void:
	if _is_dead:
		return

	if action_id == "trade_request":
		_on_trade_requested(attacker_peer_id)
		return

	if action_id == "thank_player":
		_on_thank_requested(attacker_peer_id)
		return

	if action_id.begins_with("pickpocket_"):
		_on_pickpocket_requested(action_id, attacker_peer_id)
		return

	if action_id != "attack_player":
		return

	# Kein Selbstangriff — sollte durch InteractionSensor (eigener Body
	# überlappt normalerweise nicht die eigene Area3D) ohnehin nicht
	# vorkommen, aber billige Absicherung statt sich darauf zu verlassen.
	if attacker_peer_id == _owner_peer_id:
		return

	# ADR-025: Autorität = Server für JEDES Player-Node — identisches Gate
	# wie EnemyNPC._on_interacted(). Kein Client-Prediction-Zweig hier
	# (anders als bei EnemyNPC): Ob ein PvP-Treffer überhaupt zählt, hängt
	# von PvPService-Zustand ab, den der Client nicht kennt — ein optimistisches
	# Hit-Feedback könnte hier leicht lügen ("Treffer!" obwohl PvP inaktiv war).
	if not is_multiplayer_authority():
		return

	if not is_instance_valid(_ctx):
		AppLogger.log_error("_on_interacted(): kein EntityContext gespeichert — PvP-Treffer verweigert.", LOG_CAT)
		return

	var combat: CombatSystem = _ctx.get_combat_system()
	var data: DataService    = _ctx.get_data()
	if not is_instance_valid(combat) or not is_instance_valid(data):
		AppLogger.log_error("_on_interacted(): CombatSystem/DataService fehlen — PvP-Treffer verweigert.", LOG_CAT)
		return

	var attacker_player_id := _resolve_player_uuid(attacker_peer_id)
	var victim_player_id   := _resolve_player_uuid(_owner_peer_id)
	if attacker_player_id.is_empty() or victim_player_id.is_empty():
		AppLogger.log_warn("_on_interacted(): player_id-Übersetzung fehlgeschlagen — PvP-Treffer verweigert.", LOG_CAT)
		return

	# Schaden-Berechnung identisch zum PvE-Pfad: gleiche Waffe, gleiche
	# Skill-Formel (combat.player_melee_damage() kennt keinen Unterschied
	# zwischen "Ziel ist EnemyNPC" und "Ziel ist Player") — nur das Ziel-
	# Resistenzprofil ändert sich (PLAYER_COMBAT_PROFILE_ID statt Monster-Profil).
	var record: DamageRecord = combat.player_melee_damage(attacker_peer_id)
	var profile: CombatProfile = (
		data.get_combat_profile(PLAYER_COMBAT_PROFILE_ID)
		if is_instance_valid(data)
		else CombatProfile.default_profile()
	)
	record = combat.calculate_damage_with_profile(record, profile, victim_player_id)
	record.target_id = name

	# resolve_pvp_hit() macht Gate (is_pvp_active/is_vulnerable_in_safe_zone),
	# apply_damage() UND Skull-Trigger (report_pvp_damage()) in einem Aufruf —
	# siehe CombatSystem.resolve_pvp_hit()-Kommentar (ADR-032).
	var landed := combat.resolve_pvp_hit(record, health, attacker_player_id, victim_player_id)
	if landed:
		AppLogger.log_debug(
			"PvP-Treffer: '%s' → '%s': %s → %d/%d HP"
			% [attacker_player_id, victim_player_id, record.to_debug_string(), health.current_health, health.max_health],
			LOG_CAT
		)
	else:
		# Kein Log-Rauschen bei jedem verweigerten Treffer außerhalb einer
		# PvP-Zone — das ist der Normalfall (Safe-Zone-Geplänkel), kein Fehler.
		_ui_bus().emit_floating_loot_text_requested("🛡 Immun", global_position)

# ─────────────────────────────────────────────
# Handel (ADR-035) — spiegelbildlich zum PvP-Block oben.
# ─────────────────────────────────────────────

## Wird über PlayerTrade.setup_interactable() an das 'interacted'-Signal der
## "trade_request"-InteractableComponent gebunden. initiator_peer_id ist der
## Peer, der die Handelsanfrage gestellt hat — NICHT dieser Player selbst.
## Gleiches Autoritäts-Gate wie beim PvP-Block: nur auf der Autorität hat der
## Aufruf echte Wirkung, siehe TradeService.gd-Klassenkommentar.
func _on_trade_requested(initiator_peer_id: int) -> void:
	if initiator_peer_id == _owner_peer_id:
		return  # Kein Handel mit sich selbst.

	if not is_multiplayer_authority():
		return

	if not is_instance_valid(_ctx):
		AppLogger.log_error("_on_trade_requested(): kein EntityContext gespeichert — Einladung verweigert.", LOG_CAT)
		return

	var trade: TradeService = _ctx.get_trade_service()
	if not is_instance_valid(trade):
		AppLogger.log_error("_on_trade_requested(): kein TradeService im Context — Einladung verweigert.", LOG_CAT)
		return

	var initiator_id := _resolve_player_uuid(initiator_peer_id)
	var target_id     := _resolve_player_uuid(_owner_peer_id)
	if initiator_id.is_empty() or target_id.is_empty():
		AppLogger.log_warn("_on_trade_requested(): player_id-Übersetzung fehlgeschlagen — Einladung verweigert.", LOG_CAT)
		return

	trade.on_invite_confirmed(initiator_id, target_id)

## ADR-036: exaktes Gegenstück zu _on_trade_requested() — thanker_peer_id ist
## der Peer, der "Danken" ausgelöst hat (self = der Bedankte).
func _on_thank_requested(thanker_peer_id: int) -> void:
	if thanker_peer_id == _owner_peer_id:
		return  # Kein Danken an sich selbst.

	if not is_multiplayer_authority():
		return

	if not is_instance_valid(_ctx):
		AppLogger.log_error("_on_thank_requested(): kein EntityContext gespeichert — Danken verweigert.", LOG_CAT)
		return

	var aura: AuraService = _ctx.get_aura()
	if not is_instance_valid(aura):
		AppLogger.log_error("_on_thank_requested(): kein AuraService im Context — Danken verweigert.", LOG_CAT)
		return

	var thanker_id := _resolve_player_uuid(thanker_peer_id)
	var target_id   := _resolve_player_uuid(_owner_peer_id)
	if thanker_id.is_empty() or target_id.is_empty():
		AppLogger.log_warn("_on_thank_requested(): player_id-Übersetzung fehlgeschlagen — Danken verweigert.", LOG_CAT)
		return

	aura.request_thank(thanker_id, target_id)

## ADR-039: exaktes Gegenstück zu _on_thank_requested() — thief_peer_id ist
## der Peer, der den Pickpocket-Versuch ausgelöst hat (self = das Opfer).
## action_id bestimmt die Kristall-Stufe (siehe PlayerPickpocket.gd) — der
## Kristall-ITEM_ID wird daraus abgeleitet, nicht vom Client übergeben (der
## Client wählt nur die AKTION, nicht direkt eine Item-ID).
const _PICKPOCKET_CRYSTAL_BY_ACTION := {
	"pickpocket_weak":   "theft_crystal_weak",
	"pickpocket_normal": "theft_crystal_normal",
	"pickpocket_strong": "theft_crystal_strong",
}

func _on_pickpocket_requested(action_id: String, thief_peer_id: int) -> void:
	if thief_peer_id == _owner_peer_id:
		return  # Kein Diebstahl an sich selbst.

	if not is_multiplayer_authority():
		return

	if not is_instance_valid(_ctx):
		AppLogger.log_error("_on_pickpocket_requested(): kein EntityContext gespeichert — Diebstahl verweigert.", LOG_CAT)
		return

	var pickpocket: PickpocketService = _ctx.get_pickpocket()
	if not is_instance_valid(pickpocket):
		AppLogger.log_error("_on_pickpocket_requested(): kein PickpocketService im Context — Diebstahl verweigert.", LOG_CAT)
		return

	var crystal_item_id: String = _PICKPOCKET_CRYSTAL_BY_ACTION.get(action_id, "")
	if crystal_item_id.is_empty():
		AppLogger.log_error("_on_pickpocket_requested(): unbekannte action_id '%s'." % action_id, LOG_CAT)
		return

	var thief_id  := _resolve_player_uuid(thief_peer_id)
	var victim_id := _resolve_player_uuid(_owner_peer_id)
	if thief_id.is_empty() or victim_id.is_empty():
		AppLogger.log_warn("_on_pickpocket_requested(): player_id-Übersetzung fehlgeschlagen — Diebstahl verweigert.", LOG_CAT)
		return

	pickpocket.request_pickpocket(thief_id, victim_id, crystal_item_id)

# ─────────────────────────────────────────────
# Jump / Death / Respawn
# ─────────────────────────────────────────────

func request_jump() -> void:
	_jump_requested = true

func _ui_bus() -> UIEvents:
	return _bus.ui()

## record: DamageRecord des todesursächlichen Treffers (ADR-019 — trägt
## attacker_peer_id, damit ein PvP-Tod dem richtigen Killer zugeordnet werden
## kann). record kann null sein (z.B. Umweltschaden/Sturz ohne DamageRecord-
## Pfad) — in dem Fall ist es strukturell kein PvP-Tod, kein Verlust.
func _on_player_died(record: DamageRecord = null) -> void:
	if _is_dead:
		return
	_is_dead = true
	dismount()
	# ADR-032/PvP: nicht-anklickbar solange tot — identisch zu
	# EnemyNPC._die()'s remove_from_group("interactable").
	remove_from_group("interactable")
	AppLogger.log_info("Spieler gestorben — Respawn in 2s.", LOG_CAT)
	# ADR-036/ADR-037: ein Tod ist ENTWEDER PvP ODER PvE — nie beides. Erst
	# den PvP-Zweig versuchen; nur wenn der NICHT gegriffen hat (kein anderer
	# Spieler als Verursacher aufgelöst werden konnte), den PvE-Zweig
	# (Gravestone-Loot) auslösen.
	if not _apply_pvp_death_loss_if_applicable(record):
		_apply_pve_death_loot_if_applicable()
	_bus.player().emit_player_died()
	_respawn_timer = get_tree().create_timer(2.0)
	_respawn_timer.timeout.connect(_respawn)

## ADR-036: PvP-Tod-Verlust. Läuft immer auf demselben Node, auf dem
## take_damage_record() den Tod ausgelöst hat — für PvP-Treffer ist das
## bereits ausschließlich die Autorität (siehe _on_interacted()-Gate oben,
## ADR-025/032), kein separater Authority-Check hier nötig.
##
## "War das ein PvP-Tod?" wird HIER erkannt (record.attacker_peer_id löst auf
## einen ANDEREN Spieler auf), nicht in CombatSystem — resolve_pvp_hit() weiß
## bereits beim Treffer, dass es PvP war, aber der TOD selbst ist ein
## separates, asynchrones Ereignis (health_changed → died, ggf. erst nach
## mehreren Treffern). record.attacker_peer_id ist der einzige Träger dieser
## Information bis hierher (ADR-019).
##
## Gibt true zurück wenn PvP-Verlust tatsächlich angewendet wurde — der
## Rückgabewert entscheidet in _on_player_died(), ob stattdessen der
## PvE-Zweig (ADR-037) greifen muss. false deckt sowohl "war eindeutig kein
## PvP" (record null/attacker_peer_id -1) als auch "sah wie PvP aus, aber
## Auflösung ist fehlgeschlagen" ab — beide Fälle sollen in den PvE-Zweig
## durchfallen, damit ein Tod nie komplett folgenlos bleibt.
func _apply_pvp_death_loss_if_applicable(record: DamageRecord) -> bool:
	if not is_instance_valid(record) or record.attacker_peer_id == -1:
		return false
	if not is_instance_valid(_ctx):
		return false
	var death_loss: PvPDeathLossService = _ctx.get_pvp_death_loss()
	if not is_instance_valid(death_loss):
		return false

	var killer_player_id := _resolve_player_uuid(record.attacker_peer_id)
	var victim_player_id := _resolve_player_uuid(_owner_peer_id)
	if killer_player_id.is_empty() or victim_player_id.is_empty() or killer_player_id == victim_player_id:
		return false

	death_loss.apply_death_loss(victim_player_id, killer_player_id)
	return true

## ADR-037: PvE-Tod-Loot (Grab-Hybrid-Timer) — Gegenstück zu
## _apply_pvp_death_loss_if_applicable() für den "nicht PvP"-Fall. Läuft aus
## demselben Grund ausschließlich auf der Autorität (siehe dortiger
## Kommentar), kein separater Guard nötig.
func _apply_pve_death_loot_if_applicable() -> void:
	if not is_instance_valid(_ctx):
		return
	var death_loot: DeathLootService = _ctx.get_death_loot()
	if not is_instance_valid(death_loot):
		return
	var victim_player_id := _resolve_player_uuid(_owner_peer_id)
	if victim_player_id.is_empty():
		return
	death_loot.handle_pve_death(victim_player_id, global_position)

func _respawn() -> void:
	global_position = _spawn_position
	if is_instance_valid(health):
		health.reset()
	velocity        = Vector3.ZERO
	_is_dead        = false
	_jump_requested = false
	add_to_group("interactable")
	_bus.player().emit_player_respawned()
	AppLogger.log_info("Spieler respawnt.", LOG_CAT)

# ─────────────────────────────────────────────
# Reiten
# ─────────────────────────────────────────────

func is_mounted() -> bool:
	return _mount.is_mounted()

func get_mount() -> PetComponent:
	return _mount.get_pet()

## Besteigt pet. Gibt "" bei Erfolg zurück, sonst einen Grund-Schlüssel (siehe
## PlayerMount.can_mount(), dazu "dead", "not_solo", "busy").
func try_mount(pet: PetComponent) -> String:
	if _is_dead:
		return "dead"
	if not is_multiplayer_authority():
		return "not_authority"
	var world: WorldService = _ctx.get_world() if is_instance_valid(_ctx) else null
	if not is_instance_valid(world) or not world.is_solo_world():
		return "not_solo"
	var reason := PlayerMount.can_mount(global_position, _owner_peer_id, pet, _mount.is_mounted())
	if reason != "":
		return reason
	_mount.mount(pet)
	_ladder.reset()
	_update_mount()
	return ""

## Steigt ab (no-op ohne Reittier). Das Tier bleibt an der Stelle stehen und folgt danach wieder.
func dismount() -> void:
	if not _mount.is_mounted():
		return
	_mount.dismount()
	if is_instance_valid(visuals):
		visuals.position.y = 0.0

## Jeden Physik-Frame: Reittier an den Reiter hängen, Sitzhöhe halten. Ist das Tier
## verschwunden (z.B. freigegeben), wird sauber abgestiegen.
func _update_mount() -> void:
	if not _mount.is_mounted():
		if is_instance_valid(visuals) and not is_zero_approx(visuals.position.y):
			visuals.position.y = 0.0
		return
	var yaw := visuals.global_rotation.y if is_instance_valid(visuals) else global_rotation.y
	_mount.sync_pet(global_position, yaw)
	if is_instance_valid(visuals):
		visuals.position.y = _mount.seat_height()

## Harter Positions-Sprung ohne Tod/Loot/Reset-Nebenwirkungen — z.B. für
## Höhlen-Portale (CavePortalTrigger) oder andere Teleport-Trigger.
##
## Läuft ausschließlich auf der Autorität, exakt wie _respawn(): global_position
## HIER zu setzen genügt, kein eigener RPC/Broadcast nötig — _loop_free_authoritative()
## repliziert die neue Position wie jede normale Bewegung über den bestehenden
## MultiplayerSynchronizer, und der eigene Client holt sie über den ganz
## normalen _reconcile_if_needed()-Pfad ab (server_position weicht stark vom
## lokalen Predicted-State ab → _resimulate_from() springt einmalig mit, kein
## Sonderfall im Netcode nötig).
## velocity wird genullt, damit kein alter Schwung (Fallgeschwindigkeit,
## Sprung, o.ä.) mit in den neuen Ort übernommen wird.
func teleport_to(target_position: Vector3) -> void:
	if not is_multiplayer_authority():
		AppLogger.log_warn("teleport_to() auf Nicht-Autorität aufgerufen — ignoriert.", LOG_CAT)
		return
	dismount()   # Teleport lässt das Reittier zurück (es folgt dem Besitzer danach wie jedes Pet).
	global_position = target_position
	velocity        = Vector3.ZERO
	_ladder.reset()
	AppLogger.log_info("Spieler teleportiert nach %s." % str(target_position), LOG_CAT)

## ADR-015: movement_interrupted trägt jetzt peer_id — ohne den Filter würde
## JEDE Player-Instanz (auch fremde Repliken) den Effekt abspielen, sobald
## irgendein Spieler unterbrochen wird.
## _owner_peer_id statt get_multiplayer_authority() — siehe ADR-025-Hinweis
## oben in on_spawn().
func _on_action_interrupted(peer_id: int = 1) -> void:
	if peer_id != _owner_peer_id:
		return
	visuals.play_effect("interrupted")

## Event-Handler für State-Updates vom PlayerStateService via EventBus.
func _on_player_state_changed(new_state: int) -> void:
	_player_state = new_state as PlayerStateService.State

# ─────────────────────────────────────────────
# Öffentliche API — Interaktion
# ─────────────────────────────────────────────

## Blickrichtung des Spielers (horizontal, normiert): die Ausrichtung des Modells, das sich
## zur Laufrichtung dreht (PlayerVisuals.handle_rotation: yaw = atan2(dir.x, dir.z) → das
## Modell schaut entlang seiner lokalen +Z-Achse). Fallback: -Z des Spieler-Nodes.
func get_facing_direction() -> Vector3:
	var dir: Vector3 = visuals.global_transform.basis.z if is_instance_valid(visuals) else -global_transform.basis.z
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.FORWARD
	return dir.normalized()

## Zielpunkt `distance` Meter vor dem Spieler (für Graben/Bauen). y = Spielerhöhe — die
## echte Bodenhöhe kennt TerrainField (WorldService.get_terrain()).
func get_ground_target(distance: float = 2.5) -> Vector3:
	return global_position + get_facing_direction() * distance

## Blickstrahl der Kamera (Bildschirmmitte): {origin: Vector3, dir: Vector3 (normiert)}.
## Grundlage fürs Zielen im Baumodus (BuildAim) — der Bauplatz folgt dem Blick statt der
## Laufrichtung. Ohne Kamera: Kopfhöhe + Blickrichtung des Modells.
func get_view_ray() -> Dictionary:
	if is_instance_valid(camera) and is_instance_valid(camera.camera) and camera.camera.is_inside_tree():
		var cam: Camera3D = camera.camera
		return {"origin": cam.global_position, "dir": (-cam.global_transform.basis.z).normalized()}
	return {"origin": global_position + Vector3(0.0, 1.6, 0.0), "dir": get_facing_direction()}

func get_closest_interactable() -> Node3D:
	return sensor.get_closest() if is_instance_valid(sensor) else null

## Öffentlicher Lesezugriff auf die replizierte Server-Bestätigung (ADR-026,
## siehe Feld-Kommentar). Bislang nur intern (_reconcile_if_needed()) gelesen —
## IT-03 (tests/integration/test_movement_two_peer.gd) braucht einen echten,
## von außen abfragbaren Beleg, dass ein vom Client gesendeter Input die
## Autorität erreicht, dort verarbeitet und zurückrepliziert wurde, ohne
## private State-Introspektion von außerhalb der Klasse.
func get_last_processed_input_seq() -> int:
	return _last_processed_input_seq

# ─────────────────────────────────────────────
# Tier-2-Geräte-Grenzmessung (ADR-025 "Mitigationen")
# ─────────────────────────────────────────────
##
## ADR-025 verlangt explizit eine GEMESSENE, nicht geschätzte Tier-2-Grenze
## ("kein geschätzter 'sollte reichen'-Wert") — die Autorität simuliert pro
## Physik-Tick JEDEN angeschlossenen Spieler, auf Tier 2 auf demselben Gerät,
## das auch rendert. Diese statischen Felder sind reine Mess-Infrastruktur für
## GENAU diese Messung (siehe docs/tier2-device-verification.md für das
## dazugehörige manuelle Protokoll) — sie ändern kein Simulationsverhalten,
## nur Buchführung über dessen Kosten.
##
## `static var` statt Instanz-Feld: die Kosten sind pro PHYSIK-FRAME über
## ALLE authoritativ simulierten Spieler zu summieren (das ist die eigentlich
## interessante Zahl — "wie viel CPU-Zeit kostet dieser Tick den Host
## insgesamt", nicht "wie teuer ist EIN Spieler"), nicht pro Player-Instanz.

const TIER2_PERF_MAX_TRACKED_FRAMES := 600  # ~10s bei 60Hz Physik-Tickrate.

static var _tier2_frame_cost_usec: Dictionary = {}
static var _tier2_frame_order: Array[int] = []

static func _tier2_record_sample(elapsed_usec: int) -> void:
	var frame := Engine.get_physics_frames()
	if not _tier2_frame_cost_usec.has(frame):
		_tier2_frame_order.append(frame)
		_tier2_frame_cost_usec[frame] = 0
		if _tier2_frame_order.size() > TIER2_PERF_MAX_TRACKED_FRAMES:
			var oldest: int = _tier2_frame_order.pop_front()
			_tier2_frame_cost_usec.erase(oldest)
	_tier2_frame_cost_usec[frame] += elapsed_usec

## Aggregierte Statistik über die zuletzt getrackten Physik-Frames (Ring-
## puffer, siehe TIER2_PERF_MAX_TRACKED_FRAMES). `sample_frames` ist die
## Anzahl der Frames, nicht der Spieler — bei N gleichzeitig simulierten
## Spielern trägt jeder Frame die Summe aller N Einzelkosten.
static func get_tier2_perf_stats() -> Dictionary:
	if _tier2_frame_cost_usec.is_empty():
		return {"sample_frames": 0, "avg_usec": 0, "max_usec": 0, "p95_usec": 0}
	var values: Array = _tier2_frame_cost_usec.values()
	values.sort()
	var total := 0
	for v in values:
		total += v
	var p95_index := int(ceil(values.size() * 0.95)) - 1
	p95_index = clampi(p95_index, 0, values.size() - 1)
	return {
		"sample_frames": values.size(),
		"avg_usec": total / values.size(),
		"max_usec": values[values.size() - 1],
		"p95_usec": values[p95_index],
	}

## Für einen sauberen Mess-Lauf: z.B. direkt nachdem alle Ziel-Spieler
## verbunden und eingependelt sind, damit Boot-/Connect-Ausreißer nicht die
## Statistik verfälschen (siehe docs/tier2-device-verification.md Schritt 3).
static func reset_tier2_perf_stats() -> void:
	_tier2_frame_cost_usec.clear()
	_tier2_frame_order.clear()

# ─────────────────────────────────────────────
# Multiplayer-Sync (Sprint E / F-3)
# ─────────────────────────────────────────────

## Erstellt einen MultiplayerSynchronizer für Position, Rotation, Velocity und
## die zuletzt verarbeitete Eingabe-Sequenznummer.
##
## Autorität und Richtung (ADR-025):
##   Ein einzelner MultiplayerSynchronizer auf einem Node sendet immer
##   vom Autoritäts-Peer zu allen anderen Peers. Seit ADR-025 gilt für JEDES
##   Player-Node dieselbe Regel wie für EnemyNPC/Bäume/Tiere: Authority = 1
##   (Server) → Server→Clients, unabhängig davon, wem der Node "gehört"
##   (_owner_peer_id, siehe Feld-Kommentar). Kein Sonderfall "Client-Autorität
##   für den eigenen Spieler" mehr — set_multiplayer_authority(1) passiert
##   bereits in _ready(), bevor on_spawn() (und damit diese Methode) läuft.
##
## last_processed_input_seq (ADR-026):
##   Zusätzliches repliziertes Feld — die Autorität teilt mit, welche
##   Eingabe-Sequenznummer sie zuletzt tatsächlich simuliert hat. Der
##   vorhersagende Client (Fall 2 im Physics-Loop) nutzt das, um im eigenen
##   Ringpuffer den passenden vorhergesagten Zustand zu finden und bei
##   Abweichung zu reconcilieren (_reconcile_if_needed()). Für fremde Spieler
##   und für die Autorität selbst ungenutzt, aber harmlos (kleines int-Feld).
##
## Interval:
##   replication_interval = 0.05s → 20 Hz. Ausreichend für flüssige Bewegung,
##   deutlich weniger Bandbreite als per-frame (60+ Hz). Unabhängig von der
##   Eingabe-Übertragungsrate (submit_movement_input() läuft pro Physik-Tick,
##   s. ADR-025 "UNRELIABLE" in NetworkContract.gd) — zwei getrennte Frequenzen
##   für zwei getrennte Zwecke (Ergebnis-Replikation vs. Input-Übertragung).
func _setup_multiplayer_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSync"
	sync.replication_interval = 0.05   # 20 Hz — Bandbreite/Flüssigkeit-Kompromiss
	add_child(sync)
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	config.add_property(NodePath(".:velocity"))
	config.add_property(NodePath(".:_last_processed_input_seq"))
	sync.replication_config = config
	AppLogger.log_debug(
		"MultiplayerSynchronizer erstellt (position, rotation, velocity, last_processed_input_seq, 20Hz).",
		LOG_CAT
	)

## Jede Entity, die interagierbar ist, hängt ihre Interaktion über
## InteractableComponent ein (HarvestableEntity, AnimalBase, QuestNPC, EnemyAttack/
## EnemyNPC) — dessen _ready() setzt "interactable_components" IMMER als Meta auf
## den Parent (Liste, ADR-035 — ein Node kann mehrere InteractableComponents
## tragen, z.B. Player: "attack_player" + "trade_request"), bevor der Parent in
## die Gruppe "interactable" gelangt. Ein Target ohne diese Meta kann also
## strukturell nicht in der Gruppe stehen; Child-Traversal- und
## Synthetic-Action-Fallbacks dafür waren totes Verteidigungs-Code (0 Aufrufer,
## siehe Round-37-Cleanup) und sind entfernt.
func get_context_actions() -> Array[InteractableAction]:
	var target := get_closest_interactable()
	if not is_instance_valid(target):
		return []
	return _context_actions_for(target)

## Alle Aktionen für ALLE aktuell in Reichweite befindlichen Interactables, nicht nur das
## eine "closest"-Ziel (BUGFIX 2026-09-26, "Kontextmenü soll alles anzeigen was in der
## Nähe ist"): manche Objekte mit großer Collision-Box (z.B. Leiter) verdecken andere nahe
## Objekte (Erz) für den Tap-Raycast (InteractionTargetPicker._solid_hit_distance()) — über
## das Kontextmenü sollen sie trotzdem erreichbar sein, ganz ohne dass man sie antippen kann.
## Reihenfolge: das aktuell ausgewählte Ziel (Tap oder Autodetect, get_closest_interactable())
## zuerst, damit der Spieler im Menü sofort sieht, worauf sich seine Auswahl bezieht — der
## Rest in der Reihenfolge, in der der Sensor sie meldet.
func get_all_nearby_context_actions() -> Array[InteractableAction]:
	if not is_instance_valid(sensor):
		return []

	var ordered: Array[Node3D] = []
	var selected := get_closest_interactable()
	if is_instance_valid(selected):
		ordered.append(selected)
	for candidate in sensor.get_all_candidates():
		if candidate != selected:
			ordered.append(candidate)

	var result: Array[InteractableAction] = []
	# Label-Präfix nur wenn wirklich mehrere Ziele beitragen — bei genau einem bleibt es wie
	# gehabt ("Eiche fällen" statt "OakTree: Eiche fällen"). Ohne Präfix wären z.B. zwei
	# "Untersuchen"-Buttons (Leiter + Erz) im Menü nicht unterscheidbar — der Spieler soll
	# klar sehen, WELCHES Objekt er aus der Nähe gerade auswählt.
	var prefix_labels := ordered.size() > 1
	for target in ordered:
		var target_actions := _context_actions_for(target)
		if prefix_labels:
			for action in target_actions:
				action.label = "%s: %s" % [target.name, action.label]
		result.append_array(target_actions)
	return result

## Baut die Aktionsliste für EIN Interactable — ausgelagert aus get_context_actions(),
## damit get_all_nearby_context_actions() dieselbe Logik pro Ziel wiederverwenden kann,
## statt sie zu duplizieren.
func _context_actions_for(target: Node3D) -> Array[InteractableAction]:
	AppLogger.log_debug("Kontext für '%s'." % target.name, LOG_CAT)

	if not target.has_meta("interactable_components"):
		AppLogger.log_error(
			(
				"get_context_actions(): '%s' ist in Gruppe 'interactable' ohne "
				+ "'interactable_components'-Meta — Entity wurde nicht über InteractableComponent aufgesetzt."
			) % target.name,
			LOG_CAT
		)
		return []

	var comps: Array = target.get_meta("interactable_components")
	var actions: Array[InteractableAction] = []
	for comp in comps:
		if is_instance_valid(comp):
			actions.append_array((comp as InteractableComponent).get_actions())

	# ADR-015: peer_id kommt von HIER (der anfragende Spieler), nicht vom
	# IEntityContext des Interactables — dessen owner_peer_id ist "wem das
	# Objekt gehört" (meist 1), nicht "wer gerade interagiert".
	# _owner_peer_id statt get_multiplayer_authority() — siehe ADR-025-Hinweis
	# oben in on_spawn(). Für DIESEN Player-Node (self) ist _owner_peer_id
	# exakt "wer gerade interagiert", weil es der Spieler ist, dessen Sensor
	# gerade get_context_actions() aufruft.
	var acting_peer_id := _owner_peer_id
	for action in actions:
		action.peer_id = acting_peer_id

	AppLogger.log_info("%d Aktion(en) für '%s'." % [actions.size(), target.name], LOG_CAT)
	return actions
