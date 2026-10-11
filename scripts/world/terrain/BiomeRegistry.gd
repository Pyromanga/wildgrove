# res://scripts/world/terrain/BiomeRegistry.gd
class_name BiomeRegistry

## BiomeRegistry — Statische Sammlung aller Biom-Definitionen.
##
## Kein externes .tres nötig: Biome werden hier code-seitig definiert.
## Vorteil: kein DirAccess/DataManifest-Overhead, sofort refaktorierbar.
##
## Noise-Zuweisung via get_biome_for(temp, humid):
##   temp  –1..1  (kalt → warm)
##   humid –1..1  (trocken → feucht)

const LOG_CAT := "BiomeRegistry"

## Alle registrierten Biome, keyed by biome_id.
static var _biomes: Dictionary = {}
static var _initialized: bool = false

static func get_biome(biome_id: String) -> BiomeDefinition:
	_ensure_init()
	return _biomes.get(biome_id)

## Hauptfunktion: wählt Biom anhand Temperatur + Feuchtigkeit.
static func get_biome_for(temp: float, humid: float) -> BiomeDefinition:
	_ensure_init()
	var id := _resolve_id(temp, humid)
	return _biomes.get(id, _biomes.get("meadow"))

static func get_biome_id_for(temp: float, humid: float) -> String:
	return _resolve_id(temp, humid)

## Temperatur-Schwellen für Wüste/Schnee.
## Vorher 0.6 / -0.5 — der 2-Oktaven-Klima-Noise (TerrainField.get_climate_at())
## erreicht diese Extremwerte nur auf wenigen Prozent der Fläche, Wüste und Eis
## waren dadurch praktisch nie in Sichtweite. Bei ±0.4 liegen beide grob im
## Bereich von je ~10–15 % der Weltfläche (Näherungs-Simulation, siehe Notiz).
## Höherer Betrag = seltener/kleiner, niedrigerer Betrag = häufiger/größer.
const DESERT_MIN_TEMP: float =  0.4
const WINTER_MAX_TEMP: float = -0.4

static func _resolve_id(temp: float, humid: float) -> String:
	if temp > DESERT_MIN_TEMP:            return "desert"
	if temp < WINTER_MAX_TEMP:            return "winter"
	if humid > 0.5 and temp > 0.0:       return "swamp"
	if humid > 0.3:                       return "dense_forest"
	if humid > 0.0:                       return "forest"
	# Round 78 — neue Nische für "mountain": bisher fiel jede trockene
	# (humid <= 0), nicht-heiße/nicht-eiskalte Zone (temp zwischen -0.5 und
	# 0.6) unterschiedslos auf "meadow". Kalt UND trocken (temp < -0.15)
	# wird jetzt zu "mountain" — schroffes, felsiges Hochland statt Wiese.
	# Warm-trocken (temp >= -0.15) bleibt weiterhin "meadow", unverändert.
	if temp < -0.15:                      return "mountain"
	# Round 79 — neue Nische für "dead_forest": innerhalb der bisherigen
	# meadow-Restzone (temp >= -0.15, humid <= 0) wird der besonders trockene
	# Ausschnitt (humid < -0.5) jetzt zu "toter Wald" statt Wiese — Bäume,
	# die an Wassermangel eingegangen sind, statt gar keiner Vegetation.
	# Warm-trocken-aber-nicht-extrem (humid zwischen -0.5 und 0) bleibt
	# weiterhin "meadow", unverändert.
	if humid < -0.5:                      return "dead_forest"
	return "meadow"

static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	_register_all()

static func _register_all() -> void:
	_register(_make_forest())
	_register(_make_dense_forest())
	_register(_make_meadow())
	_register(_make_desert())
	_register(_make_winter())
	_register(_make_swamp())
	_register(_make_mountain())
	_register(_make_dead_forest())

static func _register(b: BiomeDefinition) -> void:
	_biomes[b.biome_id] = b

