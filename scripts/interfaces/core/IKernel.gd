# res://scripts/interfaces/core/IKernel.gd
class_name IKernel extends Node

## Signale für die Registry-Überwachung
signal service_registered(service_name: String)
signal service_unregistered(service_name: String)

var shortcuts: Object 

## Registry API
func register_service(_service: Object) -> void: pass
func unregister_service(_service: Object) -> void: pass
func get_service(_service_name: String) -> Object: return null
func has_service(_service_name: String) -> bool: return false
func get_registered_names() -> Array[String]: return []

## Lifecycle
func bind_shortcuts() -> void: pass