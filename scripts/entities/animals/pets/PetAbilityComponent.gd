class_name PetAbilityComponent
extends Node

## PetAbilityComponent — führt EINE Pet-Fähigkeit autonom aus (siehe PetAbilities
## für die IDs). PetComponent erzeugt pro Fähigkeit in config["abilities"] eine
## eigene Instanz und hängt sie als Kind an (siehe PetComponent._build_abilities()).
##
## ARCHITEKTUR-ENTSCHEIDUNG: Fähigkeiten laufen NICHT über den normalen
## Spieler-Interaktionspfad (InteractionExecutor — der ist pro PEER-ID
## BUSY/FREE-gated, siehe dortiger Klassenkommentar; ein Pet über die peer_id
## seines Besitzers laufen zu lassen würde jede eigene Aktion des Besitzers
## blockieren, sobald das Pet gerade sammelt/kämpft, und umgekehrt). Stattdessen
## führt diese Komponente ihre eigene, lokale Wartezeit (siehe _state-Automat
## unten) und ruft danach denselben autoritäts-geguardeten Einstiegspunkt auf,
## den auch InteractableComponent._handle_completion() für einen Spieler nutzt:
## WorldService.request_entity_interaction(uuid, action_id, owner_peer_id) für
## Ernte-/Kampf-Ziele, bzw. EventBus.world().terrain_edit_requested() für Graben
## (derselbe Weg wie GroundToolController._start()). Loot/XP/Autoritäts-Prüfung
## laufen dadurch unverändert über die bestehende, servereigene Pipeline — ein
## Pet kann strukturell nichts anderes auslösen als ein Spieler an gleicher
## Stelle auch könnte.
##
## BEHOBENE EINSCHRÄNKUNG (2026-09-26, "Pets können Ressourcen manchmal nicht
## abbauen/sammeln", Kampf war unauffällig, weil Gegner dem Besitzer meist
## näher bleiben als statische Bäume/Erze/Pilze): die serverseitige
## Reichweitenprüfung (EntityOrchestrator.resolve_for_player() bzw.
## WorldService._max_interaction_range_for()) maß bislang IMMER die Distanz
## vom BESITZER-Spieler zum Ziel, nicht vom Pet selbst — SEARCH_RADIUS (7m,
## siehe unten) bezieht sich aber auf die Position des PETS, das selbst schon
## einige Meter vom Besitzer entfernt sein kann. _complete_harvest()/_do_attack()
## übergeben WorldService.request_entity_interaction() deshalb jetzt zusätzlich
## die eigene entity_uuid als actor_uuid — die Autorität misst die Reichweite
## dann ab dem Pet selbst (siehe EntityOrchestrator.resolve_for_player()).

const LOG_CAT := "PetAbility"

## DIAGNOSE (2026-10-01, "Pet baut nur ab, wenn ich es nah hinlotse" — Symptom
## tritt NICHT beim Scannen/Zielfinden auf (laut Rückmeldung funktioniert das),
## sondern irgendwo zwischen "Ziel gefunden" und "Aktion erfolgreich". Bisher
## loggte diese Datei NUR Fehlerfälle (leere entity_uuid etc.), die laut den
## mitgeschickten Logs nie auftreten — der eigentliche Ablauf (State-Wechsel,
## Distanzen, der tatsächlich abgeschickte Request) war bisher unsichtbar.
## STATUS_LOG_INTERVAL throttled die State-Logs auf ca. 1x/Sekunde statt jeden
## Physik-Frame (60x/Sekunde) — verhindert Logspam, behält aber genug
## Auflösung, um z.B. "Pet bleibt bei 2.3m stehen, kommt nie unter
## HARVEST_ARRIVE_RADIUS" sichtbar zu machen.
const STATUS_LOG_INTERVAL := 1.0
var _status_log_cooldown: float = 0.0

## Von PetComponent._build_abilities() gesetzt, siehe PetAbilities-Konstanten.
var ability_id: String = ""

var _pet:   PetComponent    = null
var _ctx:   IEntityContext  = null
var _bus:   IEventBus       = null
var _owner_peer_id:   int    = 1
var _owner_player_id: String = ""

