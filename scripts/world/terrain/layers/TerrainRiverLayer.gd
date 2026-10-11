class_name TerrainRiverLayer
extends TerrainLayer

## TerrainRiverLayer — Flusstäler: Graben mit Wasser darin, Ufer ÜBER dem Wasser, Wasserfälle.
##
## ═══ LAUF ═══
## Flüsse verlaufen entlang der Nulldurchgänge eines Noise-Feldes (weltweit nahtlos, ohne
## Chunk-Muster). Seit 2026-10-05 wird das Feld mit einem kleinräumigen Noise verzerrt
## (Domain-Warping) → engere Mäander statt glatter Bögen. Der Abstand zur Flussmitte ist
## |noise| / |Gradient| in METERN, deshalb hat jeder Fluss dieselbe Breite.
## Breite: nach Höhe (mündungsnah breit, im Gebirge schmaler Bach) und entlang des Laufs variiert.
##
## ═══ QUERSCHNITT ═══
##        Gelände ────╮                                 ╭──── Gelände
##          Uferwall   ╲                               ╱   (Böschung: am Wasser steil,
##   Wasserspiegel S ────╲_____________________________╱───── flach auslaufend)
##                         ╲___   Flussbett (Parabel) ___╱  ← river_depth unter S
##
##   S (Wasserspiegel) = niedrigste von drei Geländehöhen — Flussmitte − river_bank_drop sowie
##   linkes/rechtes Ufer − 0.4. So liegt das Wasser auch an einem QUERNEIGENDEN Hang unter BEIDEN
##   Ufern (vorher: an Hängen floss das Wasser auf einem Damm). Mindestens Meeresspiegel + min_surface.
##   S wird an der Flussmitte gemessen (ein Newton-Schritt auf die Nulllinie) → quer zum Fluss eben.
##
## ═══ WASSERFÄLLE ═══
## Wo das Gelände ENTLANG des Flusses steil ist (≥ river_fall_slope_min), wird S zur Treppe:
##   S_stair = H · (floor(S/H) + smoothstep(1−edge, 1, frac(S/H)))      (H = river_fall_height)
## d.h. S bleibt auf Stufenhöhe stehen (ruhiges Becken) und springt dann auf einer Strecke von
## ~edge·H/Gefälle um H (steiler Abbruch). Es gilt immer S_stair ≤ S (+ minimal): das Wasser liegt
## unter dem Gelände, hinter jedem Abbruch also in einer Schlucht, die flussabwärts ausläuft.
## Dort wird die Böschung zur Felswand (schmal, steil, mit Rauheit) und der TerrainColorizer färbt
## sie als Fels. Das Wasser selbst malt TerrainWaterBuilder (Fallfläche = steile Wasserfläche).
## Stufen sind immer BERGAB gerichtet — der Fluss braucht keine Fließrichtung.
##
## Wo das Gelände tiefer läge als S + river_bank_min, entsteht ein niedriger Uferwall. Im Hochland
## läuft der Fluss aus (river_max_height), zum Meer hin verläuft er sich (river_min_surface), um
## den Spawn gibt es keinen. Wasserspiegel kommt aus get_water_target_at().

## Schrittweite (m) für den Gradienten des Flussfeldes.
const GRADIENT_EPS: float = 1.0
## Abstand (m) der Längsproben für das Gefälle ENTLANG des Flusses.
const ALONG_STEP: float = 6.0
## Zusätzlicher Abstand (m) der Querproben hinter der Wasserkante.
const CROSS_MARGIN: float = 1.5
## Mindesthöhe des Wassers unter dem Ufer (m) beim Quergefälle.
const CROSS_BANK: float = 0.4
## Ufer-Böschung wird ab dieser Höhe (m) über dem Wasser zur Felswand, voll ab BANK_STEEP_MAX.
const BANK_STEEP_MIN: float = 2.0
const BANK_STEEP_MAX: float = 6.0
const CLIFF_MIN_WIDTH: float = 2.5
## Obergrenze des Memos (Einträge), danach wird es geleert.
const MEMO_LIMIT: int = 20000

var _cfg: TerrainConfig
var _noise: FastNoiseLite
var _warp_x: FastNoiseLite
var _warp_z: FastNoiseLite
var _width_noise: FastNoiseLite
var _rock_noise: FastNoiseLite
## Optional: Geländehöhe an der Flussmitte (uneingeschnitten). Ohne Basis (Tests) wird die
## übergebene Höhe verwendet und es gibt weder Quergefälle noch Wasserfälle.
var _base: TerrainBaseLayer
## (x, z, h) → Vector3-Ergebnis. Dieselben Punkte werden pro Chunk zweimal gebraucht (Höhe und
## Wasserspiegel); die teuren Basis-Proben nur einmal.
var _memo: Dictionary = {}

