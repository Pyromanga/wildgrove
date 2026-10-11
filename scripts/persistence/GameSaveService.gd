extends Service
class_name GameSaveService

## GameSaveService — Koordinator für übergreifende Speicheroperationen.
##
## Verantwortung (klar abgegrenzt nach A-04-Fix):
##   - Lauscht auf save_requested (externer Auslöser von UI/Buttons)
##   - Emittiert save_pre_flush damit Services transiente Daten sichern können
##     (z.B. WorldService → Pets, ohne dass GameSaveService WorldService kennt)
##   - Delegiert den eigentlichen Schreibvorgang an SaveSystem
##   - Doppelaufruf-Schutz (_is_saving-Guard)
##
## Was GameSaveService NICHT tut:
##   - Kein direkter Zugriff auf andere Services via DI
##   - Kein Wissen über Pet-Daten, Spielstand-Inhalt oder Provider-Details
##   - Kein Schreiben auf Disk (delegiert an SaveSystem)
##
## Externe Auslöser:
##   EventBus.persistence.emit_save_requested()  ← von UI-Button oder Quicksave
##
## Internes Notify:
##   EventBus.persistence.save_pre_flush         ← WorldService lauscht hier (Pets)
##   EventBus.persistence.save_started           ← von SaveSystem, für UI-Feedback
##   EventBus.persistence.save_completed(bool)   ← von SaveSystem, für UI-Feedback

const LOG_CAT := "GameSave"

var _save_system: SaveSystem
var _is_saving:   bool = false
var _bus:         IEventBus

func configure(deps: ServiceDeps) -> void:
	_save_system = deps.require(ServiceKeys.SAVE_SYSTEM) as SaveSystem
	_bus          = deps.require(ServiceKeys.EVENT_BUS)    as IEventBus
	if not is_instance_valid(_save_system):
		AppLogger.log_error("SaveSystem-Dependency fehlt!", LOG_CAT)

func on_ready() -> void:
	_bus.persistence().save_requested.connect(_on_save_requested)
	AppLogger.log_info("GameSaveService bereit. Lauscht auf save_requested.", LOG_CAT)

func on_cleanup() -> void:
	if _bus.persistence().save_requested.is_connected(_on_save_requested):
		_bus.persistence().save_requested.disconnect(_on_save_requested)
	AppLogger.log_info("GameSaveService cleanup.", LOG_CAT)

## Vollständiger Speichervorgang über alle registrierten Provider.
## Gibt true zurück wenn erfolgreich.
func save_all() -> bool:
	if not is_instance_valid(_save_system):
		AppLogger.log_error("SaveSystem nicht verfügbar — Speichern abgebrochen!", LOG_CAT)
		return false

	if _is_saving:
		AppLogger.log_warn("save_all() bereits aktiv — doppelter Aufruf ignoriert.", LOG_CAT)
		return false

	_is_saving = true
	var t := AppLogger.log_begin("save_all()", LOG_CAT)

	# Pre-Flush: Services mit transienten SceneTree-Daten bereiten ihren State vor.
	# WorldService lauscht hier und sichert Pet-Positionen — GameSaveService
	# kennt WorldService nicht direkt (ADR-001 Schichttrennung).
	_bus.persistence().emit_save_pre_flush()

	var success := _save_system.save_game()
	AppLogger.log_end("save_all()", t, LOG_CAT)
	_is_saving = false

	if success:
		AppLogger.log_info("Speichervorgang erfolgreich.", LOG_CAT)
	else:
		AppLogger.log_error("Speichervorgang fehlgeschlagen!", LOG_CAT)

	return success

func _on_save_requested() -> void:
	AppLogger.log_info("save_requested empfangen — starte save_all().", LOG_CAT)
	save_all()
