extends Service
class_name ZoneService

## ZoneService — autoritative Zonen-Zugehörigkeit (ADR-030, Option C).
##
## `extends Service` statt `ServiceNode` (ADR-003): kein SceneTree-Zugriff
## nötig — `ZoneTriggerVolume` (Area3D, im Szenenbaum) ruft direkt in diesen
## Service hinein, statt dass der Service selbst Nodes sucht. Der ADR-030-
## Entwurfstext nennt dies informell "ServiceNode" (im Sinn von "World-Scope-
## Service"), nicht als Festlegung auf die Basisklasse — ADR-003s
## Entscheidungsbaum ist hier eindeutig.
##
## PEER-SCOPED, NICHT player_id-SAVE-BUCKET (wichtige Abgrenzung zu ADR-029):
## Zonen-Zugehörigkeit ist eine Live-Tatsache über eine AKTIVE Verbindung
## ("wer steht gerade wo") — ein offline Spieler ist in keiner Zone, es gibt
## nichts zu persistieren. Das ist dieselbe Kategorie wie
## `PlayerStateService` (peer_id-gekeyt) und `WorldService.get_player_by_id()`
## (siehe TODO-offene-probleme.md Round 70 / ADR-029 "Implementierungsnotizen
## Round 70") — NICHT dieselbe Kategorie wie `InventorySystem`/`QuestService`/
## `SkillSystem`/`EquipmentService`/`StatModifierService` (player_id: String,
## per-Spieler persistierter Save-Bucket). Absichtlich `peer_id: int`.
##
## AUTORITÄT: nur der Server/Host darf mutieren (report_enter()/report_exit()).
## `ZoneTriggerVolume` guardet das bereits an der Aufrufgrenze (analog zu
## `WorldService`s `not is_instance_valid(_network) or _network.is_server()`-
## Konvention) — dieser Service selbst prüft es NICHT nochmal, er vertraut
## seinem einzigen Aufrufer, genau wie `StatModifierService` seinen Aufrufern
## vertraut statt selbst RPC-Grenzen zu kennen.

const LOG_CAT := "Zones"

## { peer_id: { zone_id: true } } — Dictionary als Set (Godot-Idiom, kein
## natives Set verfügbar). Additiv (ADR-030 "Mitigationen"): ein peer_id kann
## mehrere Zonen gleichzeitig belegen.
var _memberships: Dictionary = {}

## { zone_id: ZoneConfig } — von ZoneTriggerVolume.on_ready() befüllt
## (register_zone_config()), damit has_tag()-Abfragen die Tags einer Zone
## nachschlagen können, ohne dass jeder Aufrufer selbst eine ZoneConfig-
## Referenz durchreichen muss.
var _configs: Dictionary = {}

var _bus: IEventBus = null

## ADR-030: Late-Inject (Phase C8, wie WorldService.inject_network_bridge())
## — NICHT als configure()-Dep deklariert, das wäre ein Zyklus, da
## NetworkBridge selbst "zone_service" als Dep deklariert (einseitige Kante,
## siehe BootstrapConfig.tres-Kommentar bei network_bridge).
var _network: NetworkBridge = null

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_bus = deps.get_optional(ServiceKeys.EVENT_BUS) as IEventBus
	AppLogger.log_debug("Konfiguriert.", LOG_CAT)

func on_ready() -> void:
	# Peer-scoped Laufzeit-Zustand — muss beim Disconnect weg, exakt wie
	# WorldService._on_peer_cleanup_requested() (Chunk-Tracking) und im
	# Unterschied zu den player_id-Save-Buckets (siehe Klassenkommentar).
	if is_instance_valid(_bus):
		_bus.networking().peer_cleanup_requested.connect(_on_peer_cleanup_requested)
	else:
		AppLogger.log_warn("EventBus fehlt — peer_cleanup_requested nicht verbunden.", LOG_CAT)
	AppLogger.log_info("ZoneService bereit.", LOG_CAT)

func on_cleanup() -> void:
	if is_instance_valid(_bus) and _bus.networking().peer_cleanup_requested.is_connected(_on_peer_cleanup_requested):
		_bus.networking().peer_cleanup_requested.disconnect(_on_peer_cleanup_requested)
	AppLogger.log_info("ZoneService cleanup.", LOG_CAT)

# ─────────────────────────────────────────────
# Zone-Registry
# ─────────────────────────────────────────────

