# res://scripts/core/ServiceNode.gd
class_name ServiceNode extends Node

# Wir delegieren das Interface
var service_logic: Service

func _ready() -> void:
    # Registrierung im Kernel bleibt gleich
    Kernel.register_service(self)

func init() -> void:
    if service_logic: service_logic.init()
    
func on_ready() -> void:
    if service_logic: service_logic.on_ready()