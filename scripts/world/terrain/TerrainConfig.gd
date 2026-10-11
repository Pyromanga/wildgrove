class_name TerrainConfig
extends Resource

## TerrainConfig — ALLE Stellschrauben des Geländes an EINER Stelle.
##
## WARUM: Vorher standen Chunk-Größe, Auflösung, Max-Höhe und Meeresspiegel doppelt im
## Code (WorldFactory UND ChunkManager, mit dem Kommentar "muss übereinstimmen, sonst
## stimmen Höhen nicht") — ein Fehler, der nur durch Disziplin verhindert wurde. Jetzt
## gibt es genau eine Konfiguration, die an TerrainField übergeben wird; alle anderen
## Teile (Chunks, Wasser, Spawner, Bauen) lesen sie von dort.
##
## Alle Höhen in Metern über/unter y=0. Alle Frequenzen in 1/Meter (Wellenlänge = 1/f).
## Neue Welten mit anderem Charakter = andere TerrainConfig (später als .tres ladbar).
##
## Reine Datenklasse, keine Logik außer abgeleiteten Größen.

## Seed, wenn kein world_seed gesetzt ist (0). Nur Fallback — im Spiel gibt WorldService
## immer den echten, zwischen Peers synchronisierten world_seed vor.
const DEFAULT_SEED: int = 1337

# ── Chunks ──────────────────────────────────────
## Kantenlänge eines Chunks in Metern.
const DEFAULT_CHUNK_SIZE: float = 64.0
@export var chunk_size: float = DEFAULT_CHUNK_SIZE

# ── Höhen ───────────────────────────────────────
## Obergrenze für die Höhen-Einfärbung (TerrainColorizer, Schneegrenze usw. skalieren damit).
## KEIN hartes Limit der Höhe. Höchste Gipfel liegen bei ~85-90 m (inkl. Erosion).
@export var max_height: float = 95.0
## Wasserspiegel. Alles Gelände darunter ist Wasser (Seen, Flüsse, Meer, aber auch
## vom Spieler gegrabene Senken). Eine Zahl für die ganze Welt.
@export var water_level: float = 0.0

# ── Kontinent (großräumige Form: Ebene / Hügel / Becken) ──
@export var continent_frequency: float = 0.0018
@export var continent_octaves: int = 3
## Ab welchem Kontinent-Wert Hügel beginnen (0) und voll ausgeprägt sind (1). Noise ~[-1,1].
@export var hill_start: float = 0.0
@export var hill_end: float = 0.35
## Unterhalb von basin_end beginnt ein Becken (See/Meer), unter basin_start ist es voll.
@export var basin_start: float = -0.48
@export var basin_end: float = -0.26

# ── Detail (kleinräumige Unebenheit) ────────────
@export var detail_frequency: float = 0.008
## 4 Oktaven: die feinste hat ~13 m Wellenlänge. Feinere Oktaven wären bei 2 m Vertex-Abstand
## nicht mehr darstellbar (Aliasing → zackiges, zufälliges Rauschen statt Hügelchen).
@export var detail_octaves: int = 4
@export var detail_lacunarity: float = 2.1
@export var detail_gain: float = 0.55

# ── Höhenprofile ────────────────────────────────
@export var plains_base: float = 2.4
@export var plains_amplitude: float = 2.0
@export var hill_base: float = 6.0
@export var hill_amplitude: float = 8.5
@export var basin_floor: float = -3.0
@export var basin_amplitude: float = 1.0
## Tiefsee (2026-10-05): vorher war jedes Becken überall nur ~3 m tief. Je weiter der Kontinent-Wert
## unter `basin_start` fällt, desto tiefer der Grund — kleine Becken bleiben flache Seen, große
## werden echtes Meer. Voll ausgeprägt `basin_deep_range` unter basin_start.
@export var basin_deep_floor: float = -18.0
@export var basin_deep_range: float = 0.20
## Strände: Höhen um den Meeresspiegel werden sanft gestaucht (Faktor `beach_slope` bei 0 m,
## bis `beach_band` m über/unter dem Wasser zurück auf 1). Das Vorzeichen bleibt → Küstenlinie
## und Wasseranteil ändern sich nicht, nur der Übergang wird flach statt steil.
@export var beach_slope: float = 0.35
@export var beach_band: float = 5.0

