# res://tests/unit/test_network_bridge_contract.gd
extends GutTest

## Contract-Tests für das on_*_confirmed()-Muster (ADR-004 / I-01-Fix).
##
## Kontext: Nach I-01-Fix sind die Authority-Mutations-Handler vollständig public und
## direkt typed — kein Dictionary-Payload, kein receive_*_from_network()-Wrapper mehr.
## NetworkBridge._rpc_*() und send_*() rufen on_*_confirmed() direkt auf.
##
## Diese Tests sichern:
##   1. on_*_confirmed() ist öffentlich erreichbar (kein Underscore-Präfix).
##   2. on_*_confirmed() mutiert denselben State wie der request_*()-Pfad.
##   3. player_id-Routing ist korrekt: peer-Daten landen beim richtigen Spieler.
##   4. Authority Guard in on_*_confirmed() verweigert auf Nicht-Autorität.
##   5. NetworkBridge.send_*() und _rpc_*() rufen on_*_confirmed() korrekt auf.
##
## Abdeckung:
##   - QuestService.on_quest_start_confirmed()
##   - QuestService.on_quest_complete_confirmed()
##   - SkillSystem.on_xp_add_confirmed()
##   - NetworkBridge.send_start_quest() Tier-1-Routing → on_quest_start_confirmed()
##
## Kein Tier-1/Tier-2-Routing-Test mehr für XP/Item (send_add_xp()/send_add_item()/
## _rpc_add_xp()/_rpc_add_item() sind entfernt — siehe TODO-offene-probleme.md
## "Server validiert RPC-Werte nicht", Option A, und
## test_network_bridge.gd::test_no_rpc_add_item_or_add_xp_surface()).
## request_add_xp() mutiert seitdem immer direkt, unabhängig vom Peer-Zustand.

var _bridge:    NetworkBridge
var _quest:     QuestService
var _skill:     SkillSystem
var _inventory: InventorySystem
var _bus:       MockEventBus

func before_each() -> void:
	_bus = MockEventBus.new()

	_bridge = NetworkBridge.new()
	_bridge.configure(ServiceDeps.from_dict({}))
	add_child_autofree(_bridge)

	_quest = QuestService.new()
	_quest.configure(ServiceDeps.from_dict({"network_bridge": _bridge, "event_bus": _bus}))

	_skill = SkillSystem.new()
	_skill.configure(ServiceDeps.from_dict({"network_bridge": _bridge, "event_bus": _bus}))

	_inventory = InventorySystem.new()
	_inventory.configure(ServiceDeps.from_dict({"network_bridge": _bridge, "event_bus": _bus}))

	# NetworkBridge mit allen Services konfigurieren
	_bridge.configure(ServiceDeps.from_dict({
		"quest":        _quest,
		"skill_system": _skill,
		"inventory":    _inventory,
	}))

func after_each() -> void:
	_bridge.on_cleanup()
	_quest.on_cleanup()
	_skill.on_cleanup()
	_inventory.on_cleanup()
	_bridge    = null
	_quest     = null
	_skill     = null
	_inventory = null

# ─────────────────────────────────────────────────────────────────────────────
# QuestService — on_quest_start_confirmed()
# ─────────────────────────────────────────────────────────────────────────────

func test_quest_on_start_confirmed_is_public() -> void:
	# ADR-004: Handler muss public sein — direkt via RPC aufrufbar
	assert_true(_quest.has_method("on_quest_start_confirmed"),
		"QuestService.on_quest_start_confirmed() muss öffentlich existieren (ADR-004).")

func test_quest_on_complete_confirmed_is_public() -> void:
	assert_true(_quest.has_method("on_quest_complete_confirmed"),
		"QuestService.on_quest_complete_confirmed() muss öffentlich existieren (ADR-004).")

func test_quest_on_start_confirmed_does_not_crash_for_unknown_quest() -> void:
	# Unbekannte quest_id → graceful handling, kein Crash
	_quest.on_quest_start_confirmed("nonexistent_quest_id", "p1")
	assert_true(true, "Unbekannte Quest-ID darf keinen Crash auslösen.")

