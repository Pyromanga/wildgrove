class_name GameSaveService extends ServiceNode

## GameSaveService — Koordinator für übergreifende Speicheroperationen.
##
## KEIN Data-Provider: registriert sich NICHT beim SaveSystem,
## da get_save_key() / get_save_data() hier nicht sinnvoll sind.
## Für den eigentlichen Datenaustausch sind die einzelnen Services
## (WorldService, InventorySystem, …) direkt beim SaveSystem registriert.

const LOG_CAT := "GameSave"

var _save_system: SaveSystem


func configure(deps: Dictionary) -> void:
	_save_system = deps.get("savesystem") as SaveSystem
	# HINWEIS: Kein register_save_provider(self) — GameSaveService liefert
	# keine eigenen Speicherdaten, sondern delegiert an SaveSystem.
	Logger.log_debug("GameSaveService konfiguriert.", LOG_CAT)


## Löst einen vollständigen Speichervorgang über alle registrierten Provider aus.
func save_all() -> bool:
	if not is_instance_valid(_save_system):
		Logger.log_error("SaveSystem nicht verfügbar!", LOG_CAT)
		return false
	return _save_system.save_game()
