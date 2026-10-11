# res://tests/unit/test_animal_visual_builder.gd
extends GutTest

## Unit-Tests für AnimalVisualBuilder.build() (stateless, statische Geometrie-Fabrik).
##
## Seit der Umstellung auf AnimalVisualProfile (Wunsch "Tiere sollen besser aussehen,
## gemeinsame Basis statt alles neu erfinden") ist die Geometrie deutlich reicher als
## vorher (Augen/Schnauze/Ohren/Schwanz statt nur Kapsel+Kugel+4 Beine) — die Tests unten
## prüfen weiterhin alles, was von Hand exakt nachrechenbar ist (Beine, Rumpf, Schädel —
## reine Multiplikationen von body_size-Komponenten, siehe AnimalVisualBuilder-Konstanten),
## und für die restlichen Gesichts-/Schwanzmerkmale (über ProcGenShapes.spike() platziert,
## keine einfachen Multiplikationen mehr) nur noch STRUKTURELLE Invarianten (Kind mit
## erwartetem Namen/Mesh-Typ/Material existiert) statt exakter Positionswerte.

const COLOR := Color(0.4, 0.5, 0.6, 1.0)
const BODY_SIZE := Vector3(2.0, 3.0, 1.0)  # radius=1.0, Höhe=3.0, Tiefe=1.0

var _root: Node3D
var _profile: AnimalVisualProfile


func before_each() -> void:
	# Default-Profil == AnimalBase-Defaults (ROUND/STUB/SHORT/NONE), siehe dortige Felder.
	_profile = AnimalVisualProfile.new(COLOR, BODY_SIZE)
	_root = AnimalVisualBuilder.build(_profile)
	add_child_autofree(_root)


func after_each() -> void:
	_root = null
	_profile = null


func _find(node_name: String) -> Node:
	return _root.find_child(node_name, true, false)


func test_root_is_named_visuals() -> void:
	assert_eq(_root.name, "Visuals")


# ─────────────────────────────────────────────
# Beine — reine Multiplikation von body_size, exakt nachrechenbar
# ─────────────────────────────────────────────

func test_all_four_legs_are_cylinders_with_correct_dimensions() -> void:
	for leg_name in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		var lmi: MeshInstance3D = _find(leg_name)
		assert_not_null(lmi, "Bein '%s' fehlt" % leg_name)
		assert_true(lmi.mesh is CylinderMesh, leg_name)
		var cyl: CylinderMesh = lmi.mesh
		assert_almost_eq(cyl.top_radius, 0.17, 0.0001, "body_size.x*0.085, %s" % leg_name)
		assert_almost_eq(cyl.bottom_radius, 0.13, 0.0001, "body_size.x*0.065, %s" % leg_name)
		assert_almost_eq(cyl.height, 1.65, 0.0001, "body_size.y*0.55, %s" % leg_name)

func test_all_four_legs_use_darkened_body_color() -> void:
	for leg_name in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		var lmi: MeshInstance3D = _find(leg_name)
		var mat: StandardMaterial3D = lmi.material_override
		assert_eq(mat.albedo_color, COLOR.darkened(0.2), leg_name)

func test_leg_positions_are_at_four_corners() -> void:
	# offset = (±body_size.x*0.3=±0.6, body_size.y*0.27=0.81, ±body_size.z*0.22=±0.22)
	var expected := {
		"LegFL": Vector3(-0.6, 0.81, -0.22),
		"LegFR": Vector3(0.6, 0.81, -0.22),
		"LegBL": Vector3(-0.6, 0.81, 0.22),
		"LegBR": Vector3(0.6, 0.81, 0.22),
	}
	for leg_name: String in expected:
		var lmi: MeshInstance3D = _find(leg_name)
		assert_eq(lmi.position, expected[leg_name], leg_name)


# ─────────────────────────────────────────────
# Rumpf — liegende Kapsel (90°-Drehung), exakt nachrechenbar
# ─────────────────────────────────────────────