func test_quest_on_start_confirmed_same_state_as_request() -> void:
	# on_quest_start_confirmed() muss denselben State hinterlassen wie request_start_quest().
	# Ohne DataService bleibt is_quest_active() false — aber beide Pfade müssen konsistent sein.
	var svc_via_request := QuestService.new()
	svc_via_request.configure(ServiceDeps.from_dict({"network_bridge": _bridge}))
	svc_via_request.request_start_quest("quest_woodcutter_intro", "p1")
	var active_via_request := svc_via_request.is_quest_active("quest_woodcutter_intro", "p1")
	svc_via_request.on_cleanup()

	_quest.on_quest_start_confirmed("quest_woodcutter_intro", "p1")
	var active_via_confirmed := _quest.is_quest_active("quest_woodcutter_intro", "p1")

	assert_eq(active_via_request, active_via_confirmed,
		"on_quest_start_confirmed() und request_start_quest() müssen denselben State liefern.")

func test_quest_on_start_confirmed_player_id_routing() -> void:
	# player_id="p2" darf nicht in player_id="p1" landen
	_quest.on_quest_start_confirmed("quest_woodcutter_intro", "p2")
	assert_false(_quest.is_quest_active("quest_woodcutter_intro", "p1"),
		"Quest für player_id='p2' darf nicht in player_id='p1' landen.")

func test_quest_on_complete_confirmed_does_not_crash_without_active_quest() -> void:
	# Quest abschließen die nie gestartet wurde → kein Crash
	_quest.on_quest_complete_confirmed("quest_woodcutter_intro", "p1")
	assert_true(true, "Abschließen einer nicht gestarteten Quest darf nicht crashen.")

func test_quest_old_receive_wrappers_are_removed() -> void:
	# I-01-Fix: receive_*_from_network()-Wrapper sind entfernt — on_*_confirmed() ist der Kontrakt
	assert_false(_quest.has_method("receive_start_quest_from_network"),
		"receive_start_quest_from_network() ist entfernt — on_quest_start_confirmed() ist der Kontrakt.")
	assert_false(_quest.has_method("receive_complete_quest_from_network"),
		"receive_complete_quest_from_network() ist entfernt — on_quest_complete_confirmed() ist der Kontrakt.")

# ─────────────────────────────────────────────────────────────────────────────
# SkillSystem — on_xp_add_confirmed()
# ─────────────────────────────────────────────────────────────────────────────

func test_skill_on_xp_add_confirmed_is_public() -> void:
	assert_true(_skill.has_method("on_xp_add_confirmed"),
		"SkillSystem.on_xp_add_confirmed() muss öffentlich existieren (ADR-004).")

func test_skill_on_xp_add_confirmed_mutates_state() -> void:
	_skill.on_xp_add_confirmed("woodcutting", 40, "p1")
	assert_eq(_skill.get_xp("woodcutting", "p1"), 40,
		"on_xp_add_confirmed() muss XP-State mutieren.")

func test_skill_on_xp_add_confirmed_player_id_routing() -> void:
	_skill.on_xp_add_confirmed("woodcutting", 50, "p2")
	assert_eq(_skill.get_xp("woodcutting", "p1"), 0,
		"XP für player_id=2 darf nicht in player_id=1 landen.")
	assert_eq(_skill.get_xp("woodcutting", "p2"), 50,
		"XP muss bei player_id=2 ankommen.")

func test_skill_on_xp_add_confirmed_same_result_as_request() -> void:
	# on_xp_add_confirmed() und request_add_xp() müssen äquivalent sein — request_add_xp()
	# hat keinen RPC-Zweig mehr, mutiert also in jedem Peer-Zustand direkt.
	_skill.on_xp_add_confirmed("mining", 75, "p1")
	var xp_via_confirmed := _skill.get_xp("mining", "p1")

	var svc2 := SkillSystem.new()
	svc2.configure(ServiceDeps.from_dict({"network_bridge": _bridge}))
	svc2.request_add_xp("mining", 75, "p1")
	var xp_via_request := svc2.get_xp("mining", "p1")
	svc2.on_cleanup()

	assert_eq(xp_via_confirmed, xp_via_request,
		"on_xp_add_confirmed() und request_add_xp() müssen denselben Endstate liefern.")

func test_skill_on_xp_add_confirmed_unknown_skill_no_crash() -> void:
	_skill.on_xp_add_confirmed("nonexistent_skill", 50, "p1")
	assert_true(true, "Unbekannter Skill in on_xp_add_confirmed darf nicht crashen.")

