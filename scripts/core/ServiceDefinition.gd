class_name ServiceDefinition extends Resource

@export var service_name: String = ""
@export_file("*.gd", "*.tscn") var path: String = ""
@export var deps: Array[String] = []
@export_file("*.tres", "*.res") var required_data_files: Array[String] = []
@export var interface_type: String = ""
