# res://scripts/core/ServiceFactory.gd
class_name ServiceFactory extends RefCounted

const LOG_CAT := "ServiceFactory"

func create_service(service_name: String, path: String, parent: Node) -> Node:
    var script = load(path)
    if not script:
        Logger.log_error("Script nicht gefunden: " + path, LOG_CAT)
        return null
    
    var node := Node.new()
    node.name = service_name
    node.set_script(script)
    parent.add_child(node)
    
    Logger.log_debug("Service '%s' instanziiert." % service_name, LOG_CAT)
    return node