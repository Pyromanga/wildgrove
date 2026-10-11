class_name TerrainErosionLayer
extends TerrainLayer

## TerrainErosionLayer — analytischer Erosionsfilter: verzweigte Rinnen und scharfe Grate in
## Hügeln und Bergen, ohne Erosions-Simulation.
##
## ═══ QUELLE ═══
## Rune Skovbo Johansen, "Fast and Gorgeous Erosion Filter" (blog.runevision.com, 30.03.2026),
## aufbauend auf Clay John "Eroded Terrain Noise" (2018) und Felix Westin (Fewes, 2023). Die
## Technik ist dort unter MPL 2.0 veröffentlicht; dies hier ist eine eigene, auf GDScript und
## unsere Layer-Architektur zugeschnittene Umsetzung der beschriebenen Ideen (nicht 1:1 deren
## Shader-Code).
##
## ═══ WARUM DAS HIER PASST ═══
## Echte Erosions-Simulation (Wassertropfen) braucht das ganze Gelände auf einmal — in einer
## unendlichen, chunk-weise gestreamten Welt unbrauchbar. Dieser Filter ist eine reine Funktion
## von (x, z, h): jeder Punkt wird einzeln berechnet. Damit gelten weiter alle Layer-Regeln
## (Weltkoordinaten, deterministisch, kein Zustand), Chunk-Nähte sind automatisch lückenlos, und
## Mesh, Kollision, Spawner und Bauen sehen exakt dieselbe Höhe.
##
## ═══ FUNKTIONSWEISE (pro Oktave) ═══
## 1. Fallrichtung bestimmen (Gefälle der Basis + bisher erzeugte Rinnenhänge); die Streifen
##    laufen ENTLANG des Gefälles, ihre Phase wird quer dazu gemessen.
## 2. "Phacelle"-artige Streifen: um zufällige Pivots in einem Zellraster werden Kosinus- UND
##    Sinus-Wellen mit weichen Gewichten gemittelt. Als Vektor (cos, sin) lässt sich das Ergebnis
##    normalisieren → gleichmäßig tiefe Rinnen. Nur Längen > 0.5 werden normalisiert (sonst
##    "Schlaufen"-Artefakte, siehe Blogpost).
## 3. Fade: Rinnen werden zum "Fade-Ziel" (-1 Tal … +1 Gipfel, aus der Höhe) ausgeblendet, wo
##    das Gelände flach ist (Gipfel/Täler der Basis) UND dort, wo schon größere Rinnen Grate/
##    Sohlen haben ("stacked fading"). Das hält Gipfel spitz und Rinnen-Sohlen/Grate scharf.
## 4. Der Hang der Rinne (mit festem Betrag, "straight gullies") geht in die Richtung der
##    nächsten, halb so großen Oktave ein → Verzweigungen im sauberen Winkel.
##
## Der Layer verändert nur Höhe (keine Ableitungen/Ridge-Map nötig). Er läuft direkt NACH dem
## TerrainBaseLayer und setzt voraus, dass `h` dessen Ausgabe ist (das Gefälle wird aus der Basis
## neu gemessen).

## Gaußsches Gewicht exp(-K·d²); abgezogen wird der Wert bei d = 1 (Fensterradius in Zellen),
## damit das Gewicht dort exakt 0 ist und keine Kante entsteht.
const WEIGHT_K: float = 3.0
## Pivots liegen nur in der Mitte jeder Zelle ([0.3, 0.7]): so ist in der 3x3-Nachbarschaft
## garantiert mindestens ein Pivot im Fensterradius 1 (Summe der Gewichte > 0).
const PIVOT_MIN: float = 0.3
const PIVOT_RANGE: float = 0.4

var _cfg: TerrainConfig
var _base: TerrainBaseLayer
## Optional: nur für den Abstand zum Flusslauf (Talsohlen bleiben glatt).
var _river: TerrainRiverLayer
var _salt: int
var _weight_floor: float

