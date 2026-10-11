class_name ProceduralTextureFactory
extends RefCounted

## ProceduralTextureFactory — "Natur besteht auch nur aus Mathematik": kleine,
## nahtlos kachelbare Texturen, komplett aus Value-Noise/fbm berechnet statt
## aus Bilddateien geladen. Ergänzt MeshCache (das schon alle Meshes einmalig
## prozedural baut) um dieselbe Idee für Oberflächen-Detail.
##
## Kategorien: grass, stone, wood, bark, moss, sand, gravel, dirt, ore_iron, ore_copper,
## ice, sulfur, wax, glass, charcoal (tileable Grain-Texturen für
## StandardMaterial3D.albedo_texture, siehe MeshCache.get_textured_material())
## sowie leaf_card, raindrop_streak, snowflake (Sprite-Texturen mit Alpha für
## Partikel/Karten-Meshes, siehe WeatherVfx).
##
## Determinismus: jede Kategorie hat einen fest verdrahteten internen Seed —
## bei jedem Start entsteht Pixel für Pixel exakt dieselbe Textur (wichtig,
## weil nichts davon über das Netzwerk synchronisiert wird — jeder Peer
## rechnet sie unabhängig, muss aber optisch identisch ankommen, gleiches
## Prinzip wie TerrainField/WeatherService).
##
## Einmal pro Kategorie berechnet, danach wie jede andere Textur GPU-seitig
## geteilt (statischer Cache — Analog zu MeshCache.materials).

const DEFAULT_SIZE := 96

## Blattform-Silhouetten für leaf_card() (Wunsch "Bäume ... Blätter Form macht viel Charakter
## aus"): ELLIPSE ist die bisherige Form (unverändert, Default — bestehende Aufrufer ohne
## shape-Argument, z.B. AmbientForestVfx, bleiben unangetastet). LOBED = Eiche (gerundete
## Wellenkante, fiederig gelappt), PALMATE = Ahorn (5-strahliger Stern, handförmig gelappt),
## NEEDLE = Nadelbaum (sehr schmale Sliver statt Fläche). Siehe _build_leaf()-Kommentar für die
## botanischen Begriffe dahinter.
enum LeafShape { ELLIPSE, LOBED, PALMATE, NEEDLE }

static var _cache: Dictionary = {}  # { key: ImageTexture }

# ─────────────────────────────────────────────
# Öffentliche Fabrikmethoden
# ─────────────────────────────────────────────

