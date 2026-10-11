# tests/integration/test_quest_reward_chain.gd
extends GutTest

## Quest → Reward → Inventory/XP-Kette. "Ebene A" aus dem E2E-Testplan
## (Service-Integration gegen den echten ServiceOrchestrator, kein Netzwerk,
## kein zweiter Prozess nötig) — der günstigste, am schnellsten baubare
## Baustein, bevor in ein neues Zwei-Prozess-Harness investiert wird.
##
## Nutzt die reale, bereits in data/quests/quest_woodcutter_intro.tres
## vorhandene Quest (Objective "obj_chop_trees", required=3; Reward: 50 XP
## woodcutting + 2x log_normal) statt einer erfundenen Test-Fixture — der
## Test prüft damit auch, ob der echte Content noch zur Service-Erwartung
## passt, nicht nur die Mechanik in Isolation.
##
## EHRLICHER HINWEIS (wie test_movement_two_peer.gd): geschrieben ohne
## laufendes Godot/GUT in dieser Sandbox (kein Binary, kein Netzwerk) — nach
## bestem Wissen gegen die tatsächlichen Quellen konstruiert (QuestService.
## on_quest_complete_confirmed()/request_start_quest(),
## RewardDispatcher.dispatch(), InventorySystem.has_item()/get_item_instance(),
## SkillSystem.get_xp(), QuestProgressRecord.is_complete()), aber NICHT
## ausgeführt. Vor Vertrauen:
##   godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration/ -gexit
##
## Bootet die eigene Session selbst über SceneLifecycleHarness (siehe dort
## für die "nackter Node3D statt echter World.tscn"-Annahme) — läuft dadurch
## eigenständig in einer normalen GUT-CLI-Invocation. Eine frühere Fassung
## dieses Tests prüfte nur `gamemanager.is_playing()` und übersprang sich
## sonst — das hätte in genau der `-gdir=...`-Invocation, mit der die CI
## diesen Test tatsächlich ausführt, IMMER zugeschlagen (nichts treibt die
## App sonst von MAIN_MENU nach PLAYING), der Test wäre also nie wirklich
## gelaufen. Mit dem Harness bootet der Test seine PLAYING-Session jetzt
## selbst und ist damit eigenständig lauffähig.
##
## Deckt ab:
##   1. SEC-03-Guard — Quest-Abschluss mit unvollständigem Fortschritt wird
##      verweigert, UND es wird dabei kein Reward ausgezahlt (das ist der
##      eigentliche Exploit, den der Guard in
##      QuestService.on_quest_complete_confirmed() verhindert: vorher konnte
##      jeder Aufrufer — inkl. ein modifizierter Client per RPC — eine aktive
##      Quest sofort abschließen und den vollen Reward kassieren, unabhängig
##      vom tatsächlichen Fortschritt).
##   2. Bei erfülltem Fortschritt: Reward wird korrekt ausgezahlt (Item
##      landet im Inventar, Skill-XP steigt).
##   3. Kein Reward-Dupe durch Wiederholung — eine abgeschlossene,
##      nicht-repeatable Quest (repeatable=false in dieser .tres) kann nicht
##      erneut gestartet werden.
##
## Deckt NICHT ab: stat_modifiers-Rewards (kein vorhandener Content mit
## einem solchen Reward zum Testen), die unlock_quests-Kette, den
## Multiplayer-RPC-Pfad in request_complete_quest() bei Nicht-Autorität
## (das wäre Ebene B: zwei Peers, einer davon NICHT Autorität, RPC-Weg statt
## Direktaufruf) — bewusste Lücken, kein übersehener Anspruch.

const PLAYER_ID := "it_quest_reward_chain_player"
const QUEST_ID := "quest_woodcutter_intro"
const OBJECTIVE_ID := "obj_chop_trees"
const REQUIRED_PROGRESS := 3
const REWARD_ITEM_ID := "log_normal"
const REWARD_ITEM_QTY := 2
const REWARD_SKILL := "woodcutting"

var _harness: SceneLifecycleHarness
var _skip_reason: String = ""

func _orch() -> Node:
	return get_node("/root/ServiceOrchestrator")

func _skip_if_unavailable() -> bool:
	if not _skip_reason.is_empty():
		pending(_skip_reason)
		return true
	return false

func before_each() -> void:
	_skip_reason = ""
	_harness = SceneLifecycleHarness.new(self)

	var booted := await _harness.boot_fresh_session(PLAYER_ID)
	if not booted:
		_skip_reason = "Session-Boot fehlgeschlagen: %s" % _harness.last_error
		return

	var quest: QuestService = _orch().get_service("quest")
	if quest == null:
		_skip_reason = "QuestService nicht registriert."
		return

	# Defensive Absicherung, nicht der Normalfall: boot_fresh_session() bootet
	# pro Testfall neu und nichts in dieser Datei ruft save_game() auf, ein
	# frischer Boot sollte also immer einen sauberen Ausgangszustand liefern.
	# Falls PLAYER_ID dennoch auf einen alten Save-Stand von einem vorherigen,
	# unabhängigen Lauf trifft (z. B. Save-Datei nicht zwischen CI-Läufen
	# aufgeräumt): abgeschlossene Quest hat keinen Reset-Pfad in Produktion
	# (kein "unlearn quest"-Feature) — dann überspringen statt falsch failen.
	if quest.is_quest_completed(QUEST_ID, PLAYER_ID):
		_skip_reason = "'%s' ist für '%s' bereits abgeschlossen (alter Save-Stand von einem vorherigen Lauf?) — kein Reset-Pfad vorhanden." % [QUEST_ID, PLAYER_ID]
		return
	if quest.is_quest_active(QUEST_ID, PLAYER_ID):
		quest.fail_quest(QUEST_ID, PLAYER_ID)

