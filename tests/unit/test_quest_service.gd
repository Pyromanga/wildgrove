# res://tests/unit/test_quest_service.gd
extends GutTest

## Unit-Tests für QuestService (E-02).
##
## Strategie: QuestService ohne SceneTree instanziieren.
## configure() erhält minimale Mock-Services.
## on_ready() wird NICHT aufgerufen (EventBus-Connects überspringen), außer in
## den TALK/CUSTOM-Tests weiter unten, die den vollen domain_event_received-Pfad
## brauchen.
## Direkter Aufruf von request_start_quest / request_complete_quest /
## update_objective für Tier-1-Pfade.
##
## ADR-029 Plan-Schritt 4 (Round 64): player_id ist jetzt player_uuid (String,
## Pflichtparameter, kein Default mehr) statt peer_id (int, Default 1). P1/P2
## sind hier reine opake Test-Bucket-Keys, keine echten UUIDs — das genügt,
## QuestService behandelt player_id ohnehin nur als Dictionary-Key. Die
## früheren `active_quests`/`completed_quests`/`available_quests`-Properties
## sind jetzt Methoden `get_active_quests(player_id)`/etc. (siehe
## QuestService.gd Klassenkommentar).
##
## Abgedeckt:
##   - request_start_quest(): start, already_active, already_completed, prereq_missing
##   - request_complete_quest(): normal, not_active
##   - fail_quest(): normal, not_active
##   - unlock_quest(): unlock, duplicate-ignore, already-active-ignore
##   - update_objective(): progress, auto-complete bei Ziel erfüllt
##   - is_quest_active() / is_quest_completed()
##   - Multi-Tenanz: zwei player_ids unabhängig
##   - get_save_key() / get_save_data()
##   - Save-Round-Trip
##   - TALK/CUSTOM-Objectives über den vollen domain_event_received-Pfad

# ─────────────────────────────────────────────────────────────────────────────
# Minimal-Mocks
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

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────

var _svc: QuestService
var _ds:  MockDataService
var _bus: MockEventBus

const Q_SIMPLE  := "quest_simple"
const Q_PREREQ  := "quest_prereq"
const Q_OBJ     := "quest_objective"
const P1        := "p1"
const P2        := "p2"

func before_each() -> void:
	_ds  = MockDataService.new()
	_bus = MockEventBus.new()

	# Einfache Quest ohne Voraussetzungen
	var q_simple := MockQuestDef.new(Q_SIMPLE)
	_ds._quests[Q_SIMPLE] = q_simple

	# Quest mit Voraussetzung
	var q_prereq := MockQuestDef.new(Q_PREREQ)
	q_prereq.prerequisites = [Q_SIMPLE]
	_ds._quests[Q_PREREQ] = q_prereq

	# Quest mit einem Objective (COLLECT 5x)
	var q_obj := MockQuestDef.new(Q_OBJ)
	q_obj.objectives = [MockObjectiveDef.new("obj_collect", 5, "COLLECT")]
	_ds._quests[Q_OBJ] = q_obj

	_svc = QuestService.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:       _ds,
		ServiceKeys.SAVE_SYSTEM: MockSaveSystemNoop.new(),
		ServiceKeys.EVENT_BUS:  _bus,
	}))
	# on_ready() bewusst NICHT aufrufen — kein SceneTree-Signal-Connect nötig

class MockSaveSystemNoop extends SaveSystem:
	func register_save_provider(_p) -> void: pass
	func get_state_for(_key: String) -> Dictionary: return {}

func after_each() -> void:
	_svc.on_cleanup()
	_svc = null

# ─────────────────────────────────────────────────────────────────────────────
# request_start_quest
# ─────────────────────────────────────────────────────────────────────────────

func test_start_quest_sets_active() -> void:
	var ok := _svc.request_start_quest(Q_SIMPLE, P1)
	assert_true(ok, "request_start_quest() muss true zurückgeben")
	assert_true(_svc.is_quest_active(Q_SIMPLE, P1), "Quest muss aktiv sein nach Start")

