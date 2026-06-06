extends CanvasLayer
class_name HUD

## HUD.gd — Root-CanvasLayer für alle in-game UI-Elemente.
##
## Wird von HUDManager.configure() als Instanz erstellt und in on_world_scene_ready()
## via attach_to_scene() in die Spielwelt eingehängt.
##
## LAYER-KONVENTION:
##   Layer 1 (Standard) — HUD, Joystick, Interaktions-Buttons
##   Layer 2            — Kontext-Menüs (über dem HUD)
##   Layer 10+          — Debug-Overlays (SimpleTerminal)
##
## WICHTIG: layer explizit setzen — Godot-Default ist 1, aber wir dokumentieren
## es bewusst damit zukünftige Entwickler die Hierarchie sofort verstehen.

func _ready() -> void:
	layer = 1
	Logger.log_debug(
		"HUD CanvasLayer bereit. Layer: %d, Name: '%s'." % [layer, name], "HUD"
	)
