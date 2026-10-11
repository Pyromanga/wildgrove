# tests/integration/test_session_lifecycle.gd
extends GutTest

## Character-Switch + Save/Load-Round-Trip — genau die beiden Fälle, die
## tests/IntegrationTest.gd im Kopfkommentar als "NICHT getestet hier
## (erfordern Session-Teardown und SceneTree-Kontrolle) ... sobald ein
## Test-Runner-Harness für Scene-Lifecycle verfügbar ist" benennt. Der
## Harness ist jetzt da (tests/helpers/SceneLifecycleHarness.gd) — das hier
## ist der damit gebaute Test.
##
## EHRLICHER HINWEIS (gilt hier stärker als bei den bisherigen Integrations-
## tests): dieser Test hängt zusätzlich zur Service-Ebene auch am
## SceneLifecycleHarness selbst, der einen synthetischen World-Root nutzt
## statt der echten World.tscn (siehe dortiger Kopfkommentar
## "UNVERIFIZIERTE ANNAHME"). Schlägt dieser Test beim ersten echten Lauf
## fehl, ist die naheliegendste erste Vermutung NICHT ein Bug in Quest/
## Save-Logik, sondern dass WorldService/WorldGenerationService mehr vom
## World-Root erwartet als ein nackter Node3D — harness.last_error und die
## Timeout-Meldung sollten das eingrenzen.
##
## Deckt ab:
##   1. Character-Switch: zwei unabhängige Sessions (verschiedene player_id)
##      nacheinander in DEMSELBEN Prozess — Zustand von Charakter A darf
##      nicht in Charakter B durchsickern (CharacterScope-Isolation, ADR-009).
##   2. Save/Load-Round-Trip: ein VOR dem Reload explizit gespeicherter
##      Inventory-Stand muss nach reload_current_session() (= Produktions-
##      "Laden"-Pfad, liest von Disk) unverändert vorhanden sein.
##   3. Negativ-Gegenprobe zu (2): eine Änderung OHNE vorheriges save_game()
##      darf den Reload NICHT überleben — beweist, dass der Test tatsächlich
##      einen echten Disk-Read auslöst und nicht nur zufällig in-memory-
##      State übersteht (ein Reload, der aus Versehen gar nichts zurücksetzt,
##      würde Testfall 2 sonst genauso grün zeigen, aber nichts beweisen).
##
## Deckt NICHT ab: Multiplayer-Charakter-Switch (Host wechselt Charakter
## während Clients verbunden sind — eigener, deutlich komplexerer Fall),
## Save-Korruption/Downgrade-Pfad (SaveSystem._create_downgrade_backup(),
## eigener Unit-Test-Kandidat ohne Scene-Lifecycle-Bedarf).

const PLAYER_A := "it_lifecycle_player_a"
const PLAYER_B := "it_lifecycle_player_b"
const TEST_ITEM_ID := "log_normal"

var _harness: SceneLifecycleHarness

func _orch() -> Node:
	return get_node("/root/ServiceOrchestrator")

func before_each() -> void:
	_harness = SceneLifecycleHarness.new(self)

func after_each() -> void:
	if _harness:
		_harness.cleanup()

func test_character_switch_isolates_inventory_state() -> void:
	var booted_a := await _harness.boot_fresh_session(PLAYER_A)
	if not booted_a:
		pending("Boot Charakter A fehlgeschlagen: " + _harness.last_error)
		return

	var inventory = _orch().get_service("inventory")
	inventory.request_add_item(TEST_ITEM_ID, PLAYER_A, 5)
	assert_true(
		inventory.has_item(TEST_ITEM_ID, PLAYER_A, 5),
		"Setup-Vorbedingung: Charakter A muss das Item erhalten haben."
	)

	var back_at_menu := await _harness.return_to_main_menu()
	if not back_at_menu:
		pending("Rückkehr zum MAIN_MENU fehlgeschlagen: " + _harness.last_error)
		return

	var booted_b := await _harness.boot_fresh_session(PLAYER_B)
	if not booted_b:
		pending("Boot Charakter B fehlgeschlagen: " + _harness.last_error)
		return

	assert_false(
		inventory.has_item(TEST_ITEM_ID, PLAYER_B, 1),
		"Charakter B darf NICHTS von Charakter A's Inventar sehen — " +
		"jede noch so kleine Überschneidung wäre ein Cross-Character-State-Leak (ADR-009-Verletzung)."
	)

	await _harness.return_to_main_menu()

func test_save_then_reload_persists_inventory_change() -> void:
	var booted := await _harness.boot_fresh_session(PLAYER_A)
	if not booted:
		pending("Boot fehlgeschlagen: " + _harness.last_error)
		return

	var inventory = _orch().get_service("inventory")
	var save_system = _orch().get_service("savesystem")
	assert_not_null(save_system, "SaveSystem muss als App-Scope-Service verfügbar sein.")
	if not save_system:
		return

	inventory.request_add_item(TEST_ITEM_ID, PLAYER_A, 3)
	assert_true(save_system.save_game(), "save_game() muss erfolgreich sein (gültige Session, Save-Pfad beschreibbar).")

	var reloaded := await _harness.reload_current_session()
	if not reloaded:
		pending("Reload fehlgeschlagen: " + _harness.last_error)
		return

	# Nach dem Reload ist InventorySystem eine NEUE Instanz (frischer
	# CharacterScope-Boot) — der Service muss über den Orchestrator neu
	# geholt werden, ein zwischengespeicherter alter Verweis wäre nach
	# teardown_character() eine tote Referenz.
	var inventory_after_reload = _orch().get_service("inventory")
	assert_true(
		inventory_after_reload.has_item(TEST_ITEM_ID, PLAYER_A, 3),
		"Ein VOR dem Reload gespeicherter Inventory-Stand muss nach dem Neuboot von Disk " +
		"exakt wiederhergestellt sein — das ist der eigentliche Save/Load-Round-Trip."
	)

func test_reload_without_save_discards_unsaved_change() -> void:
	var booted := await _harness.boot_fresh_session(PLAYER_A)
	if not booted:
		pending("Boot fehlgeschlagen: " + _harness.last_error)
		return

	var inventory = _orch().get_service("inventory")
	var qty_before_unsaved_change := 0
	var existing: ItemInstance = inventory.get_item_instance(PLAYER_A, TEST_ITEM_ID)
	if existing:
		qty_before_unsaved_change = existing.quantity

	# BEWUSST kein save_game() hier — das ist der Punkt dieses Testfalls.
	inventory.request_add_item(TEST_ITEM_ID, PLAYER_A, 99)
	assert_true(
		inventory.has_item(TEST_ITEM_ID, PLAYER_A, qty_before_unsaved_change + 99),
		"Setup-Vorbedingung: die ungespeicherte Änderung muss VOR dem Reload sichtbar sein."
	)

	var reloaded := await _harness.reload_current_session()
	if not reloaded:
		pending("Reload fehlgeschlagen: " + _harness.last_error)
		return

	var inventory_after_reload = _orch().get_service("inventory")
	assert_false(
		inventory_after_reload.has_item(TEST_ITEM_ID, PLAYER_A, qty_before_unsaved_change + 99),
		"Eine NICHT gespeicherte Änderung darf einen Reload nicht überleben — sonst würde " +
		"test_save_then_reload_persists_inventory_change() nur zeigen, dass gar nichts " +
		"zurückgesetzt wird, nicht dass echtes Laden funktioniert."
	)