func test_body_is_capsule_with_correct_dimensions() -> void:
	var bmi: MeshInstance3D = _find("Body")
	assert_not_null(bmi)
	assert_true(bmi.mesh is CapsuleMesh)
	var cm: CapsuleMesh = bmi.mesh
	assert_almost_eq(cm.radius, 0.84, 0.0001, "body_size.x*0.42")
	assert_almost_eq(cm.height, 2.2, 0.0001, "max(body_size.z*2.2, radius*2+0.1)")

func test_body_lies_horizontally_and_is_vertically_squashed() -> void:
	var bmi: MeshInstance3D = _find("Body")
	assert_almost_eq(bmi.rotation.x, PI * 0.5, 0.0001, "Rumpf liegt (Länge entlang Z statt Y)")
	assert_almost_eq(bmi.scale.z, 0.82, 0.0001, "BODY_VERTICAL_SQUASH")

func test_body_position_and_color() -> void:
	var bmi: MeshInstance3D = _find("Body")
	# leg_top=3.0*0.545=1.635; +radius(0.84)*0.82*0.85=0.58548 -> 2.22048
	assert_almost_eq(bmi.position.y, 2.22048, 0.001, "body_center_y")
	var mat: StandardMaterial3D = bmi.material_override
	assert_eq(mat.albedo_color, COLOR)


# ─────────────────────────────────────────────
# Kopf — Kugel, exakt nachrechenbar; Gesichtsmerkmale nur strukturell geprüft
# ─────────────────────────────────────────────

func test_head_group_exists_at_expected_position() -> void:
	var head: Node3D = _find("Head")
	assert_not_null(head)
	# body_center_y(2.22048) + head_r(0.8)*0.35 = 2.50048; body_length(2.2)*0.5 - head_r*0.2 = 0.94
	assert_almost_eq(head.position.y, 2.50048, 0.001, "head_y")
	assert_almost_eq(head.position.z, 0.94, 0.0001, "head_z")

func test_skull_is_sphere_with_correct_radius_and_lightened_color() -> void:
	var head: Node3D = _find("Head")
	var skull: MeshInstance3D = head.get_node("Skull")
	assert_true(skull.mesh is SphereMesh)
	var sm: SphereMesh = skull.mesh
	assert_almost_eq(sm.radius, 0.8, 0.0001, "body_size.x*0.40")
	var mat: StandardMaterial3D = skull.material_override
	assert_eq(mat.albedo_color, COLOR.lightened(0.1))

func test_eyes_exist_as_dark_spheres() -> void:
	for eye_name in ["EyeR", "EyeL"]:
		var eye: MeshInstance3D = _find(eye_name)
		assert_not_null(eye, eye_name)
		assert_true(eye.mesh is SphereMesh, eye_name)

func test_default_profile_has_round_ears() -> void:
	for ear_name in ["EarR", "EarL"]:
		var ear: MeshInstance3D = _find(ear_name)
		assert_not_null(ear, ear_name)
		assert_true(ear.mesh is SphereMesh, "EarStyle.ROUND -> Kugel, %s" % ear_name)

func test_default_profile_has_short_snout_nose() -> void:
	var nose: MeshInstance3D = _find("Nose")
	assert_not_null(nose)
	assert_true(nose.mesh is SphereMesh)

func test_default_profile_has_no_headgear() -> void:
	assert_null(_find("AntlerR"), "HeadgearStyle.NONE -> kein Geweih")
	assert_null(_find("TuskR"), "HeadgearStyle.NONE -> keine Hauer")


# ─────────────────────────────────────────────
# Schwanz — abhängig vom TailStyle
# ─────────────────────────────────────────────

func test_default_profile_has_stub_tail() -> void:
	var tail: MeshInstance3D = _find("Tail")
	assert_not_null(tail)
	assert_true(tail.mesh is CapsuleMesh, "TailStyle.STUB -> Kapsel")

func test_tail_style_none_produces_no_tail_node() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.tail_style = AnimalVisualProfile.TailStyle.NONE
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	assert_null(root.find_child("Tail", true, false))

