class_name SettlementMath
extends RefCounted

## SettlementMath — kleine, reine Hilfsfunktionen der Siedlungsplanung (Hash, Geometrie).
## Absichtlich ohne Weltbezug, damit alles einzeln testbar ist.

## Deterministischer 63-Bit-Mischhash (auf jedem Peer identisch; kein Variant-hash()).
static func mix(a: int, b: int, c: int, d: int) -> int:
	var h: int = a * 0x9E3779B1 + b * 0x85EBCA6B + c * 0xC2B2AE35 + d * 0x27D4EB2F
	h ^= (h >> 15)
	h *= 0x2C1B3C6D
	h ^= (h >> 12)
	h *= 0x297A2D39
	h ^= (h >> 15)
	return h & 0x7FFFFFFFFFFFFFFF

static func rng_for(a: int, b: int, c: int, d: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = mix(a, b, c, d)
	return rng

## Abstand Punkt p ↔ Strecke a-b. Gibt zusätzlich den nächsten Punkt über `out_closest[0]` zurück.
static func dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func closest_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return a
	return a + ab * clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)

## Überlappt das gedrehte Rechteck (Mitte c, halbe Maße h, Winkel yaw um Y wie Node3D.rotation.y)
## mit einem anderen, um `margin` vergrößerten? Separating-Axis-Test für zwei OBBs in 2D.
static func obb_overlap(c1: Vector2, h1: Vector2, yaw1: float, c2: Vector2, h2: Vector2, yaw2: float, margin: float = 0.0) -> bool:
	var axes: Array[Vector2] = [_axis_x(yaw1), _axis_z(yaw1), _axis_x(yaw2), _axis_z(yaw2)]
	var d: Vector2 = c2 - c1
	for ax: Vector2 in axes:
		var r1: float = absf(_axis_x(yaw1).dot(ax)) * h1.x + absf(_axis_z(yaw1).dot(ax)) * h1.y
		var r2: float = absf(_axis_x(yaw2).dot(ax)) * h2.x + absf(_axis_z(yaw2).dot(ax)) * h2.y
		if absf(d.dot(ax)) > r1 + r2 + margin:
			return false
	return true

## Lokale Achse +X eines um yaw (Y-Achse) gedrehten Gebäudes in Welt-(x,z).
static func _axis_x(yaw: float) -> Vector2:
	return Vector2(cos(yaw), -sin(yaw))

## Lokale Achse +Z (Front) in Welt-(x,z).
static func _axis_z(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))

static func local_to_world(center: Vector2, yaw: float, local: Vector2) -> Vector2:
	return center + _axis_x(yaw) * local.x + _axis_z(yaw) * local.y

static func front_dir(yaw: float) -> Vector2:
	return _axis_z(yaw)

## Liegt p im gedrehten Rechteck (Mitte c, halbe Maße h, Winkel yaw), um `pad` vergrößert?
static func point_in_obb(p: Vector2, c: Vector2, h: Vector2, yaw: float, pad: float = 0.0) -> bool:
	var d: Vector2 = p - c
	return absf(d.dot(_axis_x(yaw))) <= h.x + pad and absf(d.dot(_axis_z(yaw))) <= h.y + pad
