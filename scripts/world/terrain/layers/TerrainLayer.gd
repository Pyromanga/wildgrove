class_name TerrainLayer
extends RefCounted

## TerrainLayer — EIN Schritt in der Höhen-Berechnung (TerrainField).
##
## Das Gelände ist ein Stapel von Layern; jeder bekommt die bisherige Höhe `h` an Position
## (x, z) und gibt die neue Höhe zurück:
##
##     h = 0 → BaseLayer → RiverLayer → SpawnPlateauLayer → (Edit-Deltas)
##
## Neue Geländemerkmale (Krater, Straßen, Dorf-Plateaus, Strände, Vulkane) sind neue Layer —
## KEIN Eingriff in bestehende. Regeln für Layer:
##   - REINE FUNKTION von (x, z, h) und dem, was der Konstruktor bekommen hat. Kein
##     Zustand, der sich zur Laufzeit ändert, kein Zufall, keine Zeit. Nur so ergibt
##     jeder Peer/jeder Chunk/jeder Aufrufer dieselbe Höhe für denselben Punkt.
##   - Weltkoordinaten (nicht chunk-lokal). Nur so sind Chunk-Nähte lückenlos.
##   - Kein Zugriff auf Nodes/Services.

func apply(_world_x: float, _world_z: float, h: float) -> float:
	return h

## Einheitliche Noise-Erzeugung für alle Layer (Simplex, fBm ab 2 Oktaven).
static func make_noise(
	seed_value: int, frequency: float, octaves: int,
	lacunarity: float = 2.0, gain: float = 0.5
) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
		n.fractal_lacunarity = lacunarity
		n.fractal_gain = gain
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n
