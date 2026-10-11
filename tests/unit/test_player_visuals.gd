# res://tests/unit/test_player_visuals.gd
extends GutTest

## Tests für PlayerVisuals: Aussehens-Anwendung (apply_appearance() für die
## grobe Wizard-Farbe, apply_look() für das volle CharacterLook-Modell),
## Bone-/Slot-Struktur und die Lauf-Pose. Skeleton/Bone-Attachments selbst
## (Struktur, Namen) sind hier mitgeprüft — vorher gab es dafür keinen
## eigenen Test, nur indirekt über WeaponVisual3D-nahe Tests.

var _visuals: PlayerVisuals

func before_each() -> void:
	_visuals = autofree(PlayerVisuals.new())

# ─────────────────────────────────────────────
# apply_appearance() — grobe Wizard-Farbe (Legacy, unverändert)
# ─────────────────────────────────────────────

func test_apply_appearance_sets_albedo_color_on_mesh_material() -> void:
	_visuals.apply_appearance(Color(0.25, 0.55, 0.25))

	var mat := _visuals.mesh.material_override as StandardMaterial3D
	assert_true(is_instance_valid(mat))
	assert_eq(mat.albedo_color, Color(0.25, 0.55, 0.25))

func test_apply_appearance_can_be_called_multiple_times_reusing_the_material() -> void:
	_visuals.apply_appearance(Color(0.25, 0.55, 0.25))
	var mat_first := _visuals.mesh.material_override

	_visuals.apply_appearance(Color(0.95, 0.75, 0.25))
	var mat_second := _visuals.mesh.material_override

	assert_eq(mat_first, mat_second, "apply_appearance() soll das bestehende Material wiederverwenden statt bei jedem Aufruf ein neues zu erzeugen.")
	assert_eq((mat_second as StandardMaterial3D).albedo_color, Color(0.95, 0.75, 0.25))

# ─────────────────────────────────────────────
# Konstruktion — Default-Look, Bones, Slots
# ─────────────────────────────────────────────

func test_constructs_with_a_full_default_look() -> void:
	assert_eq(_visuals.get_look(), CharacterLook.default_look())

func test_mesh_is_set_after_construction() -> void:
	assert_true(is_instance_valid(_visuals.mesh))

func test_skeleton_has_five_named_bones() -> void:
	for bone_name in ["root", "spine", "head", "hand_r", "hand_l"]:
		assert_true(_visuals.get_bone_index(bone_name) >= 0, "Bone '%s' fehlt." % bone_name)
	assert_eq(_visuals.skeleton.get_bone_count(), 5)

func test_get_bone_attachment_returns_valid_attachment_for_known_bone() -> void:
	var att := _visuals.get_bone_attachment("hand_r")
	assert_true(is_instance_valid(att))
	assert_eq(att.bone_name, "hand_r")

func test_get_bone_attachment_returns_null_for_unknown_bone() -> void:
	assert_null(_visuals.get_bone_attachment("does_not_exist"))

func test_get_slot_returns_valid_nodes_for_head_and_back() -> void:
	assert_true(is_instance_valid(_visuals.get_slot(PlayerVisuals.SLOT_HEAD)))
	assert_true(is_instance_valid(_visuals.get_slot(PlayerVisuals.SLOT_BACK)))

func test_get_slot_returns_null_for_unknown_slot() -> void:
	assert_null(_visuals.get_slot("does_not_exist"))

# ─────────────────────────────────────────────
# apply_look()
# ─────────────────────────────────────────────

func test_apply_look_sanitizes_invalid_input() -> void:
	_visuals.apply_look({"skin": "not_a_real_option"})

	assert_eq(_visuals.get_look()["skin"], CharacterLook.DEFAULTS["skin"])

func test_apply_look_updates_torso_color_to_shirt_field() -> void:
	_visuals.apply_look(CharacterLook.sanitize({"shirt": "wald"}))

	var mat := _visuals.mesh.material_override as StandardMaterial3D
	assert_eq(mat.albedo_color, CharacterLook.color_of("shirt", "wald"))

func test_apply_look_twice_with_same_look_does_not_rebuild_parts() -> void:
	var look := CharacterLook.sanitize({"shirt": "wald"})
	_visuals.apply_look(look)
	var head_before := _visuals.get_node("Skeleton3D/Parts/Head")

	_visuals.apply_look(look.duplicate())
	var head_after := _visuals.get_node("Skeleton3D/Parts/Head")

	assert_eq(head_before, head_after, "Identischer Look darf die Körperteile nicht neu aufbauen.")

