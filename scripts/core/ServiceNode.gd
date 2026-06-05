# res://scripts/core/ServiceNode.gd
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
##   init()       — Phase 4: Abhängigkeiten auflösen (Services.xyz lesen)
##   on_ready()   — Phase 5: Cross-Service-Setup, Signals connecten
##   on_cleanup() — Phase 7: Teardown-Logik

# ─────────────────────────────────────────────
# Lifecycle-Interface (von Pipeline aufgerufen)
# ─────────────────────────────────────────────


func init() -> void:
	pass


func on_ready() -> void:
	pass


func on_cleanup() -> void:
	pass
