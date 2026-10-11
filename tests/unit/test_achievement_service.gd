# res://tests/unit/test_achievement_service.gd
extends GutTest

## Unit-Tests für AchievementService (ADR-046 "Achievement-System").
##
## Strategie: AchievementService extends Service (RefCounted) — kein
## add_child nötig für den Tier-1-Pfad. Für die drei Trigger-Quellen
## werden UNKONFIGURIERTE echte Instanzen der jeweiligen Services
## (`PvPDeathLossService.new()`/`AuctionHouseService.new()`/
## `ReportService.new()`) injiziert — AchievementService verbindet sich in
## configure() nur auf deren SIGNALE, ruft keine ihrer Methoden auf. Die
## Signale werden in den Tests direkt manuell emittiert (`.emit(...)`),
## ohne die volle Business-Logik der jeweiligen Quelle durchzuspielen —
## das ist bereits in deren eigenen Testdateien abgedeckt (test_pvp_
## death_loss_service.gd/test_auction_house_service.gd/
## test_report_service.gd). Hier wird nur geprüft, dass AchievementService
## korrekt REAGIERT, wenn diese Signale feuern.

const P1 := "player-1"
const P2 := "player-2"

var _svc: AchievementService
var _save: SaveSystem
var _fake_pvp: PvPDeathLossService
var _fake_auction: AuctionHouseService
var _fake_report: ReportService
var _fake_stats: StatsService
var _fake_character_creation: CharacterCreationService

func before_each() -> void:
	_save = SaveSystem.new()
	_save.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new()}))

	_fake_pvp = PvPDeathLossService.new()
	_fake_auction = AuctionHouseService.new()
	_fake_report = ReportService.new()
	_fake_stats = StatsService.new()
	_fake_character_creation = CharacterCreationService.new()

	_svc = AchievementService.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.PVP_DEATH_LOSS: _fake_pvp,
		ServiceKeys.AUCTION_HOUSE: _fake_auction,
		ServiceKeys.REPORT: _fake_report,
		ServiceKeys.STATS: _fake_stats,
		ServiceKeys.CHARACTER_CREATION: _fake_character_creation,
	}))

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null
	_fake_character_creation = null
	_fake_pvp = null
	_fake_auction = null
	_fake_report = null
	_fake_stats = null

class SpyNetworkBridge extends NetworkBridge:
	var unlock_calls: Array[Dictionary] = []
	var snapshot_request_calls: Array[String] = []
	var snapshot_send_calls: Array[Dictionary] = []
	func send_achievement_unlocked_for_player(player_id: String, payload: Dictionary) -> void:
		unlock_calls.append({"player_id": player_id, "payload": payload})
	func send_achievement_snapshot_request(player_id: String) -> void:
		snapshot_request_calls.append(player_id)
	func send_achievement_snapshot_for_player(player_id: String, payload: Dictionary) -> void:
		snapshot_send_calls.append({"player_id": player_id, "payload": payload})

class SpyCurrencyService extends CurrencyService:
	var add_gold_calls: Array[Dictionary] = []
	func request_add_gold(player_id: String, amount: int) -> bool:
		add_gold_calls.append({"player_id": player_id, "amount": amount})
		return true

# ─────────────────────────────────────────────────────────────────────────────
# grant_progress() / Definitionen
# ─────────────────────────────────────────────────────────────────────────────

func test_unknown_achievement_id_is_ignored() -> void:
	_svc.grant_progress(P1, "does_not_exist")
	assert_eq(_svc.get_progress(P1, "does_not_exist"), 0)
	assert_false(_svc.is_unlocked(P1, "does_not_exist"))

func test_empty_player_id_is_ignored() -> void:
	_svc.grant_progress("", "first_blood")
	assert_eq(_svc.get_unlocked("").size(), 0)

func test_progress_below_target_does_not_unlock() -> void:
	_svc.grant_progress(P1, "pvp_veteran")  # target = 10
	assert_eq(_svc.get_progress(P1, "pvp_veteran"), 1)
	assert_false(_svc.is_unlocked(P1, "pvp_veteran"))

func test_progress_reaching_target_unlocks() -> void:
	var unlocked: Array = []
	_svc.achievement_unlocked.connect(func(player_id, achievement_id): unlocked.append([player_id, achievement_id]))
	_svc.grant_progress(P1, "first_blood")  # target = 1
	assert_true(_svc.is_unlocked(P1, "first_blood"))
	assert_eq(unlocked, [[P1, "first_blood"]])

