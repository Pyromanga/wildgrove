# res://tests/unit/test_zone_trigger_volume.gd
extends GutTest

## Unit-Tests für ZoneTriggerVolume (ADR-030).
##
## Strategie: Spy-ZoneService (analog zu QuestCustomTrigger-Tests' MockNetworkBridge)
## — prüft NUR, DASS und mit welchen Argumenten report_enter()/report_exit()
## aufgerufen werden, keine echte ZoneService-Logik involviert.
##
## Abgedeckt:
##   - inject_zone_service(): setzt _zone_service UND registriert zone_config
##   - Enter/Exit für Spieler-Body meldet an ZoneService
##   - Nicht-Spieler-Body wird ignoriert
##   - Ohne zone_config / ohne zone_id: keine Meldung
##   - Ohne injizierten ZoneService: kein Crash
##   - Autoritäts-Guard: Nicht-Autorität meldet nie (anders als QuestCustomTrigger
##     KEINE "eigener Spieler"-Ausnahme, siehe ZoneTriggerVolume-Klassenkommentar)
##   - owner_peer_id-Meta wird korrekt durchgereicht (kein stiller Default-1-Bug)

class SpyZoneService extends ZoneService:
	var entered: Array[Dictionary] = []
	var exited:  Array[Dictionary] = []
	var registered_configs: Array[ZoneConfig] = []
	func report_enter(peer_id: int, zone_id: StringName) -> void:
		entered.append({"peer_id": peer_id, "zone_id": zone_id})
	func report_exit(peer_id: int, zone_id: StringName) -> void:
		exited.append({"peer_id": peer_id, "zone_id": zone_id})
	func register_zone_config(config: ZoneConfig) -> void:
		registered_configs.append(config)

## Analog zu test_quest_custom_trigger.gds MockNetworkBridge — Authority
## steuerbar ohne echten SceneTree/multiplayer-Zustand.
class MockNetworkBridge extends NetworkBridge:
	var _force_is_server: bool = true
	func is_server() -> bool:
		return _force_is_server

func _make_trigger(zone_id: StringName = &"pvp_north", tags: Array[StringName] = []) -> ZoneTriggerVolume:
	var t := ZoneTriggerVolume.new()
	if zone_id != &"":
		var config := ZoneConfig.new()
		config.zone_id = zone_id
		config.tags = tags
		t.zone_config = config
	add_child_autofree(t)
	return t

func _make_player_body(owner_peer_id: int = -1) -> Node3D:
	var p := Node3D.new()
	p.add_to_group("player")
	if owner_peer_id != -1:
		p.set_meta("owner_peer_id", owner_peer_id)
	add_child_autofree(p)
	return p

func _make_non_player_body() -> Node3D:
	var p := Node3D.new()
	add_child_autofree(p)
	return p

# ─────────────────────────────────────────────────────────────────────────────
# inject_zone_service()
# ─────────────────────────────────────────────────────────────────────────────

func test_inject_zone_service_sets_field() -> void:
	var t := _make_trigger()
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	assert_eq(t._zone_service, svc)

func test_inject_zone_service_registers_zone_config() -> void:
	var t := _make_trigger(&"pvp_north")
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	assert_eq(svc.registered_configs.size(), 1)
	assert_eq(svc.registered_configs[0], t.zone_config)

func test_inject_zone_service_without_config_does_not_register() -> void:
	var t := ZoneTriggerVolume.new()  # kein zone_config gesetzt
	add_child_autofree(t)
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	assert_eq(svc.registered_configs.size(), 0)

# ─────────────────────────────────────────────────────────────────────────────
# Enter/Exit — Kern-Funktionalität
# ─────────────────────────────────────────────────────────────────────────────

func test_player_entering_reports_enter() -> void:
	var t := _make_trigger(&"pvp_north")
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	t._on_body_entered(_make_player_body())
	assert_eq(svc.entered.size(), 1)
	assert_eq(svc.entered[0]["zone_id"], &"pvp_north")

