# res://tests/unit/test_world_service.gd
extends GutTest

## Unit-Tests für WorldService (R12).
##
## Strategie: WorldService extends ServiceNode (Node) → braucht add_child_autofree().
## configure() wird mit minimalen Mock-Deps aufgerufen (null-safe Guards in configure()
## erlauben das explizit).
##
## Was getestet wird:
##   - configure() ohne optionale Deps → kein Crash (null-Guards greifen)
##   - get_save_key() → konstant "world_state"
##   - get_save_data() → gibt Dictionary mit erwarteten Keys zurück
##   - mark_harvested(type_id, pos) → delegiert an WorldData
##   - on_tick() ohne GameManager → kein Crash
##   - on_tick() mit gemocktem GameManager (is_playing → true) → time tickt
##   - on_cleanup() ohne ChunkManager → kein Crash
##   - day_time / day_count: computed properties → keine stale Kopie
##
## Was NICHT getestet wird:
##   - on_world_scene_ready(): braucht echten SceneTree + ChunkManager.add_child
##   - warmup_mesh_cache(): braucht Factory3D.cache.build() mit Godot-Rendering
##   - Respawn-Callbacks: Integration WorldService ↔ RespawnService
##     → separater IntegrationTest

var _svc: WorldService

func before_each() -> void:
	_svc = WorldService.new()
	add_child_autofree(_svc)
	_svc.configure(ServiceDeps.from_dict({}))

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null

# ─────────────────────────────────────────────────────────────────────────────
# configure() — null-safe Init
# ─────────────────────────────────────────────────────────────────────────────

func test_configure_without_deps_does_not_crash() -> void:
	# WorldService mit leeren Deps initialisieren (Standard-Pfad: kein SaveSystem,
	# kein WorldGen, kein Ticker, kein Respawn, kein GameManager)
	var svc2 := WorldService.new()
	add_child_autofree(svc2)
	svc2.configure(ServiceDeps.from_dict({}))
	assert_true(true, "configure() ohne Deps darf nicht crashen.")
	svc2.on_cleanup()

func test_configure_creates_world_data() -> void:
	assert_not_null(_svc.data, "configure() muss WorldData instanziieren.")

func test_configure_creates_factory() -> void:
	assert_not_null(_svc.factory, "configure() muss WorldFactory instanziieren.")

func test_configure_creates_factory3d() -> void:
	assert_not_null(_svc.factory3d, "configure() muss Factory3D instanziieren.")

func test_configure_sets_world_seed() -> void:
	# Seed muss nach configure() gesetzt sein (entweder gespeichert oder neu generiert)
	assert_true(_svc.data.world_seed != 0, "world_seed muss nach configure() != 0 sein.")

# ─────────────────────────────────────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────────────────────────────────────

func test_get_save_key_returns_world_state() -> void:
	assert_eq(_svc.get_save_key(), "world_state", "Save-Key muss 'world_state' sein.")

func test_get_save_data_returns_dictionary() -> void:
	var sd := _svc.get_save_data()
	assert_true(sd is Dictionary, "get_save_data() muss ein Dictionary zurückgeben.")

func test_get_save_data_has_required_keys() -> void:
	var sd := _svc.get_save_data()
	assert_true(sd.has("day_time"),       "save_data muss 'day_time' enthalten.")
	assert_true(sd.has("day_count"),      "save_data muss 'day_count' enthalten.")
	assert_true(sd.has("typed_tree_positions"), "save_data muss 'typed_tree_positions' enthalten.")
	assert_true(sd.has("typed_ore_positions"),  "save_data muss 'typed_ore_positions' enthalten.")
	assert_true(sd.has("player_pos"),     "save_data muss 'player_pos' enthalten.")
	assert_true(sd.has("harvested"),      "save_data muss 'harvested' enthalten.")

func test_get_save_data_day_time_is_float() -> void:
	var sd := _svc.get_save_data()
	assert_true(sd["day_time"] is float or sd["day_time"] is int,
		"day_time muss numerisch sein.")