func test_progress_does_not_increment_further_after_unlock() -> void:
	_svc.grant_progress(P1, "first_blood")
	_svc.grant_progress(P1, "first_blood")
	_svc.grant_progress(P1, "first_blood")
	assert_eq(_svc.get_progress(P1, "first_blood"), 1, "Nach dem Unlock darf der Zähler nicht weiterlaufen.")

func test_progress_is_per_player() -> void:
	_svc.grant_progress(P1, "first_blood")
	assert_true(_svc.is_unlocked(P1, "first_blood"))
	assert_false(_svc.is_unlocked(P2, "first_blood"))
	assert_eq(_svc.get_progress(P2, "first_blood"), 0)

func test_pvp_veteran_unlocks_after_ten_progress_calls() -> void:
	for i in range(9):
		_svc.grant_progress(P1, "pvp_veteran")
	assert_false(_svc.is_unlocked(P1, "pvp_veteran"))
	_svc.grant_progress(P1, "pvp_veteran")
	assert_true(_svc.is_unlocked(P1, "pvp_veteran"))

func test_achievement_progress_signal_fires_with_current_and_target() -> void:
	var progress_events: Array = []
	_svc.achievement_progress.connect(func(player_id, achievement_id, current, target): progress_events.append([player_id, achievement_id, current, target]))
	_svc.grant_progress(P1, "auctioneer")
	assert_eq(progress_events, [[P1, "auctioneer", 1.0, 10.0]])

func test_get_all_definitions_contains_expected_ids() -> void:
	var defs := _svc.get_all_definitions()
	for id in ["first_blood", "pvp_veteran", "first_sale", "auctioneer", "community_watch", "wanderer", "high_jumper", "gravity_defier", "monster_hunter"]:
		assert_true(defs.has(id))

func test_get_definition_returns_a_copy() -> void:
	var d := _svc.get_definition("first_blood")
	d["target"] = 999
	assert_eq(float(_svc.get_definition("first_blood")["target"]), 1.0)

# ─────────────────────────────────────────────────────────────────────────────
# Trigger-Verdrahtung (PvP / Auction / Report)
# ─────────────────────────────────────────────────────────────────────────────

func test_pvp_death_loss_applied_grants_progress_to_killer_not_victim() -> void:
	_fake_pvp.death_loss_applied.emit(P2, P1, 100, [], 0.25, false)  # victim=P2, killer=P1
	assert_true(_svc.is_unlocked(P1, "first_blood"), "Der Killer muss den Fortschritt bekommen.")
	assert_false(_svc.is_unlocked(P2, "first_blood"), "Das Opfer darf keinen Fortschritt bekommen.")

func test_auction_listing_created_grants_progress_to_seller() -> void:
	_fake_auction.listing_created.emit("listing-123", P1)
	assert_true(_svc.is_unlocked(P1, "first_sale"))
	assert_eq(_svc.get_progress(P1, "auctioneer"), 1)

func test_report_submitted_grants_progress_to_reporter() -> void:
	_fake_report.report_submitted.emit({"reporter_player_id": P1, "reported_player_id": P2, "reason": "spam"})
	assert_true(_svc.is_unlocked(P1, "community_watch"))

func test_on_cleanup_disconnects_trigger_signals() -> void:
	_svc.on_cleanup()
	_fake_pvp.death_loss_applied.emit(P2, P1, 100, [], 0.25, false)
	_fake_stats.stat_changed.emit(P1, "meters_walked", 2000.0, 2000.0)
	assert_false(_svc.is_unlocked(P1, "first_blood"), "Nach on_cleanup() dürfen Trigger-Signale keine Wirkung mehr haben.")
	assert_false(_svc.is_unlocked(P1, "wanderer"), "Nach on_cleanup() dürfen Stats-Trigger keine Wirkung mehr haben.")

# ─────────────────────────────────────────────────────────────────────────────
# Round 103: Stats als vierte Trigger-Quelle
# ─────────────────────────────────────────────────────────────────────────────

func test_stat_changed_grants_progress_to_mapped_achievement() -> void:
	_fake_stats.stat_changed.emit(P1, "meters_walked", 400.0, 400.0)
	assert_eq(_svc.get_progress(P1, "wanderer"), 400.0)
	assert_false(_svc.is_unlocked(P1, "wanderer"))

func test_stat_changed_unlocks_when_target_reached() -> void:
	_fake_stats.stat_changed.emit(P1, "meters_fallen", 500.0, 500.0)
	assert_true(_svc.is_unlocked(P1, "gravity_defier"))