## Registriert eine ZoneConfig unter ihrer zone_id — idempotent, mehrere
## ZoneTriggerVolumes derselben Zone dürfen dieselbe Config mehrfach
## registrieren (z.B. eine Zone aus mehreren Teilflächen).
func register_zone_config(config: ZoneConfig) -> void:
	if config == null or config.zone_id == &"":
		AppLogger.log_warn("register_zone_config(): ZoneConfig ohne zone_id ignoriert.", LOG_CAT)
		return
	_configs[config.zone_id] = config

func get_zone_config(zone_id: StringName) -> ZoneConfig:
	return _configs.get(zone_id)

# ─────────────────────────────────────────────
# Öffentliche API — Mutation (nur Autorität, siehe Klassenkommentar)
# ─────────────────────────────────────────────

## Meldet, dass peer_id zone_id betreten hat. Idempotent — ein bereits
## bestehender Eintrag emittiert kein zweites Signal (kein Doppel-Enter bei
## sich überlappenden Trigger-Volumes derselben Zone).
func report_enter(peer_id: int, zone_id: StringName) -> void:
	var zone_set: Dictionary = _memberships.get(peer_id, {})
	if zone_set.has(zone_id):
		return
	zone_set[zone_id] = true
	_memberships[peer_id] = zone_set
	if is_instance_valid(_bus):
		_bus.zones().emit_zone_entered(peer_id, zone_id)
	# ADR-030 "Entscheidung": Client bekommt seine eigene Zonen-Zugehörigkeit
	# nur per Broadcast, nie durch eigene Area3D-Overlaps. send_zone_update_for_peer()
	# ist auf Nicht-Autorität und Tier 1 ein No-op (siehe dortiger Guard) — hier
	# also gefahrlos unbedingt aufrufbar, kein weiterer eigener Autoritäts-Check nötig.
	if is_instance_valid(_network):
		_network.send_zone_update_for_peer(peer_id, zone_id, true)

## Meldet, dass peer_id zone_id verlassen hat. Idempotent.
func report_exit(peer_id: int, zone_id: StringName) -> void:
	var zone_set: Dictionary = _memberships.get(peer_id, {})
	if not zone_set.has(zone_id):
		return
	zone_set.erase(zone_id)
	if zone_set.is_empty():
		_memberships.erase(peer_id)
	else:
		_memberships[peer_id] = zone_set
	if is_instance_valid(_bus):
		_bus.zones().emit_zone_exited(peer_id, zone_id)
	if is_instance_valid(_network):
		_network.send_zone_update_for_peer(peer_id, zone_id, false)

# ─────────────────────────────────────────────
# Öffentliche API — Queries
# ─────────────────────────────────────────────

func is_in_zone(peer_id: int, zone_id: StringName) -> bool:
	var zone_set: Dictionary = _memberships.get(peer_id, {})
	return zone_set.has(zone_id)

func get_zones_for(peer_id: int) -> Array[StringName]:
	var zone_set: Dictionary = _memberships.get(peer_id, {})
	var result: Array[StringName] = []
	for zone_id in zone_set.keys():
		result.append(zone_id)
	return result

## Prüft, ob peer_id in IRGENDEINER Zone mit diesem Tag steht — additiv,
## keine Prioritätsauflösung (ADR-030 "Mitigationen"). Konsumenten wie ein
## PvP-Check rufen dies mit ihrem eigenen Tag (&"pvp") und ignorieren, welche
## konkrete Zone es war.
func has_tag(peer_id: int, tag: StringName) -> bool:
	for zone_id in get_zones_for(peer_id):
		var config := get_zone_config(zone_id)
		if is_instance_valid(config) and config.has_tag(tag):
			return true
	return false

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

## Peer disconnected — Zonen-Mitgliedschaft ist Laufzeit-Zustand, kein
## Save-Feld (siehe Klassenkommentar), räumt also komplett weg statt nur
## Routing-Zuordnung. Emittiert bewusst KEIN zone_exited für jede verlassene
## Zone — der Peer ist bereits weg, es gibt niemanden mehr, der das Signal
## sinnvoll konsumieren könnte (kein Client mehr verbunden, dem UI-Feedback
## zusteht), und ein erneut verbindender Peer bekommt ohnehin einen frischen
## Trigger-Volume-Enter, sobald er physisch wieder in der Zone steht.
func _on_peer_cleanup_requested(peer_id: int) -> void:
	if _memberships.erase(peer_id):
		AppLogger.log_info("Peer %d: Zonen-Mitgliedschaft entfernt (Disconnect)." % peer_id, LOG_CAT)
