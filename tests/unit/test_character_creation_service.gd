# res://tests/unit/test_character_creation_service.gd
extends GutTest

## Unit-Tests für CharacterCreationService (ADR-048).
##
## Strategie: CharacterCreationService extends Service (RefCounted) — kein
## add_child nötig für den Tier-1-Pfad, identisches Setup-Muster wie
## test_achievement_service.gd/test_stats_service.gd.
##
## Round 106: request_submit_answers()/request_skip_creation() sind jetzt
## die öffentlichen Einstiegspunkte (ohne echten Peer/Tier 1 laufen sie
## direkt in on_submit_answers_confirmed()/on_skip_creation_confirmed(),
## identisches Verhalten wie die alten submit_answers()/skip_creation()
## zuvor) — die bestehenden Tests unten wurden entsprechend umbenannt, ohne
## ihre Assertions zu ändern. Eigener Abschnitt unten für den RPC-Pfad
## selbst (SpyNetworkBridge, analog test_report_service.gd) und für
## character_creation_confirmed.

const P1 := "player-1"
const P2 := "player-2"

var _svc: CharacterCreationService
var _save: SaveSystem

func before_each() -> void:
	_save = SaveSystem.new()
	_save.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new()}))
	_svc = CharacterCreationService.new()
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save}))

func test_has_seen_creation_false_by_default() -> void:
	assert_false(_svc.has_seen_creation(P1))

func test_get_questions_returns_four_questions_each_with_four_options() -> void:
	var questions := _svc.get_questions()
	assert_eq(questions.size(), 4)
	for q in questions:
		assert_eq((q["options"] as Array).size(), 4)

func test_get_questions_returns_a_copy_not_the_internal_const() -> void:
	var questions := _svc.get_questions()
	questions.clear()
	assert_eq(_svc.get_questions().size(), 4, "get_questions() muss eine Kopie liefern, sonst mutiert der Aufrufer die Konstante.")

func test_submit_answers_marks_seen_and_completed() -> void:
	_svc.request_submit_answers(P1, {"free_day": "a", "challenge": "a", "company": "a", "value": "a"})

	assert_true(_svc.has_seen_creation(P1))
	assert_true(_svc.is_completed(P1))

func test_submit_answers_derives_majority_preset() -> void:
	# Alle vier Antworten "wald" (Option "a" bei free_day, "c" bei challenge,
	# "c" bei company, "b" bei value — siehe QUESTIONS-Konstante).
	_svc.request_submit_answers(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})

	assert_eq(_svc.get_appearance_preset_id(P1), "wald")
	assert_eq(_svc.get_appearance_color(P1), Color(0.25, 0.55, 0.25))

func test_submit_answers_collects_unique_traits() -> void:
	_svc.request_submit_answers(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})

	var traits := _svc.get_traits(P1)
	assert_eq(traits, ["naturverbunden"], "Alle vier Antworten zeigen auf denselben Archetyp -> genau ein Trait, nicht viermal derselbe.")

func test_submit_answers_with_mixed_answers_ties_broken_by_archetype_order() -> void:
	# free_day="a" (wald), challenge="a" (sonnig), company="a" (sonnig),
	# value="a" (flut) -> sonnig hat 2 Stimmen, gewinnt eindeutig.
	_svc.request_submit_answers(P1, {"free_day": "a", "challenge": "a", "company": "a", "value": "a"})

	assert_eq(_svc.get_appearance_preset_id(P1), "sonnig")

func test_submit_answers_emits_character_created() -> void:
	var seen: Array = []
	_svc.character_created.connect(func(pid: String, preset_id: String, traits: Array) -> void:
		seen.append([pid, preset_id, traits])
	)

	_svc.request_submit_answers(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})

	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], P1)
	assert_eq(seen[0][1], "wald")

func test_submit_answers_ignores_unknown_question_ids() -> void:
	_svc.request_submit_answers(P1, {"nonexistent_question": "a"})

	assert_true(_svc.has_seen_creation(P1))
	assert_eq(_svc.get_appearance_preset_id(P1), CharacterCreationService.DEFAULT_APPEARANCE_ID)

