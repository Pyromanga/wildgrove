class_name LevelGauge
extends RefCounted

## LevelGauge — der "Wasserwagen": zeigt, wo der Boden von einer Bezugshöhe abweicht.
##
## Reine Logik (kein Node, keine Engine-Abhängigkeit außer Vektoren/Farben) — die Anzeige
## (LevelGaugeOverlay) legt daraus ein Farbnetz auf das Gelände. Abweichung d = Boden − Bezug:
##   d > 0  Boden liegt HÖHER als der Bezug  → warm (gelb → orange → rot): abtragen
##   d < 0  Boden liegt TIEFER als der Bezug → kühl (cyan → blau → violett): auffüllen
##   |d| ≤ TOL_LEVEL                         → grün: eben genug zum Bauen
##
## Abgetastet wird auf dem Terrain-Gitter (TerrainEditLayer.SPACING): dieselben Punkte, auf denen
## das Gelände-Mesh seine Vertices hat und auf denen Graben/Ebnen arbeiten — die Anzeige zeigt
## also exakt die Punkte, die man mit der Schaufel auch wirklich bewegen kann.

## Bis hierher gilt der Boden als eben (Meter). Etwas größer als die Delta-Quantisierung
## (TerrainEditLayer.QUANTUM = 0,05), damit frisch geebnete Flächen sicher grün sind.
const TOL_LEVEL: float = 0.10
## Grenzen der Stufen (Meter): leicht / deutlich; darüber "stark".
const TOL_SLIGHT: float = 0.30
const TOL_MEDIUM: float = 0.75
## Deckkraft der Anzeige im Kern; zum Rand blendet sie aus.
const ALPHA: float = 0.62
## Wie hoch das Netz über dem Gelände schwebt (Z-Fighting-Schutz, Meter).
const LIFT: float = 0.08

const COL_LEVEL  := Color(0.25, 0.85, 0.35)
const COL_HIGH_1 := Color(1.00, 0.90, 0.20)
const COL_HIGH_2 := Color(1.00, 0.55, 0.10)
const COL_HIGH_3 := Color(0.95, 0.15, 0.15)
const COL_LOW_1  := Color(0.35, 0.90, 0.95)
const COL_LOW_2  := Color(0.20, 0.50, 1.00)
const COL_LOW_3  := Color(0.55, 0.25, 0.90)

## Stufe der Abweichung: 0 = eben, ±1 leicht, ±2 deutlich, ±3 stark (Vorzeichen: + = zu hoch).
static func band_for(dev: float) -> int:
	var a: float = absf(dev)
	var level: int = 0
	if a <= TOL_LEVEL:
		level = 0
	elif a <= TOL_SLIGHT:
		level = 1
	elif a <= TOL_MEDIUM:
		level = 2
	else:
		level = 3
	return level if dev >= 0.0 else -level

## Stufenlose Farbe (ohne Alpha): grün im Toleranzbereich, danach weicher Verlauf je Richtung.
static func color_for(dev: float) -> Color:
	var a: float = absf(dev)
	if a <= TOL_LEVEL:
		return COL_LEVEL
	var high: bool = dev > 0.0
	var c1: Color = COL_HIGH_1 if high else COL_LOW_1
	var c2: Color = COL_HIGH_2 if high else COL_LOW_2
	var c3: Color = COL_HIGH_3 if high else COL_LOW_3
	# Grün endet hart bei TOL_LEVEL (die Grenze soll als Kante lesbar sein), danach gleitend.
	if a <= TOL_SLIGHT:
		return c1
	if a <= TOL_MEDIUM:
		return c1.lerp(c2, (a - TOL_SLIGHT) / (TOL_MEDIUM - TOL_SLIGHT))
	return c2.lerp(c3, clampf((a - TOL_MEDIUM) / TOL_MEDIUM, 0.0, 1.0))

## Bezugshöhe für "wie eben ist diese Stelle?": Mittel der vier Gitterecken der Zelle, die
## `center` enthält. Für einen Boden im Baumodus sind das genau seine vier Ecken — und
## damit die Höhe, auf die BuildPlacementRules ihn einebnen würde.
static func reference_height(height_fn: Callable, center: Vector2) -> float:
	var s: float = TerrainEditLayer.SPACING
	var ix: int = floori(center.x / s)
	var iz: int = floori(center.y / s)
	var sum: float = 0.0
	for dz in range(2):
		for dx in range(2):
			var w: Vector2 = TerrainEditLayer.lattice_to_world(Vector2i(ix + dx, iz + dz))
			sum += float(height_fn.call(w.x, w.y))
	return sum / 4.0