func _init(cfg: TerrainConfig, world_seed: int, base: TerrainBaseLayer, river: TerrainRiverLayer = null) -> void:
	_cfg = cfg
	_base = base
	_river = river
	# Kleiner Salt (20 Bit): bleibt in der Hash-Multiplikation weit unter int64-Überlauf.
	_salt = TerrainSeed.derive(world_seed, "terrain.erosion") & 0xFFFFF
	_weight_floor = exp(-WEIGHT_K)

func apply(world_x: float, world_z: float, h: float) -> float:
	if not _cfg.erosion_enabled:
		return h
	# Tiefland: kein Filter. Spart in den meisten Chunks den ganzen Rechenaufwand.
	var weight: float = smoothstep(_cfg.erosion_start_alt, _cfg.erosion_full_alt, h)
	if weight <= 0.0:
		return h
	# Flusstäler: keine Rinnen. Billig (ein Noise-Aufruf), solange kein Fluss in der Nähe ist.
	if _river != null:
		var rd: float = _river.distance_m(world_x, world_z)
		if rd < _cfg.erosion_river_clear + _cfg.erosion_river_fade:
			weight *= smoothstep(_cfg.erosion_river_clear, _cfg.erosion_river_clear + _cfg.erosion_river_fade, rd)
			if weight <= 0.0:
				return h
	var grad: Vector2 = _base_gradient(world_x, world_z)
	var out: float = h + _offset_with_gradient(world_x, world_z, h, grad.x, grad.y) * weight
	return _apply_strata(out, grad.length(), weight)

## Felsstufen: an steilen Hängen wird die Höhe zur Treppe gestaucht (Wand, Sims, Wand …).
## Stetig und monoton in h — die Stufen verlaufen entlang der Höhenlinien.
static func strata_height(h: float, spacing: float, riser: float) -> float:
	var v: float = h / spacing
	var fl: float = floorf(v)
	return spacing * (fl + smoothstep(1.0 - riser, 1.0, v - fl))

func _apply_strata(h: float, slope: float, weight: float) -> float:
	if not _cfg.strata_enabled:
		return h
	var w: float = smoothstep(_cfg.strata_slope_min, _cfg.strata_slope_max, slope) \
		* smoothstep(_cfg.strata_start_alt, _cfg.strata_start_alt + 10.0, h) * _cfg.strata_weight * weight
	if w <= 0.0:
		return h
	return lerpf(h, strata_height(h, _cfg.strata_spacing, _cfg.strata_riser), w)

## Gefälle der Basis, zentrale Differenzen über ±step (grob, siehe TerrainConfig).
func _base_gradient(world_x: float, world_z: float) -> Vector2:
	var step: float = _cfg.erosion_gradient_step
	var inv: float = 1.0 / (2.0 * step)
	return Vector2(
		(_base.apply(world_x + step, world_z, 0.0) - _base.apply(world_x - step, world_z, 0.0)) * inv,
		(_base.apply(world_x, world_z + step, 0.0) - _base.apply(world_x, world_z - step, 0.0)) * inv
	)

## Rohe Höhenänderung (m) an (x, z) für Basishöhe `h`, OHNE Höhen-Gewicht. Öffentlich für Tests.
func erosion_offset(world_x: float, world_z: float, h: float) -> float:
	var grad: Vector2 = _base_gradient(world_x, world_z)
	return _offset_with_gradient(world_x, world_z, h, grad.x, grad.y)

