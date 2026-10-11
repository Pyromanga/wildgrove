# res://tests/unit/test_world_save_handler.gd
extends GutTest

## Unit-Tests für WorldSaveHandler (E-02 — WorldService save/load).
##
## Strategie: WorldSaveHandler ist eine RefCounted-Hilfsklasse ohne SceneTree-Abhängigkeit.
## WorldData und WorldTimeService direkt instanziiert — beide sind RefCounted.
## Kein Node, kein AppLogger-Problem, kein EventBus.
##
## Abgedeckt:
##   - get_save_data(): Struktur der serialisierten Keys
##   - get_save_data(): Baum-Positionen serialisiert
##   - get_save_data(): Erz-Positionen serialisiert
##   - get_save_data(): Spieler-Position
##   - get_save_data(): Tageszeit und Tagzähler
##   - restore_world(): Bäume wiederhergestellt
##   - restore_world(): Erze wiederhergestellt
##   - restore_world(): Spieler-Position wiederhergestellt
##   - restore_world(): Tageszeit und Tagzähler wiederhergestellt
##   - restore_world(): Harvested-Objects wiederhergestellt
##   - restore_world(): world_seed wiederhergestellt (Regression, siehe Round 39)
##   - Save-Round-Trip: get_save_data → restore_world → gleicher State

var _data:    WorldData
var _time:    WorldTimeService
var _handler: WorldSaveHandler

const POS_TREE_1 := Vector3(10, 0, 20)
const POS_TREE_2 := Vector3(30, 0, 40)
const POS_ORE_1  := Vector3(-5, 0, 15)
const POS_PLAYER := Vector3(7, 0, 3)

func before_each() -> void:
	_data    = WorldData.new()
	_time    = WorldTimeService.new()
	_handler = WorldSaveHandler.new(_data, _time)

func after_each() -> void:
	_handler = null
	_time    = null
	_data    = null

# ─────────────────────────────────────────────────────────────────────────────
# get_save_data — Struktur
# ─────────────────────────────────────────────────────────────────────────────

func test_save_data_has_required_keys() -> void:
	var sd := _handler.get_save_data()
	assert_true(sd.has("day_time"),       "day_time muss im Snapshot sein")
	assert_true(sd.has("day_count"),      "day_count muss im Snapshot sein")
	assert_true(sd.has("typed_tree_positions"), "typed_tree_positions muss im Snapshot sein")
	assert_true(sd.has("typed_ore_positions"),  "typed_ore_positions muss im Snapshot sein")
	assert_true(sd.has("player_pos"),     "player_pos muss im Snapshot sein")
	assert_true(sd.has("harvested"),      "harvested muss im Snapshot sein")
	assert_true(sd.has("world_seed"),     "world_seed muss im Snapshot sein")

func test_save_data_serializes_trees() -> void:
	_data.add_typed_tree("oak_tree", POS_TREE_1)
	_data.add_typed_tree("oak_tree", POS_TREE_2)
	var sd := _handler.get_save_data()
	var typed_trees := str_to_var(sd["typed_tree_positions"] as String) as Dictionary
	assert_eq((typed_trees["oak_tree"] as Array).size(), 2, "Zwei Bäume müssen serialisiert sein")

func test_save_data_serializes_player_position() -> void:
	_data.player_position = POS_PLAYER
	var sd := _handler.get_save_data()
	var restored = str_to_var(sd["player_pos"] as String)
	assert_true(restored is Vector3, "player_pos muss als Vector3 deserialisierbar sein")
	assert_almost_eq((restored as Vector3).x, POS_PLAYER.x, 0.01, "X-Koordinate muss übereinstimmen")

func test_save_data_includes_day_time() -> void:
	_time.day_time  = 14.5
	_time.day_count = 3
	var sd := _handler.get_save_data()
	assert_almost_eq(sd["day_time"]  as float, 14.5, 0.01, "day_time muss 14.5 sein")
	assert_eq(        sd["day_count"] as int,   3,          "day_count muss 3 sein")

# ─────────────────────────────────────────────────────────────────────────────
# Wetter (ADR-041, Round 95)
# ─────────────────────────────────────────────────────────────────────────────

func test_save_data_without_weather_service_has_no_weather_keys() -> void:
	# _handler wurde in before_each() ohne weather-Argument gebaut (Default null) —
	# Rückwärtskompatibilität, siehe WorldSaveHandler._init()-Kommentar.
	var sd := _handler.get_save_data()
	assert_false(sd.has("weather"), "Ohne WeatherService dürfen keine Wetter-Keys im Snapshot sein.")

