class_name Service extends RefCounted

## Service — Basisklasse für Pure Services (kein Node-Overhead).
## Geeignet für: Daten-Services, Config-Loader, Calculator, Repository-Pattern etc.
## Wird von ServiceFactory instanziiert und direkt im Kernel registriert.
## service_name MUSS gesetzt sein bevor register_service() aufgerufen wird.

## HINWEIS: Heißt bewusst service_name, nicht name.
## "name" ist eine reservierte Property auf Node — Kollision vermeiden!
var service_name: String = ""

# ─────────────────────────────────────────────
# Lifecycle (von ServiceLoader aufgerufen)
# ─────────────────────────────────────────────

## Phase 2: Abhängigkeiten auflösen, interne Initialisierung.
## Hier: Kernel.get_service() für Dependencies aufrufen.
func init() -> void:
	pass

## Phase 3: Nach allen init()-Calls. Für Cross-Service-Kommunikation.
## Hier: Signals connecten, Events feuern etc.
func on_ready() -> void:
	pass

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

## Convenience-Wrapper damit Subklassen nicht immer LOG_CAT definieren müssen.
func _log_cat() -> String:
	return service_name if not service_name.is_empty() else get_class()