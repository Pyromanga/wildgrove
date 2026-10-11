# res://tests/unit/test_wiki_service.gd
extends GutTest

## Unit-Tests für WikiService (ADR-049 "Spielerbefülltes Wiki").
##
## Strategie: WikiService extends Service (RefCounted). MockEventBus für
## die zwei EventBus-Trigger-Quellen (world().enemy_killed/
## quest().quest_started_for_player), eine echte unkonfigurierte
## SkillSystem-Instanz für die dritte (skill_changed — analog
## AchievementService-Tests: nur das Signal wird manuell emittiert, keine
## SkillSystem-Business-Logik durchgespielt). SpyNetworkBridge für die
## peer_id->player_id-Übersetzung UND für die gezielte RPC-Zustellung.
## MockDataService (DataService-Subklasse, befüllt _combat_profiles/
## _loot_tables/_quests/_skills direkt) für get_entry_details()/
## get_drop_chances().

const PEER_1 := 1
const PEER_2 := 2
const P1 := "player-1"
const P2 := "player-2"

var _svc: WikiService
var _bus: MockEventBus
var _skill_system: SkillSystem
var _data: MockDataService

class SpyNetworkBridge extends NetworkBridge:
	var discover_calls: Array[Dictionary] = []
	var snapshot_request_calls: Array[String] = []
	var snapshot_send_calls: Array[Dictionary] = []
	var peer_to_player: Dictionary = {}
	func get_player_id_for_peer(peer_id: int) -> String:
		return String(peer_to_player.get(peer_id, ""))
	func send_wiki_entry_discovered_for_player(player_id: String, payload: Dictionary) -> void:
		discover_calls.append({"player_id": player_id, "payload": payload})
	func send_wiki_snapshot_request(player_id: String) -> void:
		snapshot_request_calls.append(player_id)
	func send_wiki_snapshot_for_player(player_id: String, payload: Dictionary) -> void:
		snapshot_send_calls.append({"player_id": player_id, "payload": payload})

class MockDataService extends DataService:
	func _init() -> void:
		var goblin := CombatProfile.new()
		goblin.id = "goblin"
		goblin.display_name = "Goblin"
		goblin.armor = 0.1
		_combat_profiles["goblin"] = goblin

		var entry_a := LootEntry.new()
		entry_a.item_id = "goblin_ear"
		entry_a.weight = 80.0
		var entry_b := LootEntry.new()
		entry_b.item_id = "poison_dagger"
		entry_b.weight = 20.0
		var table := LootTable.new()
		table.entries = [entry_a, entry_b]
		table.gold_min = 2
		table.gold_max = 8
		_loot_tables["goblin_loot"] = table

		var skill := SkillDefinition.new()
		skill.id = "woodcutting"
		skill.display_name = "Holzfällen"
		skill.description = "Fälle Bäume."
		_skills["woodcutting"] = skill

		var quest := QuestDefinition.new()
		quest.id = "quest_woodcutter_intro"
		quest.title = "Der erste Holzschlag"
		quest.description = "Fälle 3 Eichen."
		quest.category = "main"
		_quests["quest_woodcutter_intro"] = quest

var _net: SpyNetworkBridge

func before_each() -> void:
	_bus = MockEventBus.new()
	_data = MockDataService.new()
	_skill_system = SkillSystem.new()
	_net = SpyNetworkBridge.new()
	_net.peer_to_player = {PEER_1: P1, PEER_2: P2}
	add_child_autofree(_net)

	_svc = WikiService.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS:    _bus,
		ServiceKeys.SKILL_SYSTEM: _skill_system,
		ServiceKeys.DATA:         _data,
	}))
	_svc.inject_network_bridge(_net)

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null
	_bus = null
	_data = null
	_skill_system = null
	_net = null

# ─────────────────────────────────────────────────────────────────────────────
# discover() / is_discovered() / get_discovered()
# ─────────────────────────────────────────────────────────────────────────────

