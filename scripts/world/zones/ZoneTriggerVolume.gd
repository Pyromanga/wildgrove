class_name ZoneTriggerVolume extends Area3D

## ZoneTriggerVolume — generisches, wiederverwendbares Trigger-Volume für
## Zonen (ADR-030, Option C). Rein mechanisch: kennt nur seine ZoneConfig,
## meldet Enter/Exit an ZoneService.
##
## Platzierbar überall in der Welt (PvP-Gebiete, Diebes-Zonen, Minigame-
## Grenzen). CollisionShape3D muss vom Aufrufer (Szene/Subklasse) gesetzt
## werden — analog zu QuestCustomTrigger.
##
## inject_zone_service()/inject_network_bridge() werden vom Aufrufer
## (WorldService, nach add_child() bzw. bei Late-Inject S8.6) gesetzt —
## exakt dasselbe Muster wie QuestCustomTrigger.inject_bus()/
## inject_network_bridge() (ADR-021).
##
## AUTORITÄTS-GUARD (ADR-030 "Entscheidung"): nur Server/Host darf
## ZoneService mutieren — ein Client bekommt Zonen-Zugehörigkeit
## ausschließlich per Broadcast (EventBus.zones(), von der Autorität
## emittiert), nie durch eigene Area3D-Overlaps. Anders als
## QuestCustomTrigger braucht dieser Trigger deshalb KEINE "eigener Spieler
## meldet sich selbst"-Ausnahme: Movement ist seit ADR-025 server-
## autoritativ simuliert, die Autorität sieht jeden Overlap bereits selbst,
## kein Client-Report nötig, um sie zu erreichen.

const LOG_CAT := "ZoneTriggerVolume"

## Welche Zone dieses Volume repräsentiert. Mehrere Volumes dürfen dieselbe
## ZoneConfig teilen (eine Zone aus mehreren Teilflächen).
@export var zone_config: ZoneConfig

var _zone_service: ZoneService = null
var _network: NetworkBridge = null

## Wird vom Aufrufer (WorldService) nach add_child() aufgerufen — registriert
## zone_config gleich mit (idempotent, siehe ZoneService.register_zone_config()).
func inject_zone_service(service: ZoneService) -> void:
	_zone_service = service
	if is_instance_valid(_zone_service) and is_instance_valid(zone_config):
		_zone_service.register_zone_config(zone_config)

## Wird vom Aufrufer (WorldService) bei Late-Inject S8.6 aufgerufen, analog
## zu QuestCustomTrigger.inject_network_bridge().
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

func _ready() -> void:
	# monitorable=false: analog zu QuestCustomTrigger — dieses Volume muss
	# nicht selbst von anderen Areas erkannt werden, nur erkennen.
	monitoring   = true
	monitorable  = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if not is_instance_valid(zone_config) or zone_config.zone_id == &"":
		AppLogger.log_warn(
			"ZoneTriggerVolume ohne gültige zone_config platziert — wird nie etwas melden.", LOG_CAT
		)
	add_to_group("zone_triggers")

func _on_body_entered(body: Node3D) -> void:
	_report(body, true)

func _on_body_exited(body: Node3D) -> void:
	_report(body, false)

func _report(body: Node3D, entering: bool) -> void:
	if not is_instance_valid(zone_config) or zone_config.zone_id == &"":
		return
	if not body.is_in_group("player"):
		return
	if not is_instance_valid(_zone_service):
		AppLogger.log_error(
			"ZoneTriggerVolume('%s'): kein ZoneService injiziert — Meldung verworfen." % zone_config.zone_id,
			LOG_CAT
		)
		return
	# Autoritäts-Guard, siehe Klassenkommentar. Tier 1 (Solo) kollabiert mit
	# rein (kein _network == Autorität) — dieselbe Konvention wie
	# WorldService.configure()s Save-Provider-Guard.
	if is_instance_valid(_network) and not _network.is_server():
		return
	# owner_peer_id-Meta: dieselbe Quelle wie überall sonst (EntityOrchestrator.
	# spawn_entity(), WorldService._on_peer_cleanup_requested(), QuestCustomTrigger).
	var owner_peer_id: int = body.get_meta("owner_peer_id", 1)
	if entering:
		_zone_service.report_enter(owner_peer_id, zone_config.zone_id)
	else:
		_zone_service.report_exit(owner_peer_id, zone_config.zone_id)
