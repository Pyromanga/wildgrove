class_name TerrainBaseLayer
extends TerrainLayer

## TerrainBaseLayer — die Grundform der Welt: Ebenen, Hügel, GEBIRGE und Becken (Seen/Meer).
##
## Noise-Felder:
##   Kontinent (langwellig, ~550 m): entscheidet WO Ebene, Hügelland oder Becken ist.
##   Detail    (kurzwellig, ~125 m): die Unebenheit darin.
##   Gebirgsmaske (~1 km):           WO Gebirgsmassive stehen.
##   Grate (Ridged Multifractal, ~360 m + Oktaven): die Form der Berge selbst.
##   Warp (2 Felder):                verschiebt die Gratlinien (Domain-Warping).
##
##   Ebene  = plains_base + Detail * plains_amplitude          (sanft, überwiegend trocken)
##   Hügel  = hill_base   + Detail * hill_amplitude            (deutlich bewegt, bis ~13 m)
##   Becken = basin_floor + Detail * basin_amplitude           (unter dem Wasserspiegel)
##   Berge  = Hügelland + Grundhebung + Grate * mountain_height (bis ~95 m, Grate & Täler)
##
## Der Kontinent-Wert blendet weich zwischen den Profilen (smoothstep). Seen und Meer sind
## KEINE eigene Geometrie: sie entstehen dort, wo das Becken-Profil unter den Wasserspiegel
## fällt — mit natürlichen, unregelmäßigen Uferlinien.
##
## GEBIRGE — warum "Ridged": normales fBm-Noise macht runde Beulen ("kleine Hügel"). Bei
## 1-|n| liegen die Gipfel dort, wo das Noise 0 kreuzt, und das sind zusammenhängende LINIEN →
## Bergkämme mit Tälern dazwischen. Jede Oktave wird mit der vorherigen gewichtet, dadurch
## sitzt Feindetail (Felsrippen) nur nahe an den Graten, die Täler bleiben ruhig.
## Berge gibt es nie im Becken/Meer und nie in Spawn-Nähe (Dorf muss eben bleiben).
##
## Ignoriert die eingehende Höhe (ist die unterste Schicht des Stapels).

var _cfg: TerrainConfig
var _continent: FastNoiseLite
var _detail: FastNoiseLite
var _mountain_mask: FastNoiseLite
var _ridge: FastNoiseLite
var _warp_x: FastNoiseLite
var _warp_z: FastNoiseLite

## Maximale Summe der gewichteten Ridge-Oktaven wäre ~1.94; real selten > 1.5 → darauf normiert.
const RIDGE_NORMALIZE: float = 1.5

func _init(cfg: TerrainConfig, world_seed: int) -> void:
	_cfg = cfg
	_continent = make_noise(
		TerrainSeed.derive(world_seed, "terrain.continent"),
		cfg.continent_frequency, cfg.continent_octaves
	)
	_detail = make_noise(
		TerrainSeed.derive(world_seed, "terrain.detail"),
		cfg.detail_frequency, cfg.detail_octaves, cfg.detail_lacunarity, cfg.detail_gain
	)
	# Neue Quellen = neue Salts: bestehende Quellen (Kontinent/Detail/Klima) ändern sich nicht.
	_mountain_mask = make_noise(
		TerrainSeed.derive(world_seed, "terrain.mountain_mask"), cfg.mountain_mask_frequency, 2
	)
	# Ein-Oktaven-Noise mit Frequenz 1: die Oktaven/Frequenzen laufen manuell in _ridged().
	_ridge = make_noise(TerrainSeed.derive(world_seed, "terrain.ridge"), 1.0, 1)
	_warp_x = make_noise(TerrainSeed.derive(world_seed, "terrain.warp_x"), cfg.warp_frequency, 2)
	_warp_z = make_noise(TerrainSeed.derive(world_seed, "terrain.warp_z"), cfg.warp_frequency, 2)