func after_each() -> void:
	if _harness:
		await _harness.return_to_main_menu()
		_harness.cleanup()

func test_incomplete_objectives_deny_completion_and_reward() -> void:
	if _skip_if_unavailable():
		return
	var quest: QuestService = _orch().get_service("quest")
	var inventory: InventorySystem = _orch().get_service("inventory")

	assert_true(quest.request_start_quest(QUEST_ID, PLAYER_ID), "Quest muss startbar sein.")
	quest.update_objective(QUEST_ID, OBJECTIVE_ID, REQUIRED_PROGRESS - 1, PLAYER_ID)  # 2 von 3 — absichtlich unvollständig

	var had_reward_item_before := inventory.has_item(REWARD_ITEM_ID, PLAYER_ID, 1)

	quest.request_complete_quest(QUEST_ID, PLAYER_ID)

	assert_true(
		quest.is_quest_active(QUEST_ID, PLAYER_ID),
		"Quest muss nach abgelehntem Abschlussversuch weiterhin aktiv sein."
	)
	assert_false(
		quest.is_quest_completed(QUEST_ID, PLAYER_ID),
		"Quest darf mit 2/%d Fortschritt nicht als completed gelten (SEC-03-Guard)." % REQUIRED_PROGRESS
	)
	if not had_reward_item_before:
		assert_false(
			inventory.has_item(REWARD_ITEM_ID, PLAYER_ID, 1),
			"Reward (%dx %s) darf bei verweigertem Abschluss NICHT ausgezahlt werden — " % [REWARD_ITEM_QTY, REWARD_ITEM_ID] +
			"genau das ist der Exploit, den der SEC-03-Guard verhindert."
		)

	quest.fail_quest(QUEST_ID, PLAYER_ID)  # Aufräumen für den nächsten Testfall in dieser Datei

func test_complete_objectives_grants_reward() -> void:
	if _skip_if_unavailable():
		return
	var quest: QuestService = _orch().get_service("quest")
	var inventory: InventorySystem = _orch().get_service("inventory")
	var skills: SkillSystem = _orch().get_service("skill_system")

	assert_true(quest.request_start_quest(QUEST_ID, PLAYER_ID), "Quest muss startbar sein.")

	var xp_before := skills.get_xp(REWARD_SKILL, PLAYER_ID) if skills else -1
	var qty_before := 0
	var item_before: ItemInstance = inventory.get_item_instance(PLAYER_ID, REWARD_ITEM_ID) if inventory else null
	if item_before:
		qty_before = item_before.quantity

	quest.update_objective(QUEST_ID, OBJECTIVE_ID, REQUIRED_PROGRESS, PLAYER_ID)
	quest.request_complete_quest(QUEST_ID, PLAYER_ID)

	assert_true(
		quest.is_quest_completed(QUEST_ID, PLAYER_ID),
		"Quest muss nach vollem Fortschritt (%d/%d) als completed gelten." % [REQUIRED_PROGRESS, REQUIRED_PROGRESS]
	)
	assert_false(
		quest.is_quest_active(QUEST_ID, PLAYER_ID),
		"Quest darf nach Abschluss nicht mehr in der aktiven Liste stehen."
	)
	assert_true(
		inventory.has_item(REWARD_ITEM_ID, PLAYER_ID, qty_before + REWARD_ITEM_QTY),
		"Reward muss genau %dx %s zusätzlich ins Inventar legen." % [REWARD_ITEM_QTY, REWARD_ITEM_ID]
	)
	if xp_before >= 0:
		assert_gt(
			skills.get_xp(REWARD_SKILL, PLAYER_ID), xp_before,
			"%s-XP muss nach dem Reward gestiegen sein." % REWARD_SKILL
		)

## Bewusst SELBSTSTÄNDIG (kein Aufbau auf einem vorherigen Testfall-Zustand):
## before_each() bootet für JEDEN Testfall neu über SceneLifecycleHarness,
## und zwischen zwei Testfällen wird nirgends save_game() aufgerufen — ein in
## test_complete_objectives_grants_reward() erreichter Abschluss-Zustand
## würde beim nächsten before_each()-Neuboot also NICHT mehr sichtbar sein
## (exakt das Verhalten, das test_session_lifecycle.gd::
## test_reload_without_save_discards_unsaved_change() eigens verifiziert).
## Dieser Testfall stellt den Abschluss deshalb selbst her, statt sich auf
## Testreihenfolge zu verlassen — Testisolation vor Kürze.
func test_completed_non_repeatable_quest_cannot_restart() -> void:
	if _skip_if_unavailable():
		return
	var quest: QuestService = _orch().get_service("quest")

	assert_true(quest.request_start_quest(QUEST_ID, PLAYER_ID), "Quest muss startbar sein (Vorbedingung für diesen Testfall).")
	quest.update_objective(QUEST_ID, OBJECTIVE_ID, REQUIRED_PROGRESS, PLAYER_ID)
	quest.request_complete_quest(QUEST_ID, PLAYER_ID)
	assert_true(
		quest.is_quest_completed(QUEST_ID, PLAYER_ID),
		"Setup-Vorbedingung: Quest muss für diesen Testfall zunächst abgeschlossen werden können."
	)

	var started := quest.request_start_quest(QUEST_ID, PLAYER_ID)
	assert_false(
		started,
		"Eine abgeschlossene, nicht-repeatable Quest (repeatable=false in %s.tres) darf nicht erneut startbar sein — sonst ließe sich der Reward beliebig oft einsammeln." % QUEST_ID
	)
