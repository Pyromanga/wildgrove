# res://tests/unit/test_quest_custom_trigger.gd
extends GutTest

## Unit-Tests für QuestCustomTrigger.
##
## Abgedeckt:
##   - inject_bus(): setzt _bus
##   - _on_body_entered(): emittiert custom_objective_triggered für Spieler
##   - _on_body_entered(): ignoriert Nicht-Spieler-Bodies
##   - _on_body_entered(): ohne Bus kein Crash
##   - trigger_once: feuert nur einmal, monitoring wird deaktiviert
##   - trigger_once=false: feuert mehrfach
##   - leerer signal_key: kein Emit, Warnung

var _bus: MockEventBus

func before_each() -> void:
	_bus = MockEventBus.new()

func _make_trigger(key: String = "test_key", once: bool = true) -> QuestCustomTrigger:
	var t := QuestCustomTrigger.new()
	t.signal_key    = key
	t.trigger_once  = once
	add_child_autofree(t)
	return t

func _make_player_body() -> Node3D:
	var p := Node3D.new()
	p.add_to_group("player")
	add_child_autofree(p)
	return p

func _make_non_player_body() -> Node3D:
	var p := Node3D.new()
	add_child_autofree(p)
	return p

## ADR-021 (R-5): spy statt echtem NetworkBridge — vermeidet SceneTree/
## multiplayer-Abhängigkeit, prüft nur DASS und mit WELCHEN Argumenten
## report_domain_event() aufgerufen wird.
class MockNetworkBridge extends NetworkBridge:
	var reported_events: Array[Dictionary] = []
	## Round 47: standardmäßig true, damit alle BESTEHENDEN Tests unten (die
	## keine Multiplayer-Rolle simulieren) unverändert weiterlaufen — echte
	## NetworkBridge.is_server() wäre in der Testumgebung ohnehin true (kein
	## Peer gesetzt), das hier macht es nur explizit steuerbar für die neuen
	## Guard-Tests.
	var _force_is_server: bool = true
	func report_domain_event(event_name: String, payload: Dictionary, peer_id: int = 1) -> void:
		reported_events.append({"event_name": event_name, "payload": payload, "peer_id": peer_id})
	func is_server() -> bool:
		return _force_is_server

# ─────────────────────────────────────────────────────────────────────────────
# inject_bus()
# ─────────────────────────────────────────────────────────────────────────────

func test_inject_bus_sets_field() -> void:
	var t := _make_trigger()
	t.inject_bus(_bus)
	assert_eq(t._bus, _bus, "inject_bus() muss _bus setzen")

func test_inject_network_bridge_sets_field() -> void:
	var t := _make_trigger()
	var network := MockNetworkBridge.new()
	t.inject_network_bridge(network)
	assert_eq(t._network, network, "inject_network_bridge() muss _network setzen")

# ─────────────────────────────────────────────────────────────────────────────
# _on_body_entered() — Kern-Funktionalität
# ─────────────────────────────────────────────────────────────────────────────

func test_player_entering_emits_custom_objective_triggered() -> void:
	var t := _make_trigger("erik_camp_explored")
	t.inject_bus(_bus)
	watch_signals(_bus.quest())
	t._on_body_entered(_make_player_body())
	assert_signal_emitted_with_parameters(
		_bus.quest(), "custom_objective_triggered", ["erik_camp_explored"]
	)

func test_non_player_entering_does_not_emit() -> void:
	var t := _make_trigger("erik_camp_explored")
	t.inject_bus(_bus)
	watch_signals(_bus.quest())
	t._on_body_entered(_make_non_player_body())
	assert_signal_not_emitted(_bus.quest(), "custom_objective_triggered",
		"Nicht-Spieler-Body darf kein CUSTOM-Objective triggern")

func test_entering_without_bus_no_crash() -> void:
	var t := _make_trigger("erik_camp_explored")
	# kein inject_bus() aufgerufen
	t._on_body_entered(_make_player_body())
	assert_true(true, "_on_body_entered() ohne injizierten Bus darf nicht crashen")

