extends InteractableObject

func _setup_visuals() -> void:
    var trunk = MeshInstance3D.new()
    trunk.mesh = CylinderMesh.new()
    add_child(trunk)

# _ready() entfällt hier komplett, da es in InteractableObject 
# definiert ist und dort den Builder aufruft!