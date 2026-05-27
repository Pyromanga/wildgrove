class_name ServiceLoader extends RefCounted

func setup_services(main_node: Node) -> void:
    # Pfade anpassen, damit sie zu deiner Ordnerstruktur passen
    _create_service(main_node, "debug_service", "res://scripts/DebugService.gd")
    _create_service(main_node, "events", "res://scripts/services/GameEvents.gd")

func _create_service(parent: Node, service_name: String, path: String) -> void:
    var service_node = Node.new()
    service_node.name = service_name
    service_node.set_script(load(path))
    parent.add_child(service_node)