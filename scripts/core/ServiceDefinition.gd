class_name ServiceDefinition extends Resource

@export var service_name: String = ""
@export_file("*.gd", "*.tscn") var path: String = ""
@export var deps: Array[String] = []
@export var is_node_service: bool = true