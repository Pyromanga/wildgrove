extends ServiceBase
class_name DebugService

func _ready() -> void:
    # ServiceBase macht die Arbeit: Registrierung + Logging
    super._ready()
    # Der Test-Ping
    Logger.log_debug("Ping-Pong-Service: 'Hallo, ich bin bereit!'", "DebugService")