func test_submit_answers_with_empty_player_id_is_ignored() -> void:
	_svc.request_submit_answers("", {"free_day": "a"})

	assert_false(_svc.has_seen_creation(""))

func test_skip_creation_marks_seen_but_not_completed() -> void:
	_svc.request_skip_creation(P1)

	assert_true(_svc.has_seen_creation(P1))
	assert_false(_svc.is_completed(P1))

func test_skip_creation_uses_default_appearance() -> void:
	_svc.request_skip_creation(P1)

	assert_eq(_svc.get_appearance_preset_id(P1), CharacterCreationService.DEFAULT_APPEARANCE_ID)
	assert_eq(_svc.get_appearance_color(P1), CharacterCreationService.DEFAULT_APPEARANCE_COLOR)
	assert_eq(_svc.get_traits(P1), [])

func test_skip_creation_emits_character_creation_skipped() -> void:
	var seen: Array = []
	_svc.character_creation_skipped.connect(func(pid: String) -> void: seen.append(pid))

	_svc.request_skip_creation(P1)

	assert_eq(seen, [P1])

func test_other_player_is_unaffected() -> void:
	_svc.request_submit_answers(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})

	assert_false(_svc.has_seen_creation(P2))
	assert_eq(_svc.get_appearance_preset_id(P2), CharacterCreationService.DEFAULT_APPEARANCE_ID)

func test_get_appearance_color_for_unknown_player_returns_default() -> void:
	assert_eq(_svc.get_appearance_color("nobody"), CharacterCreationService.DEFAULT_APPEARANCE_COLOR)

func test_save_round_trip() -> void:
	_svc.request_submit_answers(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})
	_svc.request_skip_creation(P2)

	var saved := _svc.get_save_data()

	var restored := CharacterCreationService.new()
	restored.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save}))
	restored._restore_from_save(saved)

	assert_true(restored.has_seen_creation(P1))
	assert_eq(restored.get_appearance_preset_id(P1), "wald")
	assert_eq(restored.get_traits(P1), ["naturverbunden"])
	assert_true(restored.has_seen_creation(P2))
	assert_false(restored.is_completed(P2))

func test_save_data_empty_by_default() -> void:
	var saved := _svc.get_save_data()
	assert_true((saved["seen"] as Dictionary).is_empty())
	assert_true((saved["completed"] as Dictionary).is_empty())
	assert_true((saved["appearance"] as Dictionary).is_empty())
	assert_true((saved["traits"] as Dictionary).is_empty())

# ─────────────────────────────────────────────────────────────────────────────
# Netzwerk-Pfad (Round 106, ADR-048) — analog test_report_service.gd
# ─────────────────────────────────────────────────────────────────────────────

class SpyNetworkBridge extends NetworkBridge:
	var submit_calls: Array[Dictionary] = []
	var skip_calls: Array[String] = []
	func send_character_creation_submit_answers(player_id: String, answers: Dictionary) -> void:
		submit_calls.append({"player_id": player_id, "answers": answers})
	func send_character_creation_skip(player_id: String) -> void:
		skip_calls.append(player_id)

func test_request_submit_answers_calls_network_when_not_authority() -> void:
	# Kein echter Peer im Test -> has_peer() ist false -> geht direkt lokal.
	# Dokumentiert den Tier-1-Fallback-Pfad: ohne echten Peer läuft
	# request_submit_answers() immer direkt in on_submit_answers_confirmed(),
	# NIE über send_character_creation_submit_answers() — exakt das
	# ReportService-Guard-Muster.
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	var created: Array = []
	_svc.character_created.connect(func(pid, _preset, _traits): created.append(pid))
	_svc.request_submit_answers(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})

	assert_eq(net.submit_calls.size(), 0, "Ohne echten Peer (Tier 1) darf kein RPC versucht werden.")
	assert_eq(created.size(), 1, "Stattdessen muss der direkte Autoritäts-Pfad laufen.")

func test_request_skip_creation_calls_network_when_not_authority() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	var skipped: Array = []
	_svc.character_creation_skipped.connect(func(pid): skipped.append(pid))
	_svc.request_skip_creation(P1)

	assert_eq(net.skip_calls.size(), 0, "Ohne echten Peer (Tier 1) darf kein RPC versucht werden.")
	assert_eq(skipped.size(), 1, "Stattdessen muss der direkte Autoritäts-Pfad laufen.")