# ─────────────────────────────────────────────
# Biom-Definitionen
# ─────────────────────────────────────────────

## 2026-10-08: Wälder "richtig dicht an dicht" — forest 40–60, dense_forest 64–96 Versuche/Chunk
## (≈ 21 bzw. 33 Bäume pro Chunk, Kronen überlappen). Deko-Büsche (bush_per_chunk) wurden zugunsten
## echter Sträucher (bush_*-Props, pflück-/rodbar) um etwa die Hälfte gesenkt.
## WICHTIG: die Summe der prop_chances eines Bioms bleibt <= 1.0 (Wahrscheinlichkeit pro Versuch,
## darüber wird normiert) — test_bushes_content.gd prüft das.
## ── DICHTE-TUNING (2026-10-05, Wunsch "Landschaft wirkt leer — viel zu wenig Bäume, keine
## Büsche, kein Gras") ───────────────────────────────────────────────────────────────
## Die Zahlen unter prop_chances sind seit ChunkEntitySpawner._roll_weighted_type() "echte"
## Wahrscheinlichkeiten PRO VERSUCH (Summe <= 1 → Rest = kein Prop; Summe > 1 → normiert),
## nicht mehr "wer zuerst deklariert ist, gewinnt". prop_attempts_min/max sind die Versuche
## pro 64-m-Chunk. Erwartete Bäume pro Chunk ≈ Ø-Versuche × Baum-Chance.
## Seltene Dinge (Bienenstock, Meiler, Friedhof, Goblin-Lager) wurden proportional zur
## höheren Versuchszahl gesenkt, damit ihre Häufigkeit PRO CHUNK ungefähr gleich bleibt.
## Wer die Performance dämpfen muss (viele Baum-Entities auf schwachen Handys): zuerst
## ChunkEntitySpawner.PROP_DENSITY_MULT senken, nicht jede Zahl hier einzeln anfassen.

static func _make_forest() -> BiomeDefinition:
	var b := BiomeDefinition.new()
	b.biome_id    = "forest"
	b.display_name = "Wald"
	b.terrain_color_grass = Color(0.13, 0.42, 0.12)
	b.terrain_color_dirt  = Color(0.35, 0.22, 0.10)
	b.terrain_color_rock  = Color(0.40, 0.40, 0.38)
	b.prop_attempts_min = 40
	b.prop_attempts_max = 60
	b.prop_chances = {
		"oak_tree":         0.30,
		"maple_tree":       0.12,  # Baumvielfalt: Ahorn (langsam nachwachsend, 60 XP) mischt sich unter die Eichen
		"fallen_tree":      0.03,
		"mushroom_cluster": 0.08,
		"fern":             0.12,
		"rock_boulder":     0.03,
		"wild_beehive":     0.010,  # Hain-Skill Imkerei (Bienenstock in Baumhöhle)
		"charcoal_kiln":    0.007,  # Hain-Skill Köhlerei (Kohlenmeiler im Wald)
		"ant_hill": 0.008,  # Nest-Skill Insektenkunde (Waldameisen: Nadelhügel im Nadel-/Mischwald)
		"mole_hill": 0.006,  # Maulwurfshügel (Graben)
		"wasp_nest": 0.005,  # Nest-Skill Insektenkunde (verlassenes Wespennest)
		"hornet_nest": 0.003,  # Nest-Skill Insektenkunde (Hornissen nisten in Baumhöhlen)
		"graveyard_gravestone": 0.005,  # Wunsch "Friedhöfe natürlich spawnen"
		"goblin_campfire":  0.007,  # Wunsch "Analog für Goblins/Lagerfeuer"
		# Kräuter/Blumen (herbalism/gardening) — Habitat-Logik: docs/herbalism-and-gardening.md
		"plant_nettle": 0.030,
		"plant_dandelion": 0.010,
		# Sträucher (Pflücken + Roden) — BushCatalog
		"bush_hazel": 0.060,
		"bush_blackberry": 0.050,
		"bush_elder": 0.030,
		"bush_dogrose": 0.020,
	}
	b.enemy_chances = {
		# Wunsch "zu wenig Gegner spawnen": vorher hatte NUR desert überhaupt
		# enemy_chances — jedes andere Biom spawnte nach der Erstbesiedlung
		# (WorldSpawner, einmalig) laufend GAR KEINE Gegner mehr nach.
		"goblin": 0.03,
	}
	b.structure_types = ["ruin", "cottage"]
	b.grass_per_chunk = 520
	b.bush_per_chunk  = 24
	b.grass_color_base = Color(0.10, 0.28, 0.07)
	b.grass_color_tip  = Color(0.30, 0.52, 0.15)
	b.bush_color       = Color(0.14, 0.36, 0.11)
	b.flower_per_chunk = 60
	b.flower_colors = [Color(0.95, 0.95, 0.92), Color(0.58, 0.30, 0.80), Color(0.95, 0.82, 0.15)]
	return b

