class_name SystemEvents extends BaseEvents

## SystemEvents.gd
## App-Lifecycle-Signale ohne eigene fachliche Domain (State, Settings, Boot).
##
## ADR-018: Save/Load, Session- und Netzwerk-Lifecycle wurden herausgelöst nach
## PersistenceEvents (scripts/persistence/), SessionEvents (scripts/session/)
## und NetworkingEvents (scripts/networking/) — für jeden gibt es längst einen
## eigenen Domain-Ordner, diese Signale lagen hier nur weil die Datei vor
## ADR-016 (Domain-First-Umbau) entstand und nicht mitgezogen wurde. Was hier
## bleibt (state_changed, setting_changed, boot_failed, services_initialized)
## ist tatsächlich domänenlos (App-Lifecycle) und gehört in den eventbus/-Ordner.

signal state_changed(state: int)
signal setting_changed(key: String, value: Variant)
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

func emit_services_initialized() -> void:
	_log_info("Systemdienste vollständig initialisiert.")
	services_initialized.emit()