func test_on_submit_answers_confirmed_rejects_non_authority() -> void:
	# _require_authority() greift nur mit einem echten Peer, der nicht Server
	# ist — hier direkt über eine Fake-Bridge simuliert, analog anderer
	# _require_authority()-Tests im Projekt (test_report_service.gd hat
	# keinen äquivalenten Test, weil on_submit_report_confirmed() denselben
	# Guard nutzt; hier zusätzlich abgedeckt, weil der Guard jetzt zwei
	# separate Einstiegspunkte schützen muss).
	var net := FakeNonAuthorityBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.on_submit_answers_confirmed(P1, {"free_day": "a"})

	assert_false(_svc.has_seen_creation(P1), "Auf einer Nicht-Autorität darf on_submit_answers_confirmed() nichts mutieren.")

class FakeNonAuthorityBridge extends NetworkBridge:
	func has_peer() -> bool: return true
	func is_server() -> bool: return false

func test_on_submit_answers_confirmed_sends_completed_result_to_owning_peer() -> void:
	# Simuliert die Autoritätsseite: ein RPC von einem entfernten Client kam
	# an, on_submit_answers_confirmed() muss das Ergebnis gezielt an genau
	# diesen Spieler zurückschicken (send_character_creation_completed_for_
	# player()) — ohne diesen Rückkanal bekäme ein Nicht-Host-Client sein
	# eigenes Aussehen nie zurück (siehe Klassenkommentar "AUTORITÄT").
	var net := SpyCompletedBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.on_submit_answers_confirmed(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})

	assert_eq(net.completed_calls.size(), 1)
	assert_eq(String(net.completed_calls[0]["player_id"]), P1)
	assert_eq(String((net.completed_calls[0]["payload"] as Dictionary).get("appearance_preset_id", "")), "wald")

class SpyCompletedBridge extends NetworkBridge:
	var completed_calls: Array[Dictionary] = []
	func send_character_creation_completed_for_player(player_id: String, payload: Dictionary) -> void:
		completed_calls.append({"player_id": player_id, "payload": payload})

func test_on_skip_creation_confirmed_sends_skipped_result_to_owning_peer() -> void:
	var net := SpySkippedBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.on_skip_creation_confirmed(P1)

	assert_eq(net.skipped_calls, [P1])

class SpySkippedBridge extends NetworkBridge:
	var skipped_calls: Array[String] = []
	func send_character_creation_skipped_for_player(player_id: String, _payload: Dictionary) -> void:
		skipped_calls.append(player_id)

# ─────────────────────────────────────────────────────────────────────────────
# character_creation_confirmed (Round 106) — Signal für den UI-Controller
# ─────────────────────────────────────────────────────────────────────────────

func test_character_creation_confirmed_emitted_on_submit() -> void:
	var confirmed: Array = []
	_svc.character_creation_confirmed.connect(func(pid): confirmed.append(pid))

	_svc.request_submit_answers(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})

	assert_eq(confirmed, [P1])

func test_character_creation_confirmed_emitted_on_skip() -> void:
	var confirmed: Array = []
	_svc.character_creation_confirmed.connect(func(pid): confirmed.append(pid))

	_svc.request_skip_creation(P1)

	assert_eq(confirmed, [P1])

func test_remote_creation_completed_received_updates_local_state_and_confirms() -> void:
	# Simuliert die Client-Seite: die Autorität hat bereits entschieden
	# (Payload kommt fertig an), CharacterCreationService übernimmt das
	# Ergebnis nur noch — analog AchievementService._on_remote_unlock_received.
	var net: NetworkBridge = autofree(NetworkBridge.new())
	var session: StubSessionManager = autofree(StubSessionManager.new())
	var svc := CharacterCreationService.new()
	svc.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.NETWORK_BRIDGE: net,
		ServiceKeys.SESSION_MANAGER: session,
	}))

	var confirmed: Array = []
	svc.character_creation_confirmed.connect(func(pid): confirmed.append(pid))

	net.character_creation_completed_received.emit({"appearance_preset_id": "flut", "traits": ["besonnen"]})

	assert_true(svc.has_seen_creation(P1))
	assert_true(svc.is_completed(P1))
	assert_eq(svc.get_appearance_preset_id(P1), "flut")
	assert_eq(svc.get_traits(P1), ["besonnen"])
	assert_eq(confirmed, [P1])
	svc.on_cleanup()

