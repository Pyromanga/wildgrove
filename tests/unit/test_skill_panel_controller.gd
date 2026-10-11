# res://tests/unit/test_skill_panel_controller.gd
extends GutTest

## Tests für SkillPanelController — I-02 (AUDIT-03) und R-7 (ADR-022).
##
## I-02: SkillPanelController nahm schon vor jenem Fix einen IUIContext entgegen
## (für get_skill_system()), verband aber XP-/Level-Up-Signale weiterhin direkt
## am EventBus-AutoLoad.
##
## R-7: die damalige Lösung (ctx.bus().player().xp_gained/level_up) war IMMER
## noch falsch — diese Events feuern nur auf dem Prozess, der die Mutation
## tatsächlich ausführt (die Autorität, C-02-Guard in
## SkillSystem.on_xp_add_confirmed()). Für jeden Nicht-Host-Spieler feuerten
## sie lokal nie. Der Controller hängt jetzt an SkillSystem.skill_changed
## (feuert auf JEDEM Prozess, inkl. nach Rücksync-Empfang) und filtert explizit
## auf den lokalen Spieler (ctx.get_local_player_id()) statt implizit Spieler 1
## zu lesen.
##
## ADR-029 Plan-Schritt 4 (Round 65): SkillSystem ist auf player_id: String
## migriert — StubSkillSystem-Overrides und Controller-Filter nutzen jetzt
## get_local_player_id() (String) statt get_local_peer_id() (int), analog zur
## InventoryUIController-Migration in Round 63.

## Kleines, zustandsbehaftetes Test-Double, analog zum MockSkillSystem-Muster in
## test_entity_context.gd — der Level-Wert ist im Test veränderbar, damit sich ein
## erneutes Auslesen nach einem Signal von der Initial-Anzeige unterscheiden lässt.
## Erbt `skill_changed` unverändert von SkillSystem (R-7) — kein eigenes Signal nötig.
class StubSkillSystem extends SkillSystem:
	var level: int = 3
	func get_skill_ids(_player_id: String) -> Array[String]:
		var ids: Array[String] = ["mining"]
		return ids
	func get_level(_skill_name: String, _player_id: String) -> int:
		return level
	func get_xp(_skill_name: String, _player_id: String) -> int:
		return 42
	func get_xp_to_next_level(_skill_name: String, _player_id: String) -> int:
		return 100

var _ctrl: SkillPanelController
var _ctx: UIContext
var _bus: MockEventBus
var _canvas: CanvasLayer
var _visuals: SkillPanelVisuals
var _skill_system: StubSkillSystem

func before_each() -> void:
	_canvas = autofree(CanvasLayer.new())
	_visuals = SkillPanelVisuals.new(_canvas)

	_bus = MockEventBus.new()
	_skill_system = StubSkillSystem.new()

	_ctx = UIContext.for_test()
	_ctx._bus = _bus
	_ctx._skill_system = _skill_system
	# ADR-029 Round 65: local_player_id ist jetzt der maßgebliche Filter (String),
	# nicht mehr local_peer_id (int) — siehe Klassenkommentar oben.
	_ctx._local_player_id = "p1"

	_ctrl = add_child_autofree(SkillPanelController.new())
	_ctrl.setup(_visuals, _ctx)  # setup() ruft bereits einmal _refresh_all() auf (Level 3)

func _label_text() -> String:
	return (_visuals._skill_labels["mining"]["label"] as Label).text

func test_setup_connects_to_skill_changed_on_injected_skill_system() -> void:
	assert_true(
		_skill_system.skill_changed.is_connected(_ctrl._on_skill_changed),
		"setup() muss skill_changed auf dem injizierten SkillSystem verbinden"
	)

func test_skill_changed_for_local_player_refreshes_visuals_with_new_value() -> void:
	assert_eq(_label_text(), "Mining  Lv.3", "Initialer Stand aus setup()'s _refresh_all()")

	_skill_system.level = 7
	_skill_system.skill_changed.emit("mining", _ctx.get_local_player_id())

	assert_eq(
		_label_text(), "Mining  Lv.7",
		"_on_skill_changed() muss für den lokalen Spieler erneut von get_skill_system() lesen"
	)

func test_skill_changed_for_other_player_is_ignored() -> void:
	# R-7: skill_changed feuert für JEDEN Spieler — der Controller darf nur auf
	# den eigenen lokalen Spieler reagieren (ctx.get_local_player_id() == "p1"
	# hier), sonst würde jeder Client bei fremden Mutationen mit den eigenen
	# Daten (die sich ja nicht geändert haben) unnötig neu rendern — oder
	# schlimmer, in einer Variante ohne den player_id-Filter fälschlich fremde
	# Werte zeigen.
	_skill_system.level = 99
	_skill_system.skill_changed.emit("mining", "p2")

	assert_eq(
		_label_text(), "Mining  Lv.3",
		"skill_changed für einen anderen player_id darf den Controller nicht erreichen"
	)

func test_real_eventbus_xp_gained_does_not_reach_controller() -> void:
	# R-7: der Controller hängt nicht mehr am EventBus für XP/Level — dieses
	# Event darf ihn also unter keinen Umständen erreichen, weder über den
	# echten AutoLoad noch über den injizierten Mock.
	_skill_system.level = 99
	EventBus.player.emit_xp_gained("mining", 5)
	_bus.player().emit_xp_gained("mining", 5)

	assert_eq(
		_label_text(), "Mining  Lv.3",
		"xp_gained (AutoLoad oder Mock) darf SkillPanelController nicht mehr erreichen"
	)
