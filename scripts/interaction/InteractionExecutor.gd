extends ServiceNode
# justified: on_ready() registriert EventBus-Connections; Interaction-Queue laeuft per ServiceTicker.
class_name InteractionExecutor

## InteractionExecutor — verwaltet den zeitlichen Ablauf von Interaktionen.
##
## Umbenannt von "InteractionBuilder" (alter Dateiname: InteractionBuilder.gd) — der Begriff "Builder" impliziert ein
## Erzeugungsmuster (GoF Builder), was hier falsch ist. Dieser Service
## FÜHRT Aktionen AUS, er baut keine Objekte.
##
## Früher hatte dieser Service eigene Signale (interaction_started, etc.) die
## WorldEvents dupliziert haben. Jetzt emittiert er ausschließlich über
## EventBus.world — eine einzige Signalquelle für alle Interaktions-Events.
##
## ADR-015 / MIGRATION-015 Phase 3: State ist jetzt PRO SPIELER, nicht mehr
## global. Vorher blockierte Spieler A's laufende Interaktion (Baum fällen,
## abbauen, fangen) execute_action() für JEDEN anderen Spieler — der
## Normalfall sobald zwei Spieler gleichzeitig etwas tun, nicht nur ein
## Edge-Case. peer_id kommt aus InteractableAction.peer_id, das
## Player.get_context_actions() beim Bau der Aktion auf _owner_peer_id (ADR-025)
## des anfragenden Spielers setzt (siehe dort) — nicht vom Interactable selbst.

const LOG_CAT := "InteractionExecutor"

## Abhängigkeiten via DI
var _player_states: PlayerStateService
var _stat_modifiers: StatModifierService
var _bus: IEventBus
## ADR-021 (R-5), Option C: Late-Inject wie bei Inventory/Quest/SkillSystem —
## für report_domain_event("interaction_finished", …) in _on_tween_finished().
## Bewusst NICHT über configure()/BootstrapConfig.tres (Boot-Reihenfolge, siehe
## NetworkBridge._world-Kommentar für dasselbe Muster) — BootPipeline injiziert
## automatisch in jeden Service mit inject_network_bridge()-Methode.
var _network: NetworkBridge = null

## Laufender Interaktionszustand — pro Spieler.
## { peer_id: { "action": InteractableAction, "tween": Tween } }
var _active: Dictionary = {}

## BUGFIX (2026-09-20, "Tier fangen/Interaktion läuft doppelt ab — zwei
## identische Pets an derselben Position, Physik explodiert"): der
## _active-Guard unten schützt nur gegen ÜBERLAPPENDE Starts derselben
## Aktion (peer_id ist währenddessen belegt). Er schützt NICHT gegen zwei
## sehr kurz aufeinanderfolgende, aber NICHT überlappende execute_action()-
## Aufrufe für dieselbe (peer_id, action.id)-Kombination — z.B. wenn
## interaction_execute_requested aus irgendeinem Grund (doppeltes
## Touch-Event, doppelt gefeuertes UI-Signal) zweimal kurz hintereinander
## emittiert wird. Beobachtet im Log: zwei komplette 'Tier fangen'-Durchläufe
## im selben Sekundenfenster, dadurch zwei 'Zahmes Boar2'-Pets exakt an
## derselben Position gespawnt → deren CharacterBody3D-Capsules überlappen
## komplett → Godots Physik-Auflösung schießt eines auf absurde Koordinaten
## (>1e18 units) → look_at()-Spam + Massiv-Lag (siehe PetComponent.gd:144).
## Fix: kurzes Debounce-Fenster pro (peer_id, action.id) — unabhängig davon,
## ob die erste Ausführung inzwischen schon fertig ist.
const DUPLICATE_ACTION_COOLDOWN_MSEC := 500
## { peer_id: { "action_id": String, "msec": int } }
var _last_started: Dictionary = {}

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