func test_apply_look_with_different_look_rebuilds_parts() -> void:
	_visuals.apply_look(CharacterLook.sanitize({"hair_style": "bald"}))
	var hair_before := _visuals.get_node("Skeleton3D/Parts/Head/Hair") as Node3D
	var child_count_before := hair_before.get_child_count()

	_visuals.apply_look(CharacterLook.sanitize({"hair_style": "long"}))
	var hair_after := _visuals.get_node("Skeleton3D/Parts/Head/Hair") as Node3D

	assert_eq(child_count_before, 0)
	assert_true(hair_after.get_child_count() > 0)

func test_apply_look_scales_skeleton_by_height() -> void:
	_visuals.apply_look(CharacterLook.sanitize({"height": "tall"}))
	assert_eq(_visuals.skeleton.scale, Vector3.ONE * CharacterLook.height_scale("tall"))

func test_apply_look_moves_hand_bones_to_match_shoulder_width() -> void:
	_visuals.apply_look(CharacterLook.sanitize({"build": "slim"}))
	var slim_x: float = _visuals.skeleton.get_bone_rest(_visuals.get_bone_index("hand_r")).origin.x

	_visuals.apply_look(CharacterLook.sanitize({"build": "broad"}))
	var broad_x: float = _visuals.skeleton.get_bone_rest(_visuals.get_bone_index("hand_r")).origin.x

	assert_true(broad_x > slim_x, "hand_r muss bei breiterer Statur weiter außen liegen.")

func test_apply_look_hand_bones_stay_mirrored() -> void:
	_visuals.apply_look(CharacterLook.sanitize({"build": "broad"}))
	var right_x: float = _visuals.skeleton.get_bone_rest(_visuals.get_bone_index("hand_r")).origin.x
	var left_x: float = _visuals.skeleton.get_bone_rest(_visuals.get_bone_index("hand_l")).origin.x
	assert_almost_eq(right_x, -left_x, 0.0001)

func test_get_look_returns_a_copy_not_the_internal_dict() -> void:
	var look := _visuals.get_look()
	look["skin"] = "dark"
	assert_ne(_visuals.get_look()["skin"], "dark")

func test_set_hair_visible_toggles_hair_node() -> void:
	_visuals.apply_look(CharacterLook.sanitize({"hair_style": "long"}))
	var hair := _visuals.get_node("Skeleton3D/Parts/Head/Hair") as Node3D

	_visuals.set_hair_visible(false)
	assert_false(hair.visible)

	_visuals.set_hair_visible(true)
	assert_true(hair.visible)

# ─────────────────────────────────────────────
# apply_walk_pose()
# ─────────────────────────────────────────────

func test_apply_walk_pose_zero_resets_limbs_to_rest() -> void:
	_visuals.apply_walk_pose(0.3)
	_visuals.apply_walk_pose(0.0)

	assert_almost_eq(_visuals.get_node("Skeleton3D/Parts/ArmR").rotation.x, 0.0, 0.0001)
	assert_almost_eq(_visuals.get_node("Skeleton3D/Parts/LegR").rotation.x, 0.0, 0.0001)

func test_apply_walk_pose_swings_opposite_arm_and_leg_on_same_side() -> void:
	_visuals.apply_walk_pose(0.3)

	var arm_r_rot: float = _visuals.get_node("Skeleton3D/Parts/ArmR").rotation.x
	var leg_r_rot: float = _visuals.get_node("Skeleton3D/Parts/LegR").rotation.x
	assert_true(sign(arm_r_rot) != sign(leg_r_rot), "Arm und Bein derselben Seite müssen gegenläufig schwingen (natürlicher Gang).")

func test_apply_walk_pose_mirrors_left_and_right_sides() -> void:
	_visuals.apply_walk_pose(0.3)

	var arm_r_rot: float = _visuals.get_node("Skeleton3D/Parts/ArmR").rotation.x
	var arm_l_rot: float = _visuals.get_node("Skeleton3D/Parts/ArmL").rotation.x
	assert_almost_eq(arm_r_rot, -arm_l_rot, 0.0001)

func test_apply_walk_pose_moves_hand_bone_pose_away_from_rest() -> void:
	var rest: Vector3 = _visuals.skeleton.get_bone_rest(_visuals.get_bone_index("hand_r")).origin
	_visuals.apply_walk_pose(0.4)
	var pose: Vector3 = _visuals.skeleton.get_bone_pose_position(_visuals.get_bone_index("hand_r"))
	assert_true(rest.distance_to(pose) > 0.001, "Hand-Bone-Pose muss bei ausschwingendem Arm von der Ruhepose abweichen.")

func test_apply_look_resets_walk_pose() -> void:
	_visuals.apply_walk_pose(0.4)
	_visuals.apply_look(CharacterLook.sanitize({"hair_style": "bald"}))

	assert_almost_eq(_visuals.get_node("Skeleton3D/Parts/ArmR").rotation.x, 0.0, 0.0001)