# ─────────────────────────────────────────────
# Gemeinsame Tuning-Werte
# ─────────────────────────────────────────────
const SEARCH_RADIUS   := 12.0  ## Wie weit ein Pet nach einem Ziel sucht (siehe Klassenkommentar oben).
## BUGFIX (2026-09-28, "Pets bauen nur ab, wenn ich in der Nähe stehe und mich
## nicht bewege"): vorher 7.0 — kombiniert mit PetComponent._follow_distance
## (2.5m, siehe dortiger LEASH_RADIUS-Kommentar für die eigentliche Ursache)
## bedeutete das faktisch "nur innerhalb von 7m um den STEHENDEN Besitzer".
## Jetzt größer UND unabhängig von der Leine (PetComponent.LEASH_RADIUS=16m) —
## ein Pet, das gerade irgendwo innerhalb der Leine steht, kann von DORT aus
## eigenständig 12m weit nach dem nächsten Ziel schauen, dorthin laufen, und
## von der NEUEN Position aus erneut scannen — die effektive Reichweite wächst
## dadurch mit jedem Ziel-Wechsel, statt an den Besitzer gekettet zu bleiben.
const SCAN_INTERVAL   := 1.5   ## Sekunden zwischen zwei Ziel-Suchen im IDLE-Zustand.

# Ernte-Fähigkeiten (gathering/woodcutting/mining)
## BUGFIX (2026-09-27, "Pets laufen zur Ressource, bleiben aber davor stehen statt
## abzubauen"): 1.4 m lag zu nah am Punkt, an dem _steer_toward()'s Bremsrampe
## (Geschwindigkeit sinkt proportional zu (dist - stop_distance)/3.0, siehe
## PetComponent._steer_toward()) schon fast auf null abgefallen ist — das Pet
## kroch dadurch nur noch hauchdünn weiter und blieb praktisch dauerhaft knapp
## AUSSERHALB des Radius stehen, has_arrived_at_movement_target() wurde nie true.
## Deutlich großzügiger angesetzt (wie GroundToolController.TARGET_DISTANCE für den
## Spieler) — bleibt klar unter dem serverseitigen Interaktions-Limit
## (InteractableComponent.detection_radius 3.0 + WorldService._INTERACTION_RANGE_MARGIN
## 1.5 = 4.5 m), löst das "Steckenbleiben" aber zuverlässig auf, weil die
## Bremsrampe den Radius jetzt erreicht, bevor die Geschwindigkeit gegen null geht.
const HARVEST_ARRIVE_RADIUS := 2.2

# Kampf
const ATTACK_RANGE      := 1.7
const ATTACK_CHASE_SLACK := 1.3  ## Toleranz bevor erneut auf das Ziel zubewegt wird (verhindert Zittern).
const ATTACK_COOLDOWN   := 1.3

# Graben
const DIG_RADIUS    := 2.5
const DIG_ARRIVE     := 0.6
const DIG_DURATION   := 2.0
const DIG_COOLDOWN   := 5.0

enum State { IDLE, SEEKING, ACTING }

var _state: State = State.IDLE
var _target: Node3D = null
var _act_time_left: float = 0.0
var _scan_cooldown: float = 0.0
var _attack_cooldown: float = 0.0

var _dig_point: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()

## Lese-Zugriff fürs Pet-Menü (Filter "was tut das Pet gerade"): aktueller
## Zustand dieser Fähigkeit als State-Wert (IDLE/SEEKING/ACTING). Graben führt
## einen eigenen Zustand (_dig_state, siehe _process_digging()), alle anderen
## Fähigkeiten laufen über _state. Nur auf der Besitzer-Kopie aussagekräftig —
## nur dort läuft _physics_process() (Autoritäts-Guard).
func get_activity_state() -> int:
	if ability_id == PetAbilities.DIGGING:
		return int(_dig_state)
	return int(_state)