# ── Gebirge ─────────────────────────────────────
## Gebirge sind ein eigener Layer-Anteil im TerrainBaseLayer: eine langwellige Maske
## entscheidet WO Gebirge ist (bis zu mehrere km lange Gebirgszüge), ein "Ridged Multifractal" (Grate statt
## runder Beulen) liefert die Form, Domain-Warping bricht die Regelmäßigkeit auf.
@export var mountain_mask_frequency: float = 0.0006
## Maske (Noise ~[-1,1]) ab der Gebirge beginnen / voll ausgeprägt sind.
@export var mountain_start: float = -0.02
@export var mountain_end: float = 0.36
## Frequenz der Grate (0.0015 → Gratabstand ~ 650 m). Hangneigung ≈ Höhe × Frequenz: für
## flachere Berge Höhe senken ODER Frequenz senken (simuliert: Median ~22°, 90 % unter ~43°).
@export var ridge_frequency: float = 0.0015
@export var ridge_octaves: int = 5
@export var ridge_lacunarity: float = 2.07
## Gain < 0.5: feine Oktaven bleiben klein — bei 0.5 wären die Hänge durch Feindetail zu steil.
@export var ridge_gain: float = 0.3
## Höhe der Gipfel über dem Vorland und die Grundhebung eines Massivs.
@export var mountain_height: float = 64.0
@export var mountain_uplift: float = 9.0
## Zusätzliche, kleinräumige Zerklüftung (Detail-Noise) im Gebirge, in Metern.
@export var mountain_detail_amplitude: float = 5.0
## Domain-Warping: verschiebt die Gratlinien, damit sie nicht wie Noise-Zellen aussehen.
@export var warp_frequency: float = 0.0022
@export var warp_strength: float = 60.0
## Um den Spawn bleibt das Land gebirgsfrei (Dorf!). Ab `mountain_spawn_clear` Meter vom
## Ursprung beginnen Berge, über `mountain_spawn_fade` Meter wachsen sie voll heraus.
@export var mountain_spawn_clear: float = 150.0
@export var mountain_spawn_fade: float = 200.0

# ── Erosion (analytischer Erosionsfilter) ───────
## Quelle: Rune Skovbo Johansen, "Fast and Gorgeous Erosion Filter" (2026), aufbauend auf
## Clay John (2018) und Felix Westin/Fewes (2023). Kein Simulationsschritt: jeder Punkt wird
## EINZELN aus (x, z) berechnet — deshalb Chunk-nahtlos, deterministisch und für unendliche
## Welten geeignet. Idee: entlang der Fallrichtung des Geländes werden Streifen (Rinnen und
## Grate) gelegt; deren eigene Hänge steuern die nächstkleinere Oktave → Rinnen verzweigen
## sich wie von Wasser geschnitten. Wirkt nur im Hügel-/Bergland (siehe erosion_start_alt).
@export var erosion_enabled: bool = true
## Wellenlänge der gröbsten Rinnen (m). Jede Oktave halbiert sie (erosion_lacunarity).
@export var erosion_scale: float = 180.0
## 3 Oktaven = 180 / 90 / 45 m. Mehr Oktaven kosten Rechenzeit pro Vertex (GDScript!) und
## sind bei 2 m Vertex-Abstand unter ~20 m Wellenlänge ohnehin nicht darstellbar.
@export var erosion_octaves: int = 3
@export var erosion_lacunarity: float = 2.0
## Tiefe der gröbsten Rinnen (±m); pro Oktave mal erosion_gain (halbiert = gleiche Hangneigung).
@export var erosion_strength: float = 8.0
@export var erosion_gain: float = 0.5
## Gefälle für die Rinnenrichtung wird mit zentralen Differenzen über ± dieser Strecke (m)
## gemessen. Absichtlich GROB: ein feiner Abstand folgt dem Detail-Rauschen, die Richtung
## schwankt, die Streifen verdrehen sich → senkrechte Sprünge (in der Simulation bis 14 m
## auf 1 m). Bei 64 m ist der Sprung nicht größer als der des unerodierten Geländes.
@export var erosion_gradient_step: float = 64.0
## Ab welcher Hangneigung (dh/dx) die Rinnen voll wirken; flacher blenden sie zum Fade-Ziel aus.
@export var erosion_slope_full: float = 0.6
## Angenommene Hangneigung für die Streifenrichtung der Oktaven (siehe Blogpost: "pretend slope").
@export var erosion_pretend_slope: float = 0.6
## >1 = feinere Rinnen nur an steileren Hängen, <1 = überall Feindetail.
@export var erosion_detail: float = 1.0
## Fade-Ziel: auf Höhe `valley_alt` -1 (Täler bleiben Täler), auf `peak_alt` +1 (Gipfel bleiben
## spitz). Dazwischen linear.
@export var erosion_valley_alt: float = 10.0
@export var erosion_peak_alt: float = 70.0
## Unterhalb start_alt gar keine Erosion (Tiefland, Flüsse), ab full_alt voll.
@export var erosion_start_alt: float = 6.0
@export var erosion_full_alt: float = 20.0