static func _make_dense_forest() -> BiomeDefinition:
	var b := BiomeDefinition.new()
	b.biome_id    = "dense_forest"
	b.display_name = "Dichter Wald"
	b.terrain_color_grass = Color(0.08, 0.30, 0.08)
	b.terrain_color_dirt  = Color(0.28, 0.18, 0.08)
	b.terrain_color_rock  = Color(0.35, 0.35, 0.33)
	b.fog_density = 0.3
	b.prop_attempts_min = 64
	b.prop_attempts_max = 96
	b.prop_chances = {
		"oak_tree":        0.36,
		"maple_tree":      0.10,
		"pine_tree":       0.06,  # vereinzelte Nadelbäume zwischen dem Laubwald
		"fallen_tree":     0.05,
		"mushroom_cluster":0.06,
		"fern":            0.15,
		"charcoal_kiln":   0.008,  # Hain-Skill Köhlerei
		"ant_hill": 0.010,  # Nest-Skill Insektenkunde (Waldameisen: Nadelhügel im Nadel-/Mischwald)
		"wasp_nest": 0.004,  # Nest-Skill Insektenkunde (verlassenes Wespennest)
		"hornet_nest": 0.004,  # Nest-Skill Insektenkunde (Hornissen nisten in Baumhöhlen)
		"graveyard_gravestone": 0.006,
		"goblin_campfire": 0.010,  # dichter/verstecktes Terrain — beliebtes Goblin-Lagerversteck
		# Kräuter/Blumen (herbalism/gardening) — Habitat-Logik: docs/herbalism-and-gardening.md
		"plant_nettle": 0.040,
		# Sträucher (Pflücken + Roden) — BushCatalog
		"bush_hazel": 0.050,
		"bush_blackberry": 0.060,
		"bush_elder": 0.030,
	}
	b.enemy_chances = {
		"goblin": 0.04,  # dichter/dunkler als der normale Wald — etwas häufiger
	}
	b.structure_types = ["ruin", "cottage"]
	b.grass_per_chunk = 380
	b.bush_per_chunk  = 36
	b.grass_color_base = Color(0.06, 0.22, 0.06)
	b.grass_color_tip  = Color(0.20, 0.42, 0.12)
	b.bush_color       = Color(0.09, 0.30, 0.09)
	b.flower_per_chunk = 30
	b.flower_colors = [Color(0.95, 0.95, 0.92), Color(0.58, 0.30, 0.80)]
	return b