## Aufgerufen von PetComponent unmittelbar nach add_child(). Pflicht-Setup —
## ohne gültigen ctx/bus bleibt die Komponente untätig (siehe _physics_process()-
## Guard), loggt aber nicht bei jedem Frame, nur einmalig hier.
func setup(pet: PetComponent, ctx: IEntityContext, bus: IEventBus, owner_peer_id: int, owner_player_id: String) -> void:
	_pet = pet
	_ctx = ctx
	_bus = bus
	_owner_peer_id = owner_peer_id
	_owner_player_id = owner_player_id
	_rng.randomize()
	if not is_instance_valid(_ctx) or not is_instance_valid(_ctx.get_world()):
		AppLogger.log_warn(
			"setup('%s'): kein WorldService im Context — Fähigkeit bleibt untätig." % ability_id, LOG_CAT
		)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_pet) or not is_instance_valid(_ctx):
		return
	# Nur die Netzwerk-Autorität des Pets entscheidet — Pets sind
	# client-autoritativ (siehe PetComponent.on_spawn()), genau wie deren
	# eigene Bewegungslogik in PetComponent._physics_process().
	if not _pet.is_multiplayer_authority():
		return
	if _pet.is_ridden():
		return   # Reittier wird gerade geritten — keine eigenständigen Aktionen.
	match ability_id:
		PetAbilities.COMBAT:
			_process_combat(delta)
		PetAbilities.DIGGING:
			_process_digging(delta)
		_:
			if PetAbilities.is_harvest_ability(ability_id):
				_process_harvest(delta)

func _exit_tree() -> void:
	_unclaim_target()

# ─────────────────────────────────────────────
# Sammeln / Abbauen / Fällen (gathering, mining, woodcutting)
# ─────────────────────────────────────────────

func _process_harvest(delta: float) -> void:
	_status_log_cooldown -= delta
	var should_log := _status_log_cooldown <= 0.0
	if should_log:
		_status_log_cooldown = STATUS_LOG_INTERVAL

	match _state:
		State.IDLE:
			_scan_cooldown -= delta
			if _scan_cooldown > 0.0:
				return
			_scan_cooldown = SCAN_INTERVAL
			_target = _find_harvest_target()
			if is_instance_valid(_target):
				var dist := _pet.global_position.distance_to(_target.global_position)
				AppLogger.log_info(
					"'%s' (%s): Ziel gefunden '%s' @ %.1fm (SEARCH_RADIUS=%.1f) — wechsle IDLE→SEEKING." \
					% [_pet.get_pet_name(), ability_id, _target.name, dist, SEARCH_RADIUS],
					LOG_CAT
				)
				_claim_target(_target)
				_state = State.SEEKING
			elif should_log:
				AppLogger.log_debug(
					"'%s' (%s): IDLE-Scan ohne Treffer (Pet-Pos=%s, SEARCH_RADIUS=%.1f)." \
					% [_pet.get_pet_name(), ability_id, _pet.global_position, SEARCH_RADIUS],
					LOG_CAT
				)

		State.SEEKING:
			if not _target_still_valid():
				AppLogger.log_info(
					"'%s' (%s): Ziel während SEEKING ungültig geworden (despawnt/gepoolt) — zurück zu IDLE." \
					% [_pet.get_pet_name(), ability_id],
					LOG_CAT
				)
				_reset_idle()
				return
			var dist_seek := _pet.global_position.distance_to(_target.global_position)
			if not _pet.request_movement(self, _target.global_position, HARVEST_ARRIVE_RADIUS):
				if should_log:
					AppLogger.log_debug(
						"'%s' (%s): SEEKING blockiert — eine andere Fähigkeit hält gerade die Bewegungssteuerung (dist=%.2fm)." \
						% [_pet.get_pet_name(), ability_id, dist_seek],
						LOG_CAT
					)
				return  # eine andere Fähigkeit dieses Pets steuert gerade — warten
			if _pet.has_arrived_at_movement_target():
				_act_time_left = _resolve_duration(_target)
				AppLogger.log_info(
					"'%s' (%s): angekommen bei '%s' (dist=%.2fm <= ARRIVE_RADIUS=%.1f) — wechsle SEEKING→ACTING, Dauer=%.1fs." \
					% [_pet.get_pet_name(), ability_id, _target.name, dist_seek, HARVEST_ARRIVE_RADIUS, _act_time_left],
					LOG_CAT
				)
				_state = State.ACTING
			elif should_log:
				AppLogger.log_debug(
					"'%s' (%s): unterwegs zu '%s' — dist=%.2fm (Ziel: <= %.1fm), Pet-Pos=%s, Ziel-Pos=%s." \
					% [_pet.get_pet_name(), ability_id, _target.name, dist_seek, HARVEST_ARRIVE_RADIUS,
					   _pet.global_position, _target.global_position],
					LOG_CAT
				)

		State.ACTING:
			if not _target_still_valid():
				AppLogger.log_info(
					"'%s' (%s): Ziel während ACTING ungültig geworden — zurück zu IDLE, Fortschritt verloren." \
					% [_pet.get_pet_name(), ability_id],
					LOG_CAT
				)
				_reset_idle()
				return
			# Steuerung explizit auf das (unbewegliche) Ziel halten, damit das Pet
			# nicht während der Wartezeit wieder Richtung Besitzer abdriftet.
			_pet.request_movement(self, _target.global_position, HARVEST_ARRIVE_RADIUS)
			_act_time_left -= delta
			if should_log:
				AppLogger.log_debug(
					"'%s' (%s): ACTING, noch %.1fs bis Abschluss (dist=%.2fm)." \
					% [_pet.get_pet_name(), ability_id, maxf(0.0, _act_time_left),
					   _pet.global_position.distance_to(_target.global_position)],
					LOG_CAT
				)
			if _act_time_left <= 0.0:
				_complete_harvest()

