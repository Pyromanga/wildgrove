# res://tests/unit/test_quest_giver_npcs_dialogue_tree.gd
extends GutTest

## Smoke-Tests für die am 2026-09-27 von Slot-System auf
## DialogueTreeController umgestellten 6 NPC-Subklassen (MinerNPC,
## HerbalistNPC, WoodcutterNPC, WudangMasterNPC, AncestorSpiritNPC, GuardNPC).
##
## Ziel: billige, mechanische Regressions-Sicherung gegen Copy/Paste-Fehler
## über alle 6 Dateien hinweg (z.B. vergessenes quest_id="", falscher
## npc_id-String, _build_dialogue_tree() vergessen zu überschreiben) — NICHT
## eine erneute inhaltliche Prüfung jedes einzelnen Dialogtexts (die
## Dialog-Strings selbst sind 1:1 aus den alten Slot-Feldern übernommen,
## siehe Git-Historie der jeweiligen Datei).

var _bus: MockEventBus

func before_each() -> void:
	_bus = MockEventBus.new()

func _spawn(npc: QuestNPC) -> QuestNPC:
	add_child_autofree(npc)
	var ctx := EntityContext.for_test()
	ctx._bus = _bus
	npc.on_spawn({}, ctx)
	return npc

func _assert_uses_tree(npc: QuestNPC, expected_npc_id: String) -> void:
	assert_eq(npc.npc_id, expected_npc_id)
	assert_not_null(npc._dialogue_tree, "%s muss _build_dialogue_tree() überschreiben" % expected_npc_id)

func test_miner_npc_uses_dialogue_tree() -> void:
	_assert_uses_tree(_spawn(MinerNPC.new()), "mira_miner")

func test_herbalist_npc_uses_dialogue_tree() -> void:
	_assert_uses_tree(_spawn(HerbalistNPC.new()), "senna_herbalist")

func test_woodcutter_npc_uses_dialogue_tree() -> void:
	_assert_uses_tree(_spawn(WoodcutterNPC.new()), "erik_woodcutter")

func test_wudang_master_npc_uses_dialogue_tree() -> void:
	_assert_uses_tree(_spawn(WudangMasterNPC.new()), "wei_master")

func test_ancestor_spirit_npc_uses_dialogue_tree() -> void:
	_assert_uses_tree(_spawn(AncestorSpiritNPC.new()), "babatunde_spirit")

func test_guard_npc_uses_dialogue_tree() -> void:
	_assert_uses_tree(_spawn(GuardNPC.new()), "talia_guard")

func test_guard_npc_entry_always_offers_both_topics() -> void:
	# Talia ist der einzige NPC mit einem dauerhaft sichtbaren 2-Themen-Menü
	# (siehe GuardNPC.gd Klassenkommentar) — ohne QuestService/player_id
	# werden beide Unter-Router zu Blattknoten mit Fallback-Text, das
	# Root-Menü selbst bleibt aber ein echtes 2-Optionen-Menü.
	var npc := _spawn(GuardNPC.new())
	var fake := FakeChoiceUIForNpcTest.new()
	npc._dialogue_tree.set_choice_ui_factory(func() -> Variant: return fake)
	npc._dialogue_tree.on_interact()
	assert_eq(fake.presented_options, ["Über den Diebstahl reden", "Über die Friedhöfe reden"])

func test_base_quest_npc_builds_default_quest_giver_tree() -> void:
	# Es gibt nur EIN Dialogsystem: die Basisklasse baut ohne Override den
	# Standard-Questgeber-Baum.
	var npc := _spawn(QuestNPC.new())
	assert_not_null(npc._dialogue_tree)

class FakeChoiceUIForNpcTest extends RefCounted:
	var presented_options: Array[String] = []
	func present(options: Array[String], _on_chosen: Callable, _title: String = "") -> void:
		presented_options = options
