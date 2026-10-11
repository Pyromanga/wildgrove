class_name WorldSaveHandler
extends RefCounted

## WorldSaveHandler — Save/Restore-Logik für die Spielwelt.
##
## Ausgelagert aus WorldService (v28).
## KEIN eigener ISaveProvider: nie über register_save_provider() registriert.
## WorldService ist der tatsächliche Provider (get_save_key()/get_save_data()
## in WorldService.gd) und delegiert intern hierher. Der vorherige
## '## implements ISaveProvider'-Kommentar war schlicht falsch — kein
## fehlender Code, sondern eine unzutreffende Behauptung (siehe
## data/manager/decisions/, ADR-Neuaufbau Round 110).
## Verantwortlich für:
##   - get_save_data()  → serialisiert WorldData + WorldTimeService
##   - restore_world()  → deserialisiert gespeicherten Zustand zurück in WorldData
##
## Kein Service, kein Node. Wird von WorldService als Hilfsklasse genutzt.

const LOG_CAT := "WorldSave"

var _data: WorldData
var _time: WorldTimeService
## ADR-041: optional, Default null — bestehende Aufrufer (Tests, ältere
## Call-Sites) bleiben ohne Änderung kompilierbar; Wetter-Keys werden dann
## einfach ausgelassen statt zu crashen (siehe get_save_data()/restore_world()).
var _weather: WeatherService

func _init(data: WorldData, time: WorldTimeService, weather: WeatherService = null) -> void:
	_data = data
	_time = time
	_weather = weather

# ─────────────────────────────────────────────
# Speichern
# ─────────────────────────────────────────────

func get_save_data() -> Dictionary:
	var pets_raw: Variant = _data.get_meta("saved_pets") if _data.has_meta("saved_pets") else []

	var time_data := _time.get_save_data()
	var out := {
		"day_time":            time_data["day_time"],
		"day_count":           time_data["day_count"],
		"typed_tree_positions": var_to_str(_data.typed_tree_positions),
		"typed_ore_positions":  var_to_str(_data.typed_ore_positions),
		"player_pos":          var_to_str(_data.player_position),
		"harvested":           var_to_str(_data.harvested_objects),
		# Wunsch "Bäume ... über Spieltage hinweg wachsen": Geschwister-Feld zu "harvested",
		# gleiches "fehlt bei älteren Spielständen → leer"-Muster (siehe restore_world()) —
		# ein Baum ohne Eintrag gilt einfach als originaler Weltbestand (siehe
		# WorldData.planted_day-Kommentar), kein Migrationsschritt nötig.
		"planted_day":         var_to_str(_data.planted_day),
		"saved_pets":          var_to_str(pets_raw),
		# BUG-C-FIX (HP wird nicht gespeichert): analog zu saved_pets — Dictionary
		# { player_id: {current, max} }, siehe WorldData.player_health-Kommentar.
		"player_health":       var_to_str(_data.player_health),
		# Bugfix 2026-09-27: var_to_str() statt rohem int — siehe restore_world()-
		# Kommentar (JSON kennt int/float nicht auseinander, var_to_str()/
		# str_to_var() schon, genau wie bei jedem anderen Feld hier).
		"world_seed":          var_to_str(_data.world_seed),
		# Gelände-Änderungen und Bauteile. Fehlen bei älteren Spielständen → beim Laden
		# einfach leer (siehe restore_world()), kein Migrationsschritt nötig.
		"terrain_edits":       var_to_str(_data.terrain_edits.to_save()),
		# Bugfix 2026-09-26 ("Sand bleibt Sand"): Geschwister-Feld zu terrain_edits,
		# gleiches "fehlt bei älteren Spielständen → leer"-Muster.
		"terrain_materials":   var_to_str(_data.terrain_materials.to_save()),
		# Bugfix 2026-09-27 ("bepflanzte Felder nicht persistent"): gleiches
		# Sparse-Registry-Muster wie terrain_materials.
		"farm_plots":          var_to_str(_data.farm_plots.to_save()),
		"build_pieces":        var_to_str(_data.build_registry.to_save()),
		"ladders":             var_to_str(_data.ladders.to_save()),
		"dig_finds":           var_to_str(_data.dig_finds.to_save()),
	}
	if is_instance_valid(_weather):
		var weather_data := _weather.get_save_data()
		out["weather"] = weather_data["weather"]
		out["weather_last_rolled_day"] = weather_data["weather_last_rolled_day"]
	return out