static func _make_meadow() -> BiomeDefinition:
	var b := BiomeDefinition.new()
	b.biome_id    = "meadow"
	b.display_name = "Wiese"
	b.terrain_color_grass = Color(0.38, 0.68, 0.20)
	b.terrain_color_dirt  = Color(0.55, 0.42, 0.20)
	b.terrain_color_rock  = Color(0.50, 0.48, 0.45)
	b.prop_attempts_min = 8
	b.prop_attempts_max = 16
	b.prop_chances = {
		"oak_tree":    0.12,  # einzelne Solitärbäume statt Kahlfläche
		"maple_tree":  0.05,
		"rock_boulder":0.03,
		"fern":        0.06,  # (Fern-Rollout) Wiese war das letzte "normale" Biom ohne fern-Eintrag.
		"wild_beehive": 0.012,  # Hain-Skill Imkerei (Blütenwiese)
		"mole_hill": 0.012,  # Maulwurfshügel (Graben)
		"wasp_nest": 0.006,  # Nest-Skill Insektenkunde (verlassenes Wespennest)
		"graveyard_gravestone": 0.004,
		"goblin_campfire": 0.006,
		# Kräuter/Blumen (herbalism/gardening) — Habitat-Logik: docs/herbalism-and-gardening.md
		"plant_chamomile": 0.035,
		"plant_yarrow": 0.030,
		"plant_dandelion": 0.040,
		"plant_poppy": 0.040,
		"plant_cornflower": 0.030,
		"plant_calendula": 0.020,
		"plant_thyme": 0.010,
		"plant_meadowsweet": 0.010,
		# Sträucher (Pflücken + Roden) — BushCatalog
		"bush_blackberry": 0.030,
		"bush_dogrose": 0.030,
		"bush_hazel": 0.020,
	}
	b.enemy_chances = {
		"goblin": 0.02,
	}
	b.structure_types = ["well", "cottage", "barn"]
	b.grass_per_chunk = 900
	b.bush_per_chunk  = 18
	b.grass_color_base = Color(0.22, 0.46, 0.12)
	b.grass_color_tip  = Color(0.55, 0.78, 0.28)
	b.bush_color       = Color(0.22, 0.48, 0.16)
	b.flower_per_chunk = 260
	# Farben stehen für echte Wiesenblumen (Form ist stilisiert): Klatschmohn, Löwenzahn/Ringelblume,
	# Kamille/Margerite, Wiesen-Salbei, Kornblume, Rotklee.
	b.flower_colors = [Color(0.85, 0.15, 0.12), Color(0.95, 0.82, 0.15), Color(0.95, 0.95, 0.92), Color(0.58, 0.30, 0.80), Color(0.27, 0.38, 0.85), Color(0.90, 0.45, 0.65)]
	return b

static func _make_desert() -> BiomeDefinition:
	var b := BiomeDefinition.new()
	b.biome_id    = "desert"
	b.display_name = "Wüste"
	b.terrain_color_grass = Color(0.78, 0.65, 0.30)
	b.terrain_color_dirt  = Color(0.70, 0.55, 0.25)
	b.terrain_color_rock  = Color(0.65, 0.50, 0.30)
	# Bugfix 2026-09-26 ("überall nur Erde"): Wüste gräbt sich natürlich als Sand,
	# nicht als Erde — siehe TerrainField.get_material_at().
	b.surface_material = "sand"
	b.prop_attempts_min = 7
	b.prop_attempts_max = 13
	b.prop_chances = {
		"cactus":      0.14,
		"rock_boulder":0.08,
		"fulgurite":    0.03,  # Hain-Skill Sturmkunde: Blitz + Sand = Glas (Fulgurit)
		"meteorite":    0.012,  # Hain-Skill Sternkunde (Wüste: dunkle Steine fallen auf)
		"termite_mound": 0.012,  # Nest-Skill Insektenkunde (Termitenhügel; trocken-warmes Biom)
		"graveyard_gravestone": 0.008,
	}
	b.enemy_chances = {
		"skeleton": 0.06,  # (Round 75, Anfrage "vermehrt Skelette")
		"goblin":   0.02,
	}
	b.structure_types = ["well", "ruin"]
	# Wüste: nur dünnes, vertrocknetes Steppengras und Dornbüsche (Farbe = dürr/gelblich).
	b.grass_per_chunk = 70
	b.bush_per_chunk  = 14
	b.grass_color_base = Color(0.48, 0.40, 0.18)
	b.grass_color_tip  = Color(0.78, 0.68, 0.34)
	b.bush_color       = Color(0.46, 0.40, 0.20)
	return b