func test_start_empty_id_returns_false() -> void:
	var ok := _svc.request_start_quest("", P1)
	assert_false(ok, "Leere ID → false")

func test_start_already_active_returns_false() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	var ok := _svc.request_start_quest(Q_SIMPLE, P1)
	assert_false(ok, "Bereits aktive Quest → false")

func test_start_already_completed_returns_false() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	_svc.request_complete_quest(Q_SIMPLE, P1)
	var ok := _svc.request_start_quest(Q_SIMPLE, P1)
	assert_false(ok, "Abgeschlossene Quest → false")

func test_start_with_unmet_prereq_returns_false() -> void:
	var ok := _svc.request_start_quest(Q_PREREQ, P1)
	assert_false(ok, "Fehlende Voraussetzung → false")
	assert_false(_svc.is_quest_active(Q_PREREQ, P1), "Quest darf nicht aktiv sein")

func test_start_with_met_prereq_succeeds() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	_svc.request_complete_quest(Q_SIMPLE, P1)
	var ok := _svc.request_start_quest(Q_PREREQ, P1)
	assert_true(ok, "Erfüllte Voraussetzung → Quest kann starten")

# ─────────────────────────────────────────────────────────────────────────────
# request_complete_quest
# ─────────────────────────────────────────────────────────────────────────────

func test_complete_quest_moves_to_completed() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	_svc.request_complete_quest(Q_SIMPLE, P1)
	assert_false(_svc.is_quest_active(Q_SIMPLE, P1),    "Nicht mehr aktiv nach Abschluss")
	assert_true( _svc.is_quest_completed(Q_SIMPLE, P1), "Muss als abgeschlossen markiert sein")

func test_complete_inactive_quest_is_noop() -> void:
	_svc.request_complete_quest(Q_SIMPLE, P1)  # nie gestartet
	assert_false(_svc.is_quest_completed(Q_SIMPLE, P1), "Nie gestartete Quest kann nicht abgeschlossen werden")

# ─────────────────────────────────────────────────────────────────────────────
# SEC-03: Completion muss gegen tatsächlichen Objective-Fortschritt verifiziert werden
# ─────────────────────────────────────────────────────────────────────────────

func test_complete_quest_with_unmet_objective_is_rejected() -> void:
	# Q_OBJ braucht obj_collect x5 — request_complete_quest() direkt (ohne
	# vorheriges update_objective()) darf NICHT durchgehen. Simuliert einen
	# Aufrufer (z.B. modifizierter Client per RPC), der Completion beansprucht
	# ohne den Fortschritt tatsächlich erreicht zu haben.
	_svc.request_start_quest(Q_OBJ, P1)
	_svc.request_complete_quest(Q_OBJ, P1)
	assert_true(_svc.is_quest_active(Q_OBJ, P1), "Quest muss trotz Completion-Claim aktiv bleiben")
	assert_false(_svc.is_quest_completed(Q_OBJ, P1), "Quest darf ohne erfüllte Objectives nicht als abgeschlossen gelten")

func test_complete_quest_with_partially_met_objective_is_rejected() -> void:
	_svc.request_start_quest(Q_OBJ, P1)
	_svc.update_objective(Q_OBJ, "obj_collect", 3, P1)  # required = 5 → noch nicht genug
	_svc.request_complete_quest(Q_OBJ, P1)
	assert_true(_svc.is_quest_active(Q_OBJ, P1), "Quest muss bei unvollständigem Fortschritt aktiv bleiben")
	assert_false(_svc.is_quest_completed(Q_OBJ, P1), "Quest darf bei unvollständigem Fortschritt nicht abgeschlossen werden")

func test_complete_quest_with_fully_met_objective_succeeds() -> void:
	_svc.request_start_quest(Q_OBJ, P1)
	_svc.update_objective(Q_OBJ, "obj_collect", 5, P1)  # required = 5 → erfüllt
	# Bereits durch Auto-Complete in update_objective() abgeschlossen — expliziter
	# zweiter request_complete_quest()-Aufruf muss ein no-op sein (nicht mehr aktiv).
	_svc.request_complete_quest(Q_OBJ, P1)
	assert_true(_svc.is_quest_completed(Q_OBJ, P1), "Quest muss bei vollständig erfülltem Objective abgeschlossen sein")

