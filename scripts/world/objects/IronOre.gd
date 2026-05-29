extends InteractableObject

func _init() -> void:
    label = "Eisenerz abbauen"
    duration = 4.0
    xp_type = "mining"
    xp_amount = 40

func _setup_visuals() -> void:
    var m := MeshInstance3D.new()
    m.mesh = BoxMesh.new()
    add_child(m)