static func _make_winter() -> BiomeDefinition:
	var b := BiomeDefinition.new()
	b.biome_id    = "winter"
	b.display_name = "Schnee"
	b.terrain_color_grass = Color(0.85, 0.90, 0.95)
	b.terrain_color_dirt  = Color(0.70, 0.75, 0.80)
	b.terrain_color_rock  = Color(0.60, 0.65, 0.70)
	b.snow_coverage = 1.0
	b.prop_attempts_min = 12
	b.prop_attempts_max = 22
	b.prop_chances = {
		"pine_tree":   0.30,
		"rock_boulder":0.06,
		"fallen_tree": 0.03,
		"ice_crystal": 0.05,  # (Round 77) IceCrystal-Entity existiert jetzt, spawnt automatisch.
		"meteorite":   0.010,  # Hain-Skill Sternkunde (dunkler Stein auf hellem Eis)
		"graveyard_gravestone": 0.005,
	}
	b.enemy_chances = {
		"skeleton": 0.02,
		"goblin":   0.02,
	}
	b.structure_types = ["cottage"]
	# Kaum Gras im Schnee — nur vereinzelte, schneebestäubte Sträucher.
	b.grass_per_chunk = 0
	b.bush_per_chunk  = 18
	b.bush_color       = Color(0.55, 0.62, 0.56)
	return b

static func _make_swamp() -> BiomeDefinition:
	var b := BiomeDefinition.new()
	b.biome_id    = "swamp"
	b.display_name = "Sumpf"
	b.terrain_color_grass = Color(0.28, 0.38, 0.12)
	b.terrain_color_dirt  = Color(0.22, 0.28, 0.10)
	b.terrain_color_rock  = Color(0.30, 0.32, 0.22)
	b.fog_density = 0.5
	b.prop_attempts_min = 12
	b.prop_attempts_max = 22
	b.prop_chances = {
		"willow_tree":      0.16,  # Sumpf hatte bisher KEINE lebenden Bäume — Trauerweiden passen
		"fallen_tree":      0.08,
		"mushroom_cluster": 0.10,
		"fern":             0.06,
		"sulfur_crust":     0.012,  # Hain-Skill Alchemie
		"graveyard_gravestone": 0.008,  # Sumpf + Friedhof passt atmosphärisch gut zusammen
		"goblin_campfire":  0.008,
		# Kräuter/Blumen (herbalism/gardening) — Habitat-Logik: docs/herbalism-and-gardening.md
		"plant_meadowsweet": 0.050,
		"plant_nettle": 0.030,
		# Sträucher (Pflücken + Roden) — BushCatalog
		"bush_elder": 0.040,
		"bush_blackberry": 0.030,
	}
	b.enemy_chances = {
		"goblin":   0.04,
		"skeleton": 0.03,
	}
	b.structure_types = ["ruin"]
	b.grass_per_chunk = 420
	b.bush_per_chunk  = 22
	b.grass_color_base = Color(0.16, 0.24, 0.07)
	b.grass_color_tip  = Color(0.38, 0.46, 0.16)
	b.bush_color       = Color(0.20, 0.30, 0.10)
	b.flower_per_chunk = 50
	b.flower_colors = [Color(0.50, 0.30, 0.70), Color(0.90, 0.85, 0.40)]
	return b

