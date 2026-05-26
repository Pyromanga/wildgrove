extends Node3D

func _ready():
    var m = MeshInstance3D.new()
        m.mesh = BoxMesh.new()
            add_child(m)

                # KORREKTUR: Zugriff über Kernel.builder und Kernel.events
                    Kernel.builder.create(self)\
                            .set_label("Eisenerz abbauen")\
                                    .set_duration(4.0)\
                                            .on_complete(func(): 
                                                        Kernel.events.emit_xp("mining", 40)
                                                                    queue_free()
                                                                            ).build()extends