func _find_harvest_target() -> Node3D:
	var allowed := PetAbilities.harvest_type_ids_for(ability_id)
	if allowed.is_empty():
		AppLogger.log_warn(
			"_find_harvest_target(): ability_id='%s' hat keine harvest_type_ids_for()-Einträge — Fähigkeit falsch konfiguriert?" % ability_id,
			LOG_CAT
		)
		return null
	return _find_nearest_in_group("interactable", func(node: Node) -> bool:
		if not node.has_method("_get_entity_type_id"):
			return false
		if not (String(node.call("_get_entity_type_id")) in allowed):
			return false
		return not bool(node.get_meta("pet_claimed", false))
	, SEARCH_RADIUS)

## Liest die Interaktions-Dauer aus der InteractableComponent des Ziels (Meta
## "interactable_components", siehe WorldService._max_interaction_range_for()
## für dasselbe Muster) — Fallback 2.0s falls das Meta fehlt (sollte bei jeder
## HarvestableEntity-Instanz gesetzt sein, siehe InteractableComponent._ready()).
func _resolve_duration(node: Node) -> float:
	var comps: Array = node.get_meta("interactable_components", [])
	for comp in comps:
		if is_instance_valid(comp) and comp is InteractableComponent:
			return maxf(0.2, (comp as InteractableComponent).data.duration)
	return 2.0

func _resolve_action_id(node: Node) -> String:
	var comps: Array = node.get_meta("interactable_components", [])
	for comp in comps:
		if is_instance_valid(comp) and comp is InteractableComponent:
			return (comp as InteractableComponent).data.id
	return ""