func test_stat_changed_accumulates_across_multiple_batches() -> void:
	_fake_stats.stat_changed.emit(P1, "meters_jumped", 40.0, 40.0)
	_fake_stats.stat_changed.emit(P1, "meters_jumped", 40.0, 80.0)
	assert_false(_svc.is_unlocked(P1, "high_jumper"))
	_fake_stats.stat_changed.emit(P1, "meters_jumped", 40.0, 120.0)
	assert_true(_svc.is_unlocked(P1, "high_jumper"))

func test_stat_changed_ignores_unmapped_stat_names() -> void:
	_fake_stats.stat_changed.emit(P1, "some_future_stat", 9999.0, 9999.0)
	assert_true(_svc.get_unlocked(P1).is_empty())

func test_npcs_killed_stat_unlocks_monster_hunter() -> void:
	for i in range(49):
		_fake_stats.stat_changed.emit(P1, "npcs_killed", 1.0, float(i + 1))
	assert_false(_svc.is_unlocked(P1, "monster_hunter"))
	_fake_stats.stat_changed.emit(P1, "npcs_killed", 1.0, 50.0)
	assert_true(_svc.is_unlocked(P1, "monster_hunter"))

# ─────────────────────────────────────────────────────────────────────────────
# Round 103: Gold-Belohnung bei Unlock
# ─────────────────────────────────────────────────────────────────────────────

func test_unlock_grants_reward_gold_via_currency_service() -> void:
	var currency := SpyCurrencyService.new()
	var svc2 := AchievementService.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.CURRENCY: currency}))

	svc2.grant_progress(P1, "first_blood")  # reward_gold = 50

	assert_eq(currency.add_gold_calls.size(), 1)
	assert_eq(currency.add_gold_calls[0]["player_id"], P1)
	assert_eq(int(currency.add_gold_calls[0]["amount"]), 50)
	svc2.on_cleanup()

func test_unlock_without_currency_service_does_not_crash() -> void:
	# _svc (Standard-Fixture) hat keine CurrencyService injiziert.
	_svc.grant_progress(P1, "first_blood")
	assert_true(_svc.is_unlocked(P1, "first_blood"), "Fehlende CurrencyService darf das Unlock selbst nicht verhindern.")

func test_unlocked_payload_includes_reward_gold() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.grant_progress(P1, "pvp_veteran")  # target=10 — nur um Zähler zu füllen
	for i in range(9):
		_svc.grant_progress(P1, "pvp_veteran")

	assert_eq(int(net.unlock_calls[0]["payload"]["reward_gold"]), 250)

# ─────────────────────────────────────────────────────────────────────────────
# Round 103: Snapshot-Sync
# ─────────────────────────────────────────────────────────────────────────────

func test_request_snapshot_without_peer_calls_on_snapshot_requested_directly() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.grant_progress(P1, "first_blood")
	_svc.request_snapshot(P1)

	assert_eq(net.snapshot_request_calls.size(), 0, "Ohne echten Peer (Tier 1) darf kein RPC versucht werden.")
	assert_eq(net.snapshot_send_calls.size(), 1)
	assert_eq(net.snapshot_send_calls[0]["player_id"], P1)
	var payload: Dictionary = net.snapshot_send_calls[0]["payload"]
	assert_true("first_blood" in (payload["unlocked"] as Array))

func test_on_snapshot_requested_includes_progress_and_unlocked() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.grant_progress(P1, "pvp_veteran")  # 1/10, kein Unlock
	_svc.grant_progress(P1, "first_blood")  # Unlock

	_svc.on_snapshot_requested(P1)

	var payload: Dictionary = net.snapshot_send_calls[0]["payload"]
	assert_eq(float((payload["progress"] as Dictionary)["pvp_veteran"]), 1.0)
	assert_true("first_blood" in (payload["unlocked"] as Array))

func test_on_snapshot_requested_ignores_empty_player_id() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)
	_svc.on_snapshot_requested("")
	assert_eq(net.snapshot_send_calls.size(), 0)

# ─────────────────────────────────────────────────────────────────────────────
# Round 103: Datengetriebene Definitionen (DataService-Merge)
# ─────────────────────────────────────────────────────────────────────────────

class FakeDataService extends DataService:
	var _fake_achievements: Dictionary = {}
	func get_all_achievements() -> Dictionary:
		return _fake_achievements
	func get_achievement(achievement_id: String) -> AchievementDefinition:
		return _fake_achievements.get(achievement_id)

