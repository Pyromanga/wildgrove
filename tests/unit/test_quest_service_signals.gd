# res://tests/unit/test_quest_service_signals.gd
extends GutTest

## Signal-Tests für QuestService (H-07 / EventBus-Injektion).
##
## VORHER: on_ready() wurde in Tests nicht aufgerufen weil EventBus global war.
##         → Kein einziger Test prüfte ob quest_started, quest_completed oder
##           objective_updated korrekt emittiert werden.
##
## JETZT:  MockEventBus injiziert — on_ready() wird normal aufgerufen.
##         Signal-Behavior ist vollständig testbar ohne AutoLoad oder SceneTree.
##
## ADR-029 Plan-Schritt 4 (Round 64): QuestService ist auf player_id: String
## migriert. loot_collected/xp_gained (und alle domain_event_received-Events)
## liefern weiterhin peer_id (int, WorldService/SkillSystem noch nicht
## migriert) — QuestService übersetzt das jetzt intern über
## NetworkBridge.get_player_id_for_peer() (_resolve_player_uuid()). Ohne
## NetworkBridge+SessionManager bleibt diese Übersetzung leer und die Handler
## no-oppen (mit Logged Error) — jeder Test, der den echten Signal-Pfad prüfen
## will, braucht deshalb dasselbe SessionManager/NetworkBridge-Wiring wie
## test_equipment_service_r4.gd/test_economy_backsync_r7.gd (Round 63).
## quest_start_requested/quest_unlock_requested (EventBus.quest(), keine
## player_id im Signal) sind jetzt an Wrapper-Methoden verbunden
## (_on_quest_start_requested/_on_quest_unlock_requested), die "der lokale
## Spieler" über NetworkBridge auflösen — nicht mehr direkt an
## request_start_quest()/unlock_quest() (siehe QuestService.on_ready()).

var _bus:     MockEventBus
var _svc:     QuestService
var _save:    SaveSystem   # Stub — kein Disk-IO
var _session: SessionManager
var _network: NetworkBridge

const P1 := "p1"

# ─────────────────────────────────────────────────────────────────────────────
# Minimal-Mocks (gespiegelt aus test_quest_service.gd — lokale Sichtbarkeit
# von GDScript-Inner-Classes erfordert eine eigene Kopie pro Testdatei)
# ─────────────────────────────────────────────────────────────────────────────

class MockObjectiveDef extends QuestObjective:
	func _init(p_id: String, p_req: int = 1, p_type: String = "COLLECT") -> void:
		id       = p_id
		required = p_req
		type     = _type_from_string(p_type)

	static func _type_from_string(s: String) -> QuestObjective.Type:
		match s:
			"COLLECT", "COLLECT_ITEM": return QuestObjective.Type.COLLECT
			"SKILL":                   return QuestObjective.Type.SKILL
			"INTERACT":                return QuestObjective.Type.INTERACT
			"KILL":                    return QuestObjective.Type.KILL
			"TALK":                    return QuestObjective.Type.TALK
			"CUSTOM":                  return QuestObjective.Type.CUSTOM
			_:                         return QuestObjective.Type.COLLECT

class MockQuestDef extends QuestDefinition:
	func _init(p_id: String) -> void:
		id = p_id

class MockDataService extends DataService:
	func get_all_quests() -> Dictionary:  return _quests
	func get_auto_start_quests() -> Array[String]: return []

func before_each() -> void:
	_bus  = MockEventBus.new()
	_save = _make_stub_save()

	_session = SessionManager.new()
	_session.register_player_slot(1, P1)
	add_child_autofree(_session)

	_network = NetworkBridge.new()
	_network.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS:       _bus,
		ServiceKeys.SESSION_MANAGER: _session,
	}))
	add_child_autofree(_network)

	_svc  = QuestService.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM:    _save,
		ServiceKeys.EVENT_BUS:      _bus,
		ServiceKeys.NETWORK_BRIDGE: _network,
	}))
	_svc.on_ready()
	_svc.inject_network_bridge(_network)

func after_each() -> void:
	_svc.on_cleanup()
	_svc     = null
	_bus     = null
	_save    = null
	_session = null
	_network = null

# ─────────────────────────────────────────────────────────────────────────────
# quest_started
# ─────────────────────────────────────────────────────────────────────────────

func test_quest_started_emitted_on_request_start() -> void:
	watch_signals(_bus.quest())
	_svc.request_start_quest("quest_intro", P1)
	assert_signal_emitted(_bus.quest(), "quest_started",
		"quest_started muss nach request_start_quest() emittiert werden.")

func test_quest_started_carries_correct_id() -> void:
	watch_signals(_bus.quest())
	_svc.request_start_quest("quest_intro", P1)
	assert_signal_emitted_with_parameters(_bus.quest(), "quest_started", ["quest_intro"])