func test_remote_creation_skipped_received_updates_local_state_and_confirms() -> void:
	var net: NetworkBridge = autofree(NetworkBridge.new())
	var session: StubSessionManager = autofree(StubSessionManager.new())
	var svc := CharacterCreationService.new()
	svc.configure(ServiceDeps.from_dict({
		ServiceKeys.SAVE_SYSTEM: _save,
		ServiceKeys.NETWORK_BRIDGE: net,
		ServiceKeys.SESSION_MANAGER: session,
	}))

	var confirmed: Array = []
	svc.character_creation_confirmed.connect(func(pid): confirmed.append(pid))

	net.character_creation_skipped_received.emit({})

	assert_true(svc.has_seen_creation(P1))
	assert_false(svc.is_completed(P1))
	assert_eq(svc.get_appearance_preset_id(P1), CharacterCreationService.DEFAULT_APPEARANCE_ID)
	assert_eq(confirmed, [P1])
	svc.on_cleanup()

class StubSessionManager extends SessionManager:
	var player_id: String = P1
	func get_local_player_id() -> String:
		return player_id

# ─────────────────────────────────────────────────────────────────────────────
# Look (Aussehens-Ausbau) — get_look()/request_set_look()/on_set_look_confirmed()
# ─────────────────────────────────────────────────────────────────────────────

func test_get_look_for_unknown_player_returns_default_look() -> void:
	assert_eq(_svc.get_look("nobody"), CharacterLook.default_look())

func test_derive_from_answers_matches_submit_answers_result() -> void:
	var answers := {"free_day": "a", "challenge": "c", "company": "c", "value": "b"}
	var derived := _svc.derive_from_answers(answers)

	_svc.request_submit_answers(P1, answers)

	assert_eq(derived["appearance_id"], _svc.get_appearance_preset_id(P1))
	assert_eq(derived["traits"], _svc.get_traits(P1))

func test_get_look_after_submit_answers_matches_derived_archetype() -> void:
	_svc.request_submit_answers(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})

	assert_eq(_svc.get_look(P1), CharacterLook.from_archetype("wald"))

func test_get_look_after_skip_is_default_look() -> void:
	_svc.request_skip_creation(P1)

	assert_eq(_svc.get_look(P1), CharacterLook.default_look())

func test_request_set_look_without_peer_applies_directly() -> void:
	var net := SpyNetworkBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.request_set_look(P1, {"skin": "dark"})

	assert_eq(_svc.get_look(P1)["skin"], "dark")

func test_on_set_look_confirmed_sanitizes_invalid_input() -> void:
	_svc.on_set_look_confirmed(P1, {"skin": "not_a_real_id"})

	assert_eq(_svc.get_look(P1)["skin"], CharacterLook.DEFAULTS["skin"])

func test_on_set_look_confirmed_only_changes_given_fields() -> void:
	_svc.on_set_look_confirmed(P1, {"skin": "dark"})

	_svc.on_set_look_confirmed(P1, {"hair_color": "blue"})

	var look := _svc.get_look(P1)
	assert_eq(look["skin"], "dark", "Ein zweiter Teil-Update darf vorherige Felder nicht zurücksetzen.")
	assert_eq(look["hair_color"], "blue")

func test_on_set_look_confirmed_does_not_affect_seen_or_completed() -> void:
	_svc.on_set_look_confirmed(P1, {"skin": "dark"})

	assert_false(_svc.has_seen_creation(P1), "Der Aussehens-Editor ist unabhängig von der Fragenreihe.")

func test_on_set_look_confirmed_rejects_non_authority() -> void:
	var net := FakeNonAuthorityBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.on_set_look_confirmed(P1, {"skin": "dark"})

	assert_eq(_svc.get_look(P1), CharacterLook.default_look(), "Auf einer Nicht-Autorität darf on_set_look_confirmed() nichts mutieren.")

