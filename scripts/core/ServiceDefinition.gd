# res://scripts/core/ServiceDefinition.gd
class_name ServiceDefinition extends Resource
@export var name: String
@export var path: String
@export var deps: Array[String]

# res://scripts/core/BootstrapConfig.gd
class_name BootstrapConfig extends Resource
@export var services: Array[ServiceDefinition]