func _complete_harvest() -> void:
	var target := _target
	var action_id := _resolve_action_id(target) if is_instance_valid(target) else ""
	if is_instance_valid(target) and not action_id.is_empty():
		var world: WorldService = _ctx.get_world()
		var uuid := world.resolve_entity_uuid(target)
		if not uuid.is_empty():
			# Bugfix 2026-09-26 (siehe Klassenkommentar oben): Reichweite ab dem
			# Pet selbst messen, nicht ab dem Besitzer — sonst lehnt die Autorität
			# eine Ernte ab, die räumlich direkt vor dem Pet stattfindet, nur weil
			# der Besitzer selbst weiter weg steht.
			var actor_uuid := world.resolve_entity_uuid(_pet)
			# DIAGNOSE (siehe Klassenkommentar oben, "Pet baut nur ab, wenn ich es nah
			# hinlotse"): das ist exakt der Moment, an dem sich entscheidet, ob die
			# Reichweite ab dem PET (korrekt) oder — falls actor_uuid aus irgendeinem
			# Grund leer ist — ab dem BESITZER (der alte Bug) gemessen wird. Wenn das
			# Problem wieder auftritt, zeigt diese Zeile, ob actor_uuid tatsächlich
			# gesetzt war, oder ob resolve_entity_uuid(_pet) silent leer zurückkam.
			AppLogger.log_info(
				"'%s' (%s): ACTING abgeschlossen — sende request_entity_interaction(uuid='%s', action='%s', peer=%d, actor_uuid='%s' [%s])." \
				% [
					_pet.get_pet_name(), ability_id, uuid, action_id, _owner_peer_id, actor_uuid,
					"Pet-Position wird verwendet" if not actor_uuid.is_empty() else "LEER — fällt auf Besitzer-Position zurück!"
				],
				LOG_CAT
			)
			world.request_entity_interaction(uuid, action_id, _owner_peer_id, actor_uuid)
			# FEATURE (Pet-XP/Level, siehe PetLeveling): optimistisch vergeben, sobald
			# der Request abgeschickt ist — kein Bestätigungs-Callback vom Server
			# verfügbar (gleiche fire-and-forget-Natur wie der Request selbst). Im
			# ganz seltenen Fall, dass der Server die Aktion doch ablehnt (z.B.
			# Reichweite knapp überschritten), bekommt das Pet ein paar XP "umsonst"
			# — unkritisch angesichts der ohnehin bewusst simplen Kurve.
			_pet.add_xp(PetLeveling.xp_reward_for(ability_id))
		else:
			AppLogger.log_warn(
				"_complete_harvest('%s'): keine entity_uuid für Ziel '%s' — Aktion nicht ausgelöst." % [ability_id, target.name],
				LOG_CAT
			)
	else:
		AppLogger.log_warn(
			"_complete_harvest('%s'): Ziel ungültig oder keine action_id auflösbar (target_valid=%s, action_id='%s') — Aktion nicht ausgelöst." \
			% [ability_id, is_instance_valid(target), action_id],
			LOG_CAT
		)
	_reset_idle()

# ─────────────────────────────────────────────
# Kampf
# ─────────────────────────────────────────────

func _process_combat(delta: float) -> void:
	match _state:
		State.IDLE:
			_scan_cooldown -= delta
			if _scan_cooldown > 0.0:
				return
			_scan_cooldown = SCAN_INTERVAL
			_target = _find_combat_target()
			if is_instance_valid(_target):
				AppLogger.log_info(
					"'%s' (combat): Gegner gefunden '%s' @ %.1fm — wechsle IDLE→SEEKING." \
					% [_pet.get_pet_name(), _target.name, _pet.global_position.distance_to(_target.global_position)],
					LOG_CAT
				)
				_claim_target(_target)
				_attack_cooldown = 0.0
				_state = State.SEEKING

		State.SEEKING:
			if not _combat_target_alive():
				_reset_idle()
				return
			if not _pet.request_movement(self, _target.global_position, ATTACK_RANGE * 0.7):
				return
			if _pet.has_arrived_at_movement_target():
				AppLogger.log_info(
					"'%s' (combat): in Angriffsreichweite von '%s' — wechsle SEEKING→ACTING." \
					% [_pet.get_pet_name(), _target.name],
					LOG_CAT
				)
				_state = State.ACTING

		State.ACTING:
			if not _combat_target_alive():
				_reset_idle()
				return
			var dist := _pet.global_position.distance_to(_target.global_position)
			if dist > ATTACK_RANGE * ATTACK_CHASE_SLACK:
				_state = State.SEEKING
				return
			# Nah dran halten (Ziel kann sich bewegen — EnemyAI verfolgt den Besitzer).
			_pet.request_movement(self, _target.global_position, ATTACK_RANGE * 0.7)
			_attack_cooldown -= delta
			if _attack_cooldown <= 0.0:
				_do_attack()
				_attack_cooldown = ATTACK_COOLDOWN

