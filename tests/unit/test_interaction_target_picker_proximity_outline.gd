# res://tests/unit/test_interaction_target_picker_proximity_outline.gd
extends GutTest

## BUGFIX (2026-09-26, "Umrandung soll auch automatisch bei Proximity/Autodetect
## funktionieren — im Endeffekt worauf das ! zeigt"): InteractionTargetPicker zeigte die
## Umrandung vorher NUR nach einem Tap. Jetzt folgt sie proximity_changed
## (InteractionSensor) — demselben Signal, dem auch der Interaktions-Button schon folgt —
## und markiert damit auch ein rein per Nähe (Autodetect) erkanntes Ziel, ohne dass es
## angetippt werden muss.
##
## Reine Signal-Logik, ohne Physik-Overlap nötig: _on_proximity_changed()/_select() reagieren
## nur auf das übergebene Ziel und rufen selbst keine Reichweiten-Prüfung auf (siehe
## test_interaction_sensor_manual_target.gd für den physik-basierten Deselect-Fallback-Test).

var _picker: InteractionTargetPicker
var _sensor: InteractionSensor
var _owner: StaticBody3D
var _bus: MockEventBus

func _make_target(node_name: String) -> Node3D:
	var t := Node3D.new()
	t.name = node_name
	add_child_autofree(t)
	return t

func before_each() -> void:
	_owner = StaticBody3D.new()
	add_child_autofree(_owner)

	_sensor = InteractionSensor.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	_sensor.add_child(shape)
	_owner.add_child(_sensor)

	_bus = MockEventBus.new()
	_sensor.inject_bus(_bus)

	_picker = InteractionTargetPicker.new()
	add_child_autofree(_picker)
	_picker.setup(null, _sensor, _owner)
	_picker.inject_bus(_bus)

func test_proximity_changed_true_shows_outline_without_any_tap() -> void:
	var tree := _make_target("Tree")
	_bus.world().emit_proximity_changed(tree, true)
	assert_true(is_instance_valid(_picker._outline),
		"proximity_changed(true) muss eine Umrandung erzeugen — auch ohne Tap (Autodetect).")
	assert_eq(_picker._outline.get_target(), tree)

func test_proximity_changed_false_clears_matching_outline() -> void:
	var tree := _make_target("Tree")
	_bus.world().emit_proximity_changed(tree, true)
	_bus.world().emit_proximity_changed(tree, false)
	assert_null(_picker._outline,
		"proximity_changed(false) für das aktuell umrandete Ziel muss die Umrandung entfernen.")

func test_proximity_changed_false_for_other_target_keeps_outline() -> void:
	var tree := _make_target("Tree")
	var other := _make_target("Other")
	_bus.world().emit_proximity_changed(tree, true)
	_bus.world().emit_proximity_changed(other, false)
	assert_eq(_picker._outline.get_target(), tree,
		"proximity_changed(false) für ein ANDERES Ziel darf die aktuelle Umrandung nicht entfernen.")

func test_tap_select_then_proximity_change_switches_outline() -> void:
	# Simuliert: Spieler tippt ein weit entferntes Ziel an, der Sensor selbst wechselt aber
	# (weil das getippte Ziel nicht in Reichweite ist) auf ein näheres automatisches Ziel —
	# die Umrandung muss dem TATSÄCHLICHEN Sensor-Ziel folgen (= worauf das "!" zeigt),
	# nicht am alten Tap kleben bleiben.
	var tapped := _make_target("Tapped")
	_picker._select(tapped)
	assert_eq(_picker._outline.get_target(), tapped)

	var nearer := _make_target("Nearer")
	_bus.world().emit_proximity_changed(nearer, true)
	assert_eq(_picker._outline.get_target(), nearer,
		"Wechselt der Sensor sein aktuelles Ziel, muss die Umrandung folgen.")

func test_deselect_without_manual_target_keeps_ambient_outline() -> void:
	var tree := _make_target("Tree")
	_bus.world().emit_proximity_changed(tree, true)
	_picker._deselect()
	assert_eq(_picker._outline.get_target(), tree,
		"Tap ins Leere darf ein rein automatisch (Autodetect) markiertes Ziel nicht abwählen.")

func test_repeated_proximity_changed_same_target_does_not_rebuild_outline() -> void:
	var tree := _make_target("Tree")
	_bus.world().emit_proximity_changed(tree, true)
	var first_outline: InteractionOutline = _picker._outline
	_bus.world().emit_proximity_changed(tree, true)
	assert_eq(_picker._outline, first_outline,
		"Dasselbe Ziel erneut zu melden darf die Umrandung nicht unnötig neu aufbauen.")