func test_save_data_with_weather_service_includes_weather_keys() -> void:
	var weather := WeatherService.new()
	weather.roll_for_day(1, 42)
	var handler_with_weather := WorldSaveHandler.new(_data, _time, weather)
	var sd := handler_with_weather.get_save_data()
	assert_true(sd.has("weather"), "Mit WeatherService muss 'weather' im Snapshot sein.")
	assert_eq(sd["weather"], weather.current_weather, "Snapshot-Wetter muss dem Service-Wetter entsprechen.")

func test_restore_world_with_weather_service_restores_weather() -> void:
	var weather1 := WeatherService.new()
	weather1.roll_for_day(2, 77)
	var handler1 := WorldSaveHandler.new(_data, _time, weather1)
	var snapshot := handler1.get_save_data()

	var data2 := WorldData.new()
	var time2 := WorldTimeService.new()
	var weather2 := WeatherService.new()
	var h2 := WorldSaveHandler.new(data2, time2, weather2)
	h2.restore_world(snapshot)

	assert_eq(weather2.current_weather, weather1.current_weather,
		"restore_world() muss das gespeicherte Wetter übernehmen.")

func test_restore_world_without_weather_in_snapshot_does_not_crash() -> void:
	# Alt-Save ohne Wetter-Keys (vor Round 95) — WeatherService.restore() muss
	# defensiv auf den Default zurückfallen, kein KeyError.
	var legacy_snapshot := _handler.get_save_data()
	assert_false(legacy_snapshot.has("weather"))

	var data2 := WorldData.new()
	var time2 := WorldTimeService.new()
	var weather2 := WeatherService.new()
	var h2 := WorldSaveHandler.new(data2, time2, weather2)
	h2.restore_world(legacy_snapshot)
	assert_eq(weather2.current_weather, WeatherService.DEFAULT_WEATHER,
		"Alt-Save ohne Wetter-Keys muss auf den Default zurückfallen.")

# ─────────────────────────────────────────────────────────────────────────────
# restore_world
# ─────────────────────────────────────────────────────────────────────────────

func test_restore_trees() -> void:
	_data.add_typed_tree("oak_tree", POS_TREE_1)
	_data.add_typed_tree("oak_tree", POS_TREE_2)
	var snapshot := _handler.get_save_data()

	# Neue Instanzen
	var data2 := WorldData.new()
	var time2 := WorldTimeService.new()
	var h2    := WorldSaveHandler.new(data2, time2)
	h2.restore_world(snapshot)

	assert_eq(data2.get_tree_count(), 2, "Zwei Bäume müssen wiederhergestellt sein")

func test_restore_ores() -> void:
	_data.add_typed_ore("iron_ore", POS_ORE_1)
	var snapshot := _handler.get_save_data()

	var data2 := WorldData.new()
	var time2 := WorldTimeService.new()
	var h2    := WorldSaveHandler.new(data2, time2)
	h2.restore_world(snapshot)

	assert_eq(data2.get_ore_count(), 1, "Ein Erz muss wiederhergestellt sein")

func test_restore_player_position() -> void:
	_data.player_position = POS_PLAYER
	var snapshot := _handler.get_save_data()

	var data2 := WorldData.new()
	var time2 := WorldTimeService.new()
	var h2    := WorldSaveHandler.new(data2, time2)
	h2.restore_world(snapshot)

	assert_almost_eq(data2.player_position.x, POS_PLAYER.x, 0.01, "X-Koordinate muss passen")
	assert_almost_eq(data2.player_position.z, POS_PLAYER.z, 0.01, "Z-Koordinate muss passen")

func test_restore_day_time() -> void:
	_time.day_time  = 18.0
	_time.day_count = 7
	var snapshot := _handler.get_save_data()

	var data2 := WorldData.new()
	var time2 := WorldTimeService.new()
	var h2    := WorldSaveHandler.new(data2, time2)
	h2.restore_world(snapshot)

	assert_almost_eq(time2.day_time,  18.0, 0.01, "Tageszeit muss 18.0 sein")
	assert_eq(        time2.day_count, 7,          "Tagzähler muss 7 sein")

func test_restore_world_seed() -> void:
	## Regressionstest: world_seed wurde früher nicht persistiert — jede geladene
	## Welt bekam dadurch einen neuen Zufallsseed statt des gespeicherten.
	_data.world_seed = 123456789
	var snapshot := _handler.get_save_data()

	var data2 := WorldData.new()
	var time2 := WorldTimeService.new()
	var h2    := WorldSaveHandler.new(data2, time2)
	h2.restore_world(snapshot)

	assert_eq(data2.world_seed, 123456789, "world_seed muss nach Round-Trip erhalten bleiben")

# ─────────────────────────────────────────────────────────────────────────────
# Save-Round-Trip (A-04)
# ─────────────────────────────────────────────────────────────────────────────