func _find_combat_target() -> Node3D:
	# "enemies" + gleichzeitig noch "interactable" = lebt noch (EnemyNPC._die()
	# entfernt die Gruppe "interactable" beim Tod, siehe dortiger Kommentar) —
	# ohne eigenen Zugriff auf EnemyAI.State (privater Zustand der Entity).
	return _find_nearest_in_group("enemies", func(node: Node) -> bool:
		if not node.is_in_group("interactable"):
			return false
		return not bool(node.get_meta("pet_claimed", false))
	, SEARCH_RADIUS)

func _combat_target_alive() -> bool:
	return _target_still_valid() and _target.is_in_group("interactable")

func _do_attack() -> void:
	if not is_instance_valid(_target):
		return
	var world: WorldService = _ctx.get_world()
	var uuid := world.resolve_entity_uuid(_target)
	if uuid.is_empty():
		AppLogger.log_warn("_do_attack(): keine entity_uuid für Kampfziel '%s'." % _target.name, LOG_CAT)
		return
	# Bugfix 2026-09-26 (siehe Klassenkommentar oben): dieselbe latente Lücke wie
	# bei der Ernte, hier bisher seltener sichtbar, weil Gegner dem Besitzer meist
	# näher bleiben als ein statischer Baum/Erz — Reichweite trotzdem korrekt ab
	# dem Pet selbst messen, nicht ab dem Besitzer.
	var actor_uuid := world.resolve_entity_uuid(_pet)
	AppLogger.log_debug(
		"'%s' (combat): Angriff — request_entity_interaction(uuid='%s', peer=%d, actor_uuid='%s')." \
		% [_pet.get_pet_name(), uuid, _owner_peer_id, actor_uuid],
		LOG_CAT
	)
	world.request_entity_interaction(uuid, "attack_enemy", _owner_peer_id, actor_uuid)
	# FEATURE (Pet-XP/Level): pro GELANDETEM Angriff, nicht erst beim Kill — ein
	# Pet bekommt keine Bestätigung, ob sein Treffer den Gegner erledigt hat
	# (Server-autoritativ, siehe PetLeveling.XP_COMBAT-Kommentar), daher der
	# kleinere Betrag pro Schwung statt ein großer Betrag nur beim Kill.
	_pet.add_xp(PetLeveling.xp_reward_for(PetAbilities.COMBAT))

# ─────────────────────────────────────────────
# Graben
# ─────────────────────────────────────────────

var _dig_state: State = State.IDLE

func _process_digging(delta: float) -> void:
	match _dig_state:
		State.IDLE:
			_scan_cooldown -= delta
			if _scan_cooldown > 0.0:
				return
			_scan_cooldown = DIG_COOLDOWN
			_dig_point = _pick_dig_point()
			_dig_state = State.SEEKING

		State.SEEKING:
			if not _pet.request_movement(self, _dig_point, DIG_ARRIVE):
				return
			if _pet.has_arrived_at_movement_target():
				_act_time_left = DIG_DURATION
				_dig_state = State.ACTING

		State.ACTING:
			_pet.request_movement(self, _dig_point, DIG_ARRIVE)
			_act_time_left -= delta
			if _act_time_left <= 0.0:
				_do_dig()
				_pet.release_movement(self)
				_dig_state = State.IDLE

func _pick_dig_point() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	var radius := _rng.randf_range(0.5, DIG_RADIUS)
	var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	return _pet.global_position + offset

## Gleicher Weg wie GroundToolController._start()/build_action() —
## EventBus.world().terrain_edit_requested() → WorldService.request_terrain_edit().
## Nur Solo unterstützt (siehe WorldService._edit_gate(): "coop_unsupported" in
## Mehrspieler-Sitzungen) — dort schlägt der Aufruf mit einem Log-Warn fehl,
## kein Crash, kein Sonderfall hier nötig.
func _do_dig() -> void:
	if not is_instance_valid(_bus):
		return
	if _owner_player_id.is_empty():
		AppLogger.log_warn("_do_dig(): keine owner_player_id — Graben nicht ausgelöst.", LOG_CAT)
		return
	AppLogger.log_info(
		"'%s' (digging): grabe an %s (owner_player_id='%s')." % [_pet.get_pet_name(), _dig_point, _owner_player_id],
		LOG_CAT
	)
	_bus.world().emit_terrain_edit_requested(_owner_player_id, WorldTerrainEditor.MODE_DIG, _dig_point)
	# FEATURE (Pet-XP/Level): optimistisch vergeben, wie bei Ernte/Kampf (siehe
	# dortiger Kommentar) — kein Bestätigungs-Callback für terrain_edit_requested.
	_pet.add_xp(PetLeveling.xp_reward_for(PetAbilities.DIGGING))