func test_discover_marks_entry_as_discovered() -> void:
	_svc.discover(P1, WikiService.CATEGORY_ENEMIES, "goblin")
	assert_true(_svc.is_discovered(P1, WikiService.CATEGORY_ENEMIES, "goblin"))

func test_discover_is_per_player() -> void:
	_svc.discover(P1, WikiService.CATEGORY_ENEMIES, "goblin")
	assert_false(_svc.is_discovered(P2, WikiService.CATEGORY_ENEMIES, "goblin"))

func test_discover_is_idempotent() -> void:
	var events: Array = []
	_svc.wiki_entry_discovered.connect(func(player_id, category, entry_id): events.append([player_id, category, entry_id]))
	_svc.discover(P1, WikiService.CATEGORY_ENEMIES, "goblin")
	_svc.discover(P1, WikiService.CATEGORY_ENEMIES, "goblin")
	assert_eq(events.size(), 1, "Ein bereits entdeckter Eintrag darf das Signal nicht erneut feuern.")

func test_discover_ignores_empty_player_id() -> void:
	_svc.discover("", WikiService.CATEGORY_ENEMIES, "goblin")
	assert_eq(_svc.get_discovered("", WikiService.CATEGORY_ENEMIES).size(), 0)

func test_discover_ignores_empty_entry_id() -> void:
	_svc.discover(P1, WikiService.CATEGORY_ENEMIES, "")
	assert_eq(_svc.get_discovered(P1, WikiService.CATEGORY_ENEMIES).size(), 0)

func test_discover_rejects_unknown_category() -> void:
	_svc.discover(P1, "not_a_real_category", "goblin")
	assert_eq(_svc.get_all_discovered(P1).size(), 0)

func test_discover_notifies_network_for_remote_player() -> void:
	_svc.discover(P1, WikiService.CATEGORY_ENEMIES, "goblin")
	assert_eq(_net.discover_calls.size(), 1)
	assert_eq(_net.discover_calls[0]["player_id"], P1)
	assert_eq(_net.discover_calls[0]["payload"]["category"], WikiService.CATEGORY_ENEMIES)
	assert_eq(_net.discover_calls[0]["payload"]["entry_id"], "goblin")

func test_get_discovered_returns_a_copy() -> void:
	_svc.discover(P1, WikiService.CATEGORY_SKILLS, "woodcutting")
	var copy := _svc.get_discovered(P1, WikiService.CATEGORY_SKILLS)
	copy.append("mining")
	assert_eq(_svc.get_discovered(P1, WikiService.CATEGORY_SKILLS).size(), 1)

# ─────────────────────────────────────────────────────────────────────────────
# Trigger-Verdrahtung: enemy_killed → "enemies" + "drops"
# ─────────────────────────────────────────────────────────────────────────────

func test_enemy_killed_discovers_enemy_entry() -> void:
	_bus.world().emit_enemy_killed("goblin", Vector3.ZERO, PEER_1)
	assert_true(_svc.is_discovered(P1, WikiService.CATEGORY_ENEMIES, "goblin"))

func test_enemy_killed_also_discovers_mapped_loot_table() -> void:
	_bus.world().emit_enemy_killed("goblin", Vector3.ZERO, PEER_1)
	assert_true(_svc.is_discovered(P1, WikiService.CATEGORY_DROPS, "goblin_loot"))

func test_enemy_killed_falls_back_to_convention_loot_table_id() -> void:
	_bus.world().emit_enemy_killed("skeleton", Vector3.ZERO, PEER_1)
	assert_true(_svc.is_discovered(P1, WikiService.CATEGORY_DROPS, "skeleton_loot"))

func test_enemy_killed_ignores_unresolvable_peer() -> void:
	_bus.world().emit_enemy_killed("goblin", Vector3.ZERO, 999)
	assert_eq(_svc.get_all_discovered(P1).size(), 0)