## Round 78 (Anfrage "rock_boulder im Gebirge-Biom") — neues Biom, siehe
## _resolve_id() für die Noise-Nische (kalt + trocken). rock_boulder hier die
## Hauptattraktion des Bioms.
static func _make_mountain() -> BiomeDefinition:
	var b := BiomeDefinition.new()
	b.biome_id    = "mountain"
	b.display_name = "Gebirge"
	b.terrain_color_grass = Color(0.48, 0.46, 0.44)
	b.terrain_color_dirt  = Color(0.40, 0.36, 0.32)
	b.terrain_color_rock  = Color(0.35, 0.35, 0.34)
	# Bugfix 2026-09-26: felsig-geröllig statt Erde, siehe TerrainField.get_material_at().
	b.surface_material = "gravel"
	b.prop_attempts_min = 9
	b.prop_attempts_max = 16
	b.prop_chances = {
		"rock_boulder": 0.30,
		"pine_tree":    0.14,  # Baumgrenze — kein eigenes Winter-Biom, aber realistisch für Hochland
		"fern":         0.04,  # (Fern-Rollout) vereinzelt zwischen den Felsen, nicht dominant
		"sulfur_crust":  0.012,  # Hain-Skill Alchemie
		"meteorite":    0.010,  # Hain-Skill Sternkunde
		"graveyard_gravestone": 0.005,
		"goblin_campfire": 0.012,  # höchste Rate aller Biome — Gebirgspässe sind DAS Goblin-Terrain
		# Kräuter/Blumen (herbalism/gardening) — Habitat-Logik: docs/herbalism-and-gardening.md
		"plant_thyme": 0.040,
		"plant_yarrow": 0.020,
		"plant_lavender": 0.020,
		# Sträucher (Pflücken + Roden) — BushCatalog
		"bush_dogrose": 0.030,
	}
	b.enemy_chances = {
		"goblin": 0.05,  # Gebirgspässe — klassisches Banditen/Goblin-Terrain
	}
	b.structure_types = ["ruin"]
	# Karges Hochland: vereinzelte Grasbüschel in Felsritzen, wenige Sträucher.
	b.grass_per_chunk = 110
	b.bush_per_chunk  = 8
	b.grass_color_base = Color(0.28, 0.30, 0.16)
	b.grass_color_tip  = Color(0.50, 0.54, 0.28)
	b.bush_color       = Color(0.26, 0.34, 0.18)
	b.flower_per_chunk = 50
	b.flower_colors = [Color(0.45, 0.40, 0.85), Color(0.95, 0.95, 0.92)]
	return b

## Round 79 (Anfrage "toter Wald: paar lebende Bäume & viele Baumstämme") —
## fallen_tree deutlich dominant, oak_tree nur als seltene Ausnahme.
static func _make_dead_forest() -> BiomeDefinition:
	var b := BiomeDefinition.new()
	b.biome_id    = "dead_forest"
	b.display_name = "Toter Wald"
	b.terrain_color_grass = Color(0.42, 0.38, 0.30)
	b.terrain_color_dirt  = Color(0.35, 0.30, 0.22)
	b.terrain_color_rock  = Color(0.40, 0.38, 0.35)
	b.fog_density = 0.25
	b.prop_attempts_min = 12
	b.prop_attempts_max = 22
	b.prop_chances = {
		"fallen_tree": 0.24,
		"oak_tree":    0.04,
		"fern":        0.03,  # (Fern-Rollout) vereinzeltes zähes Grün trotz Trockenheit
		"hornet_nest": 0.005,  # Nest-Skill Insektenkunde (Hornissen nisten in Baumhöhlen)
		"graveyard_gravestone": 0.008,  # höchste Rate aller Biome — "toter Wald" passt am besten zu einem Friedhof
	}
	b.enemy_chances = {
		"skeleton": 0.05,
		"goblin":   0.02,
	}
	b.structure_types = ["ruin"]
	b.grass_per_chunk = 160
	b.bush_per_chunk  = 20  # dürre, kahle Sträucher
	b.grass_color_base = Color(0.30, 0.26, 0.14)
	b.grass_color_tip  = Color(0.52, 0.46, 0.26)
	b.bush_color       = Color(0.34, 0.28, 0.18)
	return b
