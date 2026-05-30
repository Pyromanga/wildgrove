extends InteractableObject

func _init() -> void:
    label = "Eiche fällen"
    duration = 3.5
    xp_type = "woodcutting"
    xp_amount = 25

func _setup_visuals() -> void:
    # Hier nutzt du jetzt die Factory über den Kernel!
    Kernel.factory3d.create_simple_tree(self)