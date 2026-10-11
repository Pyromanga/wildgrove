class_name QuestCustomTrigger extends Area3D

## QuestCustomTrigger — generischer, wiederverwendbarer Trigger für CUSTOM-
## Quest-Objectives (QuestObjective.Type.CUSTOM).
##
## Platzierbar überall in der Welt (Lore-Punkte, geheime Bereiche, Events).
## Beim Betreten durch einen Spieler emittiert dieser Node genau einmal
## (pro Spawn-Zyklus) custom_objective_triggered(signal_key) über den
## injizierten IEventBus — signal_key muss exakt obj.target_id in der
## passenden QuestObjective entsprechen.
##
## Beispiel: Lager-Erkundung als CUSTOM-Objective.
##   signal_key = "erik_camp_explored"
##   → QuestObjective.target_id = "erik_camp_explored", type = CUSTOM (5)
##
## IEventBus wird via inject_bus() injiziert — kein AutoLoad-Zugriff
## (analog zu InteractionSensor.inject_bus(), vgl. Runde 4 EventBus-Migration).
## CollisionShape3D muss vom Aufrufer (Szene/Subklasse) gesetzt werden.

const LOG_CAT := "QuestCustomTrigger"

## Der Key der via custom_objective_triggered emittiert wird.
## Muss exakt einer QuestObjective.target_id (type=CUSTOM) entsprechen.
@export var signal_key: String = ""

## Ob der Trigger nach erstmaligem Auslösen deaktiviert wird (Default: ja —
## verhindert wiederholtes Triggern bei jedem erneuten Betreten der Zone).
@export var trigger_once: bool = true

## Optionaler Sofort-Feedback-Text (Hint-Popup, z.B. "Lager erkundet!").
## Leer = kein Popup (Default, rückwärtskompatibel zu bestehenden Platzierungen).
## Wenn gesetzt, wird er ausschließlich lokal über EventBus.ui().notification_requested
## angezeigt — NICHT die Quelle der Wahrheit für Objective-Fortschritt (das bleibt
## ausschließlich der Domain-Event-Round-Trip, siehe _on_body_entered()). Bewusst
## als eigenes Feld statt Lookup aus QuestObjective.label: dieser Trigger ist ein
## reiner, wiederverwendbarer Area3D-Mechanismus ohne Kenntnis von Quest-Daten
## (siehe Klassenkommentar) — ein Label-Lookup würde ihn an QuestService koppeln.
@export var hint_text: String = ""

var _bus: IEventBus = null
## ADR-021 (R-5): analog zu inject_bus() — optionaler Dep für report_domain_event().
## Ohne NetworkBridge feuert weiterhin nur das lokale custom_objective_triggered-
## Signal (Tier 1 unverändert), aber ein Nicht-Host-Spieler erreicht damit nie
## die Autorität — siehe _on_body_entered().
## Round 47: mit NetworkBridge injiziert, greift zusätzlich der Authority-Guard
## in _on_body_entered() (nur Autorität oder eigener Spieler melden) — siehe
## dortiger Kommentar.
var _network: NetworkBridge = null
var _has_triggered: bool = false

## Wird vom Aufrufer (EntityOrchestrator/World-Setup) nach add_child() aufgerufen.
func inject_bus(bus: IEventBus) -> void:
	_bus = bus

## Wird vom Aufrufer (EntityOrchestrator/World-Setup) nach add_child() aufgerufen,
## analog zu inject_bus() — siehe Klassenkommentar zu ADR-021 oben.
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

func _ready() -> void:
	monitoring   = true
	monitorable  = false
	body_entered.connect(_on_body_entered)
	if signal_key.is_empty():
		AppLogger.log_warn(
			"QuestCustomTrigger ohne signal_key platziert — wird nie etwas auslösen.", LOG_CAT
		)