func test_data_service_definitions_override_defaults() -> void:
	var data := FakeDataService.new()
	var custom := AchievementDefinition.new()
	custom.id = "first_blood"
	custom.display_name = "Überschriebener Name"
	custom.description = "Custom-Beschreibung"
	custom.target = 5.0
	custom.category = "combat"
	custom.reward_gold = 999
	data._fake_achievements = {"first_blood": custom}

	var svc2 := AchievementService.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.DATA: data}))

	var def := svc2.get_definition("first_blood")
	assert_eq(String(def["name"]), "Überschriebener Name")
	assert_eq(float(def["target"]), 5.0)
	svc2.on_cleanup()

func test_data_service_definitions_add_new_ids() -> void:
	var data := FakeDataService.new()
	var custom := AchievementDefinition.new()
	custom.id = "brand_new"
	custom.display_name = "Brandneu"
	custom.description = "Ein Achievement, das nur über DataService existiert."
	custom.target = 1.0
	custom.category = "misc"
	data._fake_achievements = {"brand_new": custom}

	var svc2 := AchievementService.new()
	svc2.configure(ServiceDeps.from_dict({ServiceKeys.DATA: data}))

	assert_true(svc2.get_all_definitions().has("brand_new"))
	assert_true(svc2.get_all_definitions().has("first_blood"), "Defaults müssen weiterhin vorhanden sein, nicht komplett ersetzt.")
	svc2.on_cleanup()

func test_works_without_data_service_using_defaults_only() -> void:
	assert_eq(_svc.get_all_definitions().size(), AchievementService.DEFAULT_DEFINITIONS.size())

# ─────────────────────────────────────────────────────────────────────────────
# Netzwerk-Benachrichtigung (ADR-046)
# ─────────────────────────────────────────────────────────────────────────────

func test_unlock_notifies_target_player_via_network() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.grant_progress(P1, "first_blood")

	assert_eq(net.unlock_calls.size(), 1)
	assert_eq(net.unlock_calls[0]["player_id"], P1)
	assert_eq(String(net.unlock_calls[0]["payload"]["achievement_id"]), "first_blood")
	assert_eq(String(net.unlock_calls[0]["payload"]["name"]), "Erstes Blut")

func test_progress_without_unlock_does_not_notify_network() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.grant_progress(P1, "pvp_veteran")  # target = 10, nur 1 Fortschritt

	assert_eq(net.unlock_calls.size(), 0)

# ─────────────────────────────────────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────────────────────────────────────

func test_save_key_is_achievements() -> void:
	assert_eq(_svc.get_save_key(), "achievements")

func test_save_data_round_trip_preserves_progress_and_unlocks() -> void:
	_svc.grant_progress(P1, "first_blood")
	_svc.grant_progress(P1, "auctioneer")
	var snapshot := _svc.get_save_data()

	var svc2 := AchievementService.new()
	svc2.configure(ServiceDeps.from_dict({}))
	svc2._restore_from_save(snapshot)

	assert_true(svc2.is_unlocked(P1, "first_blood"))
	assert_eq(svc2.get_progress(P1, "auctioneer"), 1)
	svc2.on_cleanup()

func test_save_data_empty_by_default() -> void:
	var saved := _svc.get_save_data()
	assert_true((saved["progress"] as Dictionary).is_empty())
	assert_true((saved["unlocked"] as Dictionary).is_empty())

# ─────────────────────────────────────────────────────────────────────────────
# Round 104: Client-Empfang (achievement_unlocked_received/
# achievement_snapshot_received) — bis dahin kam auf einem Nicht-Autoritäts-
# Peer nichts an, siehe AchievementService.gd "CLIENT-EMPFANG".
# ─────────────────────────────────────────────────────────────────────────────

class StubSessionManager extends SessionManager:
	var player_id: String = P1
	func get_local_player_id() -> String:
		return player_id

func _configure_with_network_and_session(net: NetworkBridge, session: SessionManager) -> AchievementService:
	var svc := AchievementService.new()
	svc.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.NETWORK_BRIDGE: net,
		ServiceKeys.SESSION_MANAGER: session,
	}))
	return svc

func test_configure_connects_network_receive_signals() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	var session: StubSessionManager = autofree(StubSessionManager.new())

	var svc := _configure_with_network_and_session(net, session)

	assert_true(net.achievement_unlocked_received.is_connected(svc._on_remote_unlock_received))
	assert_true(net.achievement_snapshot_received.is_connected(svc._on_remote_snapshot_received))
	svc.on_cleanup()

func test_inject_network_bridge_also_connects_receive_signals() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)

	_svc.inject_network_bridge(net)

	assert_true(net.achievement_unlocked_received.is_connected(_svc._on_remote_unlock_received))
	assert_true(net.achievement_snapshot_received.is_connected(_svc._on_remote_snapshot_received))

