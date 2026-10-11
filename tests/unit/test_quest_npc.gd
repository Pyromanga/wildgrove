# res://tests/unit/test_quest_npc.gd
extends GutTest

## Unit-Tests für QuestNPC (tree-only: EIN Dialog-System, DialogueTreeController).
##
## Abgedeckt:
##   - on_spawn(): Pflicht-Deps (IEventBus, QuestService, NetworkBridge) — fehlende Deps
##     werden LAUT gemeldet, kein Crash; Baum wird trotzdem gebaut, wenn der Bus da ist
##   - Standard-Baum aus den Export-Feldern (Default von _build_dialogue_tree())
##   - Subklassen-Override von _build_dialogue_tree()
##   - _on_interacted(): genau ein Identitätsweg (peer_id → player_id), kein stiller Ersatz
##   - BUG-26: Quest-Tracking nur auf der Autorität

var _bus: MockEventBus

func before_each() -> void:
	_bus = MockEventBus.new()

func _make_npc() -> QuestNPC:
	var npc := QuestNPC.new()
	npc.quest_id         = "quest_woodcutter_intro"
	npc.quest_obj_id     = "obj_chop_trees"
	npc.npc_display_name = "Test-NPC"
	add_child_autofree(npc)
	return npc

class BareContext extends IEntityContext:
	func get_service(_k: String) -> Variant: return null

## Spy statt echtem NetworkBridge (kein SceneTree/multiplayer nötig). Löst jede peer_id auf
## "player_<peer>" auf und merkt sich gemeldete Domain-Events.
class MockNetworkBridge extends NetworkBridge:
	var reported_events: Array[Dictionary] = []
	var resolvable: bool = true
	func get_player_id_for_peer(peer_id: int) -> String:
		return "player_%d" % peer_id if resolvable else ""
	func report_domain_event(event_name: String, payload: Dictionary, peer_id: int = 1) -> void:
		reported_events.append({"event_name": event_name, "payload": payload, "peer_id": peer_id})

func _spawned_npc(network: MockNetworkBridge = null, npc: QuestNPC = null) -> QuestNPC:
	if npc == null:
		npc = _make_npc()
	var ctx := EntityContext.for_test()
	ctx._bus = _bus
	if network != null:
		ctx._network = network
	npc.on_spawn({}, ctx)
	return npc

# ── on_spawn() ─────────────────────────────────

func test_on_spawn_without_bus_no_crash_and_no_tree() -> void:
	var npc := _make_npc()
	npc.on_spawn({}, BareContext.new())
	assert_null(npc._dialogue_tree, "Ohne IEventBus (Pflicht-Dep) wird kein Baum gebaut")

func test_on_spawn_with_bus_sets_field_and_builds_tree() -> void:
	var npc := _spawned_npc()
	assert_eq(npc._bus, _bus)
	assert_not_null(npc._dialogue_tree, "Default-_build_dialogue_tree() baut den Standard-Questgeber")

func test_default_tree_is_standard_quest_giver() -> void:
	var npc := _spawned_npc()
	for node_id in ["entry", "offer1", "active1", "done1"]:
		assert_true(npc._dialogue_tree._nodes.has(node_id), "Standard-Baum braucht Knoten '%s'" % node_id)

func test_default_tree_with_next_quest_adds_second_stage() -> void:
	var npc := _make_npc()
	npc.next_quest_id = "quest_next"
	npc.next_quest_obj_id = "obj_next"
	_spawned_npc(null, npc)
	assert_true(npc._dialogue_tree._nodes.has("offer2"))

func test_on_spawn_wires_choice_ui_factory() -> void:
	var npc := _spawned_npc()
	assert_true(npc._dialogue_tree._choice_ui_factory.is_valid())

func test_on_despawn_no_crash() -> void:
	var npc := _spawned_npc()
	npc.on_despawn()
	_make_npc().on_despawn()
	assert_true(true)

# ── Subklassen-Override ────────────────────────