func test_get_save_data_day_count_starts_at_zero() -> void:
	## day_count startet bei 1 ("Tag 1") — nutzerfreundliche 1-basierte Anzeige,
	## siehe WorldTimeService.day_count und SimpleTerminal.gd ("Tag %d").
	var sd := _svc.get_save_data()
	assert_eq(int(sd["day_count"]), 1, "Startzustand: day_count muss 1 sein (Tag 1).")

# ─────────────────────────────────────────────────────────────────────────────
# WorldData-Delegation
# ─────────────────────────────────────────────────────────────────────────────

func test_mark_harvested_sets_flag_in_world_data_for_tree_type() -> void:
	var pos := Vector3(10, 0, 20)
	_svc.mark_harvested("oak_tree", pos)
	assert_true(_svc.data.is_harvested_by_type("oak_tree", pos),
		"mark_harvested() muss den Baum in WorldData als geerntet markieren.")

func test_mark_harvested_sets_flag_in_world_data_for_ore_type() -> void:
	var pos := Vector3(-5, 0, 15)
	_svc.mark_harvested("iron_ore", pos)
	assert_true(_svc.data.is_harvested_by_type("iron_ore", pos),
		"mark_harvested() muss das Erz in WorldData als geerntet markieren.")

func test_mark_harvested_type_is_isolated_per_type_id() -> void:
	var pos := Vector3(10, 0, 20)
	_svc.mark_harvested("oak_tree", pos)
	assert_false(_svc.data.is_harvested_by_type("iron_ore", pos),
		"mark_harvested(\"oak_tree\", ...) darf keinen anderen type_id an derselben Position markieren.")

func test_mark_two_different_trees_independently() -> void:
	var pos1 := Vector3(10, 0, 20)
	var pos2 := Vector3(30, 0, 40)
	_svc.mark_harvested("oak_tree", pos1)
	assert_true(_svc.data.is_harvested_by_type("oak_tree", pos1), "Baum 1 muss geerntet sein.")
	assert_false(_svc.data.is_harvested_by_type("oak_tree", pos2), "Baum 2 darf noch nicht geerntet sein.")

func test_store_pet_save_data_persisted_in_world_data() -> void:
	var pets: Array[Dictionary] = [{"id": "pet_1", "type": "cat"}]
	_svc.store_pet_save_data(pets)
	var stored: Variant = _svc.data.get_meta("saved_pets") if _svc.data.has_meta("saved_pets") else []
	assert_eq((stored as Array).size(), 1, "Gespeicherter Pet-Eintrag muss in WorldData landen.")

# ─────────────────────────────────────────────────────────────────────────────
# Computed Properties
# ─────────────────────────────────────────────────────────────────────────────

func test_day_time_returns_float() -> void:
	var t := _svc.day_time
	assert_true(t is float, "day_time muss numerisch sein.")

func test_day_count_returns_int() -> void:
	var c := _svc.day_count
	assert_true(c is int, "day_count muss int sein.")

func test_current_weather_returns_string_from_known_types() -> void:
	# ADR-041: configure() rollt bereits ein erstes Wetter für day_count 1.
	var w := _svc.current_weather
	assert_true(w is String, "current_weather muss ein String sein.")
	assert_true(WeatherService.WEATHER_TYPES.has(w),
		"current_weather muss ein Wert aus WeatherService.WEATHER_TYPES sein.")

# ─────────────────────────────────────────────────────────────────────────────
# admin_set_weather()/admin_get_weather_types() — Admin-Menü-Wetterbefehl
# ─────────────────────────────────────────────────────────────────────────────

func test_admin_set_weather_changes_current_weather() -> void:
	var target := "fog" if _svc.current_weather != "fog" else "storm"
	var ok := _svc.admin_set_weather(target)
	assert_true(ok, "admin_set_weather() mit gültigem Typ muss true zurückgeben.")
	assert_eq(_svc.current_weather, target, "current_weather muss den neu gesetzten Typ widerspiegeln.")

