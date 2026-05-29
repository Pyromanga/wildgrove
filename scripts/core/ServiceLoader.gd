class_name ServiceLoader extends RefCounted

func setup_services(main_node: Node) -> void:
    _create("debug_service",   main_node, "res://scripts/services/DebugService.gd")
    _create("debug_console",   main_node, "res://scripts/services/DebugConsole.gd")  # NEU
    _create("events",          main_node, "res://scripts/services/GameEvents.gd")
    _create("data",            main_node, "res://scripts/services/DataService.gd")
    _create("states",          main_node, "res://scripts/services/StateService.gd")
    _create("utils",           main_node, "res://scripts/services/Utils.gd")
    _create("builder",         main_node, "res://scripts/services/InteractionBuilder.gd")
    _create("ui_factory",      main_node, "res://scripts/services/UIFactory.gd")
    _create("factory3d",       main_node, "res://scripts/services/Factory3D.gd")
    _create("inventory",       main_node, "res://scripts/services/InventorySystem.gd")
    _create("skill_system",    main_node, "res://scripts/services/SkillSystem.gd")

func _create(service_name: String, parent: Node, path: String) -> void:
    var node := Node.new()
    node.name = service_name
    node.set_script(load(path))
    parent.add_child(node)