func _init(cfg: TerrainConfig, world_seed: int, base: TerrainBaseLayer = null) -> void:
	_cfg = cfg
	_base = base
	_noise = make_noise(TerrainSeed.derive(world_seed, "terrain.river"), cfg.river_frequency, 1)
	_warp_x = make_noise(TerrainSeed.derive(world_seed, "terrain.river_warp_x"), cfg.river_warp_frequency, 1)
	_warp_z = make_noise(TerrainSeed.derive(world_seed, "terrain.river_warp_z"), cfg.river_warp_frequency, 1)
	_width_noise = make_noise(TerrainSeed.derive(world_seed, "terrain.river_width"), 0.006, 1)
	_rock_noise = make_noise(TerrainSeed.derive(world_seed, "terrain.river_rock"), 0.12, 1)

func apply(world_x: float, world_z: float, h: float) -> float:
	return _sample(world_x, world_z, h).x

## Flussfeld mit Domain-Warping. Nulllinie = Flussmitte.
func _river_noise(x: float, z: float) -> float:
	var a: float = _cfg.river_warp_amplitude
	return _noise.get_noise_2d(x + a * _warp_x.get_noise_2d(x, z), z + a * _warp_z.get_noise_2d(x + 97.0, z - 53.0))

## Billiger Vorfilter: kann hier überhaupt ein Fluss sein?
func is_candidate(world_x: float, world_z: float) -> bool:
	return absf(_river_noise(world_x, world_z)) < _cfg.river_search_band

## Ungefährer Abstand (m) zur Flussmitte, INF wenn weiter als die Suchbreite. Für Erosion/Seen
## ("kein Fels-Gekräusel im Tal", "See nicht auf dem Fluss").
func distance_m(world_x: float, world_z: float) -> float:
	var n: float = _river_noise(world_x, world_z)
	if absf(n) >= _cfg.river_search_band:
		return INF
	var grad: float = _gradient(world_x, world_z).length()
	if grad < 0.0001:
		return INF
	return absf(n) / grad

func _gradient(x: float, z: float) -> Vector2:
	var e: float = GRADIENT_EPS
	return Vector2(
		(_river_noise(x + e, z) - _river_noise(x - e, z)) / (2.0 * e),
		(_river_noise(x, z + e) - _river_noise(x, z - e)) / (2.0 * e)
	)

## Wasserspiegel-Ziel an (x, z) oder NAN außerhalb jedes Flusswassers.
func get_water_target_at(world_x: float, world_z: float, h_before: float) -> float:
	return _sample(world_x, world_z, h_before).y

## Wie stark wirkt der Fluss hier (0 … 1)? Für Färbung.
func get_influence_at(world_x: float, world_z: float, h_before: float) -> float:
	return _sample(world_x, world_z, h_before).z

## Wasserfall-Treppe (öffentlich, damit testbar). `weight` 0 → s unverändert, 1 → volle Treppe.
static func fall_surface(s: float, fall_height: float, edge: float, weight: float) -> float:
	var v: float = s / fall_height
	var fl: float = floorf(v)
	var stair: float = fall_height * (fl + smoothstep(1.0 - edge, 1.0, v - fl))
	return lerpf(s, stair, weight)

## Rückgabe: x = neue Geländehöhe, y = Wasserspiegel (NAN = kein Flusswasser hier),
##           z = Einfluss/Fade 0 … 1.
func _sample(world_x: float, world_z: float, h: float) -> Vector3:
	var none := Vector3(h, NAN, 0.0)

	var n: float = _river_noise(world_x, world_z)
	if absf(n) >= _cfg.river_search_band:
		return none

	# Spawn-Umgebung bleibt flussfrei (Dorf, NPCs, Beete müssen trocken sein).
	var spawn_fade: float = smoothstep(
		_cfg.spawn_blend_radius, _cfg.spawn_blend_radius + _cfg.river_spawn_margin,
		Vector2(world_x, world_z).length()
	)
	if spawn_fade <= 0.0:
		return none

	var g: Vector2 = _gradient(world_x, world_z)
	var grad_sq: float = g.length_squared()
	if grad_sq < 0.000000001:
		return none
	var grad: float = sqrt(grad_sq)
	var dist_m: float = absf(n) / grad

	# Größtmögliche Reichweite (breitester Fluss) für den billigen Frühausstieg — die echte
	# Breite braucht schon eine Basis-Probe.
	var wmul_max: float = 1.3 * maxf(_cfg.river_width_low_mul, _cfg.river_width_high_mul)
	var reach_max: float = (_cfg.river_channel_half_width + _cfg.river_bank_width + _cfg.river_outer_blend) * wmul_max
	if dist_m >= reach_max:
		return none

	var key := Vector3(world_x, world_z, h)
	if _memo.has(key):
		return _memo[key]
	var result: Vector3 = _compute(world_x, world_z, h, n, g, grad_sq, grad, dist_m, spawn_fade)
	if _memo.size() >= MEMO_LIMIT:
		_memo.clear()
	_memo[key] = result
	return result

