extends "res://addons/gut/test.gd"

var kernel = null

func before_all():
    var kernel_scene = load("res://scripts/Kernel.gd")
    kernel = kernel_scene.new()
    kernel.name = "Kernel"
    add_child(kernel)
    # Warte auf das neue Signal, das wir eingebaut haben
    await kernel.services_ready

func after_all():
    if is_instance_valid(kernel):
        kernel.queue_free()