func test_complete_quest_unknown_definition_still_completes_without_reward() -> void:
	# Bestehendes, bewusst permissives Verhalten für Quests ohne registrierte
	# Definition (siehe test_quest_service_signals.gd "quest_intro"): kein Reward
	# möglich (reward leitet sich aus def.reward ab) → kein Exploit-Vektor, also
	# nicht blockiert, um bestehende Aufrufer nicht zu brechen.
	_ds._quests.erase(Q_SIMPLE)
	_svc._definitions = _ds._quests
	_svc.request_start_quest(Q_SIMPLE, P1)
	_svc.request_complete_quest(Q_SIMPLE, P1)
	assert_true(_svc.is_quest_completed(Q_SIMPLE, P1), "Unbekannte Definition darf Completion nicht blockieren")

# ─────────────────────────────────────────────────────────────────────────────
# fail_quest
# ─────────────────────────────────────────────────────────────────────────────

func test_fail_quest_removes_from_active() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	_svc.fail_quest(Q_SIMPLE, P1)
	assert_false(_svc.is_quest_active(Q_SIMPLE, P1), "Fehlgeschlagene Quest darf nicht aktiv sein")

func test_fail_inactive_quest_is_noop() -> void:
	_svc.fail_quest(Q_SIMPLE, P1)  # kein Crash erwartet
	assert_false(_svc.is_quest_active(Q_SIMPLE, P1), "Nicht-aktive Quest bleibt inaktiv")

# ─────────────────────────────────────────────────────────────────────────────
# unlock_quest
# ─────────────────────────────────────────────────────────────────────────────

func test_unlock_adds_to_available() -> void:
	_svc.unlock_quest(Q_PREREQ, P1)
	assert_true(_svc.get_available_quests(P1).has(Q_PREREQ), "Quest muss in available_quests erscheinen")

func test_unlock_duplicate_is_ignored() -> void:
	_svc.unlock_quest(Q_PREREQ, P1)
	_svc.unlock_quest(Q_PREREQ, P1)
	var count := _svc.get_available_quests(P1).count(Q_PREREQ)
	assert_eq(count, 1, "Doppeltes Unlock darf keinen Duplicate-Eintrag erzeugen")

func test_unlock_already_active_is_ignored() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	_svc.unlock_quest(Q_SIMPLE, P1)
	assert_false(_svc.get_available_quests(P1).has(Q_SIMPLE), "Aktive Quest darf nicht in available erscheinen")

func test_unlock_already_completed_is_ignored() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	_svc.request_complete_quest(Q_SIMPLE, P1)
	_svc.unlock_quest(Q_SIMPLE, P1)
	assert_false(_svc.get_available_quests(P1).has(Q_SIMPLE), "Abgeschlossene Quest darf nicht in available erscheinen")

# ─────────────────────────────────────────────────────────────────────────────
# update_objective / Auto-Complete
# ─────────────────────────────────────────────────────────────────────────────

func test_update_objective_tracks_progress() -> void:
	_svc.request_start_quest(Q_OBJ, P1)
	_svc.update_objective(Q_OBJ, "obj_collect", 3, P1)
	var progress := _svc.get_objective_progress(Q_OBJ, "obj_collect", P1)
	assert_eq(progress, 3, "Fortschritt muss 3 sein nach +3")

func test_update_objective_accumulates() -> void:
	_svc.request_start_quest(Q_OBJ, P1)
	_svc.update_objective(Q_OBJ, "obj_collect", 2, P1)
	_svc.update_objective(Q_OBJ, "obj_collect", 2, P1)
	var progress := _svc.get_objective_progress(Q_OBJ, "obj_collect", P1)
	assert_eq(progress, 4, "Fortschritt muss 4 sein nach 2×2")

