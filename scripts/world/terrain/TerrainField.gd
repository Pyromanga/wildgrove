class_name TerrainField
extends RefCounted

## TerrainField — DIE eine Wahrheit über das Gelände: Höhe, Wasser und Klima an jedem Punkt.
##
## ═══ WARUM ES DAS GIBT ═══
## Vorher wusste jeder etwas anderes: der Mesh-Bau kannte Flüsse/Seen, get_height_at()
## (für Bäume, NPCs, Gegner, Bauen) kannte sie nicht; der Fluss war pro Chunk lokal; der
## world_seed kam nie im Noise an; Wasser waren begehbare Rechtecke. Jetzt gilt:
##
##   get_height_at(x, z) ist die Höhe. Punkt. Mesh, Kollision, Spawner, Bauen und Graben
##   fragen ALLE dieselbe Funktion — deshalb kann nichts mehr in der Luft schweben oder im
##   Boden stecken, und man braucht keine Physik-Raycasts, um zu wissen, wo der Boden ist
##   (funktioniert auch für nicht geladene Chunks, auf Servern ohne Grafik und in Tests).
##
## ═══ AUFBAU ═══
##     Höhe = Stapel aus TerrainLayern (Basis → Erosion → Fluss → Spawn-Plateau) + Edit-Deltas
##
##   - Layer sind reine Funktionen in Weltkoordinaten (siehe TerrainLayer).
##   - Edit-Deltas (TerrainEditLayer) sind die Spieler-Änderungen und kommen zuletzt.
##   - Wasser ist KEIN Objekt, sondern eine Eigenschaft: Wasser ist überall, wo die Höhe
##     unter get_water_level() liegt (Seen, Flüsse, Meer, gegrabene Senken).
##   - Klima (Temperatur/Feuchte) ist von der Höhe unabhängig und bestimmt das Biom.
##
## ═══ KONVENTIONEN ═══
##   - IMMER Weltkoordinaten. (Der alte TerrainGenerator.get_height_at() war chunk-LOKAL,
##     get_biome_at() absolut — eine Dauer-Fehlerquelle.)
##   - Deterministisch: (Config, world_seed) → immer dieselbe Welt, auf jedem Peer.
##   - Kein Node, kein Service, kein Zustand außer der (austauschbaren) Edit-Schicht.
##
## Tests können TerrainField per `extends TerrainField` überschreiben (get_height_at()).

var _config: TerrainConfig
var _seed: int
var _layers: Array[TerrainLayer] = []
var _base_layer: TerrainBaseLayer
var _river_layer: TerrainRiverLayer
var _lake_layer: TerrainLakeLayer
var _edit_layer: TerrainEditLayer = null
var _material_layer: TerrainMaterialLayer = null
var _settlements: SettlementRegistry = null
var _temperature: FastNoiseLite
var _humidity: FastNoiseLite

func _init(config: TerrainConfig = null, world_seed: int = 0) -> void:
	_config = config if config != null else TerrainConfig.new()
	_seed = world_seed if world_seed != 0 else TerrainConfig.DEFAULT_SEED

	# Reihenfolge = Berechnungsreihenfolge. Spätere Layer sehen das Ergebnis der früheren.
	_base_layer = TerrainBaseLayer.new(_config, _seed)
	# Der Fluss bekommt die Basis, um die Geländehöhe an der Flussmitte zu messen (daraus ergibt
	# sich der Wasserspiegel: Ufer stehen ÜBER dem Wasser, siehe TerrainRiverLayer).
	_river_layer = TerrainRiverLayer.new(_config, _seed, _base_layer)
	# Stapel-Reihenfolge: Basis → Erosion → Fluss → See → Spawn-Plateau.
	_layers.append(_base_layer)
	# Erosion direkt nach der Basis (Rinnen/Grate/Felsstufen in Hügeln und Bergen), VOR den Flüssen.
	# Sie kennt den Fluss nur für den Abstand: in Flusstälern wirkt sie nicht (glatte Talsohle) —
	# das hält Basis und erodiertes Gelände an der Flussmitte identisch (Wasserspiegel!).
	_layers.append(TerrainErosionLayer.new(_config, _seed, _base_layer, _river_layer))
	_layers.append(_river_layer)
	# Bergseen: messen ihren Spiegel an der Höhe ALLER Layer unter ihnen (Callable → kein Zyklus).
	_lake_layer = TerrainLakeLayer.new(_config, _seed, Callable(self, "_height_below_lakes"), _river_layer)
	_layers.append(_lake_layer)
	_layers.append(TerrainSpawnPlateauLayer.new(_config))

	_temperature = TerrainLayer.make_noise(
		TerrainSeed.derive(_seed, "climate.temperature"), _config.temperature_frequency, 2)
	_humidity = TerrainLayer.make_noise(
		TerrainSeed.derive(_seed, "climate.humidity"), _config.humidity_frequency, 2)

