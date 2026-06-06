extends ServiceNode
class_name GameSaveService

## GameSaveService — Koordinator für übergreifende Speicheroperationen.
##
## BUG-FIX (Session 4):
##   VORHER: _on_save_requested() lauschte auf save_started (internes Signal von
##           SaveSystem) und tat dann nichts — "kein double trigger"-Guard der
##           nie save_all() aufrief. Externe Saves via EventBus funktionierten nicht.
##   NACHHER: Neues Signal save_requested in SystemEvents für externe Auslöser.
##            save_started bleibt internes Notify von SaveSystem (nur Logging).
##
## Externe Auslöser (UI-Button, Quicksave):
##   EventBus.system.emit_save_requested()  ← löst save_all() aus
##
## Internes Notify (nur lesend):
##   EventBus.system.save_started           ← von SaveSystem, für UI-Feedback

const LOG_CAT := "GameSave"

var _save_system: SaveSystem
var _is_saving: bool = false


func configure(deps: Dictionary) -> void:
	_save_system = deps.get("savesystem") as SaveSystem
	if not is_instance_valid(_save_system):
		Logger.log_error("SaveSystem-Dependency fehlt!", LOG_CAT)


func on_ready() -> void:
	EventBus.system.save_requested.connect(_on_save_requested)
	Logger.log_info("GameSaveService bereit. Lauscht auf save_requested.", LOG_CAT)


## Vollständiger Speichervorgang über alle registrierten Provider.
## Gibt true zurück wenn erfolgreich.
func save_all() -> bool:
	if not is_instance_valid(_save_system):
		Logger.log_error("SaveSystem nicht verfügbar — Speichern abgebrochen!", LOG_CAT)
		return false

	if _is_saving:
		Logger.log_warn("save_all() bereits aktiv — doppelter Aufruf ignoriert.", LOG_CAT)
		return false

	_is_saving = true
	var t := Logger.log_begin("save_all()", LOG_CAT)
	var success := _save_system.save_game()
	Logger.log_end("save_all()", t, LOG_CAT)
	_is_saving = false

	if success:
		Logger.log_info("Speichervorgang erfolgreich.", LOG_CAT)
	else:
		Logger.log_error("Speichervorgang fehlgeschlagen!", LOG_CAT)

	return success


func _on_save_requested() -> void:
	Logger.log_info("save_requested empfangen — starte save_all().", LOG_CAT)
	save_all()