## Save-Round-Trip mit neuem Key-Pfad (P0-Fix):
## mark_harvested via WorldData.make_key() — der Pfad den HarvestableEntity.on_despawn() geht.
## Stellt sicher dass der neue API-Pfad bei Save/Load korrekt round-trippt.
func test_round_trip_new_key_path_oak_tree() -> void:
	_data.add_typed_tree("oak_tree", POS_TREE_1)
	# Neuer Pfad: WorldService.mark_harvested() → WorldData.mark_harvested(make_key(...))
	_data.mark_harvested(WorldData.make_key("oak_tree", POS_TREE_1))

	var snapshot := _handler.get_save_data()

	var data2 := WorldData.new()
	var time2 := WorldTimeService.new()
	var h2    := WorldSaveHandler.new(data2, time2)
	h2.restore_world(snapshot)

	# Nach Restore: is_harvested_by_type() muss den Key finden (nicht is_tree_harvested,
	# das wäre trivial — wir testen is_harvested_by_type direkt).
	assert_true(
		data2.is_harvested_by_type("oak_tree", POS_TREE_1),
		"P0: is_harvested_by_type('oak_tree') muss nach Round-Trip via make_key() True sein"
	)

func test_round_trip_new_key_path_copper_ore() -> void:
	## Neuer Typ (copper_ore) der vorher gar nicht getestet wurde.
	var pos := Vector3(-2, 0, 8)
	_data.add_typed_ore("copper_ore", pos)
	_data.mark_harvested(WorldData.make_key("copper_ore", pos))

	var snapshot := _handler.get_save_data()

	var data2 := WorldData.new()
	var time2 := WorldTimeService.new()
	var h2    := WorldSaveHandler.new(data2, time2)
	h2.restore_world(snapshot)

	assert_true(
		data2.is_harvested_by_type("copper_ore", pos),
		"P0: copper_ore-Key muss nach Round-Trip via make_key() in is_harvested_by_type() gefunden werden"
	)

func test_round_trip_make_key_and_legacy_dont_alias() -> void:
	## Stellt sicher dass make_key("oak_tree", pos) und der alte "tree_x_y_z"-Key
	## nicht dieselbe Entry sind — sonst wäre das ein stiller false-positive.
	var data2 := WorldData.new()
	var pos   := Vector3(5, 0, 5)
	data2.mark_harvested(WorldData.make_key("oak_tree", pos))
	# Der alte Key war "tree_5_0_5" — der neue ist "oak_tree_5_0_5"
	assert_false(
		data2.harvested_objects.has("tree_5_0_5"),
		"Neues Key-Schema darf den alten 'tree_x_y_z'-Schlüssel nicht setzen (kein Alias)"
	)
	assert_true(
		data2.harvested_objects.has("oak_tree_5_0_5"),
		"Neues Key-Schema muss 'oak_tree_5_0_5' schreiben"
	)

func test_round_trip_full_state_after_restore() -> void:
	# Phase 1: State befüllen
	_data.add_typed_tree("oak_tree", POS_TREE_1)
	_data.add_typed_tree("oak_tree", POS_TREE_2)
	_data.add_typed_ore("iron_ore", POS_ORE_1)
	_data.player_position = POS_PLAYER
	_data.mark_harvested(WorldData.make_key("oak_tree", POS_TREE_1))
	_time.day_time  = 12.0
	_time.day_count = 5

	var snapshot := _handler.get_save_data()

	# Phase 2: neue Instanzen + Restore
	var data2 := WorldData.new()
	var time2 := WorldTimeService.new()
	var h2    := WorldSaveHandler.new(data2, time2)
	h2.restore_world(snapshot)

	assert_eq(data2.get_tree_count(), 2,    "2 Bäume nach Round-Trip")
	assert_eq(data2.get_ore_count(),  1,    "1 Erz nach Round-Trip")
	assert_almost_eq(time2.day_time,       12.0, 0.01, "Tageszeit 12.0 nach Round-Trip")
	assert_eq(time2.day_count,             5,    "Tagzähler 5 nach Round-Trip")
	assert_true(data2.is_harvested_by_type("oak_tree", POS_TREE_1),
		"Geernteter Baum muss nach Round-Trip markiert sein")

# ─────────────────────────────────────────────────────────────────────────────
# Gelände-Änderungen + Bauteile (Umgraben/Bauen)
# ─────────────────────────────────────────────────────────────────────────────

func test_save_data_has_terrain_and_build_keys() -> void:
	var sd := _handler.get_save_data()
	assert_true(sd.has("terrain_edits"), "terrain_edits muss im Snapshot sein")
	assert_true(sd.has("build_pieces"), "build_pieces muss im Snapshot sein")

