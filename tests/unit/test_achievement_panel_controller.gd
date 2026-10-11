# res://tests/unit/test_achievement_panel_controller.gd
extends GutTest

## Tests für AchievementPanelController (Round 104), analog
## test_skill_panel_controller.gd/test_quest_panel_controller.gd.
##
## Strategie: eine ECHTE, konfigurierte AchievementService-Instanz (kein Mock
## der Business-Logik nötig, siehe test_achievement_service.gd — grant_progress()/
## _on_remote_unlock_received() etc. sind dort bereits abgedeckt). Hier wird nur
## geprüft, dass der Controller korrekt auf die drei Service-Signale reagiert
## und dabei konsequent nach player_id filtert.

const P1 := "p1"
const P2 := "p2"

var _ctrl: AchievementPanelController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: AchievementPanelVisuals
var _svc: AchievementService

func before_each() -> void:
	_canvas = autofree(CanvasLayer.new())
	_visuals = AchievementPanelVisuals.new(_canvas)

	_bus = MockEventBus.new()

	var save := SaveSystem.new()
	save.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))

	_svc = AchievementService.new()
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.SAVE_SYSTEM: save}))  # DEFAULT_DEFINITIONS, kein Netzwerk/Session

	_ctx = UIContext.for_test()
	_ctx._bus = _bus
	_ctx._achievement = _svc
	_ctx._local_player_id = P1

	_ctrl = add_child_autofree(AchievementPanelController.new())
	_ctrl.setup(_visuals, _ctx)

func after_each() -> void:
	_svc.on_cleanup()

func _row_name_text(achievement_id: String) -> String:
	return (_visuals._rows[achievement_id]["name_label"] as Label).text

func test_setup_connects_all_three_achievement_signals() -> void:
	assert_true(_svc.achievement_unlocked.is_connected(_ctrl._on_achievement_unlocked))
	assert_true(_svc.achievement_progress.is_connected(_ctrl._on_achievement_progress))
	assert_true(_svc.achievements_synced.is_connected(_ctrl._on_achievements_synced))

func test_setup_renders_all_known_definitions_locked_by_default() -> void:
	for achievement_id in AchievementService.DEFAULT_DEFINITIONS.keys():
		assert_true(_visuals._rows.has(achievement_id), "Zeile für '%s' muss nach setup() existieren." % achievement_id)
	assert_true(_row_name_text("first_blood").begins_with("🔒"), "Unbekanntes Achievement muss initial gesperrt dargestellt werden.")

func test_achievement_unlocked_for_local_player_updates_row_to_unlocked() -> void:
	_svc.grant_progress(P1, "first_blood")

	assert_true(_row_name_text("first_blood").begins_with("✅"))

func test_achievement_unlocked_for_other_player_is_ignored() -> void:
	_svc.grant_progress(P2, "first_blood")

	assert_true(
		_row_name_text("first_blood").begins_with("🔒"),
		"achievement_unlocked für einen fremden player_id darf den Controller nicht erreichen."
	)

func test_achievement_unlocked_shows_notification_toast_with_reward() -> void:
	var notifications: Array = []
	_bus.ui().notification_requested.connect(func(text: String) -> void: notifications.append(text))

	_svc.grant_progress(P1, "first_blood")  # reward_gold = 50

	assert_eq(notifications.size(), 1)
	assert_true(String(notifications[0]).contains("Erstes Blut"))
	assert_true(String(notifications[0]).contains("50 Gold"))

func test_achievement_progress_for_local_player_updates_progress_label() -> void:
	_svc.grant_progress(P1, "pvp_veteran")  # target = 10, +1 Fortschritt, kein Unlock

	var progress_text: String = (_visuals._rows["pvp_veteran"]["progress_label"] as Label).text
	assert_true(progress_text.begins_with("1 / 10"))

func test_achievement_progress_for_other_player_is_ignored() -> void:
	_svc.grant_progress(P2, "pvp_veteran")

	var progress_text: String = (_visuals._rows["pvp_veteran"]["progress_label"] as Label).text
	assert_true(progress_text.begins_with("0 / 10"), "Fortschritt eines fremden Spielers darf die lokale Anzeige nicht ändern.")

func test_achievements_synced_for_local_player_triggers_full_refresh() -> void:
	# Simuliert das, was Round-104-Client-Empfang produziert: direkte
	# State-Mutation (kein grant_progress(), das würde ein zweites
	# achievement_progress-Signal feuern) + achievements_synced.
	_svc._unlocked[P1] = ["first_blood"]
	_svc.achievements_synced.emit(P1)

	assert_true(_row_name_text("first_blood").begins_with("✅"))

func test_achievements_synced_for_other_player_is_ignored() -> void:
	_svc._unlocked[P2] = ["first_blood"]
	_svc.achievements_synced.emit(P2)

	assert_true(_row_name_text("first_blood").begins_with("🔒"))
