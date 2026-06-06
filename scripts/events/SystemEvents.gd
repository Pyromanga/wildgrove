class_name SystemEvents extends BaseEvents

## SystemEvents.gd
## Alle systemrelevanten Signals (Save, Load, Settings, State).

signal state_changed(state: int)
signal setting_changed(key: String, value: Variant)
## Internes Notify: von SaveSystem.save_game() emittiert wenn Vorgang beginnt.
## NUR für UI-Feedback/Logging nutzen — NICHT um save_all() zu triggern!
signal save_started
## Externer Auslöser: von UI/Buttons emittiert um einen Speichervorgang anzufordern.
## GameSaveService lauscht hierauf und ruft save_all() auf.
signal save_requested
signal save_completed(success: bool)
signal load_started
signal load_completed(success: bool)
signal services_initialized
signal boot_failed(phase: String, reason: String)


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


func emit_save_requested() -> void:
	_log_info("Speichervorgang angefordert (extern).")
	save_requested.emit()


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
