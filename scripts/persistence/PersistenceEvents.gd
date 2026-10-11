class_name PersistenceEvents extends BaseEvents

## PersistenceEvents — EventBus-Namespace für Save/Load-Signale.
##
## ADR-018: Aus SystemEvents herausgelöst. Save/Load ist eine eigenständige
## fachliche Domain mit eigenem Ordner (scripts/persistence/) — die Signale
## gehörten dort schon immer hin, lagen aber im domänenlosen eventbus/-Ordner,
## weil diese Datei vor ADR-016 (Domain-First-Umbau) entstand und beim Umbau
## nicht mitgezogen wurde.
##
## Einbinden in EventBus.gd:
##   var persistence: PersistenceEvents
##   # in _ready():
##   persistence = PersistenceEvents.new()
##
## Verwendung:
##   EventBus.persistence.save_completed.connect(_on_save_completed)
##   EventBus.persistence.emit_save_requested()

## Internes Notify: von SaveSystem.save_game() emittiert wenn Vorgang beginnt.
## NUR für UI-Feedback/Logging nutzen — NICHT um save_all() zu triggern!
signal save_started
## Externer Auslöser: von UI/Buttons emittiert um einen Speichervorgang anzufordern.
## GameSaveService lauscht hierauf und ruft save_all() auf.
signal save_requested
## Pre-Flush-Hook: von GameSaveService emittiert direkt BEVOR save_game() läuft.
signal save_pre_flush
signal save_completed(success: bool)
signal load_started
signal load_completed(success: bool)
## Emittiert von SaveSystem.delete_save_for() wenn ein Slot erfolgreich gelöscht wurde.
signal save_slot_deleted(player_id: String)

func _init() -> void:
	super._init("Events/Persistence")

func emit_save_started() -> void:
	_log_info("Speichervorgang gestartet...")
	save_started.emit()

func emit_save_pre_flush() -> void:
	_log_info("Pre-Flush: Services bereiten Save-Daten vor.")
	save_pre_flush.emit()

func emit_save_requested() -> void:
	_log_info("Speichervorgang angefordert (extern).")
	save_requested.emit()

func emit_save_completed(success: bool) -> void:
	if success:
		_log_info("Speichervorgang erfolgreich.")
	else:
		_log_warn("Speichervorgang fehlgeschlagen!")
	save_completed.emit(success)

func emit_save_slot_deleted(player_id: String) -> void:
	_log_info("Save-Slot gelöscht: '%s'" % player_id)
	save_slot_deleted.emit(player_id)

func emit_load_started() -> void:
	_log_info("Ladevorgang gestartet...")
	load_started.emit()

func emit_load_completed(success: bool) -> void:
	if success:
		_log_info("Ladevorgang erfolgreich.")
	else:
		_log_warn("Ladevorgang fehlgeschlagen!")
	load_completed.emit(success)
