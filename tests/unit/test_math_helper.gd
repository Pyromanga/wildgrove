# res://tests/unit/test_math_helper.gd
extends GutTest

## Unit-Tests für MathHelper (statische, reine Funktionen — kein Service,
## kein DI, aus der Tier-1-Triage der ungetesteten Klassen).
##
## Strategie: calculate_move_direction_from_yaw() ist vollständig pure
## (float + Vector2 -> Vector3, kein Node nötig). calculate_move_direction()
## braucht einen echten Node3D für global_transform.basis — dafür ein
## einfacher Node3D via add_child_autofree(), keine volle Spieler-Szene.
##
## WICHTIGER HINWEIS zur Test-Strategie: Ich kann hier keine Godot-Laufzeit
## ausführen und wollte die Rotationsmatrix nicht von Hand nachrechnen (zu
## fehleranfällig ohne Ausführung — eine falsch abgeleitete Trig-Erwartung
## sieht genauso "grün" aus wie eine richtige, bis sie es nicht ist). Deshalb
## zwei Test-Strategien statt "erwarteten Zahlen":
##   1. Rotations-UNABHÄNGIGE Invarianten (Einheitsvektor, Y-Komponente immer
##      0, forward⊥right) — gelten für JEDEN Yaw-Wert, unabhängig von
##      Rotationsrichtung/Vorzeichen-Konvention.
##   2. Differential-Test: MathHelper's eigener ADR-025-Kommentar behauptet
##      "bit-identische Ergebnisse" zwischen calculate_move_direction() (Node)
##      und calculate_move_direction_from_yaw() (reiner Winkel) für denselben
##      Yaw. Das lässt sich prüfen OHNE die Formel selbst nachzurechnen: Node
##      auf denselben Yaw rotieren, beide Funktionen aufrufen, vergleichen.
##      Das ist zugleich der wertvollste Test hier — er verifiziert genau die
##      Garantie, die der Code-Kommentar selbst gibt, und würde Drift
##      zwischen den beiden (duplizierten) Formeln sofort auffangen.
##   3. Für yaw=0 UND yaw=PI (180°) sind konkrete Zahlen trotzdem sicher
##      angebbar: bei diesen beiden Winkeln ist sin(yaw)=0, wodurch die
##      Rotationsrichtungs-Konvention (im/gegen Uhrzeigersinn) keine Rolle
##      spielt — die Erwartung ist bei beiden möglichen Konventionen gleich.


func _assert_is_unit_or_zero(v: Vector3, context: String) -> void:
	var len := v.length()
	assert_true(len < 0.0001 or absf(len - 1.0) < 0.0001,
		"%s: Ergebnis muss Einheitsvektor oder Nullvektor sein, war Länge %s" % [context, len])


# ─────────────────────────────────────────────
# calculate_move_direction_from_yaw() — Invarianten für beliebigen Yaw
# ─────────────────────────────────────────────

func test_from_yaw_zero_input_is_zero_vector() -> void:
	for yaw in [0.0, 1.0, -2.5, PI, TAU]:
		assert_eq(MathHelper.calculate_move_direction_from_yaw(yaw, Vector2.ZERO), Vector3.ZERO)

func test_from_yaw_result_never_has_y_component() -> void:
	for yaw in [0.0, 0.7, -1.9, PI / 2.0, PI]:
		var result := MathHelper.calculate_move_direction_from_yaw(yaw, Vector2(0.5, -0.8))
		assert_eq(result.y, 0.0, "Bewegungsrichtung ist immer in der XZ-Ebene, nie Y.")

func test_from_yaw_nonzero_input_yields_unit_vector() -> void:
	for yaw in [0.0, 0.7, -1.9, PI / 2.0, PI, 3.9]:
		var result := MathHelper.calculate_move_direction_from_yaw(yaw, Vector2(0.3, -0.6))
		_assert_is_unit_or_zero(result, "yaw=%s" % yaw)

func test_from_yaw_pure_forward_and_pure_right_are_perpendicular() -> void:
	# forward-only und right-only Eingabe getrennt abfragen und Orthogonalität
	# prüfen — hält für jede Rotationsrichtungs-Konvention.
	for yaw in [0.0, 1.2, -0.4, PI]:
		var fwd := MathHelper.calculate_move_direction_from_yaw(yaw, Vector2(0.0, -1.0))
		var right := MathHelper.calculate_move_direction_from_yaw(yaw, Vector2(1.0, 0.0))
		assert_almost_eq(fwd.dot(right), 0.0, 0.0001, "forward und right müssen bei yaw=%s orthogonal sein." % yaw)