# ─────────────────────────────────────────────────────────────────────────────
# Trigger-Verdrahtung: quest_started_for_player → "quests"
# ─────────────────────────────────────────────────────────────────────────────

func test_quest_started_for_player_discovers_quest_entry() -> void:
	_bus.quest().emit_quest_started_for_player(P1, "quest_woodcutter_intro")
	assert_true(_svc.is_discovered(P1, WikiService.CATEGORY_QUESTS, "quest_woodcutter_intro"))

func test_quest_started_for_player_is_per_player() -> void:
	_bus.quest().emit_quest_started_for_player(P1, "quest_woodcutter_intro")
	assert_false(_svc.is_discovered(P2, WikiService.CATEGORY_QUESTS, "quest_woodcutter_intro"))

# ─────────────────────────────────────────────────────────────────────────────
# Trigger-Verdrahtung: skill_changed → "skills"
# ─────────────────────────────────────────────────────────────────────────────

func test_skill_changed_discovers_skill_entry() -> void:
	_skill_system.skill_changed.emit("woodcutting", P1)
	assert_true(_svc.is_discovered(P1, WikiService.CATEGORY_SKILLS, "woodcutting"))

# ─────────────────────────────────────────────────────────────────────────────
# on_cleanup()
# ─────────────────────────────────────────────────────────────────────────────

func test_on_cleanup_disconnects_all_trigger_signals() -> void:
	_svc.on_cleanup()
	_bus.world().emit_enemy_killed("goblin", Vector3.ZERO, PEER_1)
	_bus.quest().emit_quest_started_for_player(P1, "quest_woodcutter_intro")
	_skill_system.skill_changed.emit("woodcutting", P1)
	assert_eq(_svc.get_all_discovered(P1).size(), 0, "Nach on_cleanup() dürfen die Trigger-Signale keine Wirkung mehr haben.")

# ─────────────────────────────────────────────────────────────────────────────
# get_entry_details() / get_drop_chances()
# ─────────────────────────────────────────────────────────────────────────────

func test_get_entry_details_for_enemy() -> void:
	var details := _svc.get_entry_details(WikiService.CATEGORY_ENEMIES, "goblin")
	assert_eq(details["display_name"], "Goblin")
	assert_eq(details["loot_table_id"], "goblin_loot")

func test_get_entry_details_for_drops() -> void:
	var details := _svc.get_entry_details(WikiService.CATEGORY_DROPS, "goblin_loot")
	assert_eq(details["gold_min"], 2)
	assert_eq(details["gold_max"], 8)
	assert_true(details["drop_chances"].has("goblin_ear"))

func test_get_entry_details_for_skill() -> void:
	var details := _svc.get_entry_details(WikiService.CATEGORY_SKILLS, "woodcutting")
	assert_eq(details["display_name"], "Holzfällen")

func test_get_entry_details_for_quest() -> void:
	var details := _svc.get_entry_details(WikiService.CATEGORY_QUESTS, "quest_woodcutter_intro")
	assert_eq(details["title"], "Der erste Holzschlag")

func test_get_entry_details_returns_empty_dict_for_unknown_id() -> void:
	assert_eq(_svc.get_entry_details(WikiService.CATEGORY_SKILLS, "does_not_exist"), {})

func test_get_drop_chances_sums_to_hundred_percent() -> void:
	var chances := _svc.get_drop_chances("goblin_loot")
	var total := 0.0
	for item_id in chances:
		total += chances[item_id]
	assert_almost_eq(total, 100.0, 0.01)

func test_get_drop_chances_returns_empty_for_unknown_table() -> void:
	assert_eq(_svc.get_drop_chances("does_not_exist"), {})

# ─────────────────────────────────────────────────────────────────────────────
# Snapshot-Sync
# ─────────────────────────────────────────────────────────────────────────────

