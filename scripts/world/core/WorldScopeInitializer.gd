class_name WorldScopeInitializer extends Node

## WorldScopeInitializer — Sitzt in World.tscn als Child-Node.
##
## Einzige Verantwortung: signalisiert wenn der World-Root bereit ist.
## Kein AutoLoad-Zugriff. Kein EventBus. Kein Pull.
##
## CharacterScope connectet sich auf world_ready bevor World.tscn geladen wird.
## Wenn _ready() feuert ist der SceneTree bereit — world_ready.emit() pushed
## den Root nach oben. CharacterScope ruft daraufhin create_world_scope() auf.
##
## Push-Pattern: dieser Node pushed Existenz nach oben, niemand pollt ihn.

## Emittiert einmalig wenn dieser Node im SceneTree bereit ist.
## get_parent() ist zu diesem Zeitpunkt der World-Root (Node3D).
signal world_ready(world_root: Node3D)

func _ready() -> void:
	var root := get_parent()
	if not root is Node3D:
		push_error(
			"WorldScopeInitializer: Parent ist kein Node3D — in World.tscn direkt unter Root einsetzen."
		)
		return
	# BUG-FIX (grauer Bildschirm): _ready() eines Kind-Nodes feuert, WÄHREND
	# Godot den Eltern-Node (world_root) noch in den SceneTree einhängt — der
	# Engine-interne "Kinder werden aufgebaut"-Zustand ist noch aktiv.
	# Der synchrone world_ready-Handler (ServiceOrchestrator → BootPipeline →
	# WorldService.on_world_scene_ready) hängt selbst wieder Kinder unter
	# world_root (Terrain, ChunkManager, Entities, WaterBodies, Player) —
	# das schlägt mit "Parent node is busy setting up children" fehl und
	# die Welt bleibt leer (nur grauer Clear-Color-Viewport sichtbar).
	# Fix: Emission auf den nächsten Frame verschieben, wenn world_root
	# garantiert fertig eingehängt ist.
	call_deferred("_emit_world_ready", root as Node3D)

func _emit_world_ready(root: Node3D) -> void:
	world_ready.emit(root)
	## Nach emit ist dieser Node fertig. Er bleibt im SceneTree für Teardown-Signale
	## aber hat keine weitere aktive Rolle.