static func grass(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("grass_%d" % size, func() -> Image: return _build_fibrous(size, 91))

static func stone(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("stone_%d" % size, func() -> Image: return _build_mottled(size, 47, 6, 0.45))

static func wood(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("wood_%d" % size, func() -> Image: return _build_grain_streaks(size, 12))

static func sand(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("sand_%d" % size, func() -> Image: return _build_mottled(size, 33, 14, 0.16))

static func gravel(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("gravel_%d" % size, func() -> Image: return _build_mottled(size, 58, 9, 0.55))

static func dirt(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("dirt_%d" % size, func() -> Image: return _build_mottled(size, 71, 5, 0.32))

## Raue Rinde — wie wood(), aber mit zusätzlichen queren Rissen zwischen den
## Maserungslinien und höherem Kontrast. Eigene Kategorie statt wood()-Parameter,
## weil beide gleichzeitig gebraucht werden (glattes Bauholz vs. lebende Baumrinde).
static func bark(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("bark_%d" % size, func() -> Image: return _build_bark(size, 23))

## Fleckiger Moosbewuchs — für liegende Stämme/Steine im Wald. Größere,
## weicher geformte Flecken statt feinem Korn (niedrigere Frequenz, höherer
## Kontrast als _build_mottled) — modelliert Moospolster, nicht Gestein.
static func moss(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("moss_%d" % size, func() -> Image: return _build_moss(size, 65))

## Eisenerz — grauer Stein mit rostroten Adern. Siehe _build_ore()-Kommentar
## für die Adern-Technik; die Farbe ist fest in die Textur gebacken, deshalb
## am Aufrufort (MeshCache) mit einem eher neutralen Ton tönen statt erneut
## mit einer kräftigen Farbe, sonst verschluckt das den Adernton.
static func ore_iron(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("ore_iron_%d" % size, func() -> Image: return _build_ore(size, 140, Color(0.55, 0.18, 0.08)))

## Kupfererz — dieselbe Steinbasis wie ore_iron(), grün-türkise Oxidations-
## adern statt rostroter.
static func ore_copper(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("ore_copper_%d" % size, func() -> Image: return _build_ore(size, 141, Color(0.15, 0.55, 0.35)))

## Facettiertes Kristalleis — siehe _build_ice()-Kommentar.
static func ice(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("ice_%d" % size, func() -> Image: return _build_ice(size, 205))

## Schwefelkruste — gelbe Fläche mit dunklen Trockenriss-Linien.
static func sulfur(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("sulfur_%d" % size, func() -> Image: return _build_sulfur(size, 88))

## Bienenwachs/Wabenpapier — für den wilden Bienenstock.
static func wax(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("wax_%d" % size, func() -> Image: return _build_wax(size, 302))

## Glasige Schmelzstreifen — für Fulgurit (Blitzglas).
static func glass(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("glass_%d" % size, func() -> Image: return _build_glass(size, 410))

## Verkohltes Holz mit vereinzelten Glutpunkten — für den Kohlenmeiler.
static func charcoal(size: int = DEFAULT_SIZE) -> ImageTexture:
	return _cached("charcoal_%d" % size, func() -> Image: return _build_charcoal(size, 512))

## Blattkarte mit Alpha-Ausschnitt — für Farn/Unterholz-Karten-Meshes, fallende-Blätter-Partikel
## UND (neu) Baumkronen-Karten-Cluster (siehe MeshCache._assemble_tree()). hue_seed variiert
## Grünton leicht (mehrere Blatt-Varianten ohne neuen Code), `shape` wählt die Silhouette
## (siehe LeafShape-Kommentar) — Default ELLIPSE ist bit-identisch zur bisherigen Form, bestehende
## Aufrufer ohne shape-Argument sind unverändert.
static func leaf_card(size: int = 64, hue_seed: int = 0, shape: int = LeafShape.ELLIPSE) -> ImageTexture:
	return _cached(
		"leaf_card_%d_%d_%d" % [size, hue_seed, shape],
		func() -> Image: return _build_leaf(size, hue_seed, shape))

## Laub-BÜSCHEL-Karte (2026-10-07, "jeder Baum hat gefühlt nur 7 Blätter"): EINE Karte zeigt viele
## kleine Blätter bzw. einen Nadelzweig, nicht ein einzelnes Riesenblatt wie leaf_card(). Die
## Baumkronen (MeshCache._assemble_tree) setzen hunderte solcher Karten per MultiMesh.
## `leaf_count` Blätter (bzw. Nadelpaare), Form wie LeafShape; `aspect` = Blattbreite relativ zur
## Länge (Weide ≈ 0.2 lanzettlich, Eiche 0.55). Deterministisch aus hue_seed, gecacht.
static func foliage_card(size: int = 128, hue_seed: int = 0, shape: int = LeafShape.ELLIPSE, leaf_count: int = 14, aspect: float = 0.55) -> ImageTexture:
	return _cached(
		"foliage_%d_%d_%d_%d_%s" % [size, hue_seed, shape, leaf_count, str(aspect)],
		func() -> Image: return _build_foliage(size, hue_seed, shape, leaf_count, aspect))

## Schmale, oben transparente / unten zulaufende Strähne — Regen-Partikel-Billboard.
static func raindrop_streak(width: int = 8, height: int = 64) -> ImageTexture:
	return _cached("raindrop_%dx%d" % [width, height], func() -> Image: return _build_raindrop(width, height))

## Weicher, runder Punkt mit Falloff — Schnee-Partikel-Billboard.
static func snowflake(size: int = 16) -> ImageTexture:
	return _cached("snowflake_%d" % size, func() -> Image: return _build_soft_dot(size))

# ─────────────────────────────────────────────
# Noise-Bausteine (Value-Noise + fbm, nahtlos kachelbar)
# ─────────────────────────────────────────────

## Ganzzahliger Hash → deterministisches Pseudo-Zufall in [0, 1). Kein
## FastNoiseLite (das ist nicht exakt bit-identisch über Godot-Versionen
## garantiert) — reine Integer-Arithmetik, damit die Textur wirklich für
## immer gleich bleibt (analog TerrainSeed.derive(), FNV statt String.hash()).
static func _hash2(x: int, y: int, seed: int) -> float:
	var n: int = x * 374761393 + y * 668265263 + seed * 2654435761
	n = (n << 13) ^ n
	n = n * (n * n * 15731 + 789221) + 1376312589
	return float(n & 0x7fffffff) / float(0x7fffffff)

## Value-Noise, dessen Gitter bei `period` umbricht (posmod der Gitterpunkte)
## → an der rechten/unteren Kante schließt die Textur nahtlos an die linke/
## obere an (wichtig: diese Texturen werden per uv1_scale gekachelt).
static func _value_noise_tiled(x: float, y: float, seed: int, period: int) -> float:
	var xi: int = int(floor(x))
	var yi: int = int(floor(y))
	var xf: float = x - xi
	var yf: float = y - yi
	var x0: int = posmod(xi, period)
	var x1: int = posmod(xi + 1, period)
	var y0: int = posmod(yi, period)
	var y1: int = posmod(yi + 1, period)
	var v00: float = _hash2(x0, y0, seed)
	var v10: float = _hash2(x1, y0, seed)
	var v01: float = _hash2(x0, y1, seed)
	var v11: float = _hash2(x1, y1, seed)
	var u: float = xf * xf * (3.0 - 2.0 * xf)
	var v: float = yf * yf * (3.0 - 2.0 * yf)
	return lerp(lerp(v00, v10, u), lerp(v01, v11, u), v)

## Mehrere Oktaven übereinander (jede Oktave verdoppelt Frequenz + eigene
## Periode, damit jede Oktave für sich sauber kachelt).
static func _fbm_tiled(x: float, y: float, seed: int, base_period: int, octaves: int = 4) -> float:
	var total: float = 0.0
	var amp: float = 0.5
	var freq: float = 1.0
	var norm: float = 0.0
	for i in range(octaves):
		var period: int = base_period * int(freq)
		total += _value_noise_tiled(x * freq, y * freq, seed + i * 97, period) * amp
		norm += amp
		amp *= 0.5
		freq *= 2.0
	return total / norm

# ─────────────────────────────────────────────
# Oberflächen-Texturen (RGB, für albedo_texture — Farbe kommt vom Material,
# hier nur Helligkeits-/Grain-Variation um 1.0 herum)
# ─────────────────────────────────────────────

## Fleckig/körnig — trägt Stein, Kies, Erde, Sand (Unterschied nur in
## Skalierung/Kontrast der Aufrufer): grobe fbm-Basis + feine Sprenkel obendrauf.
static func _build_mottled(size: int, seed: int, base_period: int, contrast: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in range(size):
		for x in range(size):
			var nx: float = float(x) / size * base_period
			var ny: float = float(y) / size * base_period
			var base: float = _fbm_tiled(nx, ny, seed, base_period, 4)
			var speck: float = _value_noise_tiled(nx * 6.0, ny * 6.0, seed + 500, base_period * 6)
			var v: float = 1.0 + (base - 0.5) * contrast + (speck - 0.5) * contrast * 0.35
			v = clampf(v, 0.35, 1.25)
			img.set_pixel(x, y, Color(v, v, v))
	return img

## Feine, in eine Richtung gestreckte Streifen — trägt Gras (Halme).
static func _build_fibrous(size: int, seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var period: int = 10
	for y in range(size):
		for x in range(size):
			# X gestaucht, Y gestreckt → längliche Halm-Fasern statt runder Flecken
			var nx: float = float(x) / size * period * 2.2
			var ny: float = float(y) / size * period * 0.6
			var base: float = _fbm_tiled(nx, ny, seed, period, 3)
			var blade: float = _value_noise_tiled(nx * 3.0, ny * 0.8, seed + 300, period * 3)
			var v: float = 0.75 + (base - 0.5) * 0.7 + (blade - 0.5) * 0.3
			v = clampf(v, 0.4, 1.3)
			img.set_pixel(x, y, Color(v, v * 1.02, v * 0.95))
	return img

## Vertikale Maserung mit leichtem Sinus-Verzug — trägt Holz/Rinde.
static func _build_grain_streaks(size: int, seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var period: int = 8
	for y in range(size):
		for x in range(size):
			var nx: float = float(x) / size * period
			var ny: float = float(y) / size * period
			var warp: float = (_fbm_tiled(nx, ny, seed, period, 3) - 0.5) * 3.0
			var grain: float = sin((nx + warp) * TAU * 1.5) * 0.5 + 0.5
			var fine: float = _value_noise_tiled(nx * 5.0, ny * 5.0, seed + 200, period * 5)
			var v: float = 0.65 + grain * 0.5 + (fine - 0.5) * 0.2
			v = clampf(v, 0.35, 1.25)
			img.set_pixel(x, y, Color(v, v * 0.92, v * 0.80))
	return img

## Vertikale Maserung wie _build_grain_streaks(), plus eine zweite, quer
## verlaufende Riss-Maske (dünne, unregelmäßige horizontale Linien) und mehr
## Gesamtkontrast — wirkt zerklüftet/borkig statt glatt gehobelt.
static func _build_bark(size: int, seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var period: int = 7
	for y in range(size):
		for x in range(size):
			var nx: float = float(x) / size * period
			var ny: float = float(y) / size * period
			var warp: float = (_fbm_tiled(nx, ny, seed, period, 3) - 0.5) * 4.0
			var grain: float = sin((nx + warp) * TAU * 1.8) * 0.5 + 0.5
			# Queres Rissmuster: eigene, niederfrequente Noise-Achse entlang Y,
			# nur dort abgedunkelt wo sie über einer Schwelle liegt -> vereinzelte
			# Furchen statt gleichmäßiger Streifen.
			var crack_n: float = _value_noise_tiled(ny * 2.5, nx * 0.4, seed + 700, period * 3)
			var crack: float = 1.0 if crack_n > 0.78 else 0.0
			var fine: float = _value_noise_tiled(nx * 6.0, ny * 6.0, seed + 200, period * 6)
			var v: float = 0.55 + grain * 0.6 + (fine - 0.5) * 0.25 - crack * 0.35
			v = clampf(v, 0.25, 1.3)
			img.set_pixel(x, y, Color(v, v * 0.88, v * 0.72))
	return img

## Weiche, klumpige Flecken (niedrige Grundfrequenz, scharf am oberen Ende
## geclampt) simulieren Moospolster; feine zweite Oktave bricht die Kanten
## der Flecken auf, damit sie nicht wie gestempelt wirken.
static func _build_moss(size: int, seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var period: int = 5
	for y in range(size):
		for x in range(size):
			var nx: float = float(x) / size * period
			var ny: float = float(y) / size * period
			var clump: float = _fbm_tiled(nx, ny, seed, period, 3)
			var edge_break: float = _value_noise_tiled(nx * 4.0, ny * 4.0, seed + 400, period * 4)
			var patch: float = clump + (edge_break - 0.5) * 0.25
			# Scharfe Schwelle statt linearer Mischung -> klar abgesetzte Polster
			# statt einem gleichmäßigen Verlauf.
			var v: float = 1.15 if patch > 0.55 else 0.55
			v = lerp(v, 0.85, 0.15)  # etwas Grundhelligkeit dazwischen, kein hartes Schwarz/Weiß
			v = clampf(v, 0.4, 1.2)
			img.set_pixel(x, y, Color(v, v, v))
	return img

## Graue Steinbasis (wie _build_mottled) plus dünne, geäderte Farb-Adern —
## der klassische "Marmor-Vene"-Trick: statt die Ader direkt zu zeichnen, wird
## dort eine Farbe eingeblendet, wo ein ZWEITES fbm-Feld nahe seiner Mittellinie
## (0.5) liegt. Ergebnis sind dünne, verzweigt wirkende Linien statt gerader
## Striche — genau das Adernmuster von Erzgestein. `vein_color` wird direkt in
## die Textur gebacken (nicht nur Helligkeit wie bei den anderen Kategorien),
## weil Eisen (rostrot) und Kupfer (grünlich) zwei unterschiedliche Farbtöne auf
## demselben grauen Stein brauchen — ein einzelner albedo_color-Multiplikator
## könnte das nicht (der färbt Stein UND Ader gleich um).
static func _build_ore(size: int, seed: int, vein_color: Color) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var period: int = 6
	for y in range(size):
		for x in range(size):
			var nx: float = float(x) / size * period
			var ny: float = float(y) / size * period
			var base: float = _fbm_tiled(nx, ny, seed, period, 4)
			var grey: float = clampf(0.55 + (base - 0.5) * 0.5, 0.3, 0.85)
			var vein_field: float = _fbm_tiled(nx * 1.6, ny * 1.6, seed + 900, period * 2, 3)
			var vein_mask: float = 1.0 - smoothstep(0.0, 0.06, abs(vein_field - 0.5))
			var stone_col := Color(grey, grey, grey)
			img.set_pixel(x, y, stone_col.lerp(vein_color, clampf(vein_mask, 0.0, 1.0)))
	return img

## Facettierte Eisstruktur: eine um 0.6 rad gedrehte Koordinatenachse wird in
## diskrete Stufen gerastert (floor() statt eines weichen Verlaufs) — das
## erzeugt harte, kantige Bruchflächen statt runder Flecken, wie bei echtem
## Kristalleis. Leicht bläuliche Grundfärbung direkt in den Kanälen gebacken.
static func _build_ice(size: int, seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var period: int = 6
	for y in range(size):
		for x in range(size):
			var nx: float = float(x) / size * period
			var ny: float = float(y) / size * period
			var rot_x: float = nx * cos(0.6) - ny * sin(0.6)
			var facet_raw: float = rot_x * 3.0 + _fbm_tiled(nx, ny, seed, period, 2) * 0.3
			var facet: float = facet_raw - floor(facet_raw)  # fract() gibt es in GDScript nicht
			var shard: float = floor(facet * 5.0) / 5.0
			var fine: float = _value_noise_tiled(nx * 8.0, ny * 8.0, seed + 300, period * 8)
			var v: float = 0.85 + shard * 0.25 + (fine - 0.5) * 0.1
			v = clampf(v, 0.7, 1.3)
			img.set_pixel(x, y, Color(v * 0.92, v * 0.97, v * 1.05))
	return img

## Gelbe Kruste mit dunklen Trockenriss-Linien — dieselbe Konturlinien-Ader-
## Technik wie _build_ore(), nur breiter/niederfrequenter und die "Ader" ist
## hier eine Abdunkelung statt einer eingefärbten Linie (Risse in Gestein sind
## dunkler, keine andersfarbige Substanz).
static func _build_sulfur(size: int, seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var period: int = 5
	for y in range(size):
		for x in range(size):
			var nx: float = float(x) / size * period
			var ny: float = float(y) / size * period
			var base: float = _fbm_tiled(nx, ny, seed, period, 4)
			var yellow: float = 0.85 + (base - 0.5) * 0.3
			var crack_field: float = _fbm_tiled(nx * 1.3, ny * 1.3, seed + 600, period * 2, 3)
			var crack: float = 1.0 - smoothstep(0.0, 0.045, abs(crack_field - 0.5))
			var v: float = clampf(yellow - crack * 0.5, 0.2, 1.15)
			img.set_pixel(x, y, Color(v, v * 0.92, v * 0.35))
	return img

## Wachs-/Wabenpapier-Optik fürs wilde Bienennest: wie _build_mottled(), aber
## mit fest gebackenem Amberton statt neutralem Grau — reines Bienenwachs ist
## kein Grauton, den man sinnvoll über albedo_color hintönen könnte.
static func _build_wax(size: int, seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var period: int = 6
	for y in range(size):
		for x in range(size):
			var nx: float = float(x) / size * period
			var ny: float = float(y) / size * period
			var base: float = _fbm_tiled(nx, ny, seed, period, 4)
			var speck: float = _value_noise_tiled(nx * 5.0, ny * 5.0, seed + 250, period * 5)
			var v: float = clampf(0.85 + (base - 0.5) * 0.35 + (speck - 0.5) * 0.15, 0.5, 1.25)
			img.set_pixel(x, y, Color(v, v * 0.75, v * 0.25))
	return img

## Glatte, grünlich-gläserne Schmelzstreifen fürs Blitzglas (Fulgurit) — wie
## _build_grain_streaks(), aber mit größerer Wellenlänge (weniger, breitere
## Streifen wirken "geschmolzen" statt "gewachsen") und niedrigerem Kontrast
## (Glas ist glatt, kein raues Holzkorn).
static func _build_glass(size: int, seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var period: int = 5
	for y in range(size):
		for x in range(size):
			var nx: float = float(x) / size * period
			var ny: float = float(y) / size * period
			var warp: float = (_fbm_tiled(nx, ny, seed, period, 2) - 0.5) * 2.0
			var streak: float = sin((nx + warp) * TAU) * 0.5 + 0.5
			var v: float = clampf(0.8 + streak * 0.3, 0.6, 1.15)
			img.set_pixel(x, y, Color(v * 0.75, v * 1.05, v * 0.85))
	return img

## Nahezu schwarze, verkohlte Maserung (wie _build_bark(), aber viel dunkler)
## plus sehr seltene, sehr helle Einzelpixel — glimmende Glutpunkte im
## Kohlenmeiler. Fein genug (Schwellwert 0.965 auf 10-fach-Frequenz-Noise),
## dass sie wie vereinzelte Funken wirken statt wie ein Muster.
static func _build_charcoal(size: int, seed: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var period: int = 7
	for y in range(size):
		for x in range(size):
			var nx: float = float(x) / size * period
			var ny: float = float(y) / size * period
			var warp: float = (_fbm_tiled(nx, ny, seed, period, 3) - 0.5) * 4.0
			var streak: float = sin((nx + warp) * TAU * 1.6) * 0.5 + 0.5
			var base_v: float = 0.16 + streak * 0.12
			var ember_field: float = _value_noise_tiled(nx * 10.0, ny * 10.0, seed + 888, period * 10)
			var ember: float = 1.0 if ember_field > 0.965 else 0.0
			img.set_pixel(x, y, Color(base_v + ember * 0.9, base_v * 0.5 + ember * 0.35, base_v * 0.3))
	return img

# ─────────────────────────────────────────────
# Sprite-Texturen (RGBA, Alpha-Cutout — für Karten-Meshes/Partikel)
# ─────────────────────────────────────────────

## Blattform-Silhouette + Adern/Grain — gemeinsame Basis für alle vier LeafShape-Varianten.
## Botanischer Hintergrund (Recherche "wie Bäume wirklich aussehen"): ELLIPSE ist eine schlichte,
## glattrandige Fläche (entire margin); LOBED bildet einen fiederig gelappten Rand nach (pinnately
## lobed, wie Eiche — gerundete Buchten/Ausstülpungen um den ganzen Umriss statt einer glatten
## Kante); PALMATE bildet handförmig gelappte Blätter nach (palmately lobed, wie Ahorn — mehrere
## Spitzen strahlen aus der Mitte statt aus einer Mittelrippe); NEEDLE ist keine Fläche mehr,
## sondern ein sehr schmaler Sliver (Nadelbaum). Die eigentliche Form kommt aus radius_limit(theta)
## — je nach Shape ein anisotroper Ellipsen-Schwellwert (ELLIPSE/NEEDLE) oder ein winkelabhängiger
## Wellen-/Stern-Radius (LOBED/PALMATE) — der Rest (Vene/Grain/Farbverlauf) bleibt für alle Shapes
## identisch, damit sich nur die Silhouette ändert, nicht der "Materialeindruck".
static func _build_leaf(size: int, hue_seed: int, shape: int = LeafShape.ELLIPSE) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng_offset: float = float(hue_seed) * 0.37
	# 0.13 statt 0.08 (Wunsch "Blätter sehen nicht gut aus"): mit jetzt deutlich mehr Karten pro
	# Krone (siehe _leaf_cloud_offsets()) fiel die enge Farbspanne als einheitlicher grüner
	# Fleck auf statt als natürlich geflecktes Blätterdach.
	var green_shift: float = sin(rng_offset) * 0.13
	for y in range(size):
		for x in range(size):
			var u: float = (float(x) / size) * 2.0 - 1.0   # -1..1, 0 = Mitte
			var v: float = (float(y) / size) * 2.0 - 1.0
			var theta: float = atan2(v, u)
			var r: float = sqrt(u * u + v * v)
			var inside: bool = false
			var edge_fade: float = 0.0
			match shape:
				LeafShape.PALMATE:
					# Handförmig gelappt: 5-strahliger Stern-Radius statt Mittelrippen-Ellipse —
					# cos(5*theta) schließt nahtlos (integer Vielfaches), 5 Spitzen wie beim Ahorn.
					# 0.30/0.32 statt 0.34/0.28 (Wunsch "Blätter sehen nicht gut aus"): tiefere
					# Buchten zwischen den Zacken — bei Karten-Größe im Spiel war der alte,
					# flachere Stern kaum von einer Ellipse zu unterscheiden.
					var star: float = 0.30 + 0.32 * cos(5.0 * theta)
					inside = r <= star
					edge_fade = clampf((star - r) * 10.0, 0.0, 1.0)
				LeafShape.NEEDLE:
					# Nadel: dieselbe Verjüngung-zur-Spitze wie ELLIPSE, aber sehr schmal (kaum
					# Fläche, fast ein Strich) statt eines breiten Blatts.
					var taper_n: float = 1.0 - clampf(v, -1.0, 1.0) * 0.15
					var dist_n: float = (u * u) / (0.16 * taper_n * 0.16 * taper_n) + v * v
					inside = dist_n <= 1.0
					edge_fade = clampf((1.0 - dist_n) * 6.0, 0.0, 1.0)
				_:
					# ELLIPSE (Default, glattrandig) und LOBED (gewellter Rand obendrauf) teilen
					# sich dieselbe zur-Spitze-verjüngte Grundellipse.
					var taper: float = 1.0 - clampf(v, -1.0, 1.0) * 0.4
					var lobe_mult: float = 1.0
					if shape == LeafShape.LOBED:
						# 0.32 statt 0.22 + 6 statt 7 Wellen (Wunsch "Blätter sehen nicht gut
						# aus"): kräftigere, etwas gröbere Buchten lesen sich auf Kartengröße
						# klarer als "gelappt" statt als leicht zackige Ellipse.
						lobe_mult = 1.0 + 0.32 * cos(6.0 * theta)
					var ax: float = 0.55 * taper * lobe_mult
					var dist: float = (u * u) / (ax * ax) + v * v
					inside = dist <= 1.0
					edge_fade = clampf((1.0 - dist) * 6.0, 0.0, 1.0)
			if not inside:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var vein: float = absf(u)
			var vein_shade: float = 1.0 - clampf(1.0 - vein * 4.0, 0.0, 1.0) * 0.25
			var grain: float = _value_noise_tiled(float(x) * 0.3, float(y) * 0.3, hue_seed + 900, size)
			# BUGFIX (Wunsch "Blätter sehen hässlich aus" — Screenshots zeigten fast schwarze
			# Karten statt Blattfarbe): die Textur hatte bisher SELBST schon eine dunkle
			# Grünfärbung (albedo um ~0.1-0.4) UND wurde im Shader zusätzlich mit der
			# Art-Farbe (albedo_color, z.B. Nadelgrün 0.08/0.28/0.12 — ebenfalls dunkel)
			# MULTIPLIZIERT — zwei dunkle Farben multipliziert ergeben eine noch viel
			# dunklere, fast schwarze Karte. Jetzt moduliert die Textur nur noch die
			# Helligkeit um ~1.0 (Ader-Schatten, Korn, leichte Streuung über green_shift)
			# statt eine eigene Farbe beizusteuern — die tatsächliche Farbe kommt allein aus
			# albedo_color je Aufrufer/Karte (siehe MeshCache.get_foliage_material()).
			var lum: float = clampf((0.88 + green_shift * 0.6 + (grain - 0.5) * 0.3) * vein_shade, 0.35, 1.15)
			img.set_pixel(x, y, Color(lum, lum, lum, edge_fade))
	return img

## Setzt `leaf_count` Blattstempel (je nur deren Bounding-Box, nicht die ganze Karte) übereinander.
## Helligkeit variiert je Blatt — der Farbton kommt wie bei _build_leaf() allein aus albedo_color.
static func _build_foliage(size: int, hue_seed: int, shape: int, leaf_count: int, aspect: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)   # Anfangsinhalt: transparent
	if shape == LeafShape.NEEDLE:
		_stamp_needle_spray(img, size, hue_seed, leaf_count)
		return img
	for i in range(leaf_count):
		var h1: float = _hash2(i, 1, hue_seed)
		var h2: float = _hash2(i, 2, hue_seed)
		var h3: float = _hash2(i, 3, hue_seed)
		var h4: float = _hash2(i, 4, hue_seed)
		var h5: float = _hash2(i, 5, hue_seed)
		var ang: float = h2 * TAU
		var dist: float = sqrt(h1) * 0.58
		var half_len: float = 0.24 + 0.12 * h4          # in -1..1-Bildkoordinaten
		_stamp_leaf(img, size, cos(ang) * dist, sin(ang) * dist, h3 * TAU, half_len, shape, aspect, 0.62 + 0.5 * h5)
	return img

static func _stamp_leaf(img: Image, size: int, cx: float, cy: float, rot: float, half_len: float, shape: int, aspect: float, lum: float) -> void:
	var l_px: float = half_len * 0.5 * float(size)
	var c_px := Vector2((cx * 0.5 + 0.5) * float(size), (cy * 0.5 + 0.5) * float(size))
	var reach: int = int(ceil(l_px * 1.15))
	var cs: float = cos(rot)
	var sn: float = sin(rot)
	for py in range(int(c_px.y) - reach, int(c_px.y) + reach + 1):
		for px in range(int(c_px.x) - reach, int(c_px.x) + reach + 1):
			if px < 0 or py < 0 or px >= size or py >= size:
				continue
			var dx: float = float(px) - c_px.x
			var dy: float = float(py) - c_px.y
			var lu: float = (dx * cs + dy * sn) / l_px      # quer zum Blatt
			var lv: float = (-dx * sn + dy * cs) / l_px     # entlang des Blatts, -1..1
			var edge: float = 0.0
			if shape == LeafShape.PALMATE:
				var r: float = sqrt(lu * lu + lv * lv) * 0.62
				var star: float = 0.30 + 0.32 * cos(5.0 * atan2(lv, lu))
				edge = clampf((star - r) * 10.0, 0.0, 1.0)
			else:
				var taper: float = 1.0 - clampf(lv, -1.0, 1.0) * 0.4
				var lobe: float = 1.0
				if shape == LeafShape.LOBED:
					lobe = 1.0 + 0.32 * cos(6.0 * atan2(lv, lu))
				var ax: float = aspect * taper * lobe
				var d: float = (lu * lu) / (ax * ax) + lv * lv
				edge = clampf((1.0 - d) * 6.0, 0.0, 1.0)
			if edge <= 0.0:
				continue
			var vein: float = 0.85 if absf(lu) < 0.06 else 1.0
			var l: float = clampf(lum * vein, 0.3, 1.15)
			img.set_pixel(px, py, Color(l, l, l, edge))

## Nadelzweig: Mittelachse + beidseits schräg abgehende Nadeln (dünne Linien).
static func _stamp_needle_spray(img: Image, size: int, hue_seed: int, count: int) -> void:
	var sz: float = float(size)
	var steps: int = maxi(count, 6)
	_stamp_line(img, size, Vector2(0.5 * sz, 0.95 * sz), Vector2(0.5 * sz, 0.05 * sz), 2, 0.55)
	for i in range(steps):
		var t: float = (float(i) + 0.5) / float(steps)
		var y: float = sz * (0.92 - 0.84 * t)
		var len_px: float = sz * (0.36 - 0.18 * t) * (0.85 + 0.3 * _hash2(i, 7, hue_seed))
		var lum: float = 0.6 + 0.4 * _hash2(i, 8, hue_seed)
		for side in [-1.0, 1.0]:
			var tip := Vector2(0.5 * sz + side * len_px * 0.85, y - len_px * 0.55)
			_stamp_line(img, size, Vector2(0.5 * sz, y), tip, 2, lum)

static func _stamp_line(img: Image, size: int, a: Vector2, b: Vector2, width_px: int, lum: float) -> void:
	var steps: int = int(a.distance_to(b)) + 1
	for i in range(steps + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		for oy in range(-width_px / 2, width_px / 2 + 1):
			for ox in range(-width_px / 2, width_px / 2 + 1):
				var px: int = int(p.x) + ox
				var py: int = int(p.y) + oy
				if px >= 0 and py >= 0 and px < size and py < size:
					img.set_pixel(px, py, Color(lum, lum, lum, 1.0))

static func _build_raindrop(width: int, height: int) -> Image:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		var t: float = float(y) / float(height - 1)
		# oben schwach, Mitte kräftig, unten spitz auslaufend (Tropfenschweif)
		var a: float = sin(t * PI) * (0.9 - t * 0.3)
		for x in range(width):
			var cx: float = (float(x) / float(width - 1)) * 2.0 - 1.0
			var falloff: float = 1.0 - clampf(absf(cx), 0.0, 1.0)
			img.set_pixel(x, y, Color(0.75, 0.85, 0.95, clampf(a * falloff, 0.0, 1.0)))
	return img

static func _build_soft_dot(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center: float = size * 0.5
	for y in range(size):
		for x in range(size):
			var d: float = Vector2(x - center, y - center).length() / center
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a  # weicherer Falloff-Rand
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return img

# ─────────────────────────────────────────────
# Cache
# ─────────────────────────────────────────────

static func _cached(key: String, builder: Callable) -> ImageTexture:
	if not _cache.has(key):
		var img: Image = builder.call()
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]