## Um Flüsse keine Rinnen: Talsohlen sind glatt. Innerhalb `erosion_river_clear` Meter vom Flusslauf
## wirkt die Erosion gar nicht, über `erosion_river_fade` Meter blendet sie ein.
@export var erosion_river_clear: float = 30.0
@export var erosion_river_fade: float = 40.0
## Felsstufen (2026-10-05): an steilen Berghängen wird die Höhe zu "Treppen" gestaucht — steile
## Absätze (Felswände) im Wechsel mit flachen Simsen. `strata_riser` = Anteil der Höhenspanne, auf
## dem die Wand steht (kleiner = senkrechter). Das Gefälle ist das GROBE (±64 m) der Basis: im Gebirge
## liegt es bei Median 0.21, 90 % unter 0.39 — deshalb diese niedrigen Schwellen (bei 0.5/1.0 wirkte nichts).
@export var strata_enabled: bool = true
@export var strata_spacing: float = 7.0
@export var strata_riser: float = 0.30
@export var strata_weight: float = 0.8
@export var strata_slope_min: float = 0.15
@export var strata_slope_max: float = 0.4
@export var strata_start_alt: float = 14.0

# ── Flüsse ──────────────────────────────────────
## Flüsse verlaufen entlang der Nulldurchgänge eines eigenen Noise-Feldes — dadurch
## zusammenhängend, weltweit nahtlos und ohne Chunk-Muster (der alte Fluss war pro Chunk
## lokal und wiederholte sich in jedem Chunk).
@export var river_frequency: float = 0.0020
## Halbe Breite der WASSERFLÄCHE in Metern (Abstand Flussmitte → Wasserkante). Wird entlang des
## Flusses mit einem Breiten-Noise variiert (x0.7 … x1.35), damit er mal enger, mal breiter ist.
@export var river_channel_half_width: float = 4.5
## Breite der Uferböschung in Metern: vom Wasserrand steigt das Ufer über diese Strecke bis
## zum umgebenden Gelände an (steil am Wasser, flach auslaufend).
@export var river_bank_width: float = 8.0
## Weicher Auslauf außerhalb der Böschung (Meter), in dem das Ufer ins Gelände übergeht.
@export var river_outer_blend: float = 6.0
## Nur Bereiche mit |Noise| unter diesem Wert werden überhaupt auf einen Fluss geprüft
## (Vorfilter, spart Rechenzeit; muss über Gesamtbreite × maximalem Noise-Gradient liegen:
## ~34 m × ~0.009 bei Frequenz 0.002 ≈ 0.30).
@export var river_search_band: float = 0.34
## Tiefe der Flussmitte UNTER dem Wasserspiegel.
@export var river_depth: float = 2.0
## Wie weit der Wasserspiegel UNTER der ursprünglichen Geländehöhe in der Flussmitte liegt.
## DAS macht aus "Wasser auf dem Boden" einen echten Graben: Ufer liegen über dem Wasser.
@export var river_bank_drop: float = 1.4
## Mindest-Uferhöhe über dem Wasser (Meter): wo das Gelände tiefer läge, entsteht ein Uferwall.
@export var river_bank_min: float = 0.55
## Flüsse existieren nur im Tief-/Hügelland: oberhalb dieser Höhe läuft der Fluss aus.
@export var river_max_height: float = 28.0
@export var river_fade_range: float = 12.0
## Unterhalb dieser Höhe über dem Meer verläuft sich der Fluss im See/Meer (Mündung).
@export var river_min_surface: float = 0.2
## Mäander: der Flusslauf (Noise-Nulllinie) wird mit einem zweiten, kleinräumigen Noise verzerrt,
## sonst sind Flüsse sehr glatte, runde Bögen.
@export var river_warp_frequency: float = 0.008
@export var river_warp_amplitude: float = 18.0
## Breite nach Höhe: Mündungsnah (tief) breit, im Gebirge (hoch) schmale Bäche.
@export var river_width_low_mul: float = 1.5
@export var river_width_high_mul: float = 0.65
@export var river_width_alt_low: float = 2.0
@export var river_width_alt_high: float = 30.0
## WASSERFÄLLE: Ist der Fluss entlang seines Laufs steiler als `river_fall_slope_min` (dh/ds), wird sein
## Wasserspiegel zur Treppe mit Stufenhöhe `river_fall_height`: lange ruhige Becken, dazwischen
## fast senkrechte Abbrüche (Breite ~ `river_fall_edge` × Stufenhöhe ÷ Gefälle). Volle Wirkung ab
## `river_fall_slope_max`. In der Simulation sind das ~10 % der Flussstrecke im Hügelland.
@export var river_fall_height: float = 5.5
@export var river_fall_slope_min: float = 0.30
@export var river_fall_slope_max: float = 0.45
@export var river_fall_edge: float = 0.06
## Zufällige Unregelmäßigkeit der Felswand an Wasserfällen (Meter, nur nach OBEN → nie Wasser-Leck).
@export var river_fall_roughness: float = 1.4

