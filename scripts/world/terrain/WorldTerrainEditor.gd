class_name WorldTerrainEditor
extends RefCounted

## WorldTerrainEditor — führt Gelände-Änderungen aus (Graben, Aufschütten, Einebnen).
##
## Kein Service, kein Node: Hilfsklasse von WorldService (gleiches Muster wie
## WorldSaveHandler/WorldSpawner). Kennt weder Inventar noch Spieler — Materialkosten
## (Erde) und Reichweite prüft der Aufrufer (WorldService). Hier nur: Regeln + Mutation +
## Neubau der betroffenen Chunks.
##
## Nach jedem Grabvorgang meldet WorldService die Änderung an WorldDigHandler (Funde neu auf
## den Boden setzen, ggf. ein neuer Fund).
##
## Bauwerke sind tabu: in der Nähe eines Bauteils wird nicht gegraben (sonst hingen Wände
## in der Luft oder steckten im Boden). Einebnen für Böden läuft über apply_level() und
## umgeht diese Sperre bewusst — es ist ja der Bau selbst.

const LOG_CAT := "TerrainEdit"

const MODE_DIG: String = "dig"
const MODE_FILL: String = "fill"

## Pinsel: ein flacher Kern (volle Wirkung) mit weichem Rand darum. Bei 2 m Gitter deckt
## CORE_RADIUS das Zentrum + 8 Nachbarn ab (Boden ~4x4 m eben), BRUSH_RADIUS zusätzlich die
## Punkte im Abstand 4 m / 4,5 m (Wand). Flach gegraben (< ~3 m) bleibt es eine sanfte Mulde;
## tiefer wird daraus ein Schacht mit steilen Wänden — und dort braucht man Leitern
## (LadderPlanner). Der reine Glockenpinsel (CORE_RADIUS = 0, BRUSH_RADIUS = 3.5) ergab bei
## tiefen Löchern einen Trichter, auf dessen Spitze man nicht mehr stehen konnte.
const BRUSH_RADIUS: float = 5.0
const CORE_RADIUS: float = 2.9
## Änderung pro Aktion am Zentrum (Meter). Nachbarn bekommen weniger (weicher Verlauf).
const DIG_STEP: float = -0.5
const FILL_STEP: float = 0.5
## Schritthöhe pro Ebnen-Aktion am Kern (Betrag; gleich Graben/Füllen).
const DIG_STEP_ABS: float = 0.5
## Maximale Entfernung Spieler → Zielpunkt.
const REACH: float = 6.0

var _layer: TerrainEditLayer
var _registry: BuildRegistry
## func(points: Array[Vector2i]) -> void — baut betroffene, geladene Chunks neu.
var _refresh_cb: Callable
## func(world_x, world_z) -> float — siehe set_height_fn().
var _height_fn: Callable = Callable()

func _init(layer: TerrainEditLayer, registry: BuildRegistry, refresh_cb: Callable) -> void:
	_layer = layer
	_registry = registry
	_refresh_cb = refresh_cb

func get_layer() -> TerrainEditLayer:
	return _layer

## Reine Vorschau (keine Mutation) — Grundlage für den Grab-/Füll-Geist
## (TerrainEditGhost, siehe GroundToolController). Prüft dieselben Dinge wie edit() VOR der
## eigentlichen Mutation (Modus gültig, kein Bauwerk in der Nähe), damit der Geist rot wird,
## bevor der Spieler die Interaktion überhaupt startet.
##
## Rückgabe: {ok, reason, center: Vector2 (Pinselmitte in Weltkoordinaten x/z), radius: float,
##   core_radius: float}. reason: "" | "bad_mode" | "building_nearby".
func preview(mode: String, target: Vector3) -> Dictionary:
	if mode != MODE_DIG and mode != MODE_FILL:
		return {"ok": false, "reason": "bad_mode", "center": Vector2.ZERO,
			"radius": BRUSH_RADIUS, "core_radius": CORE_RADIUS}
	var center: Vector2 = TerrainEditLayer.lattice_to_world(TerrainEditLayer.world_to_lattice(target.x, target.z))
	if _registry != null and _registry.is_area_occupied(center.x, center.y, BRUSH_RADIUS):
		return {"ok": false, "reason": "building_nearby", "center": center,
			"radius": BRUSH_RADIUS, "core_radius": CORE_RADIUS}
	return {"ok": true, "reason": "", "center": center, "radius": BRUSH_RADIUS, "core_radius": CORE_RADIUS}