func test_player_exiting_reports_exit() -> void:
	var t := _make_trigger(&"pvp_north")
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	t._on_body_exited(_make_player_body())
	assert_eq(svc.exited.size(), 1)
	assert_eq(svc.exited[0]["zone_id"], &"pvp_north")

func test_non_player_entering_does_not_report() -> void:
	var t := _make_trigger()
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	t._on_body_entered(_make_non_player_body())
	assert_eq(svc.entered.size(), 0, "Nicht-Spieler-Body darf keine Zone melden")

func test_entering_without_zone_config_does_not_report() -> void:
	var t := ZoneTriggerVolume.new()  # kein zone_config
	add_child_autofree(t)
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	t._on_body_entered(_make_player_body())
	assert_eq(svc.entered.size(), 0)

func test_entering_without_zone_service_does_not_crash() -> void:
	var t := _make_trigger()
	# kein inject_zone_service() aufgerufen
	t._on_body_entered(_make_player_body())
	assert_true(true, "_on_body_entered() ohne injizierten ZoneService darf nicht crashen")

func test_entering_reports_real_owner_peer_id() -> void:
	var t := _make_trigger(&"pvp_north")
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	t._on_body_entered(_make_player_body(5))
	assert_eq(svc.entered[0]["peer_id"], 5, "Muss den echten owner_peer_id melden, nicht Default 1")

func test_entering_without_owner_peer_id_meta_defaults_to_1() -> void:
	var t := _make_trigger(&"pvp_north")
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	t._on_body_entered(_make_player_body())  # kein Meta gesetzt
	assert_eq(svc.entered[0]["peer_id"], 1, "Dokumentierter Tier-1-Default")

# ─────────────────────────────────────────────────────────────────────────────
# Autoritäts-Guard — ANDERS als QuestCustomTrigger: keine "eigener Spieler"-
# Ausnahme, weil Movement server-autoritativ simuliert ist (ADR-025) und die
# Autorität jeden Overlap bereits selbst sieht (siehe Klassenkommentar).
# ─────────────────────────────────────────────────────────────────────────────

func test_authority_reports_regardless_of_owner_peer_id() -> void:
	var t := _make_trigger(&"pvp_north")
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	var network := MockNetworkBridge.new()
	network._force_is_server = true
	t.inject_network_bridge(network)
	t._on_body_entered(_make_player_body(42))
	assert_eq(svc.entered.size(), 1, "Autorität muss unabhängig vom owner_peer_id melden")

func test_non_authority_never_reports_even_for_own_player() -> void:
	var t := _make_trigger(&"pvp_north")
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	var network := MockNetworkBridge.new()
	network._force_is_server = false
	t.inject_network_bridge(network)
	t._on_body_entered(_make_player_body(multiplayer.get_unique_id()))
	assert_eq(svc.entered.size(), 0,
		"Anders als QuestCustomTrigger: kein Client-Report, Autorität sieht Overlap selbst (ADR-025)")

func test_non_authority_never_reports_for_remote_player() -> void:
	var t := _make_trigger(&"pvp_north")
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	var network := MockNetworkBridge.new()
	network._force_is_server = false
	t.inject_network_bridge(network)
	t._on_body_entered(_make_player_body(99))
	assert_eq(svc.entered.size(), 0)

func test_entering_without_network_bridge_collapses_to_authority() -> void:
	# Tier 1 (Solo): kein _network == Autorität, dieselbe Konvention wie
	# WorldService.configure()s Save-Provider-Guard.
	var t := _make_trigger(&"pvp_north")
	var svc := SpyZoneService.new()
	t.inject_zone_service(svc)
	# kein inject_network_bridge() aufgerufen
	t._on_body_entered(_make_player_body())
	assert_eq(svc.entered.size(), 1, "Ohne NetworkBridge (Tier 1) muss weiterhin gemeldet werden")
