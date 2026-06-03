extends ServiceNode
class_name UIFactory

## UIFactory — Service für programmatische UI-Erstellung.

const LOG_CAT := "UIFactory"

var _ui_root: CanvasLayer

func init() -> void:
	Logger.log_debug("Initialisiert.", LOG_CAT)

func on_ready() -> void:
	_ui_root = _find_or_create_canvas()
	Logger.log_info("UIFactory bereit. UI-Root: %s" % _ui_root.name, LOG_CAT)

func create_hud() -> HUD:
	var hud := HUD.new()
	_ui_root.add_child(hud)
	return hud

func show_popup(text: String) -> void:
	Logger.log_debug("show_popup: '%s'" % text, LOG_CAT)

func _find_or_create_canvas() -> CanvasLayer:
	var existing: Node = get_parent().find_child("MainCanvas", false, false)
	if existing is CanvasLayer:
		return existing
	var canvas := CanvasLayer.new()
	canvas.name = "MainCanvas"
	get_parent().add_child(canvas)
	return canvas