## Graben oder Aufschütten an `target`.
##
## Der Pinsel sitzt immer auf einem GITTERPUNKT (nächster zu `target`): so ist der flache Kern
## immer genau 3x3 Punkte groß, und wiederholtes Graben an derselben Stelle vertieft dasselbe
## Loch, statt es seitlich davonwandern zu lassen. Die Wand-Reichweite des Spielers (Ziel
## 2,2 m vor ihm) verschiebt sich dadurch um höchstens ~1,4 m — das spürt man kaum.
##
## Rückgabe: {ok, reason, changed: Array[Vector2i], center: Vector2 (Pinselmitte in Weltkoordinaten x/z)}
##   reason: "" | "bad_mode" | "building_nearby" | "limit"
func edit(mode: String, target: Vector3) -> Dictionary:
	var check: Dictionary = preview(mode, target)
	if not check["ok"]:
		return {"ok": false, "reason": check["reason"], "changed": []}
	var center: Vector2 = check["center"]
	var amount: float = DIG_STEP if mode == MODE_DIG else FILL_STEP
	var changed: Array[Vector2i] = _layer.apply_brush(center.x, center.y, BRUSH_RADIUS, amount, CORE_RADIUS)
	if changed.is_empty():
		return {"ok": false, "reason": "limit", "changed": []}
	_refresh(changed)
	AppLogger.log_debug("Gelände %s @ (%.1f, %.1f): %d Punkte." % [mode, center.x, center.y, changed.size()], LOG_CAT)
	return {"ok": true, "reason": "", "changed": changed, "center": center}

## Höhenfunktion für das Ebnen (TerrainField.get_height_at, inkl. bestehender Deltas). Von
## WorldService gesetzt; ohne sie ist Ebnen nicht verfügbar (reason "no_ground").
func set_height_fn(height_fn: Callable) -> void:
	_height_fn = height_fn

## Plant "Ebnen" an `target` auf die waagerechte Ebene plane_y — OHNE etwas zu verändern.
## Gleiche Sperre wie Graben (kein Bauwerk in der Nähe), gleicher Pinsel (Gitterpunkt, Kern +
## weicher Rand), gleiche Schritthöhe. Die Richtung (TerrainPlanePlanner.DIR_*) legt fest, ob
## nur abgetragen, nur aufgefüllt oder beides wird.
##
## Rückgabe: {ok, reason, center, radius, core_radius} + bei ok die Planfelder von
## TerrainPlanePlanner.plan() (changes, lowered, raised, lowered_points, raised_points).
## reason: "" | "bad_mode" (ungültige Richtung) | "no_ground" | "building_nearby" |
## "already_level" | "nothing_to_cut" | "nothing_to_fill" | "limit"
func plan_plane(target: Vector3, plane_y: float, direction: String = TerrainPlanePlanner.DIR_BOTH) -> Dictionary:
	var center: Vector2 = TerrainEditLayer.lattice_to_world(TerrainEditLayer.world_to_lattice(target.x, target.z))
	var out: Dictionary = {"ok": false, "reason": "", "center": center,
		"radius": BRUSH_RADIUS, "core_radius": CORE_RADIUS}
	if not TerrainPlanePlanner.is_valid_direction(direction):
		out["reason"] = "bad_mode"
		return out
	if not _height_fn.is_valid() or is_nan(plane_y):
		out["reason"] = "no_ground"
		return out
	if _registry != null and _registry.is_area_occupied(center.x, center.y, BRUSH_RADIUS):
		out["reason"] = "building_nearby"
		return out
	var plan: Dictionary = TerrainPlanePlanner.plan(
		_layer, _height_fn, center, BRUSH_RADIUS, CORE_RADIUS, plane_y, DIG_STEP_ABS, direction)
	out.merge(plan, true)
	return out