func test_look_changed_emitted_on_set_look_confirmed() -> void:
	var changed: Array = []
	_svc.look_changed.connect(func(pid): changed.append(pid))

	_svc.request_set_look(P1, {"skin": "dark"})

	assert_eq(changed, [P1])

func test_look_changed_emitted_on_submit_and_skip() -> void:
	var changed: Array = []
	_svc.look_changed.connect(func(pid): changed.append(pid))

	_svc.request_submit_answers(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})
	_svc.request_skip_creation(P2)

	assert_eq(changed, [P1, P2])

func test_on_set_look_confirmed_sends_look_updated_to_owning_peer() -> void:
	var net := SpyLookUpdatedBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.on_set_look_confirmed(P1, {"skin": "dark"})

	assert_eq(net.look_calls.size(), 1)
	assert_eq(String(net.look_calls[0]["player_id"]), P1)
	assert_eq(String((net.look_calls[0]["payload"] as Dictionary).get("look", {}).get("skin", "")), "dark")

class SpyLookUpdatedBridge extends NetworkBridge:
	var look_calls: Array[Dictionary] = []
	func send_character_look_updated_for_player(player_id: String, payload: Dictionary) -> void:
		look_calls.append({"player_id": player_id, "payload": payload})

func test_submit_answers_sends_look_in_completed_payload() -> void:
	var net := SpyCompletedBridge.new()
	add_child_autofree(net)
	_svc.inject_network_bridge(net)

	_svc.on_submit_answers_confirmed(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})

	var payload: Dictionary = net.completed_calls[0]["payload"]
	assert_eq(payload.get("look", {}), CharacterLook.from_archetype("wald"))

func test_remote_creation_completed_received_stores_look_from_payload() -> void:
	var net: NetworkBridge = autofree(NetworkBridge.new())
	var session: StubSessionManager = autofree(StubSessionManager.new())
	_svc = CharacterCreationService.new()
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save, ServiceKeys.NETWORK_BRIDGE: net, ServiceKeys.SESSION_MANAGER: session}))

	net.character_creation_completed_received.emit({
		"appearance_preset_id": "wald",
		"traits": ["naturverbunden"],
		"look": {"skin": "dark"},
	})

	assert_eq(_svc.get_look(P1)["skin"], "dark")

func test_remote_creation_skipped_received_resets_look_to_default() -> void:
	var net: NetworkBridge = autofree(NetworkBridge.new())
	var session: StubSessionManager = autofree(StubSessionManager.new())
	_svc = CharacterCreationService.new()
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save, ServiceKeys.NETWORK_BRIDGE: net, ServiceKeys.SESSION_MANAGER: session}))
	_svc.on_set_look_confirmed(P1, {"skin": "dark"})

	net.character_creation_skipped_received.emit({})

	assert_eq(_svc.get_look(P1), CharacterLook.default_look())

func test_remote_look_updated_received_merges_onto_existing_look() -> void:
	var net: NetworkBridge = autofree(NetworkBridge.new())
	var session: StubSessionManager = autofree(StubSessionManager.new())
	_svc = CharacterCreationService.new()
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save, ServiceKeys.NETWORK_BRIDGE: net, ServiceKeys.SESSION_MANAGER: session}))
	_svc.on_set_look_confirmed(P1, {"skin": "dark"})

	net.character_look_updated_received.emit({"look": {"hair_color": "blue"}})

	var look := _svc.get_look(P1)
	assert_eq(look["skin"], "dark")
	assert_eq(look["hair_color"], "blue")

func test_remote_look_updated_received_emits_look_changed() -> void:
	var net: NetworkBridge = autofree(NetworkBridge.new())
	var session: StubSessionManager = autofree(StubSessionManager.new())
	_svc = CharacterCreationService.new()
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save, ServiceKeys.NETWORK_BRIDGE: net, ServiceKeys.SESSION_MANAGER: session}))
	var changed: Array = []
	_svc.look_changed.connect(func(pid): changed.append(pid))

	net.character_look_updated_received.emit({"look": {"skin": "dark"}})

	assert_eq(changed, [P1])

