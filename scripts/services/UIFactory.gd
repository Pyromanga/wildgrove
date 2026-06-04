extends ServiceNode
class_name UIFactory

## UIFactory — Service für programmatische UI-Erstellung.
## Zuständigkeit: Erstellung und Verwaltung der Canvas-Layer und Basis-UI-Elemente.

const LOG_CAT := "UIFactory"

var _ui_root: CanvasLayer


# ─────────────────────────────────────────────
# Phase 4: Configure
# ─────────────────────────────────────────────
func configure(_deps: Dictionary) -> void:
	# Die UIFactory ist meist autark, könnte aber hier Theme-Daten
	# aus dem DataService erhalten.
	Logger.log_debug("Konfiguriert.", LOG_CAT)


# ─────────────────────────────────────────────
# Phase 5: Activate
# ─────────────────────────────────────────────
func on_ready() -> void:
	# Wir suchen oder erstellen den Root-Canvas im Tree
	_ui_root = _find_or_create_canvas()
	Logger.log_info("UIFactory bereit. UI-Root: %s" % _ui_root.name, LOG_CAT)


# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


## Erstellt eine HUD-Instanz und hängt sie in den MainCanvas.
func create_hud() -> HUD:
	if not _ui_root:
		_ui_root = _find_or_create_canvas()

	var hud := HUD.new()
	hud.name = "GameHUD"
	_ui_root.add_child(hud)
	Logger.log_debug("HUD erstellt und an Canvas gebunden.", LOG_CAT)
	return hud


## Einfacher Popup-Helper (Enterprise-Erweiterung: Rückgabe des Popups für Callbacks)
func show_popup(text: String) -> void:
	Logger.log_info("Popup-Anfrage: '%s'" % text, LOG_CAT)
	# Hier würde später die Instanziierung einer Popup-Scene erfolgen.


# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────


func _find_or_create_canvas() -> CanvasLayer:
	# Wir suchen im Orchestrator-Parent (meistens die Main Scene)
	var root_node = get_parent()
	var existing = root_node.find_child("MainCanvas", false, false)

	if existing is CanvasLayer:
		return existing

	# Falls nicht vorhanden: Sauber neu erstellen
	var canvas := CanvasLayer.new()
	canvas.name = "MainCanvas"
	canvas.layer = 1  # Standard Game UI Layer
	root_node.add_child(canvas)

	Logger.log_debug("Neuen MainCanvas erstellt.", LOG_CAT)
	return canvas
