class_name ServiceLoader extends RefCounted

# Wir übergeben die 'main_node', damit wir wissen, wo wir die Services dranhängen
func setup_services(main_node: Node) -> void:
    _create_service(main_node, "debug_service", "res://scripts/services/DebugService.gd")
    _create_service(main_node, "events", "res://scripts/services/GameEvents.gd")
    # Hier kannst du einfach weitere Zeilen hinzufügen, ohne die Main anzufassen!

func _create_service(parent: Node, service_name: String, path: String) -> void:
    var service_node = Node.new()
    service_node.name = service_name
    service_node.set_script(load(path))
    parent.add_child(service_node)