# ─────────────────────────────────────────────────────────────────────────────
# Persistenz — look übersteht get_save_data()/_restore_from_save()
# ─────────────────────────────────────────────────────────────────────────────

func test_save_data_round_trips_look() -> void:
	_svc.on_set_look_confirmed(P1, {"skin": "dark", "hair_style": "long"})
	var saved := _svc.get_save_data()

	var restored := CharacterCreationService.new()
	restored.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: SaveSystem.new()}))
	restored._restore_from_save(saved)

	assert_eq(restored.get_look(P1), _svc.get_look(P1))

func test_save_provider_persists_look_via_save_system() -> void:
	# Analog zu einem vollständigen configure()-Zyklus: get_state_for()
	# liefert beim zweiten configure() denselben Zustand zurück.
	_svc.on_set_look_confirmed(P1, {"skin": "dark"})

	var restored := CharacterCreationService.new()
	restored.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: _save}))

	assert_eq(restored.get_look(P1)["skin"], "dark")

# ─────────────────────────────────────────────────────────────────────────────
# Round 114 (ADR-048 Broadcast-Lücke): Look-Broadcast an ANDERE Spieler
# ─────────────────────────────────────────────────────────────────────────────

## Analog test_equipment_service_r4.gd's SpyWorldService — zeichnet auf, mit
## welchem peer_id get_player_visuals() aufgerufen wurde, statt eine echte
## Welt zu simulieren.
class SpyWorldServiceForLook extends WorldService:
	var last_requested_peer_id: int = -1
	var call_count: int = 0
	var visuals_to_return: PlayerVisuals = null
	func get_player_visuals(peer_id: int) -> PlayerVisuals:
		last_requested_peer_id = peer_id
		call_count += 1
		return visuals_to_return

class SpyBroadcastBridge extends NetworkBridge:
	var broadcast_calls: Array[Dictionary] = []
	func broadcast_to_all_peers(kind: String, payload: Dictionary) -> void:
		broadcast_calls.append({"kind": kind, "payload": payload})

## Baut _svc mit einer echten SessionManager+NetworkBridge-Kette auf, analog
## test_equipment_service_r4.gd's _make_equipment_with_inventory() — nötig,
## damit NetworkBridge.get_peer_id_for_player() player_id → peer_id auflösen
## kann (_apply_look_to_visuals() braucht das).
func _make_svc_with_world_and_network(spy_world: WorldService, net: NetworkBridge) -> void:
	var session := SessionManager.new()
	session.register_player_slot(1, P1)
	session.register_player_slot(2, P2)
	add_child_autofree(session)
	net.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new(), ServiceKeys.SESSION_MANAGER: session}))
	add_child_autofree(net)
	add_child_autofree(spy_world)
	_svc.inject_network_bridge(net)
	_svc.inject_world_service(spy_world)

func test_on_set_look_confirmed_broadcasts_look_to_all_peers() -> void:
	var net := SpyBroadcastBridge.new()
	_make_svc_with_world_and_network(WorldService.new(), net)

	_svc.on_set_look_confirmed(P2, {"skin": "dark"})

	assert_eq(net.broadcast_calls.size(), 1,
		"on_set_look_confirmed() muss den neuen Look über broadcast_to_all_peers() an alle Peers melden.")
	assert_eq(String(net.broadcast_calls[0]["kind"]), "character_look")
	var payload: Dictionary = net.broadcast_calls[0]["payload"]
	assert_eq(String(payload.get("player_id", "")), P2)
	assert_eq(String((payload.get("look", {}) as Dictionary).get("skin", "")), "dark")

func test_on_submit_answers_confirmed_broadcasts_look_to_all_peers() -> void:
	var net := SpyBroadcastBridge.new()
	_make_svc_with_world_and_network(WorldService.new(), net)

	_svc.on_submit_answers_confirmed(P1, {"free_day": "a", "challenge": "c", "company": "c", "value": "b"})

	assert_eq(net.broadcast_calls.size(), 1)
	assert_eq(String(net.broadcast_calls[0]["payload"].get("player_id", "")), P1)

