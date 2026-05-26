extends Node3D

func _ready() -> void:
    # 1. Aussehen (Stamm)
    var trunk = MeshInstance3D.new()
    trunk.mesh = CylinderMesh.new()
    add_child(trunk)
    
    # 2. Verhalten mit dem Kernel-Builder 'bestellen'
    Kernel.builder.create(self)\
        .set_label("Eiche fällen")\
        .set_duration(3.5)\
        .on_complete(_on_felled)\
        .build()

func _on_felled() -> void:
    # 3. XP-Belohnung über den Kernel-Event-Service
    Kernel.events.emit_xp("woodcutting", 25)
    queue_free() # Baum nach dem Fällen entfernen