# ─────────────────────────────────────────────
# Gemeinsame Helfer
# ─────────────────────────────────────────────

func _find_nearest_in_group(group: String, filter: Callable, radius: float) -> Node3D:
	if not _pet.is_inside_tree():
		return null
	var best: Node3D = null
	var best_dist_sq := radius * radius
	for node in _pet.get_tree().get_nodes_in_group(group):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if node == _pet:
			continue
		# Siehe Bugfix-Kommentar in _target_still_valid(): geparkte (gepoolte,
		# bereits abgebaute) Entities bleiben in ihrer Gruppe UND is_inside_tree() —
		# ohne diese Prüfung würde ein Pet ein bereits abgeerntetes Geister-Ziel
		# als "nächstes" auswählen und wieder davor stehen bleiben.
		if not (node as Node3D).is_visible_in_tree():
			continue
		if filter.is_valid() and not bool(filter.call(node)):
			continue
		var d := _pet.global_position.distance_squared_to((node as Node3D).global_position)
		if d <= best_dist_sq:
			best_dist_sq = d
			best = node as Node3D
	return best

## BUGFIX ("Pets bleiben vor abgebauten Ressourcen stehen"): is_inside_tree() allein
## reicht nicht — ein geerntetes HarvestableEntity wird von EntityOrchestrator.despawn_entity()
## in den Pool zurückgegeben, dabei aber laut EntityPool.release()/_park_container-Kommentar
## nur UNSICHTBAR unter den Pool-Container reparented, NICHT aus dem Baum entfernt und NICHT
## aus Gruppen wie "interactable" ausgetragen. Ohne diese zusätzliche Prüfung blieb ein
## geparktes (bereits abgebautes) Ziel für _find_harvest_target()/_target_still_valid() auf
## ewig "gültig" — das Pet lief hin, blieb stehen (die Ernte-Aktion schlug serverseitig
## fehl, da die uuid längst aus EntityOrchestrator._entities entfernt ist) und wiederholte
## das bei jedem Scan mit demselben Geister-Ziel. is_visible_in_tree() ist exakt dieselbe
## Unterscheidung, die HarvestableEntity._on_day_advanced() bereits nutzt, um "aktiv in der
## Welt stehend" von "geparkt, wartet im Pool" zu trennen (siehe dortiger Kommentar).
func _target_still_valid() -> bool:
	return is_instance_valid(_target) and _target.is_inside_tree() and _target.is_visible_in_tree()

## Markiert ein Ziel als "von diesem Pet belegt" — verhindert, dass ein zweites
## Pet DESSELBEN Besitzers (auf demselben Peer) im selben Frame dasselbe Ziel
## anläuft. Wirkt nur lokal (Meta auf der lokalen Node-Kopie) — auf einem
## Nicht-Autoritäts-Peer sähe ein fremdes Pet dieses Meta nicht, siehe
## Klassenkommentar zur bekannten Reichweiten-Einschränkung für denselben
## strukturellen Grund (kein geteilter, replizierter "Claim"-Zustand).
func _claim_target(node: Node) -> void:
	if is_instance_valid(node):
		node.set_meta("pet_claimed", true)

func _unclaim_target() -> void:
	if is_instance_valid(_target):
		_target.remove_meta("pet_claimed")
	_target = null

func _reset_idle() -> void:
	AppLogger.log_debug(
		"'%s' (%s): zurück zu IDLE (letztes Ziel: %s)." \
		% [_pet.get_pet_name() if is_instance_valid(_pet) else "?", ability_id,
		   _target.name if is_instance_valid(_target) else "keins"],
		LOG_CAT
	)
	_unclaim_target()
	_pet.release_movement(self)
	_state = State.IDLE
	_scan_cooldown = SCAN_INTERVAL
