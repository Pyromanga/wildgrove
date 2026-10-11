extends Node
class_name RemotePlayerInterpolator

## RemotePlayerInterpolator — Snapshot-Interpolation für Remote-Spieler (Sprint G-04).
##
## Problem: MultiplayerSynchronizer bei 20 Hz schreibt Position/Rotation direkt auf
## den Node — Remote-Spieler springen alle 50ms sichtbar.
##
## Lösung: Snapshot-Interpolation mit festem Render-Delay (~100ms = 2 Ticks).
##   1. Eingehende Sync-Updates werden als Snapshots gepuffert (Ringpuffer, 8 Einträge).
##   2. Der visuelle Node (PlayerVisuals) wird auf RENDER_DELAY_SEC in der Vergangenheit
##      interpoliert — dadurch hat die Interpolation immer zwei Punkte.
##   3. Der physikalische Node (Player/CharacterBody3D) behält die Server-Autorität —
##      nur die visuelle Darstellung wird geglättet.
##
## Aktivierung: Player.on_spawn() hängt diesen Node nur für Remote-Peers ein.
## Für den lokalen Spieler läuft keine Interpolation (kein Sprung, da direkt gesteuert).
##
## Implementierung: Beobachtet die Eltern-Position via _process(). Wenn der
## MultiplayerSynchronizer den Parent-Node aktualisiert, wird der neue Wert als
## Snapshot gespeichert. _process() interpoliert zwischen gespeicherten Snapshots.

const LOG_CAT          := "RemoteInterp"
const SNAPSHOT_BUFFER  := 8       ## Ringpuffer-Größe — 8 * 50ms = 400ms Puffer
const RENDER_DELAY_SEC := 0.1     ## Render-Delay: 100ms hinter Echtzeit (2 Ticks bei 20Hz)

## Ein empfangener State-Snapshot.
class Snapshot:
	var timestamp: float
	var position:  Vector3
	var rotation:  Vector3

	func _init(ts: float, pos: Vector3, rot: Vector3) -> void:
		timestamp = ts
		position  = pos
		rotation  = rot

var _snapshots: Array[Snapshot] = []       ## Ringpuffer empfangener Snapshots
var _last_sync_position: Vector3           ## Letzte bekannte Sync-Position — Änderung triggert Snapshot
var _last_sync_rotation: Vector3

var _visual_node: Node3D = null            ## PlayerVisuals-Node — wird geglättet
var _parent: Node3D                        ## Der Player-CharacterBody3D

func _ready() -> void:
	_parent = get_parent() as Node3D
	if not is_instance_valid(_parent):
		push_error("RemotePlayerInterpolator: Parent ist kein Node3D!")
		return
	_last_sync_position = _parent.global_position
	_last_sync_rotation = _parent.rotation
	# PlayerVisuals-Kind-Node suchen — dieser wird statt dem Physik-Node geglättet.
	_visual_node = _parent.get_node_or_null("PlayerVisuals") as Node3D
	AppLogger.log_debug("RemotePlayerInterpolator aktiviert.", LOG_CAT)

func _process(_delta: float) -> void:
	if not is_instance_valid(_parent):
		return
	# Neuen Snapshot aufnehmen wenn sich die Server-Position geändert hat.
	var current_pos := _parent.global_position
	var current_rot := _parent.rotation
	if current_pos.distance_squared_to(_last_sync_position) > 0.0001 \
			or current_rot.distance_squared_to(_last_sync_rotation) > 0.0001:
		_push_snapshot(current_pos, current_rot)
		_last_sync_position = current_pos
		_last_sync_rotation = current_rot

	# Render-Zeit: aktuell - RENDER_DELAY_SEC.
	var render_time := Time.get_ticks_msec() / 1000.0 - RENDER_DELAY_SEC
	_apply_interpolation(render_time)

## Speichert einen neuen Snapshot im Ringpuffer.
func _push_snapshot(pos: Vector3, rot: Vector3) -> void:
	var snap := Snapshot.new(Time.get_ticks_msec() / 1000.0, pos, rot)
	_snapshots.append(snap)
	if _snapshots.size() > SNAPSHOT_BUFFER:
		_snapshots.pop_front()

## Interpoliert zur Render-Zeit zwischen den zwei nächsten Snapshots.
func _apply_interpolation(render_time: float) -> void:
	if _snapshots.size() < 2:
		return
	# Zwei Snapshots finden die render_time einschließen.
	var older: Snapshot = null
	var newer: Snapshot = null
	for i in range(_snapshots.size() - 1):
		if _snapshots[i].timestamp <= render_time and _snapshots[i + 1].timestamp >= render_time:
			older = _snapshots[i]
			newer = _snapshots[i + 1]
			break
	# Wenn render_time hinter dem neuesten liegt (noch kein Puffer gefüllt): extrapolieren nicht,
	# einfach den neuesten Snapshot anwenden.
	if older == null or newer == null:
		if not _snapshots.is_empty():
			var latest := _snapshots.back() as Snapshot
			_apply_to_visual(latest.position, latest.rotation)
		return

	var t: float = (render_time - older.timestamp) / max(newer.timestamp - older.timestamp, 0.001)
	t = clampf(t, 0.0, 1.0)
	var interp_pos := older.position.lerp(newer.position, t)
	var interp_rot := older.rotation.lerp(newer.rotation, t)
	_apply_to_visual(interp_pos, interp_rot)

## Schreibt die interpolierte Position/Rotation auf den Visual-Node (wenn vorhanden)
## oder direkt auf den Parent wenn kein separater Visual-Node existiert.
func _apply_to_visual(pos: Vector3, rot: Vector3) -> void:
	if is_instance_valid(_visual_node):
		# Visual-Node relativ zum Parent positionieren.
		_visual_node.global_position = pos
		_visual_node.rotation        = rot
	# Wenn kein Visual-Node: nichts überschreiben — der PhysikNode springt durch
	# den MultiplayerSynchronizer; das ist der Status quo ohne Interpolation.
