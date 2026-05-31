extends ServiceBase
class_name DebugService

func _ready() -> void:
    if Kernel.has_method("register_service"):
        Kernel.register_service("debug_service", self)
        
    Logger.log_debug("DebugService: 'Hallo, ich bin bereit!'", "DebugService")