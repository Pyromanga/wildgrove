# res://tests/unit/test_wiki_panel_controller.gd
extends GutTest

## Tests für WikiPanelController (Round 108), analog
## test_achievement_panel_controller.gd.
##
## Strategie: eine ECHTE, konfigurierte WikiService-Instanz (Business-Logik
## bereits in test_wiki_service.gd abgedeckt). Hier wird nur geprüft, dass
## der Controller korrekt auf die zwei Service-Signale reagiert, dabei
## konsequent nach player_id filtert, und den Katalog aus DataService
## korrekt als "???"-Platzhalter vorbefüllt.

const P1 := "p1"
const P2 := "p2"

class MockDataService extends DataService:
	func _init() -> void:
		var goblin := CombatProfile.new()
		goblin.id = "goblin"
		goblin.display_name = "Goblin"
		_combat_profiles["goblin"] = goblin

		var table := LootTable.new()
		table.entries = []
		_loot_tables["goblin_loot"] = table

		var skill := SkillDefinition.new()
		skill.id = "woodcutting"
		skill.display_name = "Holzfällen"
		_skills["woodcutting"] = skill

		var quest := QuestDefinition.new()
		quest.id = "quest_woodcutter_intro"
		quest.title = "Der erste Holzschlag"
		_quests["quest_woodcutter_intro"] = quest

var _ctrl: WikiPanelController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: WikiPanelVisuals
var _svc: WikiService
var _data: MockDataService
var _skill_system: SkillSystem

func before_each() -> void:
	_canvas = autofree(CanvasLayer.new())
	_visuals = WikiPanelVisuals.new(_canvas)

	_bus = MockEventBus.new()
	_data = MockDataService.new()
	_skill_system = SkillSystem.new()

	_svc = WikiService.new()
	_svc.configure(ServiceDeps.from_dict({
		ServiceKeys.DATA: _data,
	}))

	_ctx = UIContext.for_test()
	_ctx._bus = _bus
	_ctx._wiki = _svc
	_ctx._data = _data
	_ctx._local_player_id = P1

	_ctrl = add_child_autofree(WikiPanelController.new())
	_ctrl.setup(_visuals, _ctx)

func after_each() -> void:
	_svc.on_cleanup()

func _row_key(category: String, entry_id: String) -> String:
	return "%s/%s" % [category, entry_id]

func _row_name_text(category: String, entry_id: String) -> String:
	return (_visuals._rows[_row_key(category, entry_id)]["name_label"] as Label).text

func test_setup_connects_both_wiki_signals() -> void:
	assert_true(_svc.wiki_entry_discovered.is_connected(_ctrl._on_wiki_entry_discovered))
	assert_true(_svc.wiki_synced.is_connected(_ctrl._on_wiki_synced))

func test_setup_renders_full_catalog_locked_by_default() -> void:
	assert_true(_visuals._rows.has(_row_key(WikiService.CATEGORY_ENEMIES, "goblin")))
	assert_true(_visuals._rows.has(_row_key(WikiService.CATEGORY_DROPS, "goblin_loot")))
	assert_true(_visuals._rows.has(_row_key(WikiService.CATEGORY_SKILLS, "woodcutting")))
	assert_true(_visuals._rows.has(_row_key(WikiService.CATEGORY_QUESTS, "quest_woodcutter_intro")))
	assert_true(_row_name_text(WikiService.CATEGORY_ENEMIES, "goblin").begins_with("🔒"))

func test_discovery_for_local_player_reveals_row() -> void:
	_svc.discover(P1, WikiService.CATEGORY_ENEMIES, "goblin")

	assert_true(_row_name_text(WikiService.CATEGORY_ENEMIES, "goblin").contains("Goblin"))

func test_discovery_for_other_player_is_ignored() -> void:
	_svc.discover(P2, WikiService.CATEGORY_ENEMIES, "goblin")

	assert_true(
		_row_name_text(WikiService.CATEGORY_ENEMIES, "goblin").begins_with("🔒"),
		"wiki_entry_discovered für einen fremden player_id darf den Controller nicht erreichen."
	)

func test_discovery_shows_notification_toast() -> void:
	var notifications: Array = []
	_bus.ui().notification_requested.connect(func(text: String) -> void: notifications.append(text))

	_svc.discover(P1, WikiService.CATEGORY_SKILLS, "woodcutting")

	assert_eq(notifications.size(), 1)
	assert_true(String(notifications[0]).contains("Holzfällen"))

func test_wiki_synced_for_local_player_triggers_full_refresh() -> void:
	# Simuliert das, was der Round-107-Client-Empfang produziert: direkte
	# State-Mutation + wiki_synced (kein discover(), das würde stattdessen
	# wiki_entry_discovered feuern).
	_svc._discovered[P1] = {WikiService.CATEGORY_QUESTS: ["quest_woodcutter_intro"]}
	_svc.wiki_synced.emit(P1)

	assert_true(_row_name_text(WikiService.CATEGORY_QUESTS, "quest_woodcutter_intro").contains("Der erste Holzschlag"))

func test_wiki_synced_for_other_player_is_ignored() -> void:
	_svc._discovered[P2] = {WikiService.CATEGORY_QUESTS: ["quest_woodcutter_intro"]}
	_svc.wiki_synced.emit(P2)

	assert_true(_row_name_text(WikiService.CATEGORY_QUESTS, "quest_woodcutter_intro").begins_with("🔒"))
