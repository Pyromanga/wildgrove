extends ServiceNode
class_name UIFactory

## UIFactory — Service für programmatische UI-Erstellung.
## Hängt UI-Elemente standardmäßig in einen dedizierten CanvasLayer.

const LOG_CAT := "UIFactory"

# Wir könnten hier eine Referenz auf den Haupt-UI-Container halten
var _ui_root: CanvasLayer

# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────

func init() -> void:
	# Die UIFactory braucht oft keine anderen Services, 
	# außer vielleicht einen 'SettingsService' für Skalierung.
	Logger.log_debug("Initialisiert.", LOG_CAT)

func on_ready() -> void:
	# Hier könnten wir prüfen, ob wir einen CanvasLayer im Spiel haben
	# oder uns einen eigenen erstellen.
	_ui_root = _find_or_create_canvas()
	Logger.log_info("UIFactory bereit. UI-Root: %s" % _ui_root.name, LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

func create_hud() -> HUD:
	var hud = HUD.new()
	_ui_root.add_child(hud)
	return hud

func show_popup(text: String) -> void:
	# Wenn du später einen NotificationService hast, 
	# kannst du hier einfach Services.notifications.push(text) aufrufen.
	Logger.log_debug("show_popup: '%s'" % text, LOG_CAT)
	# ... Logik zum Erstellen eines Labels oder Panels ...

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _find_or_create_canvas() -> CanvasLayer:
	# Sucht im Orchestrator (Parent) nach einem Canvas oder erstellt einen.
	var existing = get_parent().find_child("MainCanvas", false, false)
	if existing is CanvasLayer:
		return existing
		
	var canvas = CanvasLayer.new()
	canvas.name = "MainCanvas"
	get_parent().add_child(canvas)
	return canvas