func test_objective_auto_completes_quest() -> void:
	_svc.request_start_quest(Q_OBJ, P1)
	_svc.update_objective(Q_OBJ, "obj_collect", 5, P1)  # required = 5 → Auto-Complete
	assert_false(_svc.is_quest_active(Q_OBJ, P1),    "Quest darf nach Auto-Complete nicht aktiv sein")
	assert_true( _svc.is_quest_completed(Q_OBJ, P1), "Quest muss nach Auto-Complete abgeschlossen sein")

func test_update_objective_inactive_quest_is_noop() -> void:
	_svc.update_objective(Q_OBJ, "obj_collect", 5, P1)  # Q_OBJ nie gestartet
	assert_false(_svc.is_quest_active(Q_OBJ, P1),    "Nicht-gestartete Quest bleibt inaktiv")
	assert_false(_svc.is_quest_completed(Q_OBJ, P1), "Nicht-gestartete Quest nicht abgeschlossen")

# ─────────────────────────────────────────────────────────────────────────────
# Multi-Tenanz
# ─────────────────────────────────────────────────────────────────────────────

func test_two_players_independent_quest_state() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	assert_true( _svc.is_quest_active(Q_SIMPLE, P1), "Spieler 1: Quest aktiv")
	assert_false(_svc.is_quest_active(Q_SIMPLE, P2), "Spieler 2: Quest nicht aktiv")

func test_complete_for_player1_does_not_affect_player2() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	_svc.request_start_quest(Q_SIMPLE, P2)
	_svc.request_complete_quest(Q_SIMPLE, P1)
	assert_true( _svc.is_quest_completed(Q_SIMPLE, P1), "Spieler 1: abgeschlossen")
	assert_false(_svc.is_quest_completed(Q_SIMPLE, P2), "Spieler 2: noch aktiv")

# ─────────────────────────────────────────────────────────────────────────────
# Save-Interface
# ─────────────────────────────────────────────────────────────────────────────

func test_save_key_is_quest_progress() -> void:
	assert_eq(_svc.get_save_key(), "quest_progress", "SAVE_KEY muss 'quest_progress' sein")

func test_save_data_contains_player_bucket() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	var sd := _svc.get_save_data()
	assert_true(sd.has(P1), "Save-Daten müssen den Player-1-Bucket (Key '%s') enthalten" % P1)

func test_save_data_reflects_completed() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	_svc.request_complete_quest(Q_SIMPLE, P1)
	var sd := _svc.get_save_data()
	var bucket := sd[P1] as Dictionary
	var completed := bucket["completed"] as Array
	assert_true(completed.has(Q_SIMPLE), "Abgeschlossene Quest muss im Snapshot sein")

# ─────────────────────────────────────────────────────────────────────────────
# Save-Round-Trip (A-04)
# ─────────────────────────────────────────────────────────────────────────────

func test_round_trip_restores_active_quest() -> void:
	_svc.request_start_quest(Q_OBJ, P1)
	_svc.update_objective(Q_OBJ, "obj_collect", 3, P1)
	var snapshot := _svc.get_save_data()

	var svc2 := QuestService.new()
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: _ds,
		ServiceKeys.SAVE_SYSTEM: MockSaveSystemNoop.new(),
		ServiceKeys.EVENT_BUS: MockEventBus.new(),
	}))
	svc2._restore_from_save(snapshot)

	assert_true(svc2.is_quest_active(Q_OBJ, P1), "Round-Trip: Quest muss aktiv sein")
	assert_eq(svc2.get_objective_progress(Q_OBJ, "obj_collect", P1), 3,
		"Round-Trip: Fortschritt muss 3 sein")
	svc2.on_cleanup()

func test_round_trip_restores_completed_quest() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	_svc.request_complete_quest(Q_SIMPLE, P1)
	var snapshot := _svc.get_save_data()

	var svc2 := QuestService.new()
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: _ds,
		ServiceKeys.SAVE_SYSTEM: MockSaveSystemNoop.new(),
		ServiceKeys.EVENT_BUS: MockEventBus.new(),
	}))
	svc2._restore_from_save(snapshot)

	assert_true(svc2.is_quest_completed(Q_SIMPLE, P1), "Round-Trip: Quest muss abgeschlossen sein")
	svc2.on_cleanup()