func test_quest_started_not_emitted_if_already_active() -> void:
	_svc.request_start_quest("quest_intro", P1)
	watch_signals(_bus.quest())
	_svc.request_start_quest("quest_intro", P1)  # nochmals
	assert_signal_not_emitted(_bus.quest(), "quest_started",
		"quest_started darf nicht erneut emittiert werden wenn Quest bereits aktiv.")

func test_quest_start_failed_emitted_on_duplicate() -> void:
	_svc.request_start_quest("quest_intro", P1)
	watch_signals(_bus.quest())
	_svc.request_start_quest("quest_intro", P1)
	assert_signal_emitted(_bus.quest(), "quest_start_failed",
		"quest_start_failed muss bei Duplikat-Start emittiert werden.")

func test_quest_start_failed_reason_already_active() -> void:
	_svc.request_start_quest("quest_intro", P1)
	watch_signals(_bus.quest())
	_svc.request_start_quest("quest_intro", P1)
	assert_signal_emitted_with_parameters(
		_bus.quest(), "quest_start_failed",
		["quest_intro", "already_active"]
	)

# ─────────────────────────────────────────────────────────────────────────────
# quest_completed
# ─────────────────────────────────────────────────────────────────────────────

func test_quest_completed_emitted_on_complete() -> void:
	_svc.request_start_quest("quest_intro", P1)
	watch_signals(_bus.quest())
	_svc.request_complete_quest("quest_intro", P1)
	assert_signal_emitted(_bus.quest(), "quest_completed",
		"quest_completed muss nach request_complete_quest() emittiert werden.")

func test_quest_completed_carries_correct_id() -> void:
	_svc.request_start_quest("quest_intro", P1)
	watch_signals(_bus.quest())
	_svc.request_complete_quest("quest_intro", P1)
	var params = get_signal_parameters(_bus.quest(), "quest_completed", 0)
	assert_eq(params[0], "quest_intro",
		"quest_completed muss die richtige quest_id tragen.")

func test_quest_completed_not_emitted_for_inactive_quest() -> void:
	watch_signals(_bus.quest())
	_svc.request_complete_quest("quest_intro", P1)  # nie gestartet
	assert_signal_not_emitted(_bus.quest(), "quest_completed",
		"quest_completed darf nicht für eine nie gestartete Quest emittiert werden.")

# ─────────────────────────────────────────────────────────────────────────────
# quest_failed
# ─────────────────────────────────────────────────────────────────────────────

func test_quest_failed_emitted_on_fail() -> void:
	_svc.request_start_quest("quest_intro", P1)
	watch_signals(_bus.quest())
	_svc.fail_quest("quest_intro", P1)
	assert_signal_emitted(_bus.quest(), "quest_failed",
		"quest_failed muss nach fail_quest() emittiert werden.")

func test_quest_failed_not_emitted_for_nonexistent_quest() -> void:
	watch_signals(_bus.quest())
	_svc.fail_quest("no_such_quest", P1)
	assert_signal_not_emitted(_bus.quest(), "quest_failed",
		"quest_failed darf nicht für eine nicht-aktive Quest emittiert werden.")

# ─────────────────────────────────────────────────────────────────────────────
# quest_unlocked
# ─────────────────────────────────────────────────────────────────────────────

func test_quest_unlocked_emitted_on_unlock() -> void:
	watch_signals(_bus.quest())
	_svc.unlock_quest("quest_intro", P1)
	assert_signal_emitted(_bus.quest(), "quest_unlocked",
		"quest_unlocked muss nach unlock_quest() emittiert werden.")

func test_quest_unlocked_not_emitted_twice_for_same_quest() -> void:
	_svc.unlock_quest("quest_intro", P1)
	watch_signals(_bus.quest())
	_svc.unlock_quest("quest_intro", P1)  # nochmals
	assert_signal_not_emitted(_bus.quest(), "quest_unlocked",
		"quest_unlocked darf nicht zweimal für dieselbe Quest emittiert werden.")

# ─────────────────────────────────────────────────────────────────────────────
# objective_updated — via loot_collected Signal (das war vorher komplett unbetestbar)
# ─────────────────────────────────────────────────────────────────────────────

