extends ServiceNode
class_name UICanvasService

## UICanvasService — stellt den Root-CanvasLayer für das HUD bereit.
##
## Umbenannt von "UIFactory" — der alte Name suggerierte eine Factory für beliebige
## UI-Elemente, dabei ist die einzige echte Aufgabe: einen CanvasLayer-Root zu
## finden oder zu erstellen, in den HUDManager das HUD-Node einhängt.
##
## Entfernt: create_hud() — war toter Code; HUDManager erstellt HUD selbst in configure().
## Entfernt: show_popup() — war ein leerer Stub; Popups laufen über NotificationController.

const LOG_CAT := "UICanvas"

var _ui_root: CanvasLayer


# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────
func configure(_deps: Dictionary) -> void:
	Logger.log_debug("Konfiguriert.", LOG_CAT)


# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────
func on_ready() -> void:
	_ui_root = _find_or_create_canvas()
	Logger.log_info("UICanvasService bereit. UI-Root: %s" % _ui_root.name, LOG_CAT)


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


## Gibt den Root-CanvasLayer zurück. HUDManager nutzt ihn als Eltern-Node.
func get_canvas() -> CanvasLayer:
	if not _ui_root:
		_ui_root = _find_or_create_canvas()
	return _ui_root


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _find_or_create_canvas() -> CanvasLayer:
	var root_node = get_parent()
	var existing = root_node.find_child("MainCanvas", false, false)

	if existing is CanvasLayer:
		return existing

	var canvas := CanvasLayer.new()
	canvas.name = "MainCanvas"
	canvas.layer = 1
	root_node.add_child(canvas)

	Logger.log_debug("Neuen MainCanvas erstellt.", LOG_CAT)
	return canvas