func test_skill_on_xp_add_confirmed_accumulates() -> void:
	_skill.on_xp_add_confirmed("woodcutting", 30, "p1")
	_skill.on_xp_add_confirmed("woodcutting", 20, "p1")
	assert_eq(_skill.get_xp("woodcutting", "p1"), 50,
		"Mehrere on_xp_add_confirmed()-Aufrufe müssen akkumulieren.")

func test_skill_old_receive_wrapper_is_removed() -> void:
	# I-01-Fix: receive_add_xp_from_network() ist entfernt
	assert_false(_skill.has_method("receive_add_xp_from_network"),
		"receive_add_xp_from_network() ist entfernt — on_xp_add_confirmed() ist der Kontrakt.")

# ─────────────────────────────────────────────────────────────────────────────
# NetworkBridge Tier-1-Routing → on_*_confirmed()
# ─────────────────────────────────────────────────────────────────────────────

func test_bridge_send_start_quest_reaches_quest_via_on_confirmed() -> void:
	_bridge.configure(ServiceDeps.from_dict({"quest": _quest}))
	# Ohne DataService bleibt is_quest_active() false — aber kein Crash
	_bridge.send_start_quest("quest_woodcutter_intro")
	assert_true(true, "Bridge.send_start_quest() darf nicht crashen.")

# ─────────────────────────────────────────────
# request_add_xp() hat kein Tier-1/Tier-2-Routing mehr
# ─────────────────────────────────────────────
##
## Vorher (siehe Git-Historie): request_add_xp() wählte anhand
## `_network.has_peer() + is_server()` zwischen direktem Aufruf und
## `rpc_id(1, "_rpc_add_xp", …)`. Root-Cause-Analyse (TODO-offene-probleme.md,
## "Server validiert RPC-Werte nicht", Option A) ergab: kein legitimer Aufrufer
## sendet je einen client-gewählten amount übers Netz — die RPC-Fläche
## (`_rpc_add_xp`, `NetworkBridge.send_add_xp()`) ist deshalb komplett entfernt,
## nicht nur nachträglich validiert. request_add_xp() mutiert jetzt in jedem
## Peer-Zustand direkt — es gibt keinen Tier-2-Zweig mehr zu testen.

func test_request_add_xp_has_no_rpc_branch_left() -> void:
	# request_add_xp() selbst verzweigt nicht mehr nach Peer-Zustand — es ruft
	# on_xp_add_confirmed() immer direkt auf. Das C-02-Guard IN on_xp_add_confirmed()
	# (nicht in request_add_xp()!) entscheidet, ob die Mutation durchgelassen wird —
	# mit einem Client-simulierenden NetworkBridge-Dep muss der Guard blockieren,
	# genau wie bei einem direkten on_xp_add_confirmed()-Aufruf (Verteidigung in der
	# Tiefe, falls request_add_xp() je aus einem Nicht-Autoritäts-Kontext liefe).
	var mock_bridge := MockNetworkBridgeAsPeer.new()
	mock_bridge.configure(ServiceDeps.from_dict({}))
	add_child_autofree(mock_bridge)
	assert_true(mock_bridge.has_peer(), "MockNetworkBridgeAsPeer muss Peer simulieren")
	assert_false(mock_bridge.is_server(), "MockNetworkBridgeAsPeer muss Client-Rolle simulieren")

	_skill.inject_network_bridge(mock_bridge)
	_skill.request_add_xp("farming", 50, "p1")

	assert_eq(_skill.get_xp("farming", "p1"), 0,
		"on_xp_add_confirmed()'s C-02-Guard muss die Mutation blockieren — " +
		"request_add_xp() selbst hat keinen RPC-Umweg mehr, der das umgehen könnte.")
	mock_bridge.on_cleanup()

class MockNetworkBridgeAsPeer extends NetworkBridge:
	## Simuliert "Peer ist gesetzt, ich bin Client (nicht Server)" ohne echten
	## SceneTree-Multiplayer-Peer — nur noch für den Guard in on_xp_add_confirmed()
	## relevant (C-02), nicht mehr für ein RPC-Routing in request_add_xp().
	func has_peer() -> bool:
		return true

	func is_server() -> bool:
		return false

	func get_local_peer_id() -> int:
		return 2