# ─────────────────────────────────────────────
# Zugriff auf Konfiguration
# ─────────────────────────────────────────────

func get_config() -> TerrainConfig:
	return _config

func get_seed() -> int:
	return _seed

## Globaler Wasserspiegel (Meer/Seen — stehende Gewässer, gleichen sich auf EINER Höhe aus).
## Auch die Basis, auf die Spieler-Gruben treffen, wenn sie tief genug graben (siehe
## get_water_level_at(): abseits von Flüssen liefert die immer diesen Wert).
func get_water_level() -> float:
	return _config.water_level

## Geländehöhe an (x, z), wie sie OHNE den Fluss-Layer wäre (Basis-Layer-Ergebnis) — also
## die Talsohle/Ebene, in die ein Fluss hier eingeschnitten haben könnte. Rein prozedural,
## OHNE Spieler-Edits (siehe get_water_level_at() für den Grund).
## Höhe der Layer unterhalb der Seen (Basis → Erosion → Fluss), ohne Edits. Für TerrainLakeLayer.
func _height_below_lakes(world_x: float, world_z: float) -> float:
	var h: float = 0.0
	for layer in _layers:
		if layer == _lake_layer:
			break
		h = layer.apply(world_x, world_z, h)
	return h

func get_lake_layer() -> TerrainLakeLayer:
	return _lake_layer

func get_river_layer() -> TerrainRiverLayer:
	return _river_layer

func get_height_before_rivers_at(world_x: float, world_z: float) -> float:
	var h: float = 0.0
	for layer in _layers:
		if layer == _river_layer:
			break
		h = layer.apply(world_x, world_z, h)
	return h

## Wasserspiegel GENAU an (x, z) — nicht mehr überall derselbe Wert.
##
## BUGFIX (2026-09-20, "Wasser/Flüsse & Seen sind alle auf einer Ebene"): See/Meer bleiben
## auf dem globalen Spiegel (get_water_level()) — physikalisch korrekt, stehendes Wasser
## gleicht sich auf einer Höhe aus. Aber innerhalb eines echten Flusslaufs (TerrainRiverLayer)
## folgt der Wasserspiegel jetzt der lokalen, uneingeschnittenen Geländehöhe: ein Fluss durchs
## Hügelland liegt höher als einer im Tiefland, statt weltweit auf derselben absoluten Höhe.
##
## Bewusst NUR für Flüsse, nicht überall: die Basis (get_height_before_rivers_at) ist rein
## prozedural und kennt keine Spieler-Edits. Würde sie überall statt des globalen Spiegels
## gelten, würde jedes gegrabene Loch abseits von Flüssen bei seiner EIGENEN ursprünglichen
## Geländehöhe fluten statt beim globalen Spiegel — "beim Buddeln irgendwann auf Wasser
## stoßen" bleibt dadurch unverändert an den globalen Spiegel gekoppelt.
func get_water_level_at(world_x: float, world_z: float) -> float:
	# Bergseen zuerst (billig: eine Dictionary-Abfrage): stehen auf EIGENER Höhe, nicht auf dem
	# globalen Spiegel. Vorrang vor Flüssen (Seen meiden Flüsse ohnehin, siehe TerrainLakeLayer).
	var lake_target: float = _lake_layer.get_water_target_at(world_x, world_z)
	if not is_nan(lake_target):
		return lake_target
	# Vorfilter: fast überall (>85 % der Welt) ist kein Fluss in der Nähe — dann den teuren
	# Basis-Stack gar nicht erst auswerten (wird pro Chunk 1089x aufgerufen).
	if not _river_layer.is_candidate(world_x, world_z):
		return get_water_level()
	var h_before: float = get_height_before_rivers_at(world_x, world_z)
	var river_target: float = _river_layer.get_water_target_at(world_x, world_z, h_before)
	if is_nan(river_target):
		return get_water_level()
	return maxf(get_water_level(), river_target)

## Wie stark Gebirge an (x, z) ausgeprägt ist (0 = Flachland … 1 = Hochgebirge).
func get_mountain_weight_at(world_x: float, world_z: float) -> float:
	return _base_layer.get_mountain_weight(world_x, world_z)

## Setzt die Schicht der Spieler-Änderungen. Dieselbe Instanz, die WorldData speichert.
func set_edit_layer(layer: TerrainEditLayer) -> void:
	_edit_layer = layer

func get_edit_layer() -> TerrainEditLayer:
	return _edit_layer

## Setzt die Schicht der abgelegten Bodenmaterialien. Dieselbe Instanz, die
## WorldData speichert (siehe TerrainMaterialLayer-Klassenkommentar).
func set_material_layer(layer: TerrainMaterialLayer) -> void:
	_material_layer = layer

func get_material_layer() -> TerrainMaterialLayer:
	return _material_layer

