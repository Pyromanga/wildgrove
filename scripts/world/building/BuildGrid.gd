class_name BuildGrid
extends RefCounted

## BuildGrid — Raster, Einrasten und Schlüssel für Bauteile. Rein statisch, ohne Engine-State.
##
## RASTER: Zellen von CELL Metern. Zelle (cx, cz) deckt [cx*CELL, (cx+1)*CELL) × [cz*CELL,
## (cz+1)*CELL) ab. CELL entspricht bewusst dem Terrain-Gitter (TerrainEditLayer.SPACING):
## Zellecken liegen exakt auf Terrain-Vertices — ein Boden deckt genau ein Terrain-Quad ab
## und lässt sich sauber einebnen.
##
##   Boden  (FLOOR): belegt eine ZELLE.            Schlüssel "F_<cx>_<cz>"
##   Wand   (WALL) : belegt eine ZELLKANTE.        Schlüssel "W<achse>_<cx>_<cz>"
##       Achse 0: Kante entlang X bei z = cz*CELL, von x = cx*CELL bis (cx+1)*CELL.
##       Achse 1: Kante entlang Z bei x = cx*CELL, von z = cz*CELL bis (cz+1)*CELL.
##   Tür/Fenster (DOOR/WINDOW): wandartig — TEILEN sich den Schlüsselraum von WALL (dieselbe
##       Zellkante, dieselbe snap()-Regel). Dadurch schließen sich Wand/Tür/Fenster an einer
##       Kante gegenseitig aus (nur eins von dreien), und parse_key() liefert für sie weiterhin
##       Kind.WALL zurück — strukturell tragen sie genauso wie eine Wand (halten Böden/Dächer
##       darüber), nur ihre Geometrie hat eine Öffnung (BuildPieceDefinition.get_door_boxes()/
##       get_window_boxes()).
##   Dach   (ROOF) : belegt eine ZELLE (wie Boden).  Schlüssel "R_<cx>_<cz>"
##       axis bestimmt nur die First-Ausrichtung (0 = First entlang X, 1 = entlang Z),
##       kein eigener Schlüsselraum — pro Zelle/Ebene passt ohnehin nur ein Dach.
##   Treppe (STAIRS): belegt eine ZELLE (wie Boden/Dach). Schlüssel "T_<cx>_<cz>"
##       axis bestimmt nur die Blickrichtung des Aufstiegs (0..3, wie eine volle Drehung),
##       kein eigener Schlüsselraum — pro Zelle/Ebene passt ohnehin nur eine Treppe.
##   Requisit (TARGET): belegt eine ZELLE (wie Boden/Dach/Treppe). Schlüssel "P_<cx>_<cz>"
##       ("Prop") — eigener Schlüsselraum, unabhängig von Boden/Dach/Treppe derselben Zelle.
##       axis bestimmt wie bei STAIRS nur die Blickrichtung (0..3, volle Drehung).
##
## ROTATION: Böden sind quadratisch, Drehen ändert nichts. Bei Wänden schaltet jeder
## Rotationsschritt zwischen Achse 0 und 1 um (gerade Schritte = Achse 0, ungerade = 1).
##
## EBENEN (storey): Bauteile lassen sich übereinander setzen. Ebene 0 = Gelände (Schlüssel wie
## bisher, alte Spielstände bleiben gültig), Ebene n>0 hängt "_L<n>" an den Schlüssel. Eine
## Ebene ist LEVEL_HEIGHT hoch (= Wandhöhe): Boden der Ebene n liegt in Oberkante der Wände der
## Ebene n-1, Wände der Ebene n stehen auf diesem Boden.
##
## ERWEITERUNG: Neue Bauteil-Arten (Dach, Tür, Fenster-Wand, Treppe) bekommen hier einen
## eigenen Schlüsselraum und eine snap()-Regel; Registry/Regeln arbeiten nur mit Schlüsseln.

const CELL: float = 2.0
## Bauhöhen werden auf dieses Raster gerundet, damit Nachbarn auf sanften Hängen dieselbe
## Höhe teilen und keine Stufen/Lücken entstehen.
const Y_STEP: float = 0.25
## Höhe einer Ebene in Metern. Muss der Wandhöhe der Bauteile entsprechen (data/building/*.tres).
const LEVEL_HEIGHT: float = 2.5
## Höchste baubare Ebene (0 = Boden). Begrenzt Bauhöhe und Vorschau.
const MAX_STOREY: int = 3

