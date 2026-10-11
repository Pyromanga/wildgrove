# res://tests/unit/test_interaction_target_picker.gd
extends GutTest

## Tests für die Trefferermittlung des InteractionTargetPicker (Tap → gemeintes Objekt) und
## die Tap-Deduplizierung in TouchInput. Die Physik-Verdeckung selbst (Terrain) prüft man im
## Spiel; hier wird die reine Auswahl-Logik über pick_from_ray() getestet.

func _make_box(node_name: String, pos: Vector3, size: Vector3 = Vector3(1, 2, 1)) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	add_child_autofree(root)
	root.global_position = pos
	root.add_to_group("interactable")
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	root.add_child(mi)
	return root

func test_picks_object_hit_by_ray() -> void:
	var tree := _make_box("Tree", Vector3(0, 1, 0))
	var hit := InteractionTargetPicker.pick_from_ray([tree], Vector3(0, 1, 10), Vector3(0, 0, -1), 60.0)
	assert_eq(hit, tree)

func test_picks_nearest_of_two_along_ray() -> void:
	var near := _make_box("Near", Vector3(0, 1, 0))
	var far := _make_box("Far", Vector3(0, 1, -5))
	var hit := InteractionTargetPicker.pick_from_ray([far, near], Vector3(0, 1, 10), Vector3(0, 0, -1), 60.0)
	assert_eq(hit, near)

func test_ray_beside_object_misses() -> void:
	var tree := _make_box("Tree", Vector3(0, 1, 0))
	var hit := InteractionTargetPicker.pick_from_ray([tree], Vector3(5, 1, 10), Vector3(0, 0, -1), 60.0)
	assert_null(hit)

func test_object_behind_solid_hit_is_occluded() -> void:
	var tree := _make_box("Tree", Vector3(0, 1, 0))
	# Fester Treffer (Hügel) nach 3 m — der Baum liegt 10 m entfernt dahinter.
	var hit := InteractionTargetPicker.pick_from_ray([tree], Vector3(0, 1, 10), Vector3(0, 0, -1), 3.0)
	assert_null(hit)

func test_excluded_node_is_never_picked() -> void:
	var me := _make_box("Me", Vector3(0, 1, 0))
	var hit := InteractionTargetPicker.pick_from_ray([me], Vector3(0, 1, 10), Vector3(0, 0, -1), 60.0, me)
	assert_null(hit)

func test_hidden_node_is_not_pickable() -> void:
	var tree := _make_box("Tree", Vector3(0, 1, 0))
	tree.visible = false
	var hit := InteractionTargetPicker.pick_from_ray([tree], Vector3(0, 1, 10), Vector3(0, 0, -1), 60.0)
	assert_null(hit)

func test_node_without_mesh_is_not_pickable() -> void:
	var empty := Node3D.new()
	add_child_autofree(empty)
	empty.add_to_group("interactable")
	var hit := InteractionTargetPicker.pick_from_ray([empty], Vector3(0, 1, 10), Vector3(0, 0, -1), 60.0)
	assert_null(hit)

func test_aabb_ignores_outline_clones() -> void:
	var tree := _make_box("Tree", Vector3.ZERO)
	var before := InteractionTargetPicker.compute_global_aabb(tree)
	var clone := MeshInstance3D.new()
	clone.name = "__outline__Tree"
	var big := BoxMesh.new()
	big.size = Vector3(20, 20, 20)
	clone.mesh = big
	tree.get_child(0).add_child(clone)
	var after := InteractionTargetPicker.compute_global_aabb(tree)
	assert_eq(after.size, before.size, "Umrandungs-Klone dürfen die Trefferbox nicht vergrößern.")

func test_aabb_merges_all_meshes() -> void:
	var tree := _make_box("Tree", Vector3.ZERO)
	var crown := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)
	crown.mesh = mesh
	tree.add_child(crown)
	crown.position = Vector3(0, 3, 0)
	var box := InteractionTargetPicker.compute_global_aabb(tree)
	assert_almost_eq(box.end.y, 3.5, 0.001)
	assert_almost_eq(box.position.y, -1.0, 0.001)

# ── TouchInput: Doppel-Tap-Schutz ───────────────

func test_emulated_mouse_click_is_redundant_for_tap_detection() -> void:
	var input := TouchInput.new()
	autofree(input)
	var mb := InputEventMouseButton.new()
	mb.device = InputEvent.DEVICE_ID_EMULATION
	mb.button_index = MOUSE_BUTTON_LEFT
	assert_true(input._mouse_tap_is_redundant(mb),
		"Ein aus Touch emulierter Mausklick darf keinen zweiten Tap auslösen.")
