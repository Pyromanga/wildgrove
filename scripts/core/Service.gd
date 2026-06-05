# res://scripts/core/Service.gd
class_name Service extends RefCounted

## Service — Basisklasse für Pure Services (kein Node-Overhead).
##
## Geeignet für: Daten-Services, Config-Loader, Repositories, Calculator etc.
## Wird von ServiceFactory instanziiert und direkt in der ServiceRegistry registriert.
##
## service_name MUSS gesetzt sein bevor registry.register() aufgerufen wird.
## ServiceFactory setzt ihn automatisch aus der ServiceDefinition.
##
## HINWEIS: Heißt bewusst service_name, nicht name.
## "name" ist auf Node reserviert — Kollision vermeiden.

var service_name: String = ""

# ─────────────────────────────────────────────
# Lifecycle (von Pipeline aufgerufen)
# ─────────────────────────────────────────────


## Phase 4: Abhängigkeiten auflösen, interne Initialisierung.
## Hier: Services.xyz für Abhängigkeiten abrufen.
## NICHT Services.xyz verwenden um Signale zu connecten — das ist Phase 5.
func init() -> void:
	pass


## Phase 5: Nach allen init()-Calls. Cross-Service-Kommunikation.
## Hier: EventBus.*.signal.connect(...), erste Daten laden etc.
func on_ready() -> void:
	pass


## Phase 7: Teardown. Ressourcen freigeben, Verbindungen trennen.
## Wird in umgekehrter Boot-Reihenfolge aufgerufen.
func on_cleanup() -> void:
	pass


# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────


## Convenience für Logging: gibt service_name oder Klassenname zurück.
func _log_cat() -> String:
	return service_name if not service_name.is_empty() else get_class()
