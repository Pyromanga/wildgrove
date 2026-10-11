class_name CavePortalTrigger
extends Area3D

## CavePortalTrigger — generisches, wiederverwendbares Trigger-Volume für
## Höhlen-Ein-/Ausgänge (Lager-A-Ansatz: Heightmap-Overworld + Höhlen als
## separate, weit entfernt platzierte Node3D-Bereiche im selben World-Baum —
## siehe Gespräch zu Terrain-Optionen).
##
## Bewusst NICHT über einen eigenen Service/BootstrapConfig-Eintrag verdrahtet
## (anders als ZoneTriggerVolume/ZoneService) — ein Portal braucht keinen
## eigenen State, nur "wer betritt mich" → "wohin". target_path zeigt direkt
## auf einen Marker3D (Node-Pfad, editierbar im Inspector), das hält die
## Kopplung minimal und macht das Setup rein im Editor überschaubar.
##
## MULTIPLAYER-KOSTEN: praktisch null. Kein zusätzlicher Netcode-Pfad — der
## Teleport läuft über Player.teleport_to(), das exakt denselben Mechanismus
## nutzt wie _respawn() (Autorität setzt global_position, normale
## Bewegungs-Replikation übernimmt den Rest). Es wird nichts Geometrisches
## synchronisiert: die Höhlen-Szene liegt bereits bei jedem Peer im exportierten
## Spiel, nur die Zielposition (ein Vector3) "reist".
##
## AUTORITÄTS-GUARD: identisch zu ZoneTriggerVolume — nur Server/Host darf
## den Teleport auslösen. _network ist optional (Solo/Tests kollabieren mit
## rein, dieselbe Konvention wie überall sonst im Projekt).
##
## PLATZIERUNG: als Area3D mit eigener CollisionShape3D irgendwo in der Welt
## oder in einer Höhlen-Szene platzieren, `target_path` auf den Marker3D am
## Zielort zeigen lassen (z.B. Höhlenausgang → Marker3D im Overworld-Chunk,
## oder umgekehrt Höhleneingang im Overworld → Marker3D im CaveTemplate.tscn).

const LOG_CAT := "CavePortal"

## Marker3D-Pfad, auf den teleportiert wird. Relativ zu diesem Node (kann auch
## über mehrere Szenen-Grenzen mit einem NodePath auf eine ganz andere
## instanzierte Szene zeigen, solange beide zur Laufzeit im selben Baum hängen —
## siehe CaveService-Hinweis in CaveDefinition.gd für den lazy-instantiate Fall).
@export var target_path: NodePath

## Kleiner Versatz nach oben, damit der Spieler nicht im Boden des Zielorts
## spawnt (CharacterBody3D braucht etwas Platz unter den Füßen).
@export var target_y_offset: float = 0.2

## Mindestabstand zwischen zwei Teleports desselben Peers — verhindert
## Ping-Pong, falls Eingang und Ausgang zu nah beieinander liegen und der
## Spieler nach dem Sprung sofort wieder im Ziel-Trigger steht.
@export var reentry_cooldown_sec: float = 1.5

var _network: NetworkBridge = null
var _last_teleport_msec: Dictionary = {}  # { peer_id: int (Time.get_ticks_msec()) }

## Optional — Aufrufer (WorldService, analog ZoneTriggerVolume) injiziert das
## nach add_child(). Ohne Injektion (Solo/Tests) gilt "ich bin die Autorität".
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

func _ready() -> void:
	monitoring  = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	if target_path.is_empty():
		AppLogger.log_warn(
			"CavePortalTrigger ohne target_path platziert — wird niemanden teleportieren.",
			LOG_CAT
		)
	# Gruppe analog "zone_triggers" — falls ihr später denselben Late-Inject-
	# Loop wie WorldService._wire_zone_triggers() für inject_network_bridge()
	# haben wollt, reicht ein Gegenstück, das über "cave_portals" iteriert.
	# Ohne Injektion läuft das Portal einfach im Solo-Modus (immer Autorität).
	add_to_group("cave_portals")

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if is_instance_valid(_network) and not _network.is_server():
		return  # Autoritäts-Guard, siehe Klassenkommentar
	if target_path.is_empty():
		return

	var target: Node3D = get_node_or_null(target_path)
	if not is_instance_valid(target):
		AppLogger.log_error(
			"CavePortalTrigger: target_path '%s' nicht auflösbar." % str(target_path), LOG_CAT
		)
		return

	var peer_id: int = body.get_meta("owner_peer_id", 1)
	var now := Time.get_ticks_msec()
	var last: int = _last_teleport_msec.get(peer_id, -1000000)
	if now - last < int(reentry_cooldown_sec * 1000.0):
		return  # Cooldown — verhindert Ping-Pong zwischen zwei nahen Portalen
	_last_teleport_msec[peer_id] = now

	var dest := target.global_position + Vector3(0.0, target_y_offset, 0.0)
	if body.has_method("teleport_to"):
		body.teleport_to(dest)
	else:
		AppLogger.log_warn(
			"CavePortalTrigger: Body ohne teleport_to() — Fallback auf direktes global_position.",
			LOG_CAT
		)
		body.global_position = dest
	AppLogger.log_info("Peer %d via Portal '%s' teleportiert nach %s." % [peer_id, name, str(dest)], LOG_CAT)