func test_fluffy_tail_is_a_sphere_ignoring_body_color() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.tail_style = AnimalVisualProfile.TailStyle.FLUFFY
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	var tail: MeshInstance3D = root.find_child("Tail", true, false)
	assert_true(tail.mesh is SphereMesh)
	var mat: StandardMaterial3D = tail.material_override
	assert_ne(mat.albedo_color, COLOR, "Puschelschwanz ist absichtlich naturfarben, nicht fellfarbig")


# ─────────────────────────────────────────────
# Kopfschmuck — abhängig vom HeadgearStyle
# ─────────────────────────────────────────────

func test_antlers_produce_four_pieces_per_side_group() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.headgear_style = AnimalVisualProfile.HeadgearStyle.ANTLERS
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	for n in ["AntlerR", "AntlerL", "AntlerRTine", "AntlerLTine"]:
		assert_not_null(root.find_child(n, true, false), n)

func test_tusks_produce_two_cream_colored_cones() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.headgear_style = AnimalVisualProfile.HeadgearStyle.TUSKS
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	for n in ["TuskR", "TuskL"]:
		var tusk: MeshInstance3D = root.find_child(n, true, false)
		assert_not_null(tusk, n)
		assert_true(tusk.mesh is CylinderMesh, "Kegel = CylinderMesh mit top_radius 0")
		var mat: StandardMaterial3D = tusk.material_override
		assert_ne(mat.albedo_color, COLOR, "Hauer sind absichtlich elfenbeinfarben, nicht fellfarbig")


# ─────────────────────────────────────────────
# Statelessness
# ─────────────────────────────────────────────

func test_repeated_build_calls_are_independent() -> void:
	var root2 := AnimalVisualBuilder.build(AnimalVisualProfile.new(COLOR, BODY_SIZE))
	add_child_autofree(root2)
	assert_ne(_root, root2)
	assert_not_null(root2.find_child("Body", true, false))


# ─────────────────────────────────────────────
# Neue Baupläne (Wunsch "mehr Körper für Tiere einbauen") — nur strukturelle
# Stichproben, keine exakten Positionswerte (analog zu den Gesichts-/Schwanz-Tests oben).
# ─────────────────────────────────────────────

func test_insect_body_plan_has_no_quadruped_legs() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.body_plan = AnimalVisualProfile.BodyPlan.INSECT
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	assert_null(root.find_child("LegFL", true, false), "Insekt hat keine Vierbeiner-Beine")
	assert_not_null(root.find_child("Thorax", true, false))
	assert_not_null(root.find_child("Abdomen", true, false))
	assert_not_null(root.find_child("LegFrontR", true, false), "Insekt hat eigene 6 Beine")

func test_insect_wings_depend_on_wing_style() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.body_plan = AnimalVisualProfile.BodyPlan.INSECT
	profile.wing_style = AnimalVisualProfile.WingStyle.NONE
	var root_none := AnimalVisualBuilder.build(profile)
	add_child_autofree(root_none)
	assert_null(root_none.find_child("WingR", true, false), "WingStyle.NONE -> keine Flügel")

	profile.wing_style = AnimalVisualProfile.WingStyle.TRANSLUCENT
	var root_wings := AnimalVisualBuilder.build(profile)
	add_child_autofree(root_wings)
	assert_not_null(root_wings.find_child("WingR", true, false))
	assert_not_null(root_wings.find_child("WingL", true, false))

func test_spider_body_plan_has_eight_legs() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.body_plan = AnimalVisualProfile.BodyPlan.SPIDER
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	var leg_count := 0
	for i in 4:
		for side in ["R", "L"]:
			if root.find_child("Leg%d%s" % [i, side], true, false) != null:
				leg_count += 1
	assert_eq(leg_count, 8, "Spinne hat acht Beine")
	assert_not_null(root.find_child("Cephalothorax", true, false))
	assert_not_null(root.find_child("Abdomen", true, false))

