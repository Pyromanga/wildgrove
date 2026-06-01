class_name ServiceNode extends Node

## ServiceNode — Basisklasse für Node-basierte Services.
## Registriert sich automatisch im Kernel wenn der Node in den Baum kommt.
## Subklassen können entweder:
##   A) service_logic setzen (Composition — Service-Logik in separatem Service-Objekt)
##   B) init() und on_ready() direkt überschreiben (einfacherer Fall)

## Optional: Pure Service-Objekt das die eigentliche Logik enthält.
## Wenn gesetzt, werden init() und on_ready() dorthin delegiert.
## Wenn nicht gesetzt, müssen Subklassen die Methoden direkt überschreiben.
var service_logic: Service = null

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func _ready() -> void:
	## Name muss gesetzt sein bevor _ready läuft.
	## ServiceFactory setzt node.name — das ist der Registry-Schlüssel.
	assert(not name.is_empty(), "ServiceNode braucht einen Namen vor _ready()!")
	Kernel.register_service(self)
	Logger.log_debug("ServiceNode '%s' im Baum und registriert." % name, name)

func _exit_tree() -> void:
	Kernel.unregister_service(self)

# ─────────────────────────────────────────────
# Service-Interface (von ServiceLoader aufgerufen)
# ─────────────────────────────────────────────

## Phase 2: Abhängigkeiten auflösen.
## Subklassen rufen super.init() auf wenn sie service_logic nutzen.
func init() -> void:
	if service_logic:
		service_logic.init()

## Phase 3: Cross-Service-Setup, Signals connecten.
## Subklassen rufen super.on_ready() auf wenn sie service_logic nutzen.
func on_ready() -> void:
	if service_logic:
		service_logic.on_ready()