# ─────────────────────────────────────────────
# Phase 4: Configure (Enterprise DI)
# ─────────────────────────────────────────────
func configure(deps: ServiceDeps) -> void:
	_player_states  = deps.get_optional(ServiceKeys.PLAYER_STATES)  as PlayerStateService
	_stat_modifiers = deps.get_optional(ServiceKeys.STAT_MODIFIERS) as StatModifierService
	_bus            = deps.require(ServiceKeys.EVENT_BUS)            as IEventBus
	# ADR-020 / R-1 (Round 43): StatModifierService war hier nie mehr als ein
	# get_optional() OHNE passenden Eintrag im deps-Array von BootstrapConfig.tres
	# ("playerstates", "event_bus") — die Yield-Skalierung lief in Produktion also
	# schon vorher immer ungemoddet (x1.0), nur Tests konnten sie durch manuelles
	# Setzen des Felds überhaupt beobachten. Mit der Verschiebung der Loot-
	# Berechnung nach InteractionResolver (das stat_modifiers echt vom
	# IEntityContext der Entity bekommt, siehe HarvestableEntity._on_interacted())
	# ist der Dep hier vollständig entfallen, nicht nur ungenutzt.
	AppLogger.log_debug("Konfiguriert mit PlayerStates + IEventBus.", LOG_CAT)

# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────
func on_ready() -> void:
	_bus.player().movement_interrupted.connect(cancel_interaction)
	_bus.ui().interaction_execute_requested.connect(execute_action)
	AppLogger.log_info("InteractionExecutor bereit.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func execute_action(action: InteractableAction) -> void:
	var peer_id := action.peer_id

	if not _player_states or not _player_states.is_free(peer_id):
		AppLogger.log_debug(
			"Abbruch (Spieler %d): beschäftigt oder Service fehlt." % peer_id, LOG_CAT
		)
		return

	if _active.has(peer_id):
		return

	# Dedupe-Guard (siehe Klassenkommentar zu _last_started oben): dieselbe
	# Aktion für denselben Spieler innerhalb des Cooldown-Fensters erneut
	# angefragt → als Duplikat verwerfen, statt ein zweites Mal auszuführen.
	var last: Dictionary = _last_started.get(peer_id, {})
	if last.get("action_id", "") == action.id:
		var elapsed_msec: int = Time.get_ticks_msec() - int(last.get("msec", 0))
		if elapsed_msec < DUPLICATE_ACTION_COOLDOWN_MSEC:
			AppLogger.log_warn(
				"Dupliziert verworfen (Spieler %d): '%s' / id='%s' (%d ms nach letztem Start)."
				% [peer_id, action.label, action.id, elapsed_msec],
				LOG_CAT
			)
			return
	_last_started[peer_id] = {"action_id": action.id, "msec": Time.get_ticks_msec()}

	AppLogger.log_info(
		"Starte (Spieler %d): '%s' / id='%s' (%.1fs)" % [peer_id, action.label, action.id, action.duration],
		LOG_CAT
	)
	_active[peer_id] = {"action": action, "tween": null}

	_player_states.set_state(PlayerStateService.State.BUSY, peer_id)

	# Werkzeug-Geschwindigkeitsbonus (Axt/Spitzhacke): skaliert nur die
	# clientseitig sichtbare Tween-Dauer, nicht die Drop-Menge (die läuft
	# separat über data.yield_stat_id auf dem Autoritäts-Peer, siehe
	# InteractionResolver.resolve()). Rein kosmetisch/Pacing — daher ohne
	# Autoritäts-Guard hier zulässig, siehe Klassenkommentar oben.
	var effective_duration := action.duration
	if not action.speed_stat_id.is_empty() and is_instance_valid(_stat_modifiers) and is_instance_valid(_network):
		var player_id := _network.get_player_id_for_peer(peer_id)
		if not player_id.is_empty():
			var speed_mult: float = _stat_modifiers.get_effective_stat(action.speed_stat_id, 1.0, player_id)
			if speed_mult > 0.0:
				effective_duration = action.duration / speed_mult

	_bus.world().emit_interaction_started(action.id, action.label, effective_duration)

	var tween := create_tween()
	_active[peer_id]["tween"] = tween
	tween.tween_interval(effective_duration)
	tween.finished.connect(_on_tween_finished.bind(peer_id))

func cancel_interaction(peer_id: int = 1) -> void:
	if not _active.has(peer_id):
		return

	var entry: Dictionary = _active[peer_id]
	var action: InteractableAction = entry["action"]
	var action_id := action.id
	var label     := action.label
	_cleanup(peer_id)

	AppLogger.log_info("Abgebrochen (Spieler %d): '%s' / id='%s'" % [peer_id, label, action_id], LOG_CAT)
	_bus.world().emit_interaction_cancelled(action_id, label)

	if _player_states:
		_player_states.set_state(PlayerStateService.State.FREE, peer_id)

func is_busy(peer_id: int = 1) -> bool:
	return _active.has(peer_id)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _on_tween_finished(peer_id: int = 1) -> void:
	if not _active.has(peer_id):
		return

	var completed: InteractableAction = _active[peer_id]["action"]
	_cleanup(peer_id)

	AppLogger.log_info(
		"Erfolgreich (Spieler %d): '%s' / id='%s'" % [peer_id, completed.label, completed.id], LOG_CAT
	)
	_bus.world().emit_interaction_finished(completed.id, completed.label)
	# ADR-021 (R-5), Option C: zusätzlich zum obigen, rein lokalen UI-Signal
	# (InteractionUIController etc. brauchen es pro Peer für Fortschrittsbar-
	# Cleanup) melden wir dasselbe Ereignis an die Autorität, damit
	# INTERACT-Quest-Objectives auch für Nicht-Host-Spieler trackbar sind.
	# peer_id ist hier der lokal bekannte, echte Wert (Schlüssel von _active) —
	# im Tier-2/3-Fall verwirft NetworkBridge ihn ohnehin und ersetzt ihn durch
	# den serverseitig aus dem RPC-Sender ermittelten Wert (siehe dort).
	if is_instance_valid(_network):
		_network.report_domain_event(
			"interaction_finished", {"action_id": completed.id, "label": completed.label}, peer_id
		)

	# ADR-020 / R-1 (Round 43): Loot-Roll + XP-Bemessung laufen NICHT mehr hier.
	# InteractionExecutor läuft pro Peer lokal (siehe ADR-020-Root-Cause-Analyse) —
	# jede Berechnung hier wäre grundsätzlich client-seitig fälschbar, unabhängig
	# von einem nachgelagerten Autoritäts-Check auf das *Ergebnis*. Die Berechnung
	# ist jetzt in InteractionResolver.resolve() verschoben, aufgerufen aus dem
	# bereits authority-geguardeten _on_interacted()-Hook der jeweiligen Entity
	# (HarvestableEntity, EnemyNPC), NICHT von hier aus. completed.on_complete
	# unten löst exakt diesen Hook aus (via InteractableComponent._handle_completion()).
	#
	# Was hier bleibt, ist bewusst rein visuell/lokal (kein Reward, nichts
	# Exploitbares): Tween-Abschluss, interaction_finished-Signal (Fortschrittsbar-
	# Cleanup), inspect_text-Flavortext.
	if not completed.inspect_text.is_empty():
		_bus.world().emit_interaction_reward_text(completed.inspect_text)

	# ADR-015 / MIGRATION-015 Phase 4: peer_id wird an on_complete durchgereicht
	# (nicht mehr implizit über Closure/Default) — jeder on_complete-Callable
	# muss peer_id als Parameter deklarieren, auch wenn er ihn nicht braucht.
	if completed.on_complete.is_valid():
		completed.on_complete.call(peer_id)

	if _player_states:
		_player_states.set_state(PlayerStateService.State.FREE, peer_id)

func _cleanup(peer_id: int) -> void:
	if not _active.has(peer_id):
		return
	var tween: Tween = _active[peer_id].get("tween")
	if is_instance_valid(tween):
		tween.kill()
	_active.erase(peer_id)

func on_cleanup() -> void:
	if _bus.player().movement_interrupted.is_connected(cancel_interaction):
		_bus.player().movement_interrupted.disconnect(cancel_interaction)
	if _bus.ui().interaction_execute_requested.is_connected(execute_action):
		_bus.ui().interaction_execute_requested.disconnect(execute_action)
	for peer_id in _active.keys().duplicate():
		_cleanup(peer_id)
