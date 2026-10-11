class_name TerrainPlanePlanner
extends RefCounted

## TerrainPlanePlanner — plant "Ebnen": Gitterpunkte schrittweise auf eine WAAGERECHTE Ebene
## (plane_y) ziehen, damit man danach leichter bauen kann.
##
## Gegenstück zum normalen Pinsel (TerrainEditLayer.apply_brush): der Pinsel verschiebt jeden
## Punkt um einen festen Betrag, der Planer verschiebt ihn zur Ebene hin — und nie darüber
## hinaus. Dasselbe Pinselprofil (ebener Kern, weicher Rand, siehe TerrainEditLayer.falloff()),
## dieselbe Schritthöhe pro Aktion. Ein Punkt, der schon auf der Ebene liegt, bleibt liegen;
## wiederholte Aktionen konvergieren also gegen eine plane Fläche statt zu überschwingen.
##
## RICHTUNG (direction): DIR_BOTH ("Ebnen": zu hohe Punkte abtragen UND zu tiefe auffüllen),
## DIR_DOWN ("Abtragen": nur zu hohe Punkte, nie unter die Ebene), DIR_UP ("Auffüllen": nur
## zu tiefe Punkte, nie über die Ebene).
##
## Reine Planung, KEINE Mutation (zweistufig wie TerrainEditLayer.plan_level(): ein abgelehnter
## Plan hinterlässt keinen halben Zustand). Der Aufrufer (WorldTerrainEditor) wendet
## plan["changes"] per TerrainEditLayer.apply_changes() an.
##
## Rückgabe von plan():
##   {ok, reason, changes: {Vector2i: float (neues Delta)}, lowered: float, raised: float,
##    lowered_points: Array[Vector2i], raised_points: Array[Vector2i]}
##   lowered/raised: Summe der Höhenänderung in Metern über alle Punkte (Volumen-Maß, ohne
##   Fläche pro Punkt — nur im Verhältnis zu unit_volume() sinnvoll).
##   reason (bei ok=false): "already_level" (DIR_BOTH) | "nothing_to_cut" (DIR_DOWN) |
##   "nothing_to_fill" (DIR_UP) | "limit" (es gäbe etwas zu tun, aber alle Punkte stehen am
##   Delta-Limit der Schicht).

const DIR_BOTH: String = "both"
const DIR_DOWN: String = "down"
const DIR_UP: String = "up"

## Bewegungen unter diesem Betrag zählen als "schon eben" (TerrainEditLayer rundet ohnehin auf
## QUANTUM = 0,05 m; mit diesem Wert gibt es kein endloses Hin und Her um die Ebene).
const MIN_MOVE: float = 0.03

static func is_valid_direction(direction: String) -> bool:
	return direction == DIR_BOTH or direction == DIR_DOWN or direction == DIR_UP

## height_fn(world_x, world_z) -> float: AKTUELLE Geländehöhe inkl. bestehender Deltas
## (TerrainField.get_height_at). Auf Gitterpunkten ist das exakt Basis + gespeichertes Delta.
static func plan(
	layer: TerrainEditLayer, height_fn: Callable, center: Vector2, radius: float,
	core_radius: float, plane_y: float, step: float, direction: String = DIR_BOTH
) -> Dictionary:
	var result: Dictionary = {
		"ok": false, "reason": _idle_reason(direction), "changes": {}, "lowered": 0.0, "raised": 0.0,
		"lowered_points": [] as Array[Vector2i], "raised_points": [] as Array[Vector2i],
	}
	if layer == null or not height_fn.is_valid() or is_nan(plane_y) or step <= 0.0 \
			or not is_valid_direction(direction):
		return result

	var changes: Dictionary = {}
	var lowered: float = 0.0
	var raised: float = 0.0
	var lowered_points: Array[Vector2i] = []
	var raised_points: Array[Vector2i] = []
	var blocked_by_limit: bool = false

	for p in TerrainEditLayer.lattice_points_in_radius(center.x, center.y, radius):
		var w: Vector2 = TerrainEditLayer.lattice_to_world(p)
		var weight: float = TerrainEditLayer.falloff(Vector2(w.x - center.x, w.y - center.y).length(), radius, core_radius)
		if weight <= 0.0:
			continue
		var current: float = float(height_fn.call(w.x, w.y))
		if is_nan(current):
			continue
		var diff: float = plane_y - current
		if diff < 0.0 and direction == DIR_UP:
			continue
		if diff > 0.0 and direction == DIR_DOWN:
			continue
		var allowed: float = step * weight
		var move: float = clampf(diff, -allowed, allowed)
		if absf(move) < MIN_MOVE:
			continue
		var old: float = layer.get_delta_lattice(p.x, p.y)
		var wanted: float = clampf(old + move, TerrainEditLayer.MAX_DELTA_DOWN, TerrainEditLayer.MAX_DELTA_UP)
		var actual: float = wanted - old
		if absf(actual) < MIN_MOVE:
			blocked_by_limit = true
			continue
		changes[p] = wanted
		if actual < 0.0:
			lowered -= actual
			lowered_points.append(p)
		else:
			raised += actual
			raised_points.append(p)

	if changes.is_empty():
		if blocked_by_limit:
			result["reason"] = "limit"
		return result
	result["ok"] = true
	result["reason"] = ""
	result["changes"] = changes
	result["lowered"] = lowered
	result["raised"] = raised
	result["lowered_points"] = lowered_points
	result["raised_points"] = raised_points
	return result

## Volumen-Maß einer VOLLEN normalen Grab-/Füllaktion (step * Summe der Pinselgewichte) — die
## Einheit, in der Ebnen Material verrechnet: eine normale Aktion ≙ 1 Item, Ebnen genauso
## viel Volumen pro Item (siehe WorldService.request_terrain_plane). Unabhängig von der
## Pinselposition, weil der Pinsel immer auf einem Gitterpunkt sitzt.
static func unit_volume(radius: float, core_radius: float, step: float) -> float:
	var sum: float = 0.0
	for p in TerrainEditLayer.lattice_points_in_radius(0.0, 0.0, radius):
		var w: Vector2 = TerrainEditLayer.lattice_to_world(p)
		sum += TerrainEditLayer.falloff(w.length(), radius, core_radius)
	return step * sum

static func _idle_reason(direction: String) -> String:
	match direction:
		DIR_DOWN: return "nothing_to_cut"
		DIR_UP:   return "nothing_to_fill"
		_:        return "already_level"