func test_entering_reports_custom_objective_triggered_domain_event() -> void:
	var t := _make_trigger("erik_camp_explored")
	t.inject_bus(_bus)
	var mock_network := MockNetworkBridge.new()
	t.inject_network_bridge(mock_network)
	t._on_body_entered(_make_player_body())
	assert_eq(mock_network.reported_events.size(), 1,
		"_on_body_entered() muss genau ein Domain-Event melden")
	assert_eq(mock_network.reported_events[0]["event_name"], "custom_objective_triggered")
	assert_eq(mock_network.reported_events[0]["payload"]["signal_key"], "erik_camp_explored")

# ─────────────────────────────────────────────────────────────────────────────
# hint_text — lokales Sofort-Feedback (TODO-offene-probleme.md: fehlender
# UI-Konsument für custom_objective_triggered)
# ─────────────────────────────────────────────────────────────────────────────

func test_hint_text_emits_notification_for_own_player() -> void:
	var t := _make_trigger("erik_camp_explored")
	t.hint_text = "Lager erkundet!"
	t.inject_bus(_bus)
	watch_signals(_bus.ui())
	t._on_body_entered(_make_player_body())
	assert_signal_emitted_with_parameters(
		_bus.ui(), "notification_requested", ["Lager erkundet!"]
	)

func test_empty_hint_text_emits_no_notification() -> void:
	# Default (hint_text == "") — rückwärtskompatibel zu bestehenden Platzierungen,
	# die bewusst kein Popup wollen.
	var t := _make_trigger("erik_camp_explored")
	t.inject_bus(_bus)
	watch_signals(_bus.ui())
	t._on_body_entered(_make_player_body())
	assert_signal_not_emitted(_bus.ui(), "notification_requested",
		"Leerer hint_text darf kein Popup zeigen")

func test_hint_text_not_shown_for_remote_player_observed_by_authority() -> void:
	# Tier 2/3: der Host sieht per body_entered auch den Eintritt EINES ANDEREN
	# Spielers (is_server() macht den äußeren Guard durchlässig) — das darf auf
	# dem Host-Bildschirm KEIN Popup für eine fremde Entdeckung auslösen, auch
	# wenn custom_objective_triggered (für den Domain-Event-Report) korrekt weiter
	# feuert. Siehe Kommentar in QuestCustomTrigger._on_body_entered().
	var t := _make_trigger("erik_camp_explored")
	t.hint_text = "Lager erkundet!"
	t.inject_bus(_bus)
	var mock_network := MockNetworkBridge.new()
	mock_network._force_is_server = true
	t.inject_network_bridge(mock_network)
	watch_signals(_bus.quest())
	watch_signals(_bus.ui())

	var remote_body := _make_player_body()
	remote_body.set_meta("owner_peer_id", 2)  # multiplayer.get_unique_id() ist im Test 1
	t._on_body_entered(remote_body)

	assert_signal_emitted(_bus.quest(), "custom_objective_triggered",
		"Domain-Event-Pfad darf für fremde Spieler weiterhin feuern (Autorität muss tracken)")
	assert_signal_not_emitted(_bus.ui(), "notification_requested",
		"Aber kein lokales Popup für die Entdeckung eines fremden Spielers")
	assert_eq(mock_network.reported_events[0]["peer_id"], 1,
		"Ohne owner_peer_id-Meta ist 1 der dokumentierte Tier-1-Default")

func test_entering_reports_domain_event_with_real_owner_peer_id() -> void:
	# ADR-021 (R-5): peer_id kommt aus dem "owner_peer_id"-Meta des eintretenden
	# Bodies, nicht aus einem stillen Default — sonst würde Spieler 2's Trigger
	# fälschlich Spieler 1 zugerechnet.
	var t := _make_trigger("erik_camp_explored")
	t.inject_bus(_bus)
	var mock_network := MockNetworkBridge.new()
	t.inject_network_bridge(mock_network)
	var player := _make_player_body()
	player.set_meta("owner_peer_id", 5)
	t._on_body_entered(player)
	assert_eq(mock_network.reported_events[0]["peer_id"], 5,
		"Muss den echten owner_peer_id melden, nicht Default 1")