func test_round_trip_empty_save_produces_empty_state() -> void:
	var svc2 := QuestService.new()
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: _ds,
		ServiceKeys.SAVE_SYSTEM: MockSaveSystemNoop.new(),
		ServiceKeys.EVENT_BUS: MockEventBus.new(),
	}))
	svc2._restore_from_save({})

	assert_false(svc2.is_quest_active(Q_SIMPLE, P1),    "Kein aktiver Quest nach leerem Restore")
	assert_false(svc2.is_quest_completed(Q_SIMPLE, P1), "Kein abgeschlossener Quest nach leerem Restore")
	svc2.on_cleanup()

# ─────────────────────────────────────────────────────────────────────────────
# TALK / CUSTOM Objectives (Runde 6 — vorher Enum-Einträge ohne Handler)
# ─────────────────────────────────────────────────────────────────────────────

func test_on_npc_talked_to_updates_talk_objective() -> void:
	var q := MockQuestDef.new("quest_talk")
	q.objectives = [MockObjectiveDef.new("obj_talk", 1, "TALK")]
	_ds._quests["quest_talk"] = q
	_svc._definitions = _ds._quests
	_svc.request_start_quest("quest_talk", P1)

	# Direkter update_objective()-Pfad (kein target_id gesetzt) — der volle
	# Signal-Pfad über QuestObjectiveHandler.resolve_talk() wird separat unten
	# mit echten QuestDefinition/QuestObjective-Instanzen abgedeckt.
	_svc.update_objective("quest_talk", "obj_talk", 1, P1)
	assert_eq(_svc.get_objective_progress("quest_talk", "obj_talk", P1), 1,
		"TALK-Objective muss via update_objective() Fortschritt verzeichnen")

func test_on_custom_objective_triggered_updates_custom_objective() -> void:
	var q := MockQuestDef.new("quest_custom")
	q.objectives = [MockObjectiveDef.new("obj_custom", 1, "CUSTOM")]
	_ds._quests["quest_custom"] = q
	_svc._definitions = _ds._quests
	_svc.request_start_quest("quest_custom", P1)

	_svc.update_objective("quest_custom", "obj_custom", 1, P1)
	assert_eq(_svc.get_objective_progress("quest_custom", "obj_custom", P1), 1,
		"CUSTOM-Objective muss via update_objective() Fortschritt verzeichnen")

# ─────────────────────────────────────────────────────────────────────────────
# TALK / CUSTOM über den vollen Signal-Pfad — ADR-021 (R-5) Option C:
#
# BEFUND (unabhängig von der player_id-Migration dieser Runde, beim
# Aktualisieren dieser Datei entdeckt): die vier Tests, die früher hier
# standen (test_npc_talked_to_signal_triggers_handler_when_connected,
# test_npc_talked_to_wrong_npc_id_does_not_update,
# test_custom_objective_triggered_signal_triggers_handler_when_connected,
# test_custom_objective_triggered_wrong_key_does_not_update) sowie die beiden
# on_cleanup()-Tests darunter griffen auf `_svc._on_npc_talked_to`/
# `_svc._on_custom_objective_triggered` und `_bus.quest().npc_talked_to`/
# `custom_objective_triggered` zu — Methoden/Signale, die es seit ADR-021
# (Option C, "kein direkter EventBus-Connect mehr, nur noch über
# domain_event_received") in QuestService nicht mehr gibt (siehe
# QuestService.on_ready()-Kommentar). Diese sechs Tests waren dadurch bereits
# vor dieser Migrationsrunde defekt (Zugriff auf nicht-existente Methoden) —
## kein durch Round 64 eingeführter Regressionsfund, aber beim Umschreiben
## dieser Datei mitgefixt, weil sonst die Datei insgesamt weiterhin nicht lauffähig wäre.
#
# Ersetzt durch: Tests gegen den TATSÄCHLICHEN aktuellen Pfad —
# NetworkBridge.domain_event_received → QuestService._on_domain_event_received().
# ─────────────────────────────────────────────────────────────────────────────