func test_snake_body_plan_has_segments_and_no_legs() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.body_plan = AnimalVisualProfile.BodyPlan.SNAKE
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	assert_not_null(root.find_child("Segment0", true, false))
	assert_not_null(root.find_child("Head", true, false))
	assert_null(root.find_child("LegFL", true, false), "Schlange hat keine Beine")

func test_fish_body_plan_has_fins_and_no_legs() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.body_plan = AnimalVisualProfile.BodyPlan.FISH
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	assert_not_null(root.find_child("TailFinR", true, false))
	assert_not_null(root.find_child("DorsalFin", true, false))
	assert_null(root.find_child("LegFL", true, false), "Fisch hat keine Beine")

func test_back_style_none_produces_no_back_feature_nodes() -> void:
	assert_null(_find("BackHump"))
	assert_null(_find("Mane0"))

func test_back_style_hump_adds_hump_node() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.back_style = AnimalVisualProfile.BackStyle.HUMP
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	assert_not_null(root.find_child("BackHump", true, false))

func test_back_style_mane_adds_mane_nodes() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.back_style = AnimalVisualProfile.BackStyle.MANE
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	assert_not_null(root.find_child("Mane0", true, false))


# ─────────────────────────────────────────────
# Form-/Gliedmaßen-Varianten (Wunsch "neue Shapes/Formen/Gliedmaßen — Variationen")
# ─────────────────────────────────────────────

func test_body_shape_changes_body_mesh_radius() -> void:
	var normal := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	var root_normal := AnimalVisualBuilder.build(normal)
	add_child_autofree(root_normal)
	var body_normal := root_normal.find_child("Body", true, false) as MeshInstance3D
	var radius_normal: float = (body_normal.mesh as CapsuleMesh).radius

	var stocky := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	stocky.body_shape = AnimalVisualProfile.BodyShape.STOCKY
	var root_stocky := AnimalVisualBuilder.build(stocky)
	add_child_autofree(root_stocky)
	var body_stocky := root_stocky.find_child("Body", true, false) as MeshInstance3D
	var radius_stocky: float = (body_stocky.mesh as CapsuleMesh).radius

	assert_gt(radius_stocky, radius_normal, "STOCKY soll einen dickeren Rumpf ergeben als NORMAL")

func test_leg_style_changes_leg_mesh_dimensions() -> void:
	var normal := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	var root_normal := AnimalVisualBuilder.build(normal)
	add_child_autofree(root_normal)
	var leg_normal := root_normal.find_child("LegFL", true, false) as MeshInstance3D
	var height_normal: float = (leg_normal.mesh as CylinderMesh).height

	var long_legs := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	long_legs.leg_style = AnimalVisualProfile.LegStyle.LONG
	var root_long := AnimalVisualBuilder.build(long_legs)
	add_child_autofree(root_long)
	var leg_long := root_long.find_child("LegFL", true, false) as MeshInstance3D
	var height_long: float = (leg_long.mesh as CylinderMesh).height

	assert_gt(height_long, height_normal, "LegStyle.LONG soll längere Beine ergeben als NORMAL")

func test_short_legs_still_touch_the_ground() -> void:
	# Regressionstest für den "Rumpf schwebt/wird durchstoßen"-Bug: die Bein-UNTERKANTE
	# (position.y - height/2) muss unabhängig vom leg_style immer bei (nahe) y=0 bleiben.
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.leg_style = AnimalVisualProfile.LegStyle.SHORT
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	var leg := root.find_child("LegFL", true, false) as MeshInstance3D
	var height: float = (leg.mesh as CylinderMesh).height
	var bottom_y: float = leg.position.y - height * 0.5
	assert_almost_eq(bottom_y, 0.0, 0.05)

func test_body_shape_and_leg_style_default_to_normal() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	assert_eq(profile.body_shape, AnimalVisualProfile.BodyShape.NORMAL)
	assert_eq(profile.leg_style, AnimalVisualProfile.LegStyle.NORMAL)


