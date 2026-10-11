# res://scripts/platform/ServiceNode.gd
class_name ServiceNode extends Node

## ServiceNode — Basisklasse für Node-basierte Services.
##
## Node-Services erben hiervon wenn sie im SceneTree leben müssen
## (z.B. weil sie _process, _physics_process oder Signals auf Node-Ebene brauchen).
##
## Registrierung übernimmt AUSSCHLIESSLICH die ServiceFactory — VOR add_child().
## Dieser Node sucht keinen Orchestrator, hält keine Registry-Referenz,
## und macht in _ready() gar nichts Infrastruktur-bezogenes.
##
## Lifecycle-Methoden (von ServiceInitializer / ServiceActivator aufgerufen):
##   init()       — Phase 4: Abhängigkeiten auflösen (via ServiceDeps / configure())
##   on_ready()   — Phase 5: Cross-Service-Setup, Signals connecten
##   on_cleanup() — Phase 7: Teardown-Logik

## service_name MUSS gesetzt sein bevor registry.register() aufgerufen wird.
## ServiceFactory setzt ihn automatisch aus der ServiceDefinition (siehe Service.gd).
var service_name: String = ""

# ─────────────────────────────────────────────
# Lifecycle-Interface (von Pipeline aufgerufen)
# ─────────────────────────────────────────────

## Phase 4: Dependency Injection. deps enthält alle deklarierten Service-Abhängigkeiten.
## NICHT configure() hier verwenden — Abhängigkeiten noch nicht aufgelöst.
func configure(_deps: ServiceDeps) -> void:
	pass

func on_ready() -> void:
	pass

func on_cleanup() -> void:
	pass
