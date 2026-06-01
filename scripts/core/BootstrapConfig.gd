# res://scripts/core/BootstrapConfig.gd
class_name BootstrapConfig extends Resource

@export var services: Array[ServiceDefinition]

# Hilfsklasse für den Editor
class ServiceDefinition:
    @export var name: String
    @export var path: String
    @export var deps: Array[String]