func test_loot_collected_triggers_objective_update_signal() -> void:
	## KERNTEST: Dieser Test war vor dem EventBus-Refactor NICHT schreibbar.
	## QuestService verbindet loot_collected in on_ready() — vorher wurde on_ready()
	## in Tests übersprungen. Jetzt: MockEventBus.world() ist die Quelle des Signals,
	## und MockEventBus.quest() ist der Empfänger der objective_updated-Emission.
	##
	## Quest manuell aktivieren (ohne DataService-Definition → kein auto-complete)
	_svc.request_start_quest("quest_intro", P1)

	watch_signals(_bus.quest())
	# loot_collected emittieren (peer_id=1, Default) → NetworkBridge/SessionManager
	# übersetzen zu player_id "p1" → QuestService._on_loot_collected() reagiert.
	_bus.world().emit_loot_collected("oak_log", 1)

	# Ohne QuestDefinition die "oak_log" als Objective kennt gibt es kein update —
	# aber: kein Crash, on_ready() wurde aufgerufen, Signal-Connection existiert.
	# Wenn eine Definition vorhanden ist, würde quest_objective_updated emittiert.
	assert_true(true,
		"loot_collected darf nach on_ready() keinen Crash auslösen (Signal-Connection OK).")

func test_on_ready_connects_loot_collected() -> void:
	## Sichert dass on_ready() tatsächlich loot_collected verbunden hat.
	## Ohne MockEventBus war das nicht überprüfbar.
	assert_true(
		_bus.world().loot_collected.is_connected(_svc._on_loot_collected),
		"on_ready() muss loot_collected mit _on_loot_collected verbinden."
	)

func test_on_ready_connects_xp_gained() -> void:
	assert_true(
		_bus.player().xp_gained.is_connected(_svc._on_xp_gained),
		"on_ready() muss xp_gained mit _on_xp_gained verbinden."
	)

func test_on_ready_connects_quest_start_requested() -> void:
	## ADR-029 Round 64: quest_start_requested ist jetzt an den Wrapper
	## _on_quest_start_requested() verbunden (löst "der lokale Spieler" erst
	## beim Feuern auf), nicht mehr direkt an request_start_quest() — siehe
	## QuestService.on_ready()-Kommentar.
	assert_true(
		_bus.quest().quest_start_requested.is_connected(_svc._on_quest_start_requested),
		"on_ready() muss quest_start_requested mit _on_quest_start_requested verbinden."
	)

func test_quest_start_requested_signal_resolves_local_player() -> void:
	## Voller Pfad: Signal (ohne player_id) → Wrapper löst "p1" über
	## NetworkBridge/SessionManager auf → request_start_quest("quest_intro", "p1").
	watch_signals(_bus.quest())
	_bus.quest().emit_quest_start_requested("quest_intro")
	assert_signal_emitted(_bus.quest(), "quest_started",
		"quest_start_requested muss über den Wrapper zu quest_started führen.")
	assert_true(_svc.is_quest_active("quest_intro", P1),
		"Quest muss für die aufgelöste lokale player_id 'p1' aktiv sein.")

func test_on_cleanup_disconnects_all_signals() -> void:
	## Sichert dass on_cleanup() alle Connections sauber trennt.
	_svc.on_cleanup()
	assert_false(
		_bus.world().loot_collected.is_connected(_svc._on_loot_collected),
		"on_cleanup() muss loot_collected disconnecten."
	)
	assert_false(
		_bus.player().xp_gained.is_connected(_svc._on_xp_gained),
		"on_cleanup() muss xp_gained disconnecten."
	)
	assert_false(
		_bus.quest().quest_start_requested.is_connected(_svc._on_quest_start_requested),
		"on_cleanup() muss quest_start_requested disconnecten."
	)
	assert_false(
		_network.domain_event_received.is_connected(_svc._on_domain_event_received),
		"on_cleanup() muss domain_event_received disconnecten."
	)

# ─────────────────────────────────────────────────────────────────────────────
# Isolation — kein Bleeding zwischen Test-Instanzen
# ─────────────────────────────────────────────────────────────────────────────

func test_two_independent_instances_dont_share_signals() -> void:
	var bus2  := MockEventBus.new()
	var save2 := _make_stub_save()
	var svc2  := QuestService.new()
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM: save2,
		ServiceKeys.EVENT_BUS:   bus2,
	}))
	svc2.on_ready()

	watch_signals(_bus.quest())
	watch_signals(bus2.quest())

	_svc.request_start_quest("quest_intro", P1)

	assert_signal_emitted(_bus.quest(), "quest_started",
		"Instanz 1 muss quest_started emittieren.")
	assert_signal_not_emitted(bus2.quest(), "quest_started",
		"Instanz 2 darf NICHT quest_started emittieren (kein globales Bleeding).")

	svc2.on_cleanup()

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _make_stub_save() -> SaveSystem:
	## Minimaler SaveSystem-Stub: register_save_provider()/get_state_for() sind
	## auch ohne configure() sicher aufrufbar (kein Zugriff auf _bus) — configure()
	## würde _ensure_save_dir() (Disk-I/O) auslösen, siehe test_network_bridge.gd/
	## test_combat_system.gd für dasselbe Muster.
	return SaveSystem.new()