func _on_body_entered(body: Node3D) -> void:
	if trigger_once and _has_triggered:
		return
	if not body.is_in_group("player"):
		return
	if _bus == null:
		AppLogger.log_error(
			"QuestCustomTrigger '%s': kein IEventBus injiziert — Trigger ignoriert." % signal_key,
			LOG_CAT
		)
		return
	if signal_key.is_empty():
		return

	# BUG (Round 47) — Multiplayer-Guard, fehlte bisher komplett:
	# body_entered feuert LOKAL auf JEDEM Peer, für JEDEN Body, der die Zone in
	# dessen eigener Physik-Simulation überlappt — auch für FREMDE Spieler, die
	# dieser Client nur zur Anzeige interpoliert (RemotePlayerInterpolator, kein
	# eigener Simulationspfad, siehe Player.gd _physics_process()-Kommentar,
	# Fall 3 "fremder Spieler auf meinem Client"). Ohne Guard würde ein
	# unbeteiligter Client, der bloß zusieht, wie ein ANDERER Spieler die Zone
	# durchquert, unten report_domain_event() auslösen — und weil die Autorität
	# player_id serverseitig aus dem RPC-SENDER ableitet, nicht aus dem Payload
	# (ADR-021, NetworkBridge.report_domain_event()/_rpc_report_domain_event()-
	# Kommentar), würde sich genau dieser unbeteiligte Beobachter das Objective
	# selbst gutschreiben.
	#
	# Erlaubt sind nur zwei Fälle — dieselbe Rollenteilung wie Player.gd
	# _physics_process() (ADR-025 "Tier-Kollaps"):
	#   1. is_server() (Tier-1-Solo kollabiert hier mit rein, siehe
	#      NetworkBridge.is_server()) — die Autorität sieht ohnehin die
	#      kanonische Position jedes Spielers und muss sich selbst nichts
	#      per RPC melden.
	#   2. Eigener Spieler (owner_peer_id == lokale Peer-ID) — der Spieler,
	#      der tatsächlich eintritt, meldet sich selbst (Client-Side-
	#      Prediction-Fall, ADR-026).
	# Fall 3 (weder Autorität noch eigener Spieler) wird verworfen, BEVOR
	# _has_triggered gesetzt oder monitoring deaktiviert wird — ein legitimer
	# späterer Eintritt (Autorität oder eigener Spieler) muss diesen Trigger
	# auf diesem Peer noch auslösen können.
	# owner_peer_id kommt aus "owner_peer_id"-Meta, das EntityOrchestrator.
	# spawn_entity() auf jede gespawnte Entity (inkl. Player) setzt — dieselbe
	# Quelle wie IEntityContext.get_local_player(). Meta-Default 1 ist der
	# dokumentierte Tier-1/Solo-Fallback, kein stiller Rätselwert.
	var owner_peer_id: int = body.get_meta("owner_peer_id", 1)
	# is_own_player wird jetzt UNBEDINGT berechnet (nicht mehr nur innerhalb des
	# _network-Zweigs) — wird unten für den Hint-Popup-Guard erneut gebraucht,
	# unabhängig vom Autoritäts-Guard hier.
	var is_own_player := owner_peer_id == multiplayer.get_unique_id()
	if is_instance_valid(_network):
		if not (_network.is_server() or is_own_player):
			return

	_has_triggered = true
	_bus.quest().emit_custom_objective_triggered(signal_key)
	AppLogger.log_info("CUSTOM-Objective getriggert: '%s'." % signal_key, LOG_CAT)

	# Lokales Sofort-Feedback (TODO-offene-probleme.md "custom_objective_triggered
	# hat keinen UI-Konsumenten") — bewusst zusätzlich zum obigen, rein lokalen
	# Signal, NICHT als Ersatz für den Domain-Event-Round-Trip unten. Guard mit
	# is_own_player (nicht nur is_server()!): auf Tier 2/3 passiert der obige
	# Autoritäts-Guard bereits für JEDEN Spieler, der die Zone betritt, auch für
	# fremde Clients, die der Host bloß sieht — ohne diesen zweiten Guard würde
	# der Host ein Popup für die Entdeckung eines ANDEREN Spielers auf seinem
	# eigenen Bildschirm sehen. Tier 1 (Solo): owner_peer_id-Default (1) ==
	# multiplayer.get_unique_id()-Default (1), also immer true, unverändertes
	# Verhalten.
	if not hint_text.is_empty() and is_own_player:
		_bus.ui().emit_notification_requested(hint_text)

	# ADR-021 (R-5): zusätzlich zum obigen, rein lokalen Signal an die Autorität
	# melden — sonst kann ein Nicht-Host-Spieler dieses Objective serverseitig
	# nie erfüllen (siehe ADR-021 "Befund", QuestCustomTrigger-Fall: reiner
	# Area3D-Proximity-Trigger, kein entity-basierter Autoritäts-Hook verfügbar).
	if is_instance_valid(_network):
		_network.report_domain_event("custom_objective_triggered", {"signal_key": signal_key}, owner_peer_id)

	if trigger_once:
		monitoring = false  # Keine weiteren body_entered-Events nötig
