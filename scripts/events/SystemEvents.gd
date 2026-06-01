class_name SystemEvents extends BaseEvents

## SystemEvents.gd
## Alle systemrelevanten Signals (Save, Load, Settings, State).

signal state_changed(state: int)
signal setting_changed(key: String, value: Variant)
signal save_started()
signal save_completed(success: bool)
signal load_started()
signal load_completed(success: bool)
signal services_initialized() # <--- Neu!

func _init() -> void:
	super._init("Events/System")

func emit_state_changed(state: int) -> void:
	_log_info("GameState geändert → %d" % state)
	state_changed.emit(state)

func emit_setting_changed(key: String, value: Variant) -> void:
	_log("Setting geändert: '%s' = %s" % [key, str(value)])
	setting_changed.emit(key, value)

func emit_save_started() -> void:
	_log_info("Speichervorgang gestartet...")
	save_started.emit()

func emit_save_completed(success: bool) -> void:
	if success:
		_log_info("Speichervorgang erfolgreich.")
	else:
		_log_warn("Speichervorgang fehlgeschlagen!")
	save_completed.emit(success)

func emit_load_started() -> void:
	_log_info("Ladevorgang gestartet...")
	load_started.emit()

func emit_load_completed(success: bool) -> void:
	if success:
		_log_info("Ladevorgang erfolgreich.")
	else:
		_log_warn("Ladevorgang fehlgeschlagen!")
	load_completed.emit(success)
	
func emit_services_initialized() -> void:
    _log_info("Systemdienste vollständig initialisiert.")
    services_initialized.emit()