func apply(world_x: float, world_z: float, _h: float) -> float:
	var c: float = _continent.get_noise_2d(world_x, world_z)
	var d: float = _detail.get_noise_2d(world_x, world_z)

	var hill_mask: float = smoothstep(_cfg.hill_start, _cfg.hill_end, c)
	var basin_mask: float = 1.0 - smoothstep(_cfg.basin_start, _cfg.basin_end, c)

	var plains: float = _cfg.plains_base + d * _cfg.plains_amplitude
	var hills: float = _cfg.hill_base + d * _cfg.hill_amplitude
	var h: float = lerpf(plains, hills, hill_mask)

	h += _mountain_height(world_x, world_z, c, d)

	# Tiefsee: je weiter c unter basin_start liegt, desto tiefer der Grund (siehe TerrainConfig).
	var depth_t: float = smoothstep(_cfg.basin_start, _cfg.basin_start - _cfg.basin_deep_range, c)
	var floor_h: float = lerpf(_cfg.basin_floor, _cfg.basin_deep_floor, depth_t)
	var basin: float = floor_h + d * _cfg.basin_amplitude
	return beach_remap(lerpf(h, basin, basin_mask), _cfg.beach_slope, _cfg.beach_band)

## Strand-Stauchung um den Meeresspiegel (0 m): Steigung `slope` bei 0, wächst bis `band` Meter
## Abstand auf 1 zurück; darüber unverändert. Stetig, monoton, Vorzeichen bleibt erhalten.
## → Küstenlinie (Nulldurchgang) und Wasseranteil bleiben exakt wie ohne Stauchung.
static func beach_remap(h: float, slope: float, band: float) -> float:
	var a: float = absf(h)
	var k: float = slope + (1.0 - slope) * smoothstep(0.0, band, a)
	return signf(h) * a * k

## Wie stark Gebirge an (x, z) ausgeprägt ist (0 … 1). Auch für Färbung/Spawner nutzbar.
func get_mountain_weight(world_x: float, world_z: float) -> float:
	var c: float = _continent.get_noise_2d(world_x, world_z)
	return _mountain_weight(world_x, world_z, c)

func _mountain_weight(world_x: float, world_z: float, c: float) -> float:
	# Spawn-Ausschluss zuerst: ist billig und spart in 90 % der Nähe den Noise.
	var dist: float = Vector2(world_x, world_z).length()
	var spawn_w: float = smoothstep(_cfg.mountain_spawn_clear, _cfg.mountain_spawn_clear + _cfg.mountain_spawn_fade, dist)
	if spawn_w <= 0.0:
		return 0.0
	var m: float = smoothstep(_cfg.mountain_start, _cfg.mountain_end, _mountain_mask.get_noise_2d(world_x, world_z))
	if m <= 0.0:
		return 0.0
	# Keine Berge im/am Becken: Küsten bleiben flach bis hügelig, Gebirge stehen im Landesinneren.
	var inland: float = smoothstep(_cfg.basin_end, _cfg.basin_end + 0.30, c)
	return m * inland * spawn_w

func _mountain_height(world_x: float, world_z: float, c: float, d: float) -> float:
	var m: float = _mountain_weight(world_x, world_z, c)
	if m <= 0.0:
		return 0.0
	# Domain-Warping: Gratlinien werden um bis zu warp_strength Meter verschoben.
	var wx: float = world_x + _warp_x.get_noise_2d(world_x, world_z) * _cfg.warp_strength
	var wz: float = world_z + _warp_z.get_noise_2d(world_x + 311.0, world_z - 177.0) * _cfg.warp_strength
	var ridge: float = _ridged(wx, wz)
	# m für die Grundhebung (Massiv steigt sanft an), m² für die Gipfelhöhe (Vorberge bleiben niedrig).
	return m * _cfg.mountain_uplift \
		+ m * m * ridge * _cfg.mountain_height \
		+ m * d * _cfg.mountain_detail_amplitude

## Ridged Multifractal, Ergebnis ~[0, 1].
func _ridged(x: float, z: float) -> float:
	var sum: float = 0.0
	var amp: float = 1.0
	var weight: float = 1.0
	var px: float = x * _cfg.ridge_frequency
	var pz: float = z * _cfg.ridge_frequency
	for i in range(_cfg.ridge_octaves):
		var n: float = _ridge.get_noise_2d(px, pz)
		var s: float = 1.0 - absf(n)
		s *= s
		s *= weight
		weight = clampf(s * 2.0, 0.0, 1.0)
		sum += s * amp
		amp *= _cfg.ridge_gain
		# Versatz je Oktave: sonst liegen die Nulllinien aller Oktaven übereinander.
		px = px * _cfg.ridge_lacunarity + 17.31
		pz = pz * _cfg.ridge_lacunarity - 9.77
	return clampf(sum / RIDGE_NORMALIZE, 0.0, 1.0)
