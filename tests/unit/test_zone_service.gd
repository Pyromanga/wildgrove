# res://tests/unit/test_zone_service.gd
extends GutTest

## Unit-Tests für ZoneService (ADR-030).
##
## Strategie: ZoneService extends Service (RefCounted) — kein add_child nötig,
## analog test_player_state_service.gd. MockEventBus für Signal-Assertions
## (kein globales State-Bleeding zwischen Tests).
##
## Abgedeckt:
##   - report_enter()/report_exit(): Membership + Signal-Emission
##   - Idempotenz: doppeltes Enter/Exit emittiert nicht zweimal
##   - Multi-Tenanz: zwei peer_ids unabhängig, additive Mehrfach-Zonen
##   - has_tag(): Tag-Lookup über registrierte ZoneConfig
##   - _on_peer_cleanup_requested(): räumt Mitgliedschaft beim Disconnect weg

var _svc: ZoneService
var _bus: MockEventBus

func before_each() -> void:
	_bus = MockEventBus.new()
	_svc = ZoneService.new()
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))
	_svc.on_ready()

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null
	_bus = null

func _make_config(zone_id: StringName, tags: Array[StringName] = []) -> ZoneConfig:
	var config := ZoneConfig.new()
	config.zone_id = zone_id
	config.tags = tags
	return config

# ─────────────────────────────────────────────────────────────────────────────
# report_enter / report_exit — Membership
# ─────────────────────────────────────────────────────────────────────────────

func test_default_not_in_any_zone() -> void:
	assert_false(_svc.is_in_zone(1, &"pvp_north"), "Frischer Peer darf in keiner Zone sein")

func test_report_enter_sets_membership() -> void:
	_svc.report_enter(1, &"pvp_north")
	assert_true(_svc.is_in_zone(1, &"pvp_north"))

func test_report_exit_clears_membership() -> void:
	_svc.report_enter(1, &"pvp_north")
	_svc.report_exit(1, &"pvp_north")
	assert_false(_svc.is_in_zone(1, &"pvp_north"))

func test_report_exit_without_prior_enter_is_noop() -> void:
	_svc.report_exit(1, &"pvp_north")  # kein Crash
	assert_false(_svc.is_in_zone(1, &"pvp_north"))

# ─────────────────────────────────────────────────────────────────────────────
# Signal-Emission
# ─────────────────────────────────────────────────────────────────────────────

func test_report_enter_emits_zone_entered() -> void:
	watch_signals(_bus.zones())
	_svc.report_enter(1, &"pvp_north")
	assert_signal_emitted_with_parameters(_bus.zones(), "zone_entered", [1, &"pvp_north"])

func test_report_exit_emits_zone_exited() -> void:
	_svc.report_enter(1, &"pvp_north")
	watch_signals(_bus.zones())
	_svc.report_exit(1, &"pvp_north")
	assert_signal_emitted_with_parameters(_bus.zones(), "zone_exited", [1, &"pvp_north"])

func test_duplicate_enter_does_not_emit_twice() -> void:
	_svc.report_enter(1, &"pvp_north")
	watch_signals(_bus.zones())
	_svc.report_enter(1, &"pvp_north")  # bereits drin — Idempotenz
	assert_signal_not_emitted(_bus.zones(), "zone_entered")

func test_duplicate_exit_does_not_emit_twice() -> void:
	_svc.report_enter(1, &"pvp_north")
	_svc.report_exit(1, &"pvp_north")
	watch_signals(_bus.zones())
	_svc.report_exit(1, &"pvp_north")  # bereits draußen — Idempotenz
	assert_signal_not_emitted(_bus.zones(), "zone_exited")

# ─────────────────────────────────────────────────────────────────────────────
# Multi-Tenanz + additive Mehrfach-Zonen
# ─────────────────────────────────────────────────────────────────────────────

func test_two_peers_independent_membership() -> void:
	_svc.report_enter(1, &"pvp_north")
	assert_true(_svc.is_in_zone(1, &"pvp_north"))
	assert_false(_svc.is_in_zone(2, &"pvp_north"), "Peer 2 darf nicht in Peer 1s Zone sein")

func test_peer_can_be_in_multiple_zones_additively() -> void:
	_svc.report_enter(1, &"pvp_north")
	_svc.report_enter(1, &"theft_market")
	assert_true(_svc.is_in_zone(1, &"pvp_north"))
	assert_true(_svc.is_in_zone(1, &"theft_market"))

func test_get_zones_for_returns_all_active_zones() -> void:
	_svc.report_enter(1, &"pvp_north")
	_svc.report_enter(1, &"theft_market")
	var zones := _svc.get_zones_for(1)
	assert_eq(zones.size(), 2)
	assert_true(zones.has(&"pvp_north"))
	assert_true(zones.has(&"theft_market"))

func test_exit_one_zone_does_not_affect_other_zone_of_same_peer() -> void:
	_svc.report_enter(1, &"pvp_north")
	_svc.report_enter(1, &"theft_market")
	_svc.report_exit(1, &"pvp_north")
	assert_false(_svc.is_in_zone(1, &"pvp_north"))
	assert_true(_svc.is_in_zone(1, &"theft_market"), "Zweite Zone darf unberührt bleiben")

# ─────────────────────────────────────────────────────────────────────────────
# has_tag() — Tag-Lookup über registrierte ZoneConfig
# ─────────────────────────────────────────────────────────────────────────────

func test_has_tag_false_without_registered_config() -> void:
	# Zone betreten, ohne dass jemals eine ZoneConfig registriert wurde —
	# darf nicht crashen, aber auch keinen Tag finden.
	_svc.report_enter(1, &"pvp_north")
	assert_false(_svc.has_tag(1, &"pvp"))

func test_has_tag_true_after_registering_matching_config() -> void:
	_svc.register_zone_config(_make_config(&"pvp_north", [&"pvp"]))
	_svc.report_enter(1, &"pvp_north")
	assert_true(_svc.has_tag(1, &"pvp"))

func test_has_tag_false_for_unrelated_tag() -> void:
	_svc.register_zone_config(_make_config(&"pvp_north", [&"pvp"]))
	_svc.report_enter(1, &"pvp_north")
	assert_false(_svc.has_tag(1, &"theft"))

func test_has_tag_checks_across_multiple_zones() -> void:
	_svc.register_zone_config(_make_config(&"pvp_north", [&"pvp"]))
	_svc.register_zone_config(_make_config(&"market", [&"theft"]))
	_svc.report_enter(1, &"pvp_north")
	_svc.report_enter(1, &"market")
	assert_true(_svc.has_tag(1, &"pvp"))
	assert_true(_svc.has_tag(1, &"theft"))

func test_register_zone_config_without_zone_id_ignored() -> void:
	var bad_config := ZoneConfig.new()  # zone_id bleibt leer
	_svc.register_zone_config(bad_config)  # kein Crash
	assert_null(_svc.get_zone_config(&""))

# ─────────────────────────────────────────────────────────────────────────────
# Peer-Cleanup (Disconnect) — Laufzeit-Zustand, kein Save-Feld (siehe
# Klassenkommentar ZoneService.gd, Abgrenzung zu ADR-029)
# ─────────────────────────────────────────────────────────────────────────────

func test_peer_cleanup_removes_all_memberships() -> void:
	_svc.report_enter(1, &"pvp_north")
	_svc.report_enter(1, &"theft_market")
	_bus.networking().emit_peer_cleanup_requested(1)
	assert_false(_svc.is_in_zone(1, &"pvp_north"))
	assert_true(_svc.get_zones_for(1).is_empty())

func test_peer_cleanup_does_not_affect_other_peer() -> void:
	_svc.report_enter(1, &"pvp_north")
	_svc.report_enter(2, &"pvp_north")
	_bus.networking().emit_peer_cleanup_requested(1)
	assert_false(_svc.is_in_zone(1, &"pvp_north"))
	assert_true(_svc.is_in_zone(2, &"pvp_north"), "Peer 2 darf von Peer 1s Cleanup nicht betroffen sein")

func test_peer_cleanup_for_unknown_peer_is_noop() -> void:
	_bus.networking().emit_peer_cleanup_requested(99)  # nie beigetreten — kein Crash
	assert_true(_svc.get_zones_for(99).is_empty())

# ─────────────────────────────────────────────────────────────────────────────
# ADR-030 Client-Broadcast: report_enter()/report_exit() müssen
# NetworkBridge.send_zone_update_for_peer() aufrufen — Spy statt echter RPC-
# Transport (kein MultiplayerPeer in Tier-1-Tests, siehe test_zone_network_bridge.gd
# für die Empfänger-Seite/_rpc_receive_zone_update()).
# ─────────────────────────────────────────────────────────────────────────────

class SpyNetworkBridge extends NetworkBridge:
	var calls: Array[Dictionary] = []
	func send_zone_update_for_peer(peer_id: int, zone_id: StringName, entered: bool) -> void:
		calls.append({"peer_id": peer_id, "zone_id": zone_id, "entered": entered})

func test_report_enter_pushes_to_network() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)
	_svc.report_enter(3, &"pvp_north")
	assert_eq(net.calls.size(), 1)
	assert_eq(net.calls[0], {"peer_id": 3, "zone_id": &"pvp_north", "entered": true})

func test_report_exit_pushes_to_network() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)
	_svc.report_enter(3, &"pvp_north")
	net.calls.clear()
	_svc.report_exit(3, &"pvp_north")
	assert_eq(net.calls.size(), 1)
	assert_eq(net.calls[0], {"peer_id": 3, "zone_id": &"pvp_north", "entered": false})

func test_duplicate_enter_does_not_push_to_network_either() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)
	_svc.report_enter(3, &"pvp_north")
	net.calls.clear()
	_svc.report_enter(3, &"pvp_north")  # bereits drin — Idempotenz gilt auch hier
	assert_true(net.calls.is_empty())

func test_report_enter_without_network_bridge_does_not_crash() -> void:
	# kein inject_network_bridge() aufgerufen — muss trotzdem lokal funktionieren
	_svc.report_enter(3, &"pvp_north")
	assert_true(_svc.is_in_zone(3, &"pvp_north"))
