class_name ServiceLoader extends RefCounted

# Eine Liste, zwei Zwecke: Reihenfolge für create, Namen für required-Check
const SERVICES: Array[Dictionary] = [
    { "name": "debug_service", "path": "res://scripts/services/DebugService.gd" },
    { "name": "debug_console", "path": "res://scripts/services/DebugConsole.gd" },
    { "name": "events",        "path": "res://scripts/services/GameEvents.gd" },
    { "name": "data",          "path": "res://scripts/services/DataService.gd" },
    { "name": "states",        "path": "res://scripts/services/StateService.gd" },
    { "name": "utils",         "path": "res://scripts/services/Utils.gd" },
    { "name": "builder",       "path": "res://scripts/services/InteractionBuilder.gd" },
    { "name": "ui_factory",    "path": "res://scripts/services/UIFactory.gd" },
    { "name": "factory3d",     "path": "res://scripts/services/Factory3D.gd" },
    { "name": "inventory",     "path": "res://scripts/services/InventorySystem.gd" },
    { "name": "skill_system",  "path": "res://scripts/services/SkillSystem.gd" },
]

func get_required_names() -> Array[String]:
    var names: Array[String] = []
    for s in SERVICES:
        names.append(s["name"])
    return names

func setup_services(parent: Node) -> void:
    for s in SERVICES:
        _create(s["name"], parent, s["path"])
    Logger.log_debug("Alle %d Services angefordert" % SERVICES.size(), "ServiceLoader")

func _create(service_name: String, parent: Node, path: String) -> void:
    var script = load(path)
    if not script:
        Logger.log_error("Script nicht gefunden: " + path, "ServiceLoader")
        return
    var node := Node.new()
    node.name = service_name
    node.set_script(script)
    parent.add_child(node)