## Dörfer, Straßen und Siedlungsgebäude dieser Welt (lazy, deterministisch aus Seed + Basis-Gelände).
## Eigener Cache pro TerrainField — Tests mit eigener Field-Unterklasse bekommen eine eigene Instanz.
func get_settlements() -> SettlementRegistry:
	if _settlements == null:
		_settlements = SettlementRegistry.new(self)
	return _settlements

# ─────────────────────────────────────────────
# Höhe
# ─────────────────────────────────────────────

## Endgültige Geländehöhe (mit Spieler-Änderungen) an Weltposition (x, z).
func get_height_at(world_x: float, world_z: float) -> float:
	var h: float = get_base_height_at(world_x, world_z)
	if _edit_layer != null:
		h += _edit_layer.get_delta_at(world_x, world_z)
	return h

## Höhe OHNE Spieler-Änderungen (das unberührte, prozedurale Gelände).
func get_base_height_at(world_x: float, world_z: float) -> float:
	var h: float = 0.0
	for layer in _layers:
		h = layer.apply(world_x, world_z, h)
	return h

## Steigung an (x, z) in Grad (0 = eben). Zentrale Differenzen über `sample` Meter.
func get_slope_at(world_x: float, world_z: float, sample: float = 1.0) -> float:
	var dx: float = get_height_at(world_x + sample, world_z) - get_height_at(world_x - sample, world_z)
	var dz: float = get_height_at(world_x, world_z + sample) - get_height_at(world_x, world_z - sample)
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz) / (2.0 * sample)))

# ─────────────────────────────────────────────
# Wasser
# ─────────────────────────────────────────────

## Wassertiefe an (x, z) in Metern (0 an Land).
func get_water_depth_at(world_x: float, world_z: float) -> float:
	return maxf(0.0, get_water_level_at(world_x, world_z) - get_height_at(world_x, world_z))

func is_water_at(world_x: float, world_z: float) -> bool:
	return get_height_at(world_x, world_z) < get_water_level_at(world_x, world_z)

# ─────────────────────────────────────────────
# Klima / Biome
# ─────────────────────────────────────────────

## (Temperatur, Feuchte), je ~[-1, 1]. Von der Höhe unabhängig.
func get_climate_at(world_x: float, world_z: float) -> Vector2:
	return Vector2(
		_temperature.get_noise_2d(world_x, world_z),
		_humidity.get_noise_2d(world_x, world_z)
	)

func get_biome_at(world_x: float, world_z: float) -> BiomeDefinition:
	var c: Vector2 = get_climate_at(world_x, world_z)
	return BiomeRegistry.get_biome_for(c.x, c.y)

func get_biome_id_at(world_x: float, world_z: float) -> String:
	var c: Vector2 = get_climate_at(world_x, world_z)
	return BiomeRegistry.get_biome_id_for(c.x, c.y)

# ─────────────────────────────────────────────
# Bodenmaterial (2026-09-26, "natürlich Erde/Sand je nach Biom + Kiesschicht,
# abgelegtes Material bleibt es")
# ─────────────────────────────────────────────

## Ab dieser kumulierten Grabtiefe (siehe TerrainEditLayer.get_delta_at(), negativ
## = gegraben) wird Kies zur natürlichen Antwort — UNABHÄNGIG vom Biom. Realismus:
## unter dem biomspezifischen Oberboden (Erde/Sand/…) liegt überall eine Kies-/
## Geröllschicht, kein endloser Sand oder Waldboden bis in die Tiefe. Gilt nur,
## wenn an diesem Punkt kein Spieler-Override (TerrainMaterialLayer) liegt —
## bewusst abgelegtes Material "gewinnt" immer gegen die Tiefen-Heuristik.
const SUBSOIL_DEPTH: float = -2.0

## Bodenmaterial an (x, z) als Item-ID (siehe data/items/) — Auflösungsreihenfolge:
##   1. Spieler-Override (TerrainMaterialLayer) — jemand hat hier bewusst etwas abgelegt.
##   2. Kies-Unterboden, falls tief genug gegraben (SUBSOIL_DEPTH).
##   3. Natürliches Oberflächenmaterial des Bioms (BiomeDefinition.surface_material).
## Wird sowohl von WorldService.request_terrain_edit() (welches Item Graben liefert)
## als auch von TerrainChunkBuilder._biome_color() (Einfärbung) genutzt — EINE
## Wahrheit für Gameplay und Optik, kann nicht auseinanderlaufen.
func get_material_at(world_x: float, world_z: float) -> String:
	if _material_layer != null:
		var override := _material_layer.get_override_at(world_x, world_z)
		if not override.is_empty():
			return override
	if _edit_layer != null and _edit_layer.get_delta_at(world_x, world_z) <= SUBSOIL_DEPTH:
		return "gravel"
	var biome: BiomeDefinition = get_biome_at(world_x, world_z)
	return biome.surface_material if is_instance_valid(biome) else "dirt"