# ── Bergseen ────────────────────────────────────
## Seen in Hügeln/Bergen auf EIGENER Höhe (Meer/Tiefland-Seen liegen auf dem globalen Spiegel).
## Pro Rasterzelle (lake_cell_size) höchstens ein See; Mittelpunkt in der Zellmitte
## ([0.3, 0.7]) → ein See überlappt nie die Nachbarzelle: Radius×(1+Formamplitude)+Ufer muss unter
## 0.3 × Zelle bleiben (100×1.28+16 = 144 ≤ 150), es muss immer nur EINE Zelle geprüft werden.
@export var lake_enabled: bool = true
@export var lake_cell_size: float = 500.0
@export var lake_chance: float = 0.9
@export var lake_min_radius: float = 35.0
@export var lake_max_radius: float = 100.0
## Seespiegel-Bereich (m). Darunter wäre es ohnehin Meeresniveau, darüber sind die Hänge zu zerklüftet für einen sauberen Rand.
@export var lake_min_alt: float = 3.0
@export var lake_max_alt: float = 30.0
@export var lake_depth_min: float = 2.5
@export var lake_depth_max: float = 6.0
@export var lake_bank_width: float = 9.0
@export var lake_outer_blend: float = 7.0
@export var lake_bank_min: float = 0.55
## Unregelmäßigkeit des Uferverlaufs (0 = Kreis, 0.28 = ±28 % Radius).
@export var lake_shape_amplitude: float = 0.28
@export var lake_spawn_clear: float = 230.0
## Mindestabstand (m) Seeufer ↔ Fluss.
@export var lake_river_clear: float = 45.0
## Erlaubte Höhe des Mittelpunkts ÜBER dem Seespiegel (Hügelkuppen werden nicht ausgehoben).
@export var lake_max_pit: float = 7.0
## Seespiegel = dieser Anteil (0 … 1) der aufsteigend sortierten Randhöhen − 0.3 m. 0 wäre der tiefste
## Randpunkt (See läuft nie über, fast nie ein Platz dafür); 0.3 lässt die tiefsten Randpunkte unter
## dem Spiegel — dort entsteht ein niedriger Damm (Uferwall), siehe lake_max_dam.
@export var lake_level_quantile: float = 0.3
## Höchster erlaubter künstlicher Damm (m) = Spiegel − tiefster Randpunkt. Größere → kein See.
@export var lake_max_dam: float = 6.0

## Um den Spawn-Bereich (spawn_blend_radius) gibt es keine Flüsse; über diese Strecke blenden sie ein.
@export var river_spawn_margin: float = 50.0

# ── Spawn-Plateau ───────────────────────────────
## Um den Ursprung (Dorf, NPCs, Ackerbeete, Spawn) wird das Gelände eingeebnet, damit
## der Startbereich immer begehbar und trocken ist — unabhängig vom Seed.
@export var spawn_height: float = 2.5
@export var spawn_flat_radius: float = 40.0
@export var spawn_blend_radius: float = 90.0

# ── Klima (Biome) ───────────────────────────────
@export var temperature_frequency: float = 0.0035
@export var humidity_frequency: float = 0.0046

# ── Abgeleitet ──────────────────────────────────

## Vertex-Anzahl je Chunk-Kante minus 1. Bewusst AUS dem Edit-Gitter abgeleitet
## (TerrainEditLayer.SPACING): Chunk-Vertices liegen dadurch immer exakt auf den Punkten
## der Delta-Schicht (Umgraben) — die Kopplung kann nicht mehr auseinanderlaufen.
func get_resolution() -> int:
	return maxi(1, roundi(chunk_size / TerrainEditLayer.SPACING))

func get_vertex_spacing() -> float:
	return chunk_size / float(get_resolution())
