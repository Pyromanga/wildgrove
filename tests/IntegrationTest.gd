extends "res://addons/gut/test.gd"

var kernel = null

func before_all():
    var kernel_scene = load("res://scripts/Kernel.gd")
    kernel = kernel_scene.new()
    kernel.name = "Kernel"
    add_child(kernel)
    # Warte auf das neue Signal, das wir eingebaut haben
    await kernel.services_ready

func before_each():
    # Warte kurz, bis der Kernel fertig ist, falls er gerade erst bootet
    if not Kernel._is_initialized:
        await Kernel.services_ready
        
func after_all():
    if is_instance_valid(kernel):
        kernel.queue_free()

# KEIN after_each, das Kinder löscht, wenn der Kernel darin liegt!