# ─────────────────────────────────────────────
# Rumpf-Textur (Wunsch "Textur von Tieren")
# ─────────────────────────────────────────────

func test_pattern_style_none_uses_plain_color_material() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	var body := root.find_child("Body", true, false) as MeshInstance3D
	var mat := body.material_override as StandardMaterial3D
	assert_null(mat.albedo_texture, "PatternStyle.NONE soll keine Textur erzeugen")
	assert_eq(mat.albedo_color, COLOR)

func test_pattern_style_stripes_generates_albedo_texture() -> void:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.pattern_style = AnimalVisualProfile.PatternStyle.STRIPES
	profile.pattern_color = Color(0.05, 0.05, 0.05)
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	var body := root.find_child("Body", true, false) as MeshInstance3D
	var mat := body.material_override as StandardMaterial3D
	assert_not_null(mat.albedo_texture, "PatternStyle.STRIPES soll eine Textur erzeugen")
	# albedo_color muss WEISS sein, sonst verfälscht StandardMaterial3D die in der Textur
	# fest eingebackenen Farben durch Multiplikation (siehe _build_body_material()-Kommentar).
	assert_eq(mat.albedo_color, Color.WHITE)

func test_pattern_texture_contains_both_colors() -> void:
	var profile := AnimalVisualProfile.new(Color(0.9, 0.9, 0.9), BODY_SIZE)
	profile.pattern_style = AnimalVisualProfile.PatternStyle.SPOTS
	profile.pattern_color = Color(0.05, 0.05, 0.05)
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	var body := root.find_child("Body", true, false) as MeshInstance3D
	var mat := body.material_override as StandardMaterial3D
	var img: Image = mat.albedo_texture.get_image()
	var saw_base := false
	var saw_pattern := false
	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			if px.is_equal_approx(Color(0.9, 0.9, 0.9)):
				saw_base = true
			elif px.is_equal_approx(Color(0.05, 0.05, 0.05)):
				saw_pattern = true
	assert_true(saw_base, "Textur soll die Grundfarbe enthalten")
	assert_true(saw_pattern, "Textur soll die Musterfarbe enthalten")

func test_pattern_mask_is_deterministic() -> void:
	# Dieselbe species_id (gleiche u/v-Werte) soll IMMER dasselbe Muster ergeben.
	var a := AnimalVisualBuilder._pattern_mask(0.33, 0.61, AnimalVisualProfile.PatternStyle.SPOTS)
	var b := AnimalVisualBuilder._pattern_mask(0.33, 0.61, AnimalVisualProfile.PatternStyle.SPOTS)
	assert_eq(a, b)

func test_non_quadruped_body_plans_ignore_pattern_style() -> void:
	# Insekt/Spinne/Schlange/Fisch haben eigene _build_*()-Pfade ohne Body-Material-Aufruf —
	# ein gesetzter pattern_style darf dort nicht crashen, hat aber keine Wirkung.
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	profile.body_plan = AnimalVisualProfile.BodyPlan.SNAKE
	profile.pattern_style = AnimalVisualProfile.PatternStyle.STRIPES
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	assert_not_null(root.find_child("Segment0", true, false))


# ─────────────────────────────────────────────
# Hörner / Schaufelgeweih / dünner Schwanz (Wunsch "Tiere sehen alle gleich aus")
# ─────────────────────────────────────────────

func _build_with(mutator: Callable) -> Node3D:
	var profile := AnimalVisualProfile.new(COLOR, BODY_SIZE)
	mutator.call(profile)
	var root := AnimalVisualBuilder.build(profile)
	add_child_autofree(root)
	return root

func test_horns_produce_root_and_tip_per_side() -> void:
	var root := _build_with(func(p): p.headgear_style = AnimalVisualProfile.HeadgearStyle.HORNS)
	for n in ["HornR", "HornL", "HornRTip", "HornLTip"]:
		assert_not_null(root.find_child(n, true, false), n)