func test_request_snapshot_without_peer_calls_on_snapshot_requested_directly() -> void:
	# has_peer() ist im Test standardmäßig false (kein echter MultiplayerPeer) —
	# request_snapshot() fällt daher auf den Tier-1-Pfad zurück und ruft
	# on_snapshot_requested() direkt auf, analog AchievementService-Tests.
	_svc.discover(P1, WikiService.CATEGORY_SKILLS, "woodcutting")
	_svc.request_snapshot(P1)
	assert_eq(_net.snapshot_request_calls.size(), 0, "Ohne echten Peer (Tier 1) darf kein RPC versucht werden.")
	assert_eq(_net.snapshot_send_calls.size(), 1)
	var payload: Dictionary = _net.snapshot_send_calls[0]["payload"]
	assert_true((payload[WikiService.CATEGORY_SKILLS] as Array).has("woodcutting"))

func test_on_snapshot_requested_sends_full_state_for_player() -> void:
	_svc.discover(P1, WikiService.CATEGORY_SKILLS, "woodcutting")
	_svc.on_snapshot_requested(P1)
	assert_eq(_net.snapshot_send_calls.size(), 1)
	var payload: Dictionary = _net.snapshot_send_calls[0]["payload"]
	assert_true((payload[WikiService.CATEGORY_SKILLS] as Array).has("woodcutting"))

func test_on_snapshot_requested_ignores_empty_player_id() -> void:
	_svc.on_snapshot_requested("")
	assert_eq(_net.snapshot_send_calls.size(), 0)

# ─────────────────────────────────────────────────────────────────────────────
# Client-Empfang (_on_remote_entry_discovered_received / _on_remote_snapshot_received)
# ─────────────────────────────────────────────────────────────────────────────

class StubSessionManager extends SessionManager:
	var player_id: String = P1
	func get_local_player_id() -> String:
		return player_id

func test_remote_entry_discovered_received_updates_local_state() -> void:
	var session: StubSessionManager = autofree(StubSessionManager.new())
	var svc := WikiService.new()
	svc.configure(ServiceDeps.from_dict({
		ServiceKeys.SESSION_MANAGER: session,
	}))
	svc.inject_network_bridge(_net)

	_net.wiki_entry_discovered_received.emit({"category": WikiService.CATEGORY_ENEMIES, "entry_id": "goblin"})
	assert_true(svc.is_discovered(P1, WikiService.CATEGORY_ENEMIES, "goblin"))
	svc.on_cleanup()

func test_remote_snapshot_received_replaces_local_state() -> void:
	var session: StubSessionManager = autofree(StubSessionManager.new())
	var svc := WikiService.new()
	svc.configure(ServiceDeps.from_dict({
		ServiceKeys.SESSION_MANAGER: session,
	}))
	svc.inject_network_bridge(_net)

	var synced: Array = []
	svc.wiki_synced.connect(func(player_id): synced.append(player_id))
	_net.wiki_snapshot_received.emit({WikiService.CATEGORY_QUESTS: ["quest_woodcutter_intro"]})
	assert_eq(synced, [P1])
	assert_true(svc.is_discovered(P1, WikiService.CATEGORY_QUESTS, "quest_woodcutter_intro"))
	svc.on_cleanup()

# ─────────────────────────────────────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────────────────────────────────────

func test_save_key_is_wiki() -> void:
	assert_eq(_svc.get_save_key(), "wiki")

func test_save_data_empty_by_default() -> void:
	assert_true((_svc.get_save_data()["discovered"] as Dictionary).is_empty())

func test_save_data_round_trip_preserves_discoveries() -> void:
	_svc.discover(P1, WikiService.CATEGORY_ENEMIES, "goblin")
	var snapshot := _svc.get_save_data()

	var svc2 := WikiService.new()
	svc2.configure(ServiceDeps.from_dict({}))
	svc2._restore_from_save(snapshot)

	assert_true(svc2.is_discovered(P1, WikiService.CATEGORY_ENEMIES, "goblin"))
	svc2.on_cleanup()