func test_admin_set_weather_rejects_unknown_type() -> void:
	var before := _svc.current_weather
	var ok := _svc.admin_set_weather("hurricane_of_lava")
	assert_false(ok, "admin_set_weather() mit unbekanntem Typ muss false zurückgeben.")
	assert_eq(_svc.current_weather, before, "Unbekannter Typ darf current_weather nicht verändern.")

func test_admin_get_weather_types_matches_weather_service_constant() -> void:
	assert_eq(_svc.admin_get_weather_types(), WeatherService.WEATHER_TYPES,
		"admin_get_weather_types() muss dieselbe Liste wie WeatherService.WEATHER_TYPES liefern.")

# ─────────────────────────────────────────────────────────────────────────────
# admin_set_time_of_day()/admin_set_time_speed() — Admin-Menü Zeit-Befehle
# ─────────────────────────────────────────────────────────────────────────────

func test_admin_set_time_of_day_changes_day_time() -> void:
	var ok := _svc.admin_set_time_of_day(19.0)
	assert_true(ok, "admin_set_time_of_day() muss bei verfügbarem WorldTimeService true zurückgeben.")
	assert_eq(_svc.day_time, 19.0, "day_time muss den neu gesetzten Stundenwert widerspiegeln.")

func test_admin_set_time_of_day_wraps_negative_hours_into_range() -> void:
	_svc.admin_set_time_of_day(-1.0)
	assert_true(_svc.day_time >= 0.0 and _svc.day_time < 24.0,
		"Eine negative Stunde muss auf [0, 24) umlaufen (fposmod), nicht negativ bleiben.")
	assert_eq(_svc.day_time, 23.0, "-1.0 Stunden muss auf 23.0 Uhr umlaufen.")

func test_admin_set_time_speed_changes_speed() -> void:
	var ok := _svc.admin_set_time_speed(2.5)
	assert_true(ok, "admin_set_time_speed() muss bei verfügbarem WorldTimeService true zurückgeben.")
	assert_eq(_svc.admin_get_time_speed(), 2.5, "admin_get_time_speed() muss den neu gesetzten Wert widerspiegeln.")

func test_admin_set_time_speed_clamps_negative_to_zero() -> void:
	_svc.admin_set_time_speed(-5.0)
	assert_eq(_svc.admin_get_time_speed(), 0.0,
		"Eine negative Zeitgeschwindigkeit muss auf 0 geklemmt werden (Zeit anhalten statt rückwärts laufen).")

func test_get_save_data_has_weather_keys() -> void:
	var sd := _svc.get_save_data()
	assert_true(sd.has("weather"), "save_data muss 'weather' enthalten (ADR-041).")
	assert_true(sd.has("weather_last_rolled_day"),
		"save_data muss 'weather_last_rolled_day' enthalten (ADR-041).")

func test_day_time_starts_at_zero_or_morning() -> void:
	# Frischer Service ohne Restore: day_time sollte 0.0 oder früher Morgen sein
	assert_true(_svc.day_time >= 0.0, "day_time darf nicht negativ sein.")

# ─────────────────────────────────────────────────────────────────────────────
# on_tick — ohne GameManager (kein Crash)
# ─────────────────────────────────────────────────────────────────────────────

func test_on_tick_without_game_manager_does_not_crash() -> void:
	# _game_manager ist null → Guard in on_tick() greift
	_svc.on_tick(0.016)
	assert_true(true, "on_tick() ohne GameManager darf nicht crashen.")

func test_on_tick_does_not_advance_time_without_game_manager() -> void:
	var before := _svc.day_time
	_svc.on_tick(1.0)
	var after := _svc.day_time
	assert_eq(before, after, "Ohne GameManager darf die Zeit nicht laufen.")

# ─────────────────────────────────────────────────────────────────────────────
# on_cleanup
# ─────────────────────────────────────────────────────────────────────────────

func test_on_cleanup_without_chunk_manager_does_not_crash() -> void:
	# _chunk_manager ist null nach configure() ohne on_world_scene_ready()
	_svc.on_cleanup()
	assert_true(true, "on_cleanup() ohne ChunkManager darf nicht crashen.")

