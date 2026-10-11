class_name PlayerLadder
extends RefCounted

## PlayerLadder — Klettern an Leitern (Zustand + Regeln), ohne Node und ohne Physik.
##
## Der Spieler ruft step() in jedem Physik-Tick auf (Player._apply_movement). Ist das Ergebnis
## "handled", setzt er Position und Geschwindigkeit direkt und überspringt die normale
## Bewegung. Klettern ist rein POSITIONSBASIERT (LadderRegistry.find_attach), keine Area-
## Überlappung — deshalb dasselbe Ergebnis bei Prediction/Resimulation.
##
## STEUERUNG: Richtung zur Wand laufen = hinauf, davon weg = hinab (ohne Eingabe hält man an
## der Stelle). Springen = abspringen. Oben angekommen setzt man automatisch auf den Rand,
## unten auf den Boden. Am Rand einer Grube von der Wand weg laufen = an der Leiter hinab.
##
## Leitern sind wie alle Umbauten vorerst Solo-only: in Mehrspieler-Sitzungen liefert
## WorldService.get_ladder_registry() null, dann ist dieser Zustand immer leer.

const CLIMB_SPEED: float = 2.6
const JUMP_OFF_HORIZONTAL: float = 3.5
const JUMP_OFF_VERTICAL: float = 4.5
const TOP_PUSH: float = 1.5
## Sperrzeit nach dem Loslassen, damit man nicht sofort wieder einrastet.
const COOLDOWN: float = 0.4

var _key: String = ""
var _s: float = 0.0
var _cooldown: float = 0.0

func is_climbing() -> bool:
	return not _key.is_empty()

func get_key() -> String:
	return _key

## Loslassen (z.B. Tod/Teleport).
func reset() -> void:
	_key = ""
	_s = 0.0

## Ein Physik-Tick. Rückgabe: {} (nicht beteiligt — normale Bewegung) oder
## {handled: true, position: Vector3, velocity: Vector3}.
func step(pos: Vector3, move_dir: Vector3, delta: float, jump: bool, registry: LadderRegistry) -> Dictionary:
	_cooldown = maxf(0.0, _cooldown - delta)
	if registry == null or registry.is_empty():
		reset()
		return {}
	if _key.is_empty():
		if _cooldown > 0.0:
			return {}
		var hit: Dictionary = registry.find_attach(pos, move_dir)
		if hit.is_empty():
			return {}
		_key = String(hit["key"])
		_s = float(hit["s"])
	var path: LadderPath = registry.get_path_of(_key)
	if path == null:
		reset()
		return {}

	if jump:
		var off_pos: Vector3 = path.stand_point(_s)
		var off_vel: Vector3 = -path.wall_dir * JUMP_OFF_HORIZONTAL + Vector3.UP * JUMP_OFF_VERTICAL
		_release()
		return {"handled": true, "position": off_pos, "velocity": off_vel}

	var toward_wall: float = move_dir.dot(path.wall_dir)
	var axis: float = 0.0
	if toward_wall >= LadderRegistry.INPUT_THRESHOLD:
		axis = 1.0
	elif toward_wall <= -LadderRegistry.INPUT_THRESHOLD:
		axis = -1.0
	_s += axis * CLIMB_SPEED * delta

	if _s >= path.length:
		var up_link: Dictionary = registry.find_link(_key, true)
		if not up_link.is_empty():
			_key = String(up_link["key"])
			_s = float(up_link["s"])
			return {"handled": true, "position": registry.get_path_of(_key).stand_point(_s), "velocity": Vector3.ZERO}
		var top_pos: Vector3 = path.exit_top
		_release()
		return {"handled": true, "position": top_pos, "velocity": path.wall_dir * TOP_PUSH}
	if _s <= 0.0:
		var down_link: Dictionary = registry.find_link(_key, false)
		if not down_link.is_empty():
			_key = String(down_link["key"])
			var lower: LadderPath = registry.get_path_of(_key)
			_s = lower.length if lower != null else 0.0
			return {"handled": true, "position": path.stand_point(0.0), "velocity": Vector3.ZERO}
		var bottom_pos: Vector3 = path.exit_bottom
		_release()
		return {"handled": true, "position": bottom_pos, "velocity": Vector3.ZERO}
	return {"handled": true, "position": path.stand_point(_s), "velocity": Vector3.ZERO}

func _release() -> void:
	_key = ""
	_s = 0.0
	_cooldown = COOLDOWN
