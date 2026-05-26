extends Node3D

func _ready() -> void:
    var trunk = MeshInstance3D.new()
        trunk.mesh = CylinderMesh.new()
            add_child(trunk)
                
                    # KORREKTUR: Zugriff über Kernel.builder statt Builder
                        Kernel.builder.create(self)\
                                .set_label("Eiche fällen")\
                                        .set_duration(3.5)\
                                                .on_complete(_on_felled)\
                                                        .build()

                                                        func _on_felled() -> void:
                                                            # KORREKTUR: Zugriff über Kernel.events
                                                                Kernel.events.emit_xp("woodcutting", 25)
                                                                    queue_free()extendsextends