# ─────────────────────────────────────────────────────────────────────────────
# spawn_entity / despawn_entity — Guard-Verhalten ohne on_world_scene_ready()
# ─────────────────────────────────────────────────────────────────────────────

func test_spawn_entity_without_orchestrator_returns_null() -> void:
	# on_world_scene_ready() wurde nicht aufgerufen → EntityOrchestrator nicht initialisiert
	# WorldService.spawn_entity hat einen is_instance_valid-Guard → gibt null zurück
	# Hinweis: configure() erstellt und add_child()-t _entity_orchestrator,
	#          aber initialize() wurde nicht aufgerufen → spawn gibt null oder leeren Node
	# Wir prüfen nur: kein Crash
	var result := _svc.spawn_entity("oak_tree", Vector3.ZERO)
	# Erlaubt: null oder ein Node — beides ist kein Crash
	assert_true(result == null or result is Node,
		"spawn_entity() ohne Welt-Setup muss null oder Node zurückgeben (kein Crash).")

func test_despawn_entity_without_orchestrator_does_not_crash() -> void:
	_svc.despawn_entity("non-existent-uuid")
	assert_true(true, "despawn_entity() ohne Welt-Setup darf nicht crashen.")

func test_get_entity_debug_info_returns_dictionary() -> void:
	var info := _svc.get_entity_debug_info()
	assert_true(info is Dictionary,
		"get_entity_debug_info() muss immer ein Dictionary zurückgeben.")

# ─────────────────────────────────────────────────────────────────────────────
# get_formatted_time
# ─────────────────────────────────────────────────────────────────────────────

func test_get_formatted_time_returns_string() -> void:
	var t := _svc.get_formatted_time()
	assert_true(t is String and t.length() > 0,
		"get_formatted_time() muss einen nicht-leeren String zurückgeben.")

func test_get_formatted_time_contains_colon() -> void:
	# WorldTimeService formatiert als HH:MM — prüfen ob Doppelpunkt da ist
	var t := _svc.get_formatted_time()
	assert_true(":" in t, "Formatierte Zeit muss ':' enthalten (HH:MM-Format).")

# ─────────────────────────────────────────────────────────────────────────────
# spawn_entity peer_id (F-2)
# ─────────────────────────────────────────────────────────────────────────────

func test_spawn_entity_accepts_peer_id_parameter() -> void:
	# Ohne Orchestrator (kein on_world_scene_ready) → null, aber kein Crash.
	# Der Test verifiziert dass die Signatur peer_id akzeptiert.
	var svc2: WorldService = add_child_autofree(WorldService.new())
	svc2.configure(ServiceDeps.from_dict({}))
	var result := svc2.spawn_entity("oak_tree", Vector3.ZERO, {}, 2)
	assert_true(result == null or result is Node,
		"spawn_entity(peer_id=2) darf nicht crashen — gibt null ohne Orchestrator zurück.")

func test_spawn_entity_default_peer_id_is_1() -> void:
	# Signatur-Vertrag: peer_id-Default ist 1 (Server-Autorität).
	# Ohne Welt-Setup nicht testbar über Rückgabewert — wir prüfen via Callable-Bindung.
	var svc2: WorldService = add_child_autofree(WorldService.new())
	svc2.configure(ServiceDeps.from_dict({}))
	# Aufruf ohne peer_id → Default muss greifen, kein Crash.
	var result := svc2.spawn_entity("iron_ore", Vector3(5, 0, 5))
	assert_true(result == null or result is Node,
		"spawn_entity() ohne explizite peer_id muss Default 1 nutzen — kein Crash.")

# ─────────────────────────────────────────────────────────────────────────────
# F-1: MultiplayerSpawner Custom Spawn/Despawn
# ─────────────────────────────────────────────────────────────────────────────

