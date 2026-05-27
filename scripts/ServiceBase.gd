# ServiceBase.gd
extends Node
class_name ServiceBase

signal service_ready(service_name: String)

func _ready() -> void:
    Kernel.register_service(self)
    # Sobald der Node im Baum ist, feuern wir ein Signal
    service_ready.emit(self.name.to_lower())