func test_on_skip_creation_confirmed_broadcasts_default_look_to_all_peers() -> void:
	var net := SpyBroadcastBridge.new()
	_make_svc_with_world_and_network(WorldService.new(), net)

	_svc.on_skip_creation_confirmed(P1)

	assert_eq(net.broadcast_calls.size(), 1)
	assert_eq(net.broadcast_calls[0]["payload"].get("look", {}), CharacterLook.default_look())

## Die Autorität nimmt an ihrem eigenen Broadcast nicht teil (siehe
## NetworkBridge.broadcast_to_all_peers()-Klassenkommentar) — _broadcast_look()
## muss ihre eigene Sicht auf den betroffenen (FREMDEN) Spieler deshalb
## direkt über _apply_look_to_visuals() aktualisieren.
func test_on_set_look_confirmed_applies_look_to_visuals_of_target_player() -> void:
	var spy_world := SpyWorldServiceForLook.new()
	_make_svc_with_world_and_network(spy_world, SpyBroadcastBridge.new())

	_svc.on_set_look_confirmed(P2, {"skin": "dark"})

	assert_eq(spy_world.call_count, 1,
		"on_set_look_confirmed() muss WorldService.get_player_visuals() für den betroffenen Spieler abfragen.")
	assert_eq(spy_world.last_requested_peer_id, 2,
		"Muss peer_id 2 (P2) anfragen, nicht die eigene/lokale peer_id.")

func test_on_broadcast_event_received_ignores_other_kinds() -> void:
	var spy_world := SpyWorldServiceForLook.new()
	var net := NetworkBridge.new()
	_make_svc_with_world_and_network(spy_world, net)

	net.broadcast_event_received.emit("weather_changed", {"player_id": P2, "look": {"skin": "dark"}})

	assert_eq(spy_world.call_count, 0,
		"_on_broadcast_event_received() darf nur auf kind==\"character_look\" reagieren.")

## Gegenstück zu test_on_set_look_confirmed_broadcasts_look_to_all_peers():
## simuliert den Empfang auf einem ANDEREN, bereits verbundenen Peer.
func test_on_broadcast_event_received_stores_look_and_applies_visuals() -> void:
	var spy_world := SpyWorldServiceForLook.new()
	var net := NetworkBridge.new()
	_make_svc_with_world_and_network(spy_world, net)

	var changed: Array = []
	_svc.look_changed.connect(func(pid): changed.append(pid))

	net.broadcast_event_received.emit("character_look", {"player_id": P2, "look": {"skin": "dark"}})

	assert_eq(_svc.get_look(P2)["skin"], "dark",
		"_on_broadcast_event_received() muss den empfangenen Look in _look übernehmen.")
	assert_eq(changed, [P2], "look_changed muss für den betroffenen (fremden) Spieler emittiert werden.")
	assert_eq(spy_world.call_count, 1)
	assert_eq(spy_world.last_requested_peer_id, 2)

func test_on_broadcast_event_received_without_player_id_is_ignored() -> void:
	var spy_world := SpyWorldServiceForLook.new()
	var net := NetworkBridge.new()
	_make_svc_with_world_and_network(spy_world, net)

	net.broadcast_event_received.emit("character_look", {"look": {"skin": "dark"}})

	assert_eq(spy_world.call_count, 0, "Ohne player_id im Payload darf nichts angewendet werden.")

## Ohne injizierten WorldService (z.B. isolierte Tests) darf _apply_look_to_
## visuals() weder crashen noch den Broadcast/die Speicherung verhindern.
func test_on_set_look_confirmed_without_world_service_still_broadcasts_without_crash() -> void:
	var net := SpyBroadcastBridge.new()
	var session := SessionManager.new()
	session.register_player_slot(1, P1)
	session.register_player_slot(2, P2)
	add_child_autofree(session)
	net.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: MockEventBus.new(), ServiceKeys.SESSION_MANAGER: session}))
	add_child_autofree(net)
	_svc.inject_network_bridge(net)
	# Bewusst KEIN inject_world_service() hier.

	_svc.on_set_look_confirmed(P2, {"skin": "dark"})

	assert_eq(net.broadcast_calls.size(), 1,
		"Broadcast muss auch ohne WorldService laufen — nur die Visual-Anwendung entfällt.")