func _compute(
	world_x: float, world_z: float, h: float,
	n: float, g: Vector2, grad_sq: float, grad: float, dist_m: float, spawn_fade: float
) -> Vector3:
	var none := Vector3(h, NAN, 0.0)

	# Flussmitte p_c: ein Newton-Schritt auf die Nulllinie (Feld nahe der Linie fast linear).
	var k: float = n / grad_sq
	var cx: float = world_x - k * g.x
	var cz: float = world_z - k * g.y
	var normal := g / grad                     # quer zum Fluss
	var tangent := Vector2(-normal.y, normal.x) # entlang des Flusses

	var ref_h: float = h
	if _base != null:
		ref_h = _base.apply(cx, cz, 0.0)

	# Breite: Basis × Breiten-Noise entlang des Laufs × Höhenfaktor (Mündung breit, Quelle schmal).
	var wnoise: float = clampf(_width_noise.get_noise_2d(cx, cz) * 0.5 + 0.5, 0.0, 1.0)
	var alt_t: float = smoothstep(_cfg.river_width_alt_low, _cfg.river_width_alt_high, ref_h)
	var wmul: float = lerpf(0.75, 1.3, wnoise) * lerpf(_cfg.river_width_low_mul, _cfg.river_width_high_mul, alt_t)
	var w_channel: float = _cfg.river_channel_half_width * wmul
	var w_bank: float = _cfg.river_bank_width * wmul
	var w_outer: float = _cfg.river_outer_blend * wmul
	var reach: float = w_channel + w_bank + w_outer
	if dist_m >= reach:
		return none

	# Hochland: Fluss läuft aus. Küste: Fluss verläuft sich im See/Meer.
	var lowland: float = 1.0 - smoothstep(_cfg.river_max_height, _cfg.river_max_height + _cfg.river_fade_range, ref_h)
	var inland: float = smoothstep(_cfg.water_level + _cfg.river_min_surface, _cfg.water_level + _cfg.river_min_surface + 1.4, ref_h)
	var fade: float = lowland * inland * spawn_fade
	if fade <= 0.0:
		return none

	# Wasserspiegel: unter Mitte UND beiden Ufern (Quergefälle), nie unter dem Meeresspiegel.
	var surface: float = ref_h - _cfg.river_bank_drop
	var along_slope: float = 0.0
	if _base != null:
		var off: float = w_channel + CROSS_MARGIN
		var left: float = _base.apply(cx + normal.x * off, cz + normal.y * off, 0.0)
		var right: float = _base.apply(cx - normal.x * off, cz - normal.y * off, 0.0)
		surface = minf(surface, minf(left, right) - CROSS_BANK)
		var ahead: float = _base.apply(cx + tangent.x * ALONG_STEP, cz + tangent.y * ALONG_STEP, 0.0)
		var behind: float = _base.apply(cx - tangent.x * ALONG_STEP, cz - tangent.y * ALONG_STEP, 0.0)
		along_slope = absf(ahead - behind) / (2.0 * ALONG_STEP)
	var floor_level: float = _cfg.water_level + _cfg.river_min_surface
	surface = maxf(surface, floor_level)

	# Wasserfälle: nur wo das Gelände entlang des Flusses wirklich steil ist.
	var fall_w: float = smoothstep(_cfg.river_fall_slope_min, _cfg.river_fall_slope_max, along_slope)
	if fall_w > 0.0:
		surface = maxf(fall_surface(surface, _cfg.river_fall_height, _cfg.river_fall_edge, fall_w), floor_level)

	var bank_top: float = maxf(h, surface + _cfg.river_bank_min)
	var relief: float = bank_top - surface
	# Hohe Uferwand (Wasserfall, Schlucht): Böschung wird schmal und steil statt sanft.
	var steep: float = smoothstep(BANK_STEEP_MIN, BANK_STEEP_MAX, relief)
	var w_bank_eff: float = lerpf(w_bank, maxf(CLIFF_MIN_WIDTH, relief * 0.5), steep)

	var profile: float
	if dist_m < w_channel:
		var u: float = dist_m / w_channel
		profile = surface - _cfg.river_depth * (1.0 - u * u)
	else:
		var t: float = clampf((dist_m - w_channel) / w_bank_eff, 0.0, 1.0)
		var e: float = 1.0 - (1.0 - t) * (1.0 - t)
		profile = lerpf(surface, bank_top, e)

	# Äußerer Auslauf in das ungestörte Gelände.
	var inside: float = 1.0 - smoothstep(w_channel + w_bank_eff, reach, dist_m)
	var carved: float = lerpf(h, profile, inside * fade)

	# Felsrauheit an hohen Wänden — nur nach OBEN, damit nie Wasser aus dem Bett lecken kann.
	if steep > 0.0 and fall_w > 0.0:
		var wall: float = smoothstep(w_channel + 0.5, w_channel + 2.0, dist_m) \
			* (1.0 - smoothstep(w_channel + w_bank_eff * 0.8, w_channel + w_bank_eff * 1.6, dist_m))
		var rough: float = (_rock_noise.get_noise_2d(world_x, world_z) * 0.5 + 0.5) * _cfg.river_fall_roughness
		carved += rough * steep * fall_w * wall * fade

	var water: float = surface if dist_m < w_channel + w_bank_eff else NAN
	return Vector3(carved, water, inside * fade)
