extends "res://addons/gut/test.gd"

var kernel = null

func before_all():
    # Wir laden den Kernel manuell, falls er noch nicht im Tree ist
    var kernel_scene = load("res://scripts/Kernel.gd")
    kernel = kernel_scene.new()
    add_child(kernel)
    # Kurz warten, damit _ready() durchlaufen kann
    await get_tree().process_frame

func after_each():
    for child in get_children():
        child.queue_free()