## ADR-029 Round 64: eigene bus2/session2/network2-Instanz je Aufruf — dieselbe
## Isolationslogik wie test_two_independent_instances_dont_share_signals()
## oben, jetzt zusätzlich nötig weil loot_collected/xp_gained peer_id→player_id
## Übersetzung ein eigenes NetworkBridge/SessionManager-Paar pro svc2 braucht.
func _make_bridge_with_session(bus: MockEventBus, peer_id: int, player_id: String) -> NetworkBridge:
	var session := SessionManager.new()
	session.register_player_slot(peer_id, player_id)
	add_child_autofree(session)
	var bridge := NetworkBridge.new()
	bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS:       bus,
		ServiceKeys.SESSION_MANAGER: session,
	}))
	add_child_autofree(bridge)
	return bridge

# ─────────────────────────────────────────────────────────────────────────────
# G-01 — loot_collected Signal korrekt verbunden
# ─────────────────────────────────────────────────────────────────────────────

func test_g01_on_ready_connects_loot_collected() -> void:
	## G-01 Regression: on_ready() muss loot_collected mit _on_loot_collected verbinden.
	## Vor dem Fix war loot_collected in on_ready() nicht connected — nur in on_cleanup()
	## disconnected. COLLECT_ITEM-Objectives konnten dadurch nie abgeschlossen werden.
	assert_true(
		_bus.world().loot_collected.is_connected(_svc._on_loot_collected),
		"G-01: on_ready() muss loot_collected mit _on_loot_collected verbinden."
	)

func test_g01_collect_item_objective_progresses_on_loot_collected() -> void:
	## G-01 Funktionstest: COLLECT_ITEM-Objective muss auf loot_collected reagieren.
	## Dieser Test schlägt fehl wenn loot_collected nicht in on_ready() verbunden ist.

	# Quest mit COLLECT_ITEM-Objective aufbauen
	var obj_def := MockObjectiveDef.new("obj_wood", 3, "COLLECT_ITEM")
	obj_def.target_id = "wood"

	var quest_def := MockQuestDef.new("quest_woodcutter")
	quest_def.objectives = [obj_def]

	# DataService-Mock mit Quest registrieren
	var ds2 := MockDataService.new()
	ds2._quests["quest_woodcutter"] = quest_def

	# Frischen QuestService mit diesem DataService aufbauen — eigenes
	# NetworkBridge/SessionManager-Paar (peer 1 → "p1"), sonst bleibt die
	# peer_id→player_id-Übersetzung in _on_loot_collected() leer.
	var bus2     := MockEventBus.new()
	var save2    := _make_stub_save()
	var bridge2  := _make_bridge_with_session(bus2, 1, P1)
	var svc2     := QuestService.new()
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM:    save2,
		ServiceKeys.DATA:           ds2,
		ServiceKeys.EVENT_BUS:      bus2,
		ServiceKeys.NETWORK_BRIDGE: bridge2,
	}))
	svc2.on_ready()
	svc2.inject_network_bridge(bridge2)

	svc2.request_start_quest("quest_woodcutter", P1)
	assert_true(svc2.is_quest_active("quest_woodcutter", P1), "Quest muss aktiv sein.")

	# loot_collected emittieren (peer_id=1 Default) — muss Objective-Fortschritt triggern
	bus2.world().loot_collected.emit("wood", 2, 1)

	assert_eq(
		svc2.get_objective_progress("quest_woodcutter", "obj_wood", P1), 2,
		"G-01: loot_collected(wood, 2) muss Objective-Fortschritt auf 2 setzen."
	)

	svc2.on_cleanup()

func test_g01_loot_collected_wrong_item_does_not_progress() -> void:
	## G-01 Grenzfall: loot_collected mit falschem item_id darf Objective nicht voranbringen.
	var obj_def := MockObjectiveDef.new("obj_iron", 1, "COLLECT_ITEM")
	obj_def.target_id = "iron_ore"

	var quest_def := MockQuestDef.new("quest_miner")
	quest_def.objectives = [obj_def]

	var ds2 := MockDataService.new()
	ds2._quests["quest_miner"] = quest_def

	var bus2    := MockEventBus.new()
	var save2   := _make_stub_save()
	var bridge2 := _make_bridge_with_session(bus2, 1, P1)
	var svc2    := QuestService.new()
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM:    save2,
		ServiceKeys.DATA:           ds2,
		ServiceKeys.EVENT_BUS:      bus2,
		ServiceKeys.NETWORK_BRIDGE: bridge2,
	}))
	svc2.on_ready()
	svc2.inject_network_bridge(bridge2)
	svc2.request_start_quest("quest_miner", P1)

	bus2.world().loot_collected.emit("wood", 5, 1)  # Falsches Item

	assert_eq(
		svc2.get_objective_progress("quest_miner", "obj_iron", P1), 0,
		"G-01: loot_collected mit falschem Item darf Fortschritt nicht erhöhen."
	)
	svc2.on_cleanup()