func test_remote_unlock_received_marks_local_player_unlocked() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	var session: StubSessionManager = autofree(StubSessionManager.new())
	var svc := _configure_with_network_and_session(net, session)

	net.achievement_unlocked_received.emit({"achievement_id": "first_blood", "name": "Erstes Blut", "reward_gold": 50})

	assert_true(svc.is_unlocked(P1, "first_blood"))
	assert_eq(svc.get_progress(P1, "first_blood"), 1.0)
	svc.on_cleanup()

func test_remote_unlock_received_emits_local_signals() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	var session: StubSessionManager = autofree(StubSessionManager.new())
	var svc := _configure_with_network_and_session(net, session)

	var unlocked_seen: Array = []
	svc.achievement_unlocked.connect(func(pid: String, aid: String) -> void: unlocked_seen.append([pid, aid]))
	var progress_seen: Array = []
	svc.achievement_progress.connect(func(pid: String, aid: String, cur: float, tgt: float) -> void: progress_seen.append([pid, aid, cur, tgt]))

	net.achievement_unlocked_received.emit({"achievement_id": "first_blood"})

	assert_eq(unlocked_seen, [[P1, "first_blood"]])
	assert_eq(progress_seen, [[P1, "first_blood", 1.0, 1.0]])
	svc.on_cleanup()

func test_remote_unlock_received_without_session_manager_logs_error_and_does_nothing() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	net.achievement_unlocked_received.emit({"achievement_id": "first_blood"})

	assert_false(_svc.is_unlocked("", "first_blood"))
	assert_eq(_svc.get_unlocked(P1).size(), 0)

func test_remote_snapshot_received_overwrites_local_progress_and_unlocked() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	var session: StubSessionManager = autofree(StubSessionManager.new())
	var svc := _configure_with_network_and_session(net, session)

	net.achievement_snapshot_received.emit({
		"unlocked": ["first_blood"],
		"progress": {"first_blood": 1.0, "auctioneer": 4.0},
	})

	assert_true(svc.is_unlocked(P1, "first_blood"))
	assert_eq(svc.get_progress(P1, "auctioneer"), 4.0)
	svc.on_cleanup()

func test_remote_snapshot_received_emits_achievements_synced_for_local_player() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	var session: StubSessionManager = autofree(StubSessionManager.new())
	var svc := _configure_with_network_and_session(net, session)

	var synced_seen: Array = []
	svc.achievements_synced.connect(func(pid: String) -> void: synced_seen.append(pid))

	net.achievement_snapshot_received.emit({"unlocked": [], "progress": {}})

	assert_eq(synced_seen, [P1])
	svc.on_cleanup()

func test_on_cleanup_disconnects_network_receive_signals() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	var session: StubSessionManager = autofree(StubSessionManager.new())
	var svc := _configure_with_network_and_session(net, session)

	svc.on_cleanup()

	assert_false(net.achievement_unlocked_received.is_connected(svc._on_remote_unlock_received))
	assert_false(net.achievement_snapshot_received.is_connected(svc._on_remote_snapshot_received))

# ─────────────────────────────────────────────────────────────────────────────
# Round 105: CharacterCreationService als Trigger-Quelle (ADR-048)
# ─────────────────────────────────────────────────────────────────────────────

func test_character_created_grants_character_creator_complete() -> void:
	_fake_character_creation.character_created.emit(P1, "wald", ["naturverbunden"])

	assert_true(_svc.is_unlocked(P1, "character_creator_complete"))

func test_character_created_does_not_grant_the_skip_achievement() -> void:
	_fake_character_creation.character_created.emit(P1, "wald", ["naturverbunden"])

	assert_false(_svc.is_unlocked(P1, "character_creator_skipped"))

func test_character_creation_skipped_grants_character_creator_skipped() -> void:
	_fake_character_creation.character_creation_skipped.emit(P1)

	assert_true(_svc.is_unlocked(P1, "character_creator_skipped"))

func test_character_creation_skipped_does_not_grant_the_complete_achievement() -> void:
	_fake_character_creation.character_creation_skipped.emit(P1)

	assert_false(_svc.is_unlocked(P1, "character_creator_complete"))

func test_character_created_for_one_player_does_not_affect_another() -> void:
	_fake_character_creation.character_created.emit(P1, "wald", ["naturverbunden"])

	assert_false(_svc.is_unlocked(P2, "character_creator_complete"))