class TreeNPC extends QuestNPC:
	func _init() -> void:
		quest_id         = ""
		npc_display_name = "Test-NPC (Tree)"
		npc_id            = "test_tree_npc"
	func _build_dialogue_tree(tree_label, tree, tree_bus, quest_service) -> DialogueTreeController:
		var dt := DialogueTreeController.new(tree_label, tree, tree_bus, quest_service)
		dt.add_node("start", "Hallo.")
		dt.set_start_node("start")
		return dt

func test_subclass_override_replaces_default_tree() -> void:
	var npc := TreeNPC.new()
	add_child_autofree(npc)
	_spawned_npc(null, npc)
	assert_true(npc._dialogue_tree._nodes.has("start"))
	assert_false(npc._dialogue_tree._nodes.has("offer1"))

# ── _on_interacted() ───────────────────────────

func test_on_interacted_before_on_spawn_no_crash() -> void:
	var npc := _make_npc()
	npc._on_interacted("talk_quest_npc", 1)
	assert_true(true)

func test_on_interacted_wrong_action_id_ignored() -> void:
	var net := MockNetworkBridge.new()
	var npc := _spawned_npc(net)
	npc._on_interacted("some_other_action", 1)
	assert_eq(npc._dialogue_tree._current_node_id, "", "Falsche action_id darf keinen Dialog starten")

func test_on_interacted_resolves_player_id_and_runs_tree() -> void:
	var net := MockNetworkBridge.new()
	var npc := TreeNPC.new()
	add_child_autofree(npc)
	_spawned_npc(net, npc)
	npc._on_interacted("talk_quest_npc", 4)
	assert_eq(npc._dialogue_tree._player_id, "player_4", "peer_id → player_id über NetworkBridge")
	assert_eq(npc._dialogue_tree._current_node_id, "start")

func test_on_interacted_unresolvable_identity_aborts_without_fallback() -> void:
	var net := MockNetworkBridge.new()
	net.resolvable = false
	var npc := TreeNPC.new()
	add_child_autofree(npc)
	_spawned_npc(net, npc)
	npc._on_interacted("talk_quest_npc", 4)
	assert_eq(npc._dialogue_tree._current_node_id, "", "Ohne Identität kein Dialog (kein stiller Ersatzwert)")
	assert_eq(net.reported_events.size(), 0)

func test_on_interacted_without_network_bridge_aborts() -> void:
	var npc := TreeNPC.new()
	add_child_autofree(npc)
	_spawned_npc(null, npc)
	npc._on_interacted("talk_quest_npc", 1)
	assert_eq(npc._dialogue_tree._current_node_id, "")

func test_on_interacted_reports_npc_talked_to_with_real_peer_id() -> void:
	var net := MockNetworkBridge.new()
	var npc := _spawned_npc(net)
	npc._on_interacted("talk_quest_npc", 4)
	assert_eq(net.reported_events.size(), 1)
	assert_eq(net.reported_events[0]["event_name"], "npc_talked_to")
	assert_eq(net.reported_events[0]["payload"]["npc_id"], npc.npc_id)
	assert_eq(net.reported_events[0]["peer_id"], 4)

func test_non_authority_runs_dialog_but_does_not_report() -> void:
	## BUG-26: lokales Feedback ja, Quest-Tracking nur auf der Autorität.
	var net := MockNetworkBridge.new()
	var npc := _spawned_npc(net)
	npc.set_multiplayer_authority(2)
	assert_false(npc.is_multiplayer_authority())
	npc._on_interacted("talk_quest_npc", 4)
	assert_eq(npc._dialogue_tree._player_id, "player_4", "Dialog läuft lokal")
	assert_eq(net.reported_events.size(), 0, "Kein Domain-Event auf Nicht-Autorität")

func test_authority_and_non_authority_together_report_exactly_once() -> void:
	var net := MockNetworkBridge.new()
	var npc := _spawned_npc(net)
	npc.set_multiplayer_authority(2)
	npc._on_interacted("talk_quest_npc", 4)
	npc.set_multiplayer_authority(1)
	npc._on_interacted("talk_quest_npc", 4)
	assert_eq(net.reported_events.size(), 1)
