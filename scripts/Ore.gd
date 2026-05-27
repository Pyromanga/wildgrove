extends InteractableObject

func _ready() -> void:
    # Variablen für das Erz setzen, bevor super()._ready() aufgerufen wird
    label = "Eisenerz abbauen"
    duration = 4.0
    xp_type = "mining"
    xp_amount = 40
    super._ready() # Ruft das _ready() aus InteractableObject auf

func _setup_visuals() -> void:
    var m := MeshInstance3D.new()
    m.mesh = BoxMesh.new()
    add_child(m)