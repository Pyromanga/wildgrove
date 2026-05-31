extends ServiceBase
class_name DebugService

func _ready() -> void:
	# Ruft ServiceBase._ready() auf -> Erledigt die Registrierung automatisch!
	super()
	
	# Da ServiceBase bereits ein "registriert" Log ausgibt, 
	# kannst du hier zusätzliche Infos loggen oder es ganz weglassen.
	Logger.log_debug("DebugService bereit.", "DebugService")