## Reine Vorschau für den Ebnen-Geist: wie preview(), aber mit Ebene — rot auch dann, wenn es
## nichts zu tun gibt ("already_level"), damit man das vor dem Antippen sieht.
func preview_plane(target: Vector3, plane_y: float, direction: String = TerrainPlanePlanner.DIR_BOTH) -> Dictionary:
	var plan: Dictionary = plan_plane(target, plane_y, direction)
	return {"ok": plan["ok"], "reason": plan["reason"], "center": plan["center"],
		"radius": BRUSH_RADIUS, "core_radius": CORE_RADIUS}

## Wendet einen plan_plane()-Plan an und baut betroffene Chunks neu.
## Rückgabe: {ok, reason ("" | "limit"), changed, lowered_points, raised_points (nur tatsächlich
## veränderte Punkte), center, lowered, raised}
func apply_plane_plan(plan: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)):
		return {"ok": false, "reason": String(plan.get("reason", "")), "changed": []}
	var changed: Array[Vector2i] = _layer.apply_changes(plan["changes"])
	if changed.is_empty():
		return {"ok": false, "reason": "limit", "changed": []}
	var lowered_points: Array[Vector2i] = []
	for p: Vector2i in (plan["lowered_points"] as Array):
		if changed.has(p):
			lowered_points.append(p)
	var raised_points: Array[Vector2i] = []
	for p: Vector2i in (plan["raised_points"] as Array):
		if changed.has(p):
			raised_points.append(p)
	_refresh(changed)
	var center: Vector2 = plan["center"]
	AppLogger.log_debug("Gelände eben @ (%.1f, %.1f): %d Punkte." % [center.x, center.y, changed.size()], LOG_CAT)
	return {"ok": true, "reason": "", "changed": changed, "center": center,
		"lowered": float(plan["lowered"]), "raised": float(plan["raised"]),
		"lowered_points": lowered_points, "raised_points": raised_points}

## Planen + Anwenden in einem Schritt (ohne Material-Verrechnung — die liegt beim WorldService).
func edit_plane(target: Vector3, plane_y: float, direction: String = TerrainPlanePlanner.DIR_BOTH) -> Dictionary:
	return apply_plane_plan(plan_plane(target, plane_y, direction))

## Wendet einen TerrainEditLayer.plan_level()-Plan an (Einebnen unter einem Boden).
func apply_level(changes: Dictionary) -> Array[Vector2i]:
	var changed: Array[Vector2i] = _layer.apply_changes(changes)
	if not changed.is_empty():
		_refresh(changed)
	return changed

func _refresh(points: Array[Vector2i]) -> void:
	if _refresh_cb.is_valid():
		_refresh_cb.call(points)

## Menschenlesbare Meldung zu einem reason-Code.
static func reason_text(reason: String) -> String:
	match reason:
		"building_nearby": return "Zu nah an einem Bauwerk."
		"limit":           return "Tiefer oder höher geht es hier nicht."
		"too_far":         return "Zu weit entfernt."
		"no_material":     return "Du brauchst Erde, Sand oder Kies zum Aufschütten."
		"inventory_full":  return "Dein Inventar ist voll."
		"coop_unsupported": return "Bauen und Graben sind vorerst nur im Solo-Modus möglich."
		"no_plane":        return "Lege zuerst eine Ebene fest (⌖)."
		"already_level":   return "Hier ist schon alles eben."
		"nothing_to_cut":  return "Hier gibt es nichts abzutragen."
		"nothing_to_fill": return "Hier gibt es nichts aufzufüllen."
		_:                 return "Das geht hier nicht."
