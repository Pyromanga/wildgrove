extends Node
class_name ServiceBase

## ServiceBase.gd
## Basisklasse für alle Services.
## Drei-Phasen Lifecycle: register → init → on_ready

func _ready() -> void:
	Logger.log_debug("_ready() aufgerufen.", _log_cat())
	
	if not Kernel:
		var msg := "Kernel-Autoload nicht gefunden! Autoload-Reihenfolge prüfen."
		Logger.log_error(msg, _log_cat())
		push_error("ServiceBase [%s]: %s" % [name, msg])
		return
	
	Logger.log_debug("Registriere beim Kernel...", _log_cat())
	Kernel.register_service(self)
	Logger.log_debug("Erfolgreich registriert.", _log_cat())

func _exit_tree() -> void:
	Logger.log_debug("_exit_tree() aufgerufen — melde beim Kernel ab.", _log_cat())
	
	if not Kernel:
		Logger.log_warn("Kernel nicht verfügbar beim Abmelden.", _log_cat())
		return
	
	Kernel.unregister_service(self)
	Logger.log_debug("Erfolgreich abgemeldet.", _log_cat())

## Phase 2: Abhängigkeiten auflösen, Daten laden.
## Wird vom ServiceLoader NACH allen _ready()-Calls aufgerufen.
## Überschreiben und super.init() am Anfang aufrufen.
func init() -> void:
	Logger.log_debug("init() — Basisimplementierung (kein Override).", _log_cat())

## Phase 3: Post-Init. Alle Services haben init() abgeschlossen.
## Sicher für Signal-Connections zwischen Services.
## Überschreiben und super.on_ready() am Anfang aufrufen.
func on_ready() -> void:
	Logger.log_debug("on_ready() — Basisimplementierung (kein Override).", _log_cat())

## Hilfsfunktion: Log-Kategorie immer "<ClassName>/Service"
func _log_cat() -> String:
	return "%s/Service" % name