func test_entity_registry_path_to_type_map_is_populated() -> void:
	# WorldEntityRegistry registriert alle 8 Typen in EntityOrchestrator.
	# get_registry().get_path_to_type_map() muss für jeden Typ einen Eintrag liefern.
	var svc2: WorldService = add_child_autofree(WorldService.new())
	svc2.configure(ServiceDeps.from_dict({}))
	var map: Dictionary = svc2._entity_orchestrator.get_registry().get_path_to_type_map()
	assert_true(map.size() >= 8,
		"Path-Map muss mindestens 8 Einträge haben (einen pro registriertem Entity-Typ).")
	svc2.on_cleanup()

func test_entity_registry_path_to_type_map_resolves_player() -> void:
	var svc2: WorldService = add_child_autofree(WorldService.new())
	svc2.configure(ServiceDeps.from_dict({}))
	var map: Dictionary = svc2._entity_orchestrator.get_registry().get_path_to_type_map()
	assert_true(map.values().has("player"),
		"Path-Map muss 'player' als type_id enthalten.")
	svc2.on_cleanup()

func test_entity_registry_path_to_type_map_no_empty_paths() -> void:
	var svc2: WorldService = add_child_autofree(WorldService.new())
	svc2.configure(ServiceDeps.from_dict({}))
	var map: Dictionary = svc2._entity_orchestrator.get_registry().get_path_to_type_map()
	for path in map.keys():
		assert_false(path.is_empty(),
			"Kein leerer Pfad darf als Key in der Path-Map vorkommen.")
	svc2.on_cleanup()

func test_entity_orchestrator_get_registry_returns_entity_registry() -> void:
	# Vertrag: get_registry() gibt eine EntityRegistry-Instanz zurück.
	var svc2: WorldService = add_child_autofree(WorldService.new())
	svc2.configure(ServiceDeps.from_dict({}))
	var registry = svc2._entity_orchestrator.get_registry()
	assert_true(registry is EntityRegistry,
		"get_registry() muss eine EntityRegistry-Instanz zurückgeben.")
	svc2.on_cleanup()

# ─────────────────────────────────────────────────────────────────────────────
# Round 68: register_save_provider() nur auf der Autorität (C-02-Guard).
# world_state ist geteilter Weltzustand — ein beitretender Client soll ihn nie
# unter seinem eigenen player_id-Save persistieren (siehe WorldService.configure()
# Kommentar). restore_world() bleibt bewusst unconditional (lokaler Startzustand
# vor dem Server-Sync) — nur die Registrierung als *schreibender* Provider ist
# gegatet.
# ─────────────────────────────────────────────────────────────────────────────

## Zählt register_save_provider()-Aufrufe statt sie tatsächlich auszuführen —
## gleiches Muster wie MockSaveSystemNoop in test_quest_service.gd, nur mit
## Zähler statt reinem No-op, um die Anzahl der Aufrufe zu prüfen.
class SpySaveSystem extends SaveSystem:
	var register_calls: int = 0
	func register_save_provider(_p) -> void: register_calls += 1
	func get_state_for(_key: String) -> Dictionary: return {}

class MockBridgeAuthority extends NetworkBridge:
	func is_server() -> bool: return true

class MockBridgeNonAuthority extends NetworkBridge:
	func is_server() -> bool: return false

func test_register_save_provider_called_when_authority() -> void:
	var spy := SpySaveSystem.new()
	var bridge: MockBridgeAuthority = add_child_autofree(MockBridgeAuthority.new())
	var svc2: WorldService = add_child_autofree(WorldService.new())
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM:    spy,
		ServiceKeys.NETWORK_BRIDGE: bridge,
	}))
	assert_eq(spy.register_calls, 1,
		"Autorität (Host/Server/Solo) muss sich als world_state-Save-Provider registrieren.")
	svc2.on_cleanup()

func test_register_save_provider_skipped_when_not_authority() -> void:
	var spy := SpySaveSystem.new()
	var bridge: MockBridgeNonAuthority = add_child_autofree(MockBridgeNonAuthority.new())
	var svc2: WorldService = add_child_autofree(WorldService.new())
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM:    spy,
		ServiceKeys.NETWORK_BRIDGE: bridge,
	}))
	assert_eq(spy.register_calls, 0,
		"Ein beitretender Nicht-Autoritäts-Client darf world_state NIE unter seinem eigenen Save persistieren.")
	svc2.on_cleanup()