## Tastet das Gelände im Quadrat ±cells Zellen um die Zelle von `center` ab und liefert das
## Netz samt Kennzahlen.
##
## height_fn(x, z) -> float: Geländehöhe. ref_y: Bezugshöhe. stat_radius: nur Punkte innerhalb
## dieses Radius (Meter) um `center` zählen für die Kennzahlen (z.B. die Fläche, die man gerade
## bearbeitet), das Netz selbst reicht weiter.
##
## Rückgabe: {vertices: PackedVector3Array (Weltkoordinaten, schon um LIFT angehoben),
##   colors: PackedColorArray (mit Alpha, zum Rand ausgeblendet), indices: PackedInt32Array
##   (Dreiecke), stats: Dictionary (siehe compute_stats)}
static func build_grid(
	height_fn: Callable, center: Vector2, ref_y: float, cells: int, stat_radius: float
) -> Dictionary:
	var s: float = TerrainEditLayer.SPACING
	var cx: int = floori(center.x / s)
	var cz: int = floori(center.y / s)
	var side: int = cells * 2 + 2           # Punkte pro Seite (Zellen + 1)
	var min_ix: int = cx - cells
	var min_iz: int = cz - cells
	var fade_radius: float = (float(cells) + 1.0) * s

	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var devs: Array[float] = []
	var dists: Array[float] = []
	vertices.resize(side * side)
	colors.resize(side * side)

	for j in range(side):
		for i in range(side):
			var w: Vector2 = TerrainEditLayer.lattice_to_world(Vector2i(min_ix + i, min_iz + j))
			var h: float = float(height_fn.call(w.x, w.y))
			var dev: float = h - ref_y
			var dist: float = Vector2(w.x - center.x, w.y - center.y).length()
			var col: Color = color_for(dev)
			# Zum Rand ausblenden (kein harter Kasten im Gelände).
			var fade: float = 1.0 - smoothstep(0.55, 1.0, dist / fade_radius)
			col.a = ALPHA * fade
			var idx: int = j * side + i
			vertices[idx] = Vector3(w.x, h + LIFT, w.y)
			colors[idx] = col
			devs.append(dev)
			dists.append(dist)

	var indices := PackedInt32Array()
	for j in range(side - 1):
		for i in range(side - 1):
			var a: int = j * side + i
			var b: int = a + 1
			var c: int = a + side
			var d: int = c + 1
			indices.append_array([a, c, b, b, c, d])

	return {
		"vertices": vertices,
		"colors": colors,
		"indices": indices,
		"stats": compute_stats(devs, dists, stat_radius),
	}

## Kennzahlen über die Punkte innerhalb von stat_radius:
##   {count, max_high (größte positive Abweichung, ≥ 0), max_low (größte negative, ≤ 0),
##    level_share (Anteil 0..1 der Punkte im Toleranzbereich)}
static func compute_stats(devs: Array[float], dists: Array[float], stat_radius: float) -> Dictionary:
	var count: int = 0
	var level_count: int = 0
	var max_high: float = 0.0
	var max_low: float = 0.0
	for k in range(devs.size()):
		if dists[k] > stat_radius:
			continue
		count += 1
		var dev: float = devs[k]
		if absf(dev) <= TOL_LEVEL:
			level_count += 1
		max_high = maxf(max_high, dev)
		max_low = minf(max_low, dev)
	return {
		"count": count,
		"max_high": max_high,
		"max_low": max_low,
		"level_share": float(level_count) / float(count) if count > 0 else 0.0,
	}

## Anzeigetext für das HUD, z.B. "Wasserwagen: höher +0,42 m · tiefer −0,18 m · 63 % eben".
static func summary_text(stats: Dictionary) -> String:
	if int(stats.get("count", 0)) == 0:
		return "Wasserwagen: kein Gelände in der Nähe."
	var high: float = float(stats.get("max_high", 0.0))
	var low: float = float(stats.get("max_low", 0.0))
	var pct: int = roundi(float(stats.get("level_share", 0.0)) * 100.0)
	if high <= TOL_LEVEL and low >= -TOL_LEVEL:
		return "Wasserwagen: eben (%d %%)" % pct
	return "Wasserwagen: höher %s · tiefer %s · %d %% eben" % [_meters(high), _meters(low), pct]

## "+0,42 m" / "−0,18 m" / "0,00 m" — deutsches Komma, echtes Minuszeichen.
static func _meters(value: float) -> String:
	var rounded: float = snappedf(value, 0.01)
	var text: String = ("%.2f" % absf(rounded)).replace(".", ",")
	if rounded > 0.0:
		return "+%s m" % text
	if rounded < 0.0:
		return "−%s m" % text
	return "%s m" % text