func _offset_with_gradient(world_x: float, world_z: float, h: float, gx: float, gz: float) -> float:
	var grad_len: float = sqrt(gx * gx + gz * gz)
	var nx: float = 1.0
	var nz: float = 0.0
	if grad_len > 0.000001:
		nx = gx / grad_len
		nz = gz / grad_len

	# Interne Hangrichtung mit festem Betrag ("pretend slope"); die Rinnenhänge kommen dazu.
	var sx: float = nx * _cfg.erosion_pretend_slope
	var sz: float = nz * _cfg.erosion_pretend_slope

	var span: float = maxf(_cfg.erosion_peak_alt - _cfg.erosion_valley_alt, 0.001)
	var fade: float = clampf((h - _cfg.erosion_valley_alt) / span * 2.0 - 1.0, -1.0, 1.0)
	var mask: float = _ease_out(grad_len / maxf(_cfg.erosion_slope_full, 0.001))

	var offset: float = 0.0
	var cell: float = _cfg.erosion_scale
	var amp: float = _cfg.erosion_strength

	for octave in range(_cfg.erosion_octaves):
		var slope_len: float = sqrt(sx * sx + sz * sz)
		var dx: float = 1.0
		var dz: float = 0.0
		if slope_len > 0.000001:
			dx = -sz / slope_len   # senkrecht zur Fallrichtung = Richtung, in der die Phase läuft
			dz = sx / slope_len

		var qx: float = world_x / cell
		var qz: float = world_z / cell
		var ix: int = floori(qx)
		var iz: int = floori(qz)

		var c_sum: float = 0.0
		var s_sum: float = 0.0
		var w_sum: float = 0.0
		for oi in range(-1, 2):
			for oj in range(-1, 2):
				var cx: int = ix + oi
				var cz: int = iz + oj
				var piv: Vector2 = _hash2(cx, cz, _salt + octave * 131)
				var ppx: float = qx - (float(cx) + PIVOT_MIN + PIVOT_RANGE * piv.x)
				var ppz: float = qz - (float(cz) + PIVOT_MIN + PIVOT_RANGE * piv.y)
				var w: float = exp(-WEIGHT_K * (ppx * ppx + ppz * ppz)) - _weight_floor
				if w <= 0.0:
					continue
				var phase: float = TAU * (ppx * dx + ppz * dz)
				c_sum += w * cos(phase)
				s_sum += w * sin(phase)
				w_sum += w
		if w_sum <= 0.000000001:
			break

		var c: float = c_sum / w_sum
		var s: float = s_sum / w_sum
		# Teilnormalisierung: Längen > 0.5 werden auf 1 gebracht, darunter x2 (stetig).
		var length: float = sqrt(c * c + s * s)
		if length > 0.000001:
			var scale: float = minf(1.0, 2.0 * length) / length
			c *= scale
			s *= scale

		# Gestapeltes Ausblenden: Rinne zum Fade-Ziel, wo die Maske klein ist.
		var faded: float = lerpf(fade, c, mask)
		offset += faded * amp
		fade = faded

		# Hang der Rinne mit festem Betrag (Vorzeichen von s) → gerade Verzweigungen.
		var gully_slope: float = -signf(s) * amp * TAU / cell
		sx += gully_slope * dx
		sz += gully_slope * dz

		# An Graten/Sohlen dieser Oktave (|s| ≈ 0) übernehmen die nächsten Oktaven das Fade-Ziel.
		mask = _pow_inv(mask, _cfg.erosion_detail) * _ease_out(absf(s))

		cell /= _cfg.erosion_lacunarity
		amp *= _cfg.erosion_gain
	return offset

static func _ease_out(t: float) -> float:
	var v: float = 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - v * v

static func _pow_inv(t: float, power: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), power)

## Zwei Zufallswerte [0,1) aus ganzzahligen Zellkoordinaten (Integer-Hash, plattformunabhängig).
## Negative Koordinaten sind ok: `& 0xFFFFFFFF` liefert bei 64-bit-Ints die unteren 32 Bit.
static func _hash2(ix: int, iz: int, salt: int) -> Vector2:
	var h: int = (ix * 374761393 + iz * 668265263 + salt * 1442695041) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	var h2: int = (h * 2246822519) & 0xFFFFFFFF
	h2 = h2 ^ (h2 >> 15)
	return Vector2(float(h & 0xFFFF) / 65536.0, float(h2 & 0xFFFF) / 65536.0)
