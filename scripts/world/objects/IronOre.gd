extends InteractableObject

func _setup_visuals() -> void:
    var m   := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(0.8, 0.8, 0.8)
    m.mesh   = box
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.6, 0.5, 0.4)
    m.material_override = mat
    add_child(m)

func _register_actions() -> void:
    default_action_id = "mine_iron"

    var action         := InteractableAction.new("mine_iron", "Eisenerz abbauen")
    action.duration    = 4.0
    action.xp_type     = "mining"
    action.xp_amount   = 40
    action.drops       = { "iron_ore": 1 }
    actions.append(action)

func _on_action_finished(action: InteractableAction) -> void:
    if action.id == "mine_iron":
        queue_free()