# ─────────────────────────────────────────────
# Wiederherstellen
# ─────────────────────────────────────────────

func restore_world(state: Dictionary) -> void:
	_time.restore(state)
	if is_instance_valid(_weather):
		_weather.restore(state)

	var typed_trees: Variant = str_to_var(state.get("typed_tree_positions", "{}"))
	_data.typed_tree_positions = typed_trees if typed_trees is Dictionary else {}

	var typed_ores: Variant = str_to_var(state.get("typed_ore_positions", "{}"))
	_data.typed_ore_positions = typed_ores if typed_ores is Dictionary else {}

	var player_pos_raw: Variant = str_to_var(state.get("player_pos", "Vector3(0,0,0)"))
	_data.player_position = player_pos_raw if player_pos_raw is Vector3 else Vector3.ZERO

	var harvested_raw: Variant = str_to_var(state.get("harvested", "{}"))
	_data.harvested_objects = harvested_raw if harvested_raw is Dictionary else {}

	var planted_raw: Variant = str_to_var(state.get("planted_day", "{}"))
	_data.planted_day = planted_raw if planted_raw is Dictionary else {}

	# Bugfix 2026-09-27 ("Flüsse und Biome verschieben sich nach Speichern/
	# Neuladen"): SaveSystem.gd schreibt den Spielstand als JSON
	# (JSON.stringify()/JSON.parse()) — JSON kennt keinen Unterschied zwischen
	# int und float, JSON.parse() liefert JEDE Zahl als float zurück. Der
	# frühere strikte "seed_raw is int"-Check auf dem ROHEN Zahlenwert war
	# dadurch NIE erfüllt: world_seed wurde beim Speichern korrekt als Zahl
	# geschrieben, kam beim Laden aber immer als float zurück → world_seed
	# resettete bei JEDEM Laden auf 0 → WorldService.configure() würfelte über
	# Time.get_unix_time_from_system() einen komplett neuen Zufalls-Seed. Da
	# Höhe, Klima/Biome UND Flüsse direkt aus world_seed abgeleitet werden
	# (siehe TerrainSeed.derive()), sah die Welt nach jedem Neuladen komplett
	# anders aus. Alle anderen Felder hier überleben den Roundtrip, weil sie
	# var_to_str()/str_to_var() (typtreu) nutzen — world_seed jetzt genauso.
	# raw_number-Zweig bleibt als Fallback für ältere Spielstände, die noch
	# das alte rohe Zahlenformat enthalten (var_to_str("123") würde dort
	# scheitern, str_to_var("123") aber nicht — s.u. — und akzeptiert
	# vorsichtshalber auch float, falls ein solcher alter Stand selbst schon
	# vom JSON-Bug getroffen wurde).
	var seed_raw: Variant = str_to_var(str(state.get("world_seed", 0)))
	_data.world_seed = int(seed_raw) if (seed_raw is int or seed_raw is float) else 0

	var pets_raw: Variant = str_to_var(state.get("saved_pets", "[]"))
	if pets_raw is Array:
		_data.set_meta("saved_pets", pets_raw)

	# BUG-C-FIX (HP wird nicht gespeichert): fehlt bei älteren Spielständen →
	# einfach leeres Dictionary (kein Migrationsschritt nötig, identisch zum
	# Muster bei terrain_edits/build_pieces/ladders/dig_finds unten).
	var player_health_raw: Variant = str_to_var(state.get("player_health", "{}"))
	_data.player_health = player_health_raw if player_health_raw is Dictionary else {}

	# In-place laden (Instanzen bleiben gleich — TerrainField/BuildHandler halten Referenzen).
	# str_to_var("null") bzw. fehlender Key → load_save() räumt auf, statt zu crashen.
	_data.terrain_edits.load_save(str_to_var(state.get("terrain_edits", "[]")))
	_data.terrain_materials.load_save(str_to_var(state.get("terrain_materials", "[]")))
	_data.farm_plots.load_save(str_to_var(state.get("farm_plots", "[]")))
	_data.build_registry.load_save(str_to_var(state.get("build_pieces", "[]")))
	_data.ladders.load_save(str_to_var(state.get("ladders", "[]")))
	_data.dig_finds.load_save(str_to_var(state.get("dig_finds", "[]")))

	AppLogger.log_info(
		"Welt geladen: Tag %d %s, %d Bäume, %d Erze." % [
			_time.day_count, _time.get_formatted_time(),
			_data.get_tree_count(), _data.get_ore_count()
		], LOG_CAT
	)
