class_name GameConfig extends RefCounted

var required_services: Array[String]

func _init(services: Array[String] = []) -> void:
    required_services = services