# ─────────────────────────────────────────────────────────────────────────────
# Multiplayer-Authority-Guard (Round 47)
# ─────────────────────────────────────────────────────────────────────────────
## body_entered feuert lokal auf JEDEM Peer für JEDEN Body in der Zone — auch
## für fremde, nur interpolierte Spieler. Ohne Guard würde ein unbeteiligter
## Nicht-Autoritäts-Client sich das Objective selbst gutschreiben (die Autorität
## leitet peer_id serverseitig aus dem RPC-Sender ab, nicht aus dem Payload).

func test_remote_player_observed_by_non_authority_client_does_not_report() -> void:
	var t := _make_trigger("erik_camp_explored")
	t.inject_bus(_bus)
	var mock_network := MockNetworkBridge.new()
	mock_network._force_is_server = false
	t.inject_network_bridge(mock_network)
	var other_player := _make_player_body()
	other_player.set_meta("owner_peer_id", 99)  # fremder Spieler, nicht mein lokaler Peer
	t._on_body_entered(other_player)
	assert_eq(mock_network.reported_events.size(), 0,
		"Fremder Spieler, beobachtet von Nicht-Autorität, darf kein Domain-Event melden")

func test_remote_player_observed_by_non_authority_client_does_not_emit_local_signal_either() -> void:
	var t := _make_trigger("erik_camp_explored")
	t.inject_bus(_bus)
	var mock_network := MockNetworkBridge.new()
	mock_network._force_is_server = false
	t.inject_network_bridge(mock_network)
	watch_signals(_bus.quest())
	var other_player := _make_player_body()
	other_player.set_meta("owner_peer_id", 99)
	t._on_body_entered(other_player)
	assert_signal_not_emitted(_bus.quest(), "custom_objective_triggered",
		"Fremder Spieler, beobachtet von Nicht-Autorität, darf auch kein lokales Signal auslösen")
	assert_false(t._has_triggered,
		"Verworfener Fall-3-Eintritt darf trigger_once nicht 'verbrauchen'")

func test_own_player_reports_even_when_not_authority() -> void:
	var t := _make_trigger("erik_camp_explored")
	t.inject_bus(_bus)
	var mock_network := MockNetworkBridge.new()
	mock_network._force_is_server = false
	t.inject_network_bridge(mock_network)
	var own_player := _make_player_body()
	own_player.set_meta("owner_peer_id", multiplayer.get_unique_id())
	t._on_body_entered(own_player)
	assert_eq(mock_network.reported_events.size(), 1,
		"Der eigene Spieler muss weiterhin melden, auch wenn dieser Client nicht Autorität ist")

func test_server_still_reports_regardless_of_owner_peer_id() -> void:
	var t := _make_trigger("erik_camp_explored")
	t.inject_bus(_bus)
	var mock_network := MockNetworkBridge.new()
	mock_network._force_is_server = true
	t.inject_network_bridge(mock_network)
	var other_player := _make_player_body()
	other_player.set_meta("owner_peer_id", 42)
	t._on_body_entered(other_player)
	assert_eq(mock_network.reported_events.size(), 1,
		"Autorität muss unabhängig vom owner_peer_id melden")

func test_entering_without_network_bridge_does_not_crash() -> void:
	var t := _make_trigger("erik_camp_explored")
	t.inject_bus(_bus)
	# kein inject_network_bridge() aufgerufen
	t._on_body_entered(_make_player_body())
	assert_true(true, "_on_body_entered() ohne injizierte NetworkBridge darf nicht crashen")

func test_entering_with_empty_signal_key_does_not_emit() -> void:
	var t := _make_trigger("")
	t.inject_bus(_bus)
	watch_signals(_bus.quest())
	t._on_body_entered(_make_player_body())
	assert_signal_not_emitted(_bus.quest(), "custom_objective_triggered",
		"Leerer signal_key darf kein Signal emittieren")

# ─────────────────────────────────────────────────────────────────────────────
# trigger_once
# ─────────────────────────────────────────────────────────────────────────────

func test_trigger_once_fires_only_once() -> void:
	var t := _make_trigger("key", true)
	t.inject_bus(_bus)
	var emit_count := [0]
	_bus.quest().custom_objective_triggered.connect(func(_k): emit_count[0] += 1)
	var player := _make_player_body()
	t._on_body_entered(player)
	t._on_body_entered(player)  # zweiter Eintritt
	assert_eq(emit_count[0], 1, "trigger_once=true darf nur einmal emittieren")

func test_trigger_once_disables_monitoring_after_fire() -> void:
	var t := _make_trigger("key", true)
	t.inject_bus(_bus)
	t._on_body_entered(_make_player_body())
	assert_false(t.monitoring, "Nach Trigger muss monitoring deaktiviert werden (trigger_once)")

func test_trigger_repeatable_fires_multiple_times() -> void:
	var t := _make_trigger("key", false)
	t.inject_bus(_bus)
	var emit_count := [0]
	_bus.quest().custom_objective_triggered.connect(func(_k): emit_count[0] += 1)
	var player := _make_player_body()
	t._on_body_entered(player)
	t._on_body_entered(player)
	assert_eq(emit_count[0], 2, "trigger_once=false muss bei jedem Eintritt emittieren")

func test_trigger_repeatable_keeps_monitoring_enabled() -> void:
	var t := _make_trigger("key", false)
	t.inject_bus(_bus)
	t._on_body_entered(_make_player_body())
	assert_true(t.monitoring, "Bei trigger_once=false darf monitoring nicht deaktiviert werden")

# ─────────────────────────────────────────────────────────────────────────────
# Integration mit QuestService (End-to-End über echten Bus)
# ─────────────────────────────────────────────────────────────────────────────

func test_trigger_feeds_into_quest_service_via_real_bus() -> void:
	## Voller Pfad seit ADR-021 (R-5): QuestCustomTrigger → NetworkBridge.
	## report_domain_event() → domain_event_received → QuestService.
	## custom_objective_triggered wird NICHT mehr direkt vom lokalen EventBus-
	## Signal gelesen (das feuert weiterhin, aber nur noch für etwaige lokale
	## UI-Konsumenten — kein Autoritäts-Pfad, siehe ADR-021 "Befund").
	var obj := QuestObjective.new()
	obj.id        = "obj_explore"
	obj.type      = QuestObjective.Type.CUSTOM
	obj.target_id = "erik_camp_explored"
	obj.required  = 1
	var def := QuestDefinition.new()
	def.id = "quest_x"
	def.objectives = [obj]

	var ds := QuestServiceTestHelper.new()
	ds._quests["quest_x"] = def

	var svc := QuestService.new()
	svc.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:        ds,
		ServiceKeys.SAVE_SYSTEM: QuestServiceTestHelper.NoopSaveSystem.new(),
		ServiceKeys.EVENT_BUS:   _bus,
	}))
	svc.on_ready()
	svc.request_start_quest("quest_x", "p1")

	# ADR-029 Round 64: QuestService._on_domain_event_received() übersetzt jetzt
	# peer_id → player_id über NetworkBridge/SessionManager
	# (_resolve_player_uuid()) — ohne SessionManager bliebe die Übersetzung leer
	# und das Event würde verworfen. owner_peer_id-Meta-Default des Triggers ist 1.
	var session := SessionManager.new()
	session.register_player_slot(1, "p1")
	add_child_autofree(session)
	var network := NetworkBridge.new()
	network.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS:       _bus,
		ServiceKeys.SESSION_MANAGER: session,
	}))
	add_child_autofree(network)
	svc.inject_network_bridge(network)  # verbindet domain_event_received → _on_domain_event_received

	var trigger := _make_trigger("erik_camp_explored")
	trigger.inject_bus(_bus)
	trigger.inject_network_bridge(network)
	trigger._on_body_entered(_make_player_body())  # owner_peer_id-Meta-Default: 1

	assert_eq(svc.get_objective_progress("quest_x", "obj_explore", "p1"), 1,
		"QuestCustomTrigger muss End-to-End über report_domain_event() QuestService erreichen")
	svc.on_cleanup()

## Muss "extends DataService" sein, da QuestService.configure() per DI-Konvention
## hart auf DataService castet (deps.get_optional(...) as DataService).
class QuestServiceTestHelper extends DataService:
	func get_all_quests() -> Dictionary:  return _quests
	func get_auto_start_quests() -> Array[String]: return []

	class NoopSaveSystem extends SaveSystem:
		func register_save_provider(_p) -> void: pass
		func get_state_for(_key: String) -> Dictionary: return {}