func test_broad_antlers_produce_beam_palm_and_three_tines_per_side() -> void:
	var root := _build_with(func(p): p.headgear_style = AnimalVisualProfile.HeadgearStyle.BROAD_ANTLERS)
	for side in ["R", "L"]:
		assert_not_null(root.find_child("Antler%s" % side, true, false))
		assert_not_null(root.find_child("Antler%sPalm" % side, true, false))
		for k in 3:
			assert_not_null(root.find_child("Antler%sTine%d" % [side, k], true, false))

func test_thin_tail_is_longer_than_stub_tail() -> void:
	var thin: Node3D = _build_with(func(p): p.tail_style = AnimalVisualProfile.TailStyle.THIN)
	var stub: Node3D = _build_with(func(p): p.tail_style = AnimalVisualProfile.TailStyle.STUB)
	var thin_mesh := (thin.find_child("Tail", true, false) as MeshInstance3D).mesh as CapsuleMesh
	var stub_mesh := (stub.find_child("Tail", true, false) as MeshInstance3D).mesh as CapsuleMesh
	assert_gt(thin_mesh.height, stub_mesh.height * 3.0)
	assert_lt(thin_mesh.radius, stub_mesh.radius)

# ─────────────────────────────────────────────
# AccentStyle je Bauplan
# ─────────────────────────────────────────────

func _plan_with_accent(plan: int, accent: int) -> Node3D:
	return _build_with(func(p):
		p.body_plan = plan
		p.accent_style = accent
		p.wing_style = AnimalVisualProfile.WingStyle.SHELL)

func test_snake_hood_rattle_and_triangle_head() -> void:
	var plain := _plan_with_accent(AnimalVisualProfile.BodyPlan.SNAKE, AnimalVisualProfile.AccentStyle.NONE)
	assert_null(plain.find_child("Hood", true, false))
	assert_null(plain.find_child("Rattle0", true, false))
	var plain_head: Node3D = plain.find_child("Head", true, false)
	assert_eq(plain_head.scale, Vector3.ONE)

	var cobra := _plan_with_accent(AnimalVisualProfile.BodyPlan.SNAKE, AnimalVisualProfile.AccentStyle.HOOD)
	assert_not_null(cobra.find_child("Hood", true, false))

	var rattler := _plan_with_accent(AnimalVisualProfile.BodyPlan.SNAKE, AnimalVisualProfile.AccentStyle.RATTLE)
	for k in 3:
		assert_not_null(rattler.find_child("Rattle%d" % k, true, false))
	assert_gt((rattler.find_child("Head", true, false) as Node3D).scale.x, 1.0, "Dreieckskopf breiter")

	var viper := _plan_with_accent(AnimalVisualProfile.BodyPlan.SNAKE, AnimalVisualProfile.AccentStyle.TRIANGLE_HEAD)
	assert_lt((viper.find_child("Head", true, false) as Node3D).scale.y, 1.0, "Dreieckskopf flacher")
	assert_null(viper.find_child("Rattle0", true, false))

func test_fish_accents() -> void:
	var catfish := _plan_with_accent(AnimalVisualProfile.BodyPlan.FISH, AnimalVisualProfile.AccentStyle.BARBELS)
	for n in ["Barbel0R", "Barbel0L", "Barbel1R", "Barbel1L"]:
		assert_not_null(catfish.find_child(n, true, false), n)
	assert_not_null(catfish.find_child("DorsalFin", true, false), "Wels behält normale Flossen")

	var pike := _plan_with_accent(AnimalVisualProfile.BodyPlan.FISH, AnimalVisualProfile.AccentStyle.LONG_JAW)
	assert_not_null(pike.find_child("Jaw", true, false))
	var plain := _plan_with_accent(AnimalVisualProfile.BodyPlan.FISH, AnimalVisualProfile.AccentStyle.NONE)
	var pike_dorsal: Node3D = pike.find_child("DorsalFin", true, false)
	var plain_dorsal: Node3D = plain.find_child("DorsalFin", true, false)
	assert_lt(pike_dorsal.position.z, plain_dorsal.position.z, "Hecht: Rückenflosse weiter hinten")

	var eel := _plan_with_accent(AnimalVisualProfile.BodyPlan.FISH, AnimalVisualProfile.AccentStyle.RIBBON)
	assert_not_null(eel.find_child("RibbonFin", true, false))
	assert_not_null(eel.find_child("TailTip", true, false))
	assert_null(eel.find_child("TailFinR", true, false), "Aal hat keine V-Schwanzflosse")
	assert_null(eel.find_child("DorsalFin", true, false), "Aal hat keine einzelne Rückenflosse")