static func _storey_suffix(storey: int) -> String:
	return "" if storey <= 0 else "_L%d" % storey

static func cell_of(world_x: float, world_z: float) -> Vector2i:
	return Vector2i(floori(world_x / CELL), floori(world_z / CELL))

static func floor_key(cell: Vector2i, storey: int = 0) -> String:
	return "F_%d_%d%s" % [cell.x, cell.y, _storey_suffix(storey)]

static func wall_key(axis: int, cx: int, cz: int, storey: int = 0) -> String:
	return "W%d_%d_%d%s" % [axis, cx, cz, _storey_suffix(storey)]

static func roof_key(cell: Vector2i, storey: int = 0) -> String:
	return "R_%d_%d%s" % [cell.x, cell.y, _storey_suffix(storey)]

static func stairs_key(cell: Vector2i, storey: int = 0) -> String:
	return "T_%d_%d%s" % [cell.x, cell.y, _storey_suffix(storey)]

static func target_key(cell: Vector2i, storey: int = 0) -> String:
	return "P_%d_%d%s" % [cell.x, cell.y, _storey_suffix(storey)]

## Rastet eine Zielposition auf das Bauraster ein.
## Rückgabe: {key, kind, axis, cell: Vector2i, center: Vector2 (x,z), yaw: float, storey: int}
##   axis: -1 bei Böden, sonst 0/1. yaw: Drehung um Y für die Darstellung.
static func snap(kind: int, world_pos: Vector3, rot_steps: int, storey: int = 0) -> Dictionary:
	storey = clampi(storey, 0, MAX_STOREY)
	# DOOR/WINDOW sind wandartig: dieselbe Kanten-Logik wie WALL, derselbe Schlüsselraum
	# (siehe Klassenkommentar) — nur "kind" im Ergebnis bleibt die tatsächliche Art.
	if kind == BuildPieceDefinition.Kind.WALL or kind == BuildPieceDefinition.Kind.DOOR \
			or kind == BuildPieceDefinition.Kind.WINDOW:
		var axis: int = posmod(rot_steps, 2)
		if axis == 0:
			var ez: int = roundi(world_pos.z / CELL)
			var cx: int = floori(world_pos.x / CELL)
			return {
				"key": wall_key(0, cx, ez, storey), "kind": kind, "axis": 0, "storey": storey,
				"cell": Vector2i(cx, ez),
				"center": Vector2((float(cx) + 0.5) * CELL, float(ez) * CELL),
				"yaw": 0.0,
			}
		var ex: int = roundi(world_pos.x / CELL)
		var cz: int = floori(world_pos.z / CELL)
		return {
			"key": wall_key(1, ex, cz, storey), "kind": kind, "axis": 1, "storey": storey,
			"cell": Vector2i(ex, cz),
			"center": Vector2(float(ex) * CELL, (float(cz) + 0.5) * CELL),
			"yaw": PI * 0.5,
		}
	if kind == BuildPieceDefinition.Kind.ROOF:
		var rcell: Vector2i = cell_of(world_pos.x, world_pos.z)
		var raxis: int = posmod(rot_steps, 2)
		return {
			"key": roof_key(rcell, storey), "kind": kind, "axis": raxis, "storey": storey,
			"cell": rcell,
			"center": Vector2((float(rcell.x) + 0.5) * CELL, (float(rcell.y) + 0.5) * CELL),
			"yaw": 0.0 if raxis == 0 else PI * 0.5,
		}
	if kind == BuildPieceDefinition.Kind.STAIRS:
		var scell: Vector2i = cell_of(world_pos.x, world_pos.z)
		# Volle Drehung (4 Schritte statt 2 wie bei Wand/Dach): die Blickrichtung des
		# Aufstiegs ist eine von vier Himmelsrichtungen, nicht nur eine Achse.
		var facing: int = posmod(rot_steps, 4)
		return {
			"key": stairs_key(scell, storey), "kind": kind, "axis": facing, "storey": storey,
			"cell": scell,
			"center": Vector2((float(scell.x) + 0.5) * CELL, (float(scell.y) + 0.5) * CELL),
			"yaw": float(facing) * PI * 0.5,
		}

	if kind == BuildPieceDefinition.Kind.TARGET:
		var pcell: Vector2i = cell_of(world_pos.x, world_pos.z)
		var pfacing: int = posmod(rot_steps, 4)
		return {
			"key": target_key(pcell, storey), "kind": kind, "axis": pfacing, "storey": storey,
			"cell": pcell,
			"center": Vector2((float(pcell.x) + 0.5) * CELL, (float(pcell.y) + 0.5) * CELL),
			"yaw": float(pfacing) * PI * 0.5,
		}

	# FLOOR (Standard)
	var cell: Vector2i = cell_of(world_pos.x, world_pos.z)
	return {
		"key": floor_key(cell, storey), "kind": BuildPieceDefinition.Kind.FLOOR, "axis": -1, "storey": storey,
		"cell": cell,
		"center": Vector2((float(cell.x) + 0.5) * CELL, (float(cell.y) + 0.5) * CELL),
		"yaw": 0.0,
	}