func test_terrain_edits_roundtrip() -> void:
	_data.terrain_edits.set_delta(Vector2i(3, -4), -1.5)
	_data.terrain_edits.set_delta(Vector2i(-8, 9), 0.75)
	var sd := _handler.get_save_data()

	var data2 := WorldData.new()
	var handler2 := WorldSaveHandler.new(data2, WorldTimeService.new())
	handler2.restore_world(sd)
	assert_eq(data2.terrain_edits.get_edit_count(), 2)
	assert_eq(data2.terrain_edits.get_delta_lattice(3, -4), -1.5)
	assert_eq(data2.terrain_edits.get_delta_lattice(-8, 9), 0.75)

func test_build_pieces_roundtrip() -> void:
	_data.build_registry.add({"key": "F_1_2", "piece_id": "wood_floor", "kind": 0,
		"x": 3.0, "y": 1.25, "z": 5.0, "yaw": 0.0, "owner": "p1"})
	var sd := _handler.get_save_data()

	var data2 := WorldData.new()
	var handler2 := WorldSaveHandler.new(data2, WorldTimeService.new())
	handler2.restore_world(sd)
	assert_eq(data2.build_registry.count(), 1)
	assert_eq(data2.build_registry.get_record("F_1_2")["y"], 1.25)

func test_restore_keeps_instances_so_references_stay_valid() -> void:
	var edits_before := _data.terrain_edits
	var registry_before := _data.build_registry
	_data.terrain_edits.set_delta(Vector2i(1, 1), -1.0)
	_handler.restore_world(_handler.get_save_data())
	assert_same(_data.terrain_edits, edits_before, "TerrainField hält diese Referenz — sie darf nicht ausgetauscht werden.")
	assert_same(_data.build_registry, registry_before)

func test_restore_of_old_save_without_new_keys_clears_state() -> void:
	# Älterer Spielstand kennt die Keys nicht → leerer Zustand, kein Crash.
	_data.terrain_edits.set_delta(Vector2i(1, 1), -1.0)
	var old_state := {"day_time": 0.5, "day_count": 2}
	_handler.restore_world(old_state)
	assert_true(_data.terrain_edits.is_empty())
	assert_eq(_data.build_registry.count(), 0)

func test_ladders_and_dig_finds_roundtrip() -> void:
	_data.dig_finds.add({"key": "F_1", "kind": "gem_ruby", "x": 3.0, "y": -12.0, "z": 5.0})
	_data.ladders.add({
		"key": "L_1", "x": 0.0, "y": -10.0, "z": 0.0,
		"pts": PackedFloat32Array([0.0, -10.0, 0.0, 0.0, -5.0, 1.0]),
		"dx": 0.0, "dz": 1.0, "ex": 0.0, "ey": 0.0, "ez": 2.0, "bx": 0.0, "by": -10.0, "bz": -0.7,
	})
	var sd := _handler.get_save_data()
	var data2 := WorldData.new()
	WorldSaveHandler.new(data2, WorldTimeService.new()).restore_world(sd)
	assert_eq(data2.dig_finds.count(), 1)
	assert_eq(data2.ladders.count(), 1)

# ─────────────────────────────────────────────────────────────────────────────
# BUG-C: Spieler-HP (Round-Trip)
# ─────────────────────────────────────────────────────────────────────────────

func test_save_data_has_player_health_key() -> void:
	var sd := _handler.get_save_data()
	assert_true(sd.has("player_health"), "player_health muss im Snapshot sein")

func test_player_health_roundtrip() -> void:
	## Regressionstest: HP wurde vorher überhaupt nicht persistiert (BUG-C —
	## PlayerStats.gd war totes Feature, HealthComponent hatte keine
	## Save/Load-Logik). data.player_health ist jetzt die einzige Quelle.
	_data.player_health = {
		"player-uuid-1": {"current": 12, "max": 50},
		"player-uuid-2": {"current": 50, "max": 50},
	}
	var sd := _handler.get_save_data()

	var data2 := WorldData.new()
	var time2 := WorldTimeService.new()
	var h2    := WorldSaveHandler.new(data2, time2)
	h2.restore_world(sd)

	assert_eq((data2.player_health["player-uuid-1"] as Dictionary)["current"], 12,
		"Aktuelle HP von Spieler 1 müssen nach Round-Trip erhalten bleiben")
	assert_eq((data2.player_health["player-uuid-2"] as Dictionary)["max"], 50,
		"Max-HP von Spieler 2 müssen nach Round-Trip erhalten bleiben")

func test_restore_of_old_save_without_player_health_key_defaults_empty() -> void:
	## Alt-Save ohne player_health-Key (vor BUG-C-Fix) — muss auf leeres
	## Dictionary zurückfallen statt zu crashen (identisches Muster wie
	## test_restore_of_old_save_without_new_keys_clears_state()).
	var old_state := {"day_time": 0.5, "day_count": 2}
	_handler.restore_world(old_state)
	assert_eq(_data.player_health, {}, "player_health muss ohne Key leer bleiben")