func test_spider_accents() -> void:
	var jumper := _plan_with_accent(AnimalVisualProfile.BodyPlan.SPIDER, AnimalVisualProfile.AccentStyle.BIG_EYES)
	assert_not_null(jumper.find_child("BigEyeR", true, false))
	assert_not_null(jumper.find_child("BigEyeL", true, false))

	var garden := _plan_with_accent(AnimalVisualProfile.BodyPlan.SPIDER, AnimalVisualProfile.AccentStyle.ABDOMEN_MARK)
	assert_not_null(garden.find_child("AbdomenMarkLong", true, false))
	assert_not_null(garden.find_child("AbdomenMarkCross", true, false))

	var plain := _plan_with_accent(AnimalVisualProfile.BodyPlan.SPIDER, AnimalVisualProfile.AccentStyle.NONE)
	var stout := _plan_with_accent(AnimalVisualProfile.BodyPlan.SPIDER, AnimalVisualProfile.AccentStyle.STOUT)
	var plain_leg := (plain.find_child("Leg0R", true, false) as MeshInstance3D).mesh as CylinderMesh
	var stout_leg := (stout.find_child("Leg0R", true, false) as MeshInstance3D).mesh as CylinderMesh
	assert_gt(stout_leg.bottom_radius, plain_leg.bottom_radius * 1.5, "Vogelspinne: dickere Beine")
	assert_almost_eq(stout_leg.height, plain_leg.height, 0.0001, "...aber gleich lang")

func test_insect_accents_spots_and_stripes() -> void:
	var ladybug := _plan_with_accent(AnimalVisualProfile.BodyPlan.INSECT, AnimalVisualProfile.AccentStyle.SPOTS)
	for i in 3:
		for side in ["R", "L"]:
			assert_not_null(ladybug.find_child("Spot%d%s" % [i, side], true, false))

	var no_shell := _build_with(func(p):
		p.body_plan = AnimalVisualProfile.BodyPlan.INSECT
		p.accent_style = AnimalVisualProfile.AccentStyle.SPOTS
		p.wing_style = AnimalVisualProfile.WingStyle.NONE)
	assert_null(no_shell.find_child("Spot0R", true, false), "Punkte brauchen Deckflügel")

	var wasp := _plan_with_accent(AnimalVisualProfile.BodyPlan.INSECT, AnimalVisualProfile.AccentStyle.STRIPES)
	for i in 3:
		assert_not_null(wasp.find_child("Band%d" % i, true, false))

func test_accent_style_is_ignored_on_wrong_body_plan() -> void:
	var quad := _build_with(func(p): p.accent_style = AnimalVisualProfile.AccentStyle.HOOD)
	assert_null(quad.find_child("Hood", true, false))
	assert_not_null(quad.find_child("Body", true, false))

func test_elongated_insect_has_longer_abdomen_than_compact_one() -> void:
	var compact := _build_with(func(p):
		p.body_plan = AnimalVisualProfile.BodyPlan.INSECT
		p.body_size = Vector3(0.1, 0.09, 0.1))
	var long_one := _build_with(func(p):
		p.body_plan = AnimalVisualProfile.BodyPlan.INSECT
		p.body_size = Vector3(0.1, 0.09, 0.26))
	assert_eq((compact.find_child("Abdomen", true, false) as Node3D).scale.z, 1.0)
	assert_gt((long_one.find_child("Abdomen", true, false) as Node3D).scale.z, 1.5, "Libellen-Streckung")