## Die vier Zellecken einer Zelle als Terrain-Gitterindizes (für Einebnen).
static func floor_corner_lattice(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var per_cell: int = roundi(CELL / TerrainEditLayer.SPACING)
	for dz in range(0, per_cell + 1):
		for dx in range(0, per_cell + 1):
			out.append(Vector2i(cell.x * per_cell + dx, cell.y * per_cell + dz))
	return out

## Endpunkte einer Wandkante in Weltkoordinaten: [Vector2 a, Vector2 b].
static func wall_endpoints(axis: int, cx: int, cz: int) -> Array[Vector2]:
	if axis == 0:
		return [Vector2(float(cx) * CELL, float(cz) * CELL), Vector2(float(cx + 1) * CELL, float(cz) * CELL)]
	return [Vector2(float(cx) * CELL, float(cz) * CELL), Vector2(float(cx) * CELL, float(cz + 1) * CELL)]

## Die (bis zu) zwei Zellen, an die eine Wandkante grenzt.
static func cells_adjacent_to_wall(axis: int, cx: int, cz: int) -> Array[Vector2i]:
	if axis == 0:
		return [Vector2i(cx, cz), Vector2i(cx, cz - 1)]
	return [Vector2i(cx, cz), Vector2i(cx - 1, cz)]

## Kürzester Abstand (XZ) eines Punkts zu einer Wandkante.
static func distance_to_wall(p: Vector2, axis: int, cx: int, cz: int) -> float:
	var ends: Array[Vector2] = wall_endpoints(axis, cx, cz)
	var a: Vector2 = ends[0]
	var b: Vector2 = ends[1]
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func quantize_y(y: float) -> float:
	return snappedf(y, Y_STEP)

## Baut ein snap()-Ergebnis direkt aus Rasterindizes (statt aus einer Weltposition) —
## dieselbe Form wie snap(), aber ohne floori()/roundi() auf einen konkreten Weltpunkt.
## Gebraucht von HouseTemplateDefinition-Platzierung (WorldBuildHandler._house_layout()):
## dort sind die Rasterindizes bereits bekannt (Anker-Zelle + relativer Versatz aus dem
## Bauplan), eine Rückumrechnung über einen Weltpunkt wäre nur eine Fehlerquelle.
## axis: bei WALL/DOOR/WINDOW 0/1 (wie snap()), bei ROOF Firstrichtung (0/1), bei STAIRS
## Blickrichtung (0..3), bei FLOOR ungenutzt (-1 erwartet, wird ignoriert).
static func snap_from_cell(kind: int, axis: int, cx: int, cz: int, storey: int = 0) -> Dictionary:
	storey = clampi(storey, 0, MAX_STOREY)
	if kind == BuildPieceDefinition.Kind.WALL or kind == BuildPieceDefinition.Kind.DOOR \
			or kind == BuildPieceDefinition.Kind.WINDOW:
		if posmod(axis, 2) == 0:
			return {
				"key": wall_key(0, cx, cz, storey), "kind": kind, "axis": 0, "storey": storey,
				"cell": Vector2i(cx, cz),
				"center": Vector2((float(cx) + 0.5) * CELL, float(cz) * CELL),
				"yaw": 0.0,
			}
		return {
			"key": wall_key(1, cx, cz, storey), "kind": kind, "axis": 1, "storey": storey,
			"cell": Vector2i(cx, cz),
			"center": Vector2(float(cx) * CELL, (float(cz) + 0.5) * CELL),
			"yaw": PI * 0.5,
		}
	if kind == BuildPieceDefinition.Kind.ROOF:
		var raxis: int = posmod(axis, 2)
		return {
			"key": roof_key(Vector2i(cx, cz), storey), "kind": kind, "axis": raxis, "storey": storey,
			"cell": Vector2i(cx, cz),
			"center": Vector2((float(cx) + 0.5) * CELL, (float(cz) + 0.5) * CELL),
			"yaw": 0.0 if raxis == 0 else PI * 0.5,
		}
	if kind == BuildPieceDefinition.Kind.STAIRS:
		var facing: int = posmod(axis, 4)
		return {
			"key": stairs_key(Vector2i(cx, cz), storey), "kind": kind, "axis": facing, "storey": storey,
			"cell": Vector2i(cx, cz),
			"center": Vector2((float(cx) + 0.5) * CELL, (float(cz) + 0.5) * CELL),
			"yaw": float(facing) * PI * 0.5,
		}
	if kind == BuildPieceDefinition.Kind.TARGET:
		var pfacing: int = posmod(axis, 4)
		return {
			"key": target_key(Vector2i(cx, cz), storey), "kind": kind, "axis": pfacing, "storey": storey,
			"cell": Vector2i(cx, cz),
			"center": Vector2((float(cx) + 0.5) * CELL, (float(cz) + 0.5) * CELL),
			"yaw": float(pfacing) * PI * 0.5,
		}

	# FLOOR (Standard)
	return {
		"key": floor_key(Vector2i(cx, cz), storey), "kind": BuildPieceDefinition.Kind.FLOOR, "axis": -1, "storey": storey,
		"cell": Vector2i(cx, cz),
		"center": Vector2((float(cx) + 0.5) * CELL, (float(cz) + 0.5) * CELL),
		"yaw": 0.0,
	}

## Dreht eine ZELLE (Boden/Dach/Treppe) um 90° um den Ursprung (0,0), in ganzzahligen
## Rasterindizes. Zellen sind Einheitsquadrate mit Ursprung an ihrer "kleinen" Ecke
## (Konvention wie cell_of()) — die Drehung eines Quadrats [x,x+1]×[z,z+1] um 90° liefert
## das neue Quadrat mit kleiner Ecke (-z-1, x) (Herleitung: alle vier Eckpunkte mit der
## Standard-Punktdrehung (x,z)→(-z,x) drehen, danach die neue kleine Ecke ablesen).
## Viermal angewendet ergibt wieder die Ausgangszelle (siehe Tests).
static func rotate_cell_90(cell: Vector2i) -> Vector2i:
	return Vector2i(-cell.y - 1, cell.x)

## Dreht eine WANDKANTE (axis, cx, cz) um 90° um den Ursprung, mit derselben Punktdrehung
## (x,z)→(-z,x) wie rotate_cell_90() — nur dass Kanten aus zwei GitterPUNKTEN bestehen
## (keine "kleine Ecke"-Korrektur wie bei Zellen nötig):
##   Achse 0 (cx,cz): Endpunkte (cx,cz)/(cx+1,cz) → gedreht (-cz,cx)/(-cz,cx+1)
##                     → das ist eine Achse-1-Kante bei cx'=-cz, cz'=cx.
##   Achse 1 (cx,cz): Endpunkte (cx,cz)/(cx,cz+1) → gedreht (-cz,cx)/(-cz-1,cx)
##                     → das ist eine Achse-0-Kante bei cx'=-cz-1, cz'=cx.
## Rückgabe: {axis, cx, cz}. Viermal angewendet ergibt wieder die Ausgangskante (siehe Tests).
static func rotate_wall_edge_90(axis: int, cx: int, cz: int) -> Dictionary:
	if axis == 0:
		return {"axis": 1, "cx": -cz, "cz": cx}
	return {"axis": 0, "cx": -cz - 1, "cz": cx}

## Dreht EINEN relativen Bauplan-Eintrag eines HouseTemplateDefinition
## ({piece_id, kind, axis, dx, dz}) um `steps` Schritte (je 90°) um den Ursprung (0,0) der
## Vorlage. Gemeinsame Quelle für Vorschau UND echtes Platzieren eines ganzen Hauses
## (WorldBuildHandler._house_layout()) — die Vorschau kann dadurch nie anders gedreht
## aussehen als das Ergebnis.
##   FLOOR:            Zelle dreht (rotate_cell_90), axis bleibt -1.
##   ROOF:             Zelle dreht, First-Achse kippt pro Schritt (wie bei einem Einzelteil).
##   STAIRS:           Zelle dreht, Blickrichtung (0..3) rückt pro Schritt eins weiter.
##   WALL/DOOR/WINDOW: Kante dreht (rotate_wall_edge_90), inkl. Achswechsel.
static func rotate_house_piece(entry: Dictionary, steps: int) -> Dictionary:
	var kind: int = int(entry.get("kind", BuildPieceDefinition.Kind.FLOOR))
	var axis: int = int(entry.get("axis", -1))
	var dx: int = int(entry.get("dx", 0))
	var dz: int = int(entry.get("dz", 0))
	var n: int = posmod(steps, 4)

	if kind == BuildPieceDefinition.Kind.WALL or kind == BuildPieceDefinition.Kind.DOOR \
			or kind == BuildPieceDefinition.Kind.WINDOW:
		for _i in n:
			var r: Dictionary = rotate_wall_edge_90(axis, dx, dz)
			axis = int(r["axis"])
			dx = int(r["cx"])
			dz = int(r["cz"])
		return {"piece_id": entry.get("piece_id", ""), "kind": kind, "axis": axis, "dx": dx, "dz": dz}

	var cell := Vector2i(dx, dz)
	for _i in n:
		cell = rotate_cell_90(cell)
	if kind == BuildPieceDefinition.Kind.ROOF:
		axis = posmod(axis + n, 2)
	elif kind == BuildPieceDefinition.Kind.STAIRS or kind == BuildPieceDefinition.Kind.TARGET:
		axis = posmod(axis + n, 4)
	else:
		axis = -1
	return {"piece_id": entry.get("piece_id", ""), "kind": kind, "axis": axis, "dx": cell.x, "dz": cell.y}

## Zerlegt einen Schlüssel: {kind, axis, x, z, storey} oder {} bei ungültigem Format.
## Böden: axis = -1. x/z = Zellindex (Böden) bzw. Kantenindex (Wände).
static func parse_key(key: String) -> Dictionary:
	var storey: int = 0
	var base: String = key
	var l_pos: int = key.find("_L")
	if l_pos >= 0:
		storey = int(key.substr(l_pos + 2))
		base = key.substr(0, l_pos)
	var parts: PackedStringArray = base.split("_")
	if parts.size() != 3:
		return {}
	if parts[0] == "F":
		return {"kind": BuildPieceDefinition.Kind.FLOOR, "axis": -1,
			"x": int(parts[1]), "z": int(parts[2]), "storey": storey}
	if parts[0] == "R":
		return {"kind": BuildPieceDefinition.Kind.ROOF, "axis": -1,
			"x": int(parts[1]), "z": int(parts[2]), "storey": storey}
	if parts[0] == "T":
		return {"kind": BuildPieceDefinition.Kind.STAIRS, "axis": -1,
			"x": int(parts[1]), "z": int(parts[2]), "storey": storey}
	if parts[0] == "P":
		return {"kind": BuildPieceDefinition.Kind.TARGET, "axis": -1,
			"x": int(parts[1]), "z": int(parts[2]), "storey": storey}
	if parts[0].length() == 2 and parts[0].begins_with("W"):
		return {"kind": BuildPieceDefinition.Kind.WALL, "axis": int(parts[0].substr(1)),
			"x": int(parts[1]), "z": int(parts[2]), "storey": storey}
	return {}