func _make_bridge_with_session(bus: MockEventBus, peer_id: int, player_id: String) -> NetworkBridge:
	var session := SessionManager.new()
	session.register_player_slot(peer_id, player_id)
	add_child_autofree(session)
	var bridge := NetworkBridge.new()
	bridge.configure(ServiceDeps.from_dict({
		ServiceKeys.EVENT_BUS:      bus,
		ServiceKeys.SESSION_MANAGER: session,
	}))
	add_child_autofree(bridge)
	return bridge

func test_domain_event_npc_talked_to_updates_talk_objective_via_full_path() -> void:
	var def := QuestDefinition.new()
	def.id = "quest_real_talk"
	var obj := QuestObjective.new()
	obj.id        = "obj_talk_erik"
	obj.type      = QuestObjective.Type.TALK
	obj.target_id = "erik_woodcutter"
	obj.required  = 1
	def.objectives = [obj]
	_ds._quests["quest_real_talk"] = def
	_svc._definitions = _ds._quests

	var bridge := _make_bridge_with_session(_bus, 1, P1)
	_svc.inject_network_bridge(bridge)
	_svc.request_start_quest("quest_real_talk", P1)

	bridge.domain_event_received.emit("npc_talked_to", {"npc_id": "erik_woodcutter"}, 1)

	assert_eq(_svc.get_objective_progress("quest_real_talk", "obj_talk_erik", P1), 1,
		"domain_event_received('npc_talked_to') muss TALK-Objective über den vollen Pfad aktualisieren")

func test_domain_event_npc_talked_to_wrong_npc_id_does_not_update() -> void:
	var def := QuestDefinition.new()
	def.id = "quest_real_talk2"
	var obj := QuestObjective.new()
	obj.id        = "obj_talk_erik"
	obj.type      = QuestObjective.Type.TALK
	obj.target_id = "erik_woodcutter"
	obj.required  = 1
	def.objectives = [obj]
	_ds._quests["quest_real_talk2"] = def
	_svc._definitions = _ds._quests

	var bridge := _make_bridge_with_session(_bus, 1, P1)
	_svc.inject_network_bridge(bridge)
	_svc.request_start_quest("quest_real_talk2", P1)

	bridge.domain_event_received.emit("npc_talked_to", {"npc_id": "some_other_npc"}, 1)

	assert_eq(_svc.get_objective_progress("quest_real_talk2", "obj_talk_erik", P1), 0,
		"domain_event_received('npc_talked_to') mit falscher npc_id darf Objective nicht aktualisieren")

func test_domain_event_custom_objective_triggered_updates_custom_objective_via_full_path() -> void:
	var def := QuestDefinition.new()
	def.id = "quest_real_custom"
	var obj := QuestObjective.new()
	obj.id        = "obj_explore"
	obj.type      = QuestObjective.Type.CUSTOM
	obj.target_id = "erik_camp_explored"
	obj.required  = 1
	def.objectives = [obj]
	_ds._quests["quest_real_custom"] = def
	_svc._definitions = _ds._quests

	var bridge := _make_bridge_with_session(_bus, 1, P1)
	_svc.inject_network_bridge(bridge)
	_svc.request_start_quest("quest_real_custom", P1)

	bridge.domain_event_received.emit("custom_objective_triggered", {"signal_key": "erik_camp_explored"}, 1)

	assert_eq(_svc.get_objective_progress("quest_real_custom", "obj_explore", P1), 1,
		"domain_event_received('custom_objective_triggered') muss CUSTOM-Objective über den vollen Pfad aktualisieren")

func test_domain_event_custom_objective_triggered_wrong_key_does_not_update() -> void:
	var def := QuestDefinition.new()
	def.id = "quest_real_custom2"
	var obj := QuestObjective.new()
	obj.id        = "obj_explore"
	obj.type      = QuestObjective.Type.CUSTOM
	obj.target_id = "erik_camp_explored"
	obj.required  = 1
	def.objectives = [obj]
	_ds._quests["quest_real_custom2"] = def
	_svc._definitions = _ds._quests

	var bridge := _make_bridge_with_session(_bus, 1, P1)
	_svc.inject_network_bridge(bridge)
	_svc.request_start_quest("quest_real_custom2", P1)

	bridge.domain_event_received.emit("custom_objective_triggered", {"signal_key": "wrong_key"}, 1)

	assert_eq(_svc.get_objective_progress("quest_real_custom2", "obj_explore", P1), 0,
		"domain_event_received('custom_objective_triggered') mit falschem Key darf Objective nicht aktualisieren")