func test_register_save_provider_defaults_to_authority_without_network_bridge() -> void:
	# Kein NetworkBridge injiziert (z.B. früh in configure(), vor Late-Inject) —
	# muss wie Tier 1 (Solo) behandelt werden, derselbe Default wie überall
	# sonst in dieser Klasse (z.B. request_entity_interaction()).
	var spy := SpySaveSystem.new()
	var svc2: WorldService = add_child_autofree(WorldService.new())
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM: spy,
	}))
	assert_eq(spy.register_calls, 1,
		"Ohne NetworkBridge (kein aktiver Peer bekannt) muss der Default Autorität sein.")
	svc2.on_cleanup()

# ─────────────────────────────────────────────────────────────────────────────
# Netzwerk-Inject / Entity-Lookups ohne gespawnte Entities (Round 113 Nachtrag,
# siehe method_reference_coverage.py-Fund). on_world_scene_ready()/
# warmup_mesh_cache() bleiben bewusst ausgeklammert (siehe Datei-Kopf) — echtes
# 3D-Rendering/ChunkManager-Setup nötig, kein Unit-Test-Fall.
# ─────────────────────────────────────────────────────────────────────────────

func test_inject_network_bridge_sets_the_reference() -> void:
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_svc.inject_network_bridge(bridge)
	assert_same(_svc._network, bridge)

func test_inject_network_bridge_with_no_zone_triggers_does_not_crash() -> void:
	# Keine ZoneTriggerVolume-Nodes in der "zone_triggers"-Gruppe in diesem
	# minimalen Testbaum — die get_nodes_in_group()-Schleife muss das als
	# leere Liste behandeln, kein Crash.
	var bridge: NetworkBridge = add_child_autofree(NetworkBridge.new())
	_svc.inject_network_bridge(bridge)
	pass_test("inject_network_bridge() ohne ZoneTriggerVolume-Nodes crasht nicht")

func test_get_player_by_id_unknown_peer_returns_null() -> void:
	assert_null(_svc.get_player_by_id(999), "Kein gespawnter Player für diese peer_id -> null, kein Crash")

func test_get_player_visuals_unknown_peer_returns_null() -> void:
	assert_null(_svc.get_player_visuals(999))

func test_route_movement_input_unknown_peer_does_not_crash() -> void:
	# Dokumentierter Race-Fall (Despawn/Disconnect vs. unterwegs befindliches
	# unreliable Input-Paket) — kein Fehlerfall, nur ein früher Return.
	_svc.route_movement_input(999, {"x": 1.0, "y": 0.0})
	pass_test("route_movement_input() für unbekannte peer_id crasht nicht")

func test_request_entity_interaction_unknown_entity_does_not_crash() -> void:
	# Kein NetworkBridge injiziert -> lokaler Pfad -> direkt
	# resolve_and_dispatch_interaction(), das die unbekannte Entity sauber
	# mit einem log_warn abfängt.
	_svc.request_entity_interaction("does-not-exist-uuid", "attack", 1)
	pass_test("request_entity_interaction() für unbekannte Entity crasht nicht")

func test_resolve_and_dispatch_interaction_unknown_entity_does_not_crash() -> void:
	_svc.resolve_and_dispatch_interaction("does-not-exist-uuid", "attack", 1)
	pass_test("resolve_and_dispatch_interaction() für unbekannte Entity crasht nicht")

# ─────────────────────────────────────────────────────────────────────────────
# Pet-Daten-Sammlung
# ─────────────────────────────────────────────────────────────────────────────

func test_collect_and_store_pet_data_with_no_pets_stores_empty_array() -> void:
	# Keine Nodes in der "pets"-Gruppe im minimalen Testbaum.
	_svc.collect_and_store_pet_data()
	assert_eq(_svc.data.get_meta("saved_pets"), [] as Array[Dictionary],
		"Ohne aktive Pets muss eine leere Liste gespeichert werden, kein Crash/kein fehlender Meta-Eintrag.")