# ─────────────────────────────────────────────
# calculate_move_direction_from_yaw() — konkrete Werte bei yaw=0 und yaw=PI
# (sin(yaw)=0 bei beiden -> Vorzeichen-Konvention der Rotation spielt keine Rolle)
# ─────────────────────────────────────────────

func test_from_yaw_zero_forward_press_moves_along_negative_z() -> void:
	var result := MathHelper.calculate_move_direction_from_yaw(0.0, Vector2(0.0, -1.0))
	assert_almost_eq(result.x, 0.0, 0.0001)
	assert_almost_eq(result.z, -1.0, 0.0001)

func test_from_yaw_zero_right_press_moves_along_positive_x() -> void:
	var result := MathHelper.calculate_move_direction_from_yaw(0.0, Vector2(1.0, 0.0))
	assert_almost_eq(result.x, 1.0, 0.0001)
	assert_almost_eq(result.z, 0.0, 0.0001)

func test_from_yaw_pi_forward_press_moves_along_positive_z() -> void:
	# Bei 180°-Rotation ist "vorwärts" exakt umgekehrt zu yaw=0 — unabhängig
	# von der Rotationsrichtungs-Konvention (sin(π)=0 in jeder Konvention).
	var result := MathHelper.calculate_move_direction_from_yaw(PI, Vector2(0.0, -1.0))
	assert_almost_eq(result.x, 0.0, 0.0001)
	assert_almost_eq(result.z, 1.0, 0.0001)

func test_from_yaw_pi_right_press_moves_along_negative_x() -> void:
	var result := MathHelper.calculate_move_direction_from_yaw(PI, Vector2(1.0, 0.0))
	assert_almost_eq(result.x, -1.0, 0.0001)
	assert_almost_eq(result.z, 0.0, 0.0001)


# ─────────────────────────────────────────────
# calculate_move_direction() — Node3D-Variante
# ─────────────────────────────────────────────

func test_node_variant_invalid_camera_arm_returns_zero() -> void:
	var freed := Node3D.new()
	freed.free()  # sofort freigeben -> is_instance_valid() muss false liefern
	var result := MathHelper.calculate_move_direction(freed, Vector2(1.0, 1.0))
	assert_eq(result, Vector3.ZERO)

func test_node_variant_null_camera_arm_returns_zero() -> void:
	var result := MathHelper.calculate_move_direction(null, Vector2(1.0, 1.0))
	assert_eq(result, Vector3.ZERO)

func test_node_variant_zero_input_is_zero_vector() -> void:
	var node := Node3D.new()
	add_child_autofree(node)
	var result := MathHelper.calculate_move_direction(node, Vector2.ZERO)
	assert_eq(result, Vector3.ZERO)


# ─────────────────────────────────────────────
# Differential-Test: beide Funktionen müssen für denselben Yaw übereinstimmen
# (das ist die eigentliche Behauptung aus dem ADR-025-Kommentar in MathHelper.gd)
# ─────────────────────────────────────────────

func test_node_variant_matches_yaw_variant_for_various_angles_and_inputs() -> void:
	var node := Node3D.new()
	add_child_autofree(node)
	var yaws: Array = [0.0, 0.3, 1.0, -0.7, PI / 2.0, PI, -PI / 2.0, 2.4]
	var inputs: Array = [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(0.6, -0.8), Vector2(-0.4, 0.4)]
	for yaw in yaws:
		node.rotation = Vector3(0.0, yaw, 0.0)
		for input in inputs:
			var from_node := MathHelper.calculate_move_direction(node, input)
			var from_yaw := MathHelper.calculate_move_direction_from_yaw(yaw, input)
			assert_almost_eq(from_node.x, from_yaw.x, 0.0001,
				"x weicht ab bei yaw=%s input=%s" % [yaw, input])
			assert_almost_eq(from_node.y, from_yaw.y, 0.0001,
				"y weicht ab bei yaw=%s input=%s" % [yaw, input])
			assert_almost_eq(from_node.z, from_yaw.z, 0.0001,
				"z weicht ab bei yaw=%s input=%s" % [yaw, input])