func test_inject_network_bridge_connects_domain_event_received() -> void:
	var bridge := _make_bridge_with_session(_bus, 1, P1)
	_svc.inject_network_bridge(bridge)
	assert_true(
		bridge.domain_event_received.is_connected(_svc._on_domain_event_received),
		"inject_network_bridge() muss domain_event_received mit _on_domain_event_received verbinden."
	)

func test_on_cleanup_disconnects_domain_event_received() -> void:
	var bridge := _make_bridge_with_session(_bus, 1, P1)
	_svc.inject_network_bridge(bridge)
	_svc.on_cleanup()
	assert_false(
		bridge.domain_event_received.is_connected(_svc._on_domain_event_received),
		"on_cleanup() muss domain_event_received disconnecten."
	)

# ─────────────────────────────────────────────────────────────────────────────
# get_active_quests() / get_completed_quests() / get_quest_definition() /
# on_local_identity_ready() (Round 113 Nachtrag, siehe
# method_reference_coverage.py-Fund)
# ─────────────────────────────────────────────────────────────────────────────

class MockDataServiceAutoStart extends MockDataService:
	var _auto_start: Array[String] = []
	func get_auto_start_quests() -> Array[String]:
		return _auto_start

func test_get_active_quests_reflects_started_quest() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	assert_true(_svc.get_active_quests(P1).has(Q_SIMPLE))

func test_get_active_quests_empty_for_unknown_player() -> void:
	assert_true(_svc.get_active_quests("nobody").is_empty())

func test_get_completed_quests_reflects_completed_quest() -> void:
	_svc.request_start_quest(Q_SIMPLE, P1)
	_svc.request_complete_quest(Q_SIMPLE, P1)
	assert_true(_svc.get_completed_quests(P1).has(Q_SIMPLE))

func test_get_completed_quests_empty_for_unknown_player() -> void:
	assert_true(_svc.get_completed_quests("nobody").is_empty())

func test_get_quest_definition_returns_known_definition() -> void:
	var def := _svc.get_quest_definition(Q_SIMPLE)
	assert_not_null(def)
	assert_eq(def.id, Q_SIMPLE)

func test_get_quest_definition_unknown_id_returns_null() -> void:
	assert_null(_svc.get_quest_definition("does_not_exist_xyz"))

func test_on_local_identity_ready_starts_configured_auto_start_quests() -> void:
	var ds2 := MockDataServiceAutoStart.new()
	ds2._quests[Q_SIMPLE] = MockQuestDef.new(Q_SIMPLE)
	ds2._auto_start = [Q_SIMPLE]
	var bus2 := MockEventBus.new()
	var svc2 := QuestService.new()
	svc2.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA:        ds2,
		ServiceKeys.SAVE_SYSTEM: MockSaveSystemNoop.new(),
		ServiceKeys.EVENT_BUS:   bus2,
	}))
	var bridge := _make_bridge_with_session(bus2, 1, P1)
	svc2.inject_network_bridge(bridge)

	svc2.on_local_identity_ready()

	assert_true(svc2.get_active_quests(P1).has(Q_SIMPLE),
		"on_local_identity_ready() muss die konfigurierten Auto-Start-Quests für den lokalen Spieler starten")
	svc2.on_cleanup()

func test_on_local_identity_ready_without_network_bridge_does_not_crash() -> void:
	# _local_player_id() bleibt leer ohne NetworkBridge -> früher Return mit
	# log_warn, kein Crash (siehe Klassenkommentar).
	_svc.on_local_identity_ready()
	pass_test("on_local_identity_ready() ohne NetworkBridge crasht nicht")
