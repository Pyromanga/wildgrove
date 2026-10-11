class_name BuildAim
extends RefCounted

## BuildAim — reine Zielhilfen für den Baumodus (statisch, ohne Engine-State → testbar).
##
## WARUM: Vorher lag der Bauplatz immer 3 m in LAUFrichtung vor dem Spieler — wer eine Wand
## woanders haben wollte, musste den Spieler bewegen. Jetzt
##   1. folgt der Geist dem Blick: Kamera-Mittelstrahl ↔ Gelände (ground_hit),
##   2. lässt er sich per Richtungstasten in Rasterschritten verschieben (nudge_vector),
##      relativ zur Kamera ("vor" = von der Kamera weg), gerastet auf die Weltachsen.

enum Dir { FORWARD, BACK, LEFT, RIGHT }

## Erster Schnittpunkt des Strahls mit dem Gelände zwischen t_from und t_to (Strahlparameter
## in Metern). height_fn(x, z) -> float (NAN = kein Boden). null, wenn der Strahl das Gelände
## in diesem Bereich nicht trifft (Blick zum Himmel/Horizont). Liegt schon der Startpunkt unter
## dem Gelände, ist der Startpunkt der Treffer.
static func ground_hit(
	origin: Vector3, dir: Vector3, height_fn: Callable, t_from: float, t_to: float, step: float = 0.4
) -> Variant:
	if dir.length_squared() < 0.000001 or not height_fn.is_valid() or t_to <= t_from:
		return null
	var d: Vector3 = dir.normalized()
	var prev_t: float = t_from
	var t: float = t_from
	while t <= t_to:
		if _is_below(origin + d * t, height_fn):
			var lo: float = prev_t
			var hi: float = t
			for _i in range(8):
				var mid: float = (lo + hi) * 0.5
				if _is_below(origin + d * mid, height_fn):
					hi = mid
				else:
					lo = mid
			return origin + d * hi
		prev_t = t
		t += step
	return null

static func _is_below(p: Vector3, height_fn: Callable) -> bool:
	var h: float = float(height_fn.call(p.x, p.z))
	return not is_nan(h) and p.y <= h

## Begrenzt den horizontalen Abstand des Ziels zum Spieler auf max_dist (y bleibt erhalten).
static func clamp_to_reach(target: Vector3, player_pos: Vector3, max_dist: float) -> Vector3:
	var flat := Vector2(target.x - player_pos.x, target.z - player_pos.z)
	if flat.length() <= max_dist:
		return target
	flat = flat.normalized() * max_dist
	return Vector3(player_pos.x + flat.x, target.y, player_pos.z + flat.y)

## Einheitsvektor (Weltachse, y=0) für eine Richtungstaste, relativ zur Blickrichtung `view_dir`:
## die Kamera-Richtung wird auf die nächstliegende Weltachse gerastet.
static func nudge_vector(view_dir: Vector3, direction: int) -> Vector3:
	var fwd := Vector3(view_dir.x, 0.0, view_dir.z)
	if fwd.length_squared() < 0.000001:
		fwd = Vector3(0.0, 0.0, -1.0)
	fwd = _snap_axis(fwd)
	var right := Vector3(-fwd.z, 0.0, fwd.x)   # fwd × UP
	match direction:
		Dir.FORWARD: return fwd
		Dir.BACK:    return -fwd
		Dir.LEFT:    return -right
		Dir.RIGHT:   return right
	return Vector3.ZERO

static func _snap_axis(v: Vector3) -> Vector3:
	if absf(v.x) >= absf(v.z):
		return Vector3(signf(v.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(v.z))
