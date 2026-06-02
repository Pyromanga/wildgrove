extends ServiceNode
class_name UIFactory

## UIFactory — Service für programmatische UI-Erstellung.
## Die statischen Helper-Methoden sind in UIUtils (keine ServiceNode nötig).
## Wird langfristig durch das Component-System abgelöst.

const LOG_CAT := "UIFactory"

func _ready() -> void:
	super._ready()

func init() -> void:
	super.init()

func on_ready() -> void:
	super.on_ready()
	Logger.log_info("UIFactory bereit.", LOG_CAT)

func create_hud() -> HUD:
	return HUD.new()

func show_popup(text: String) -> void:
	# Delegiert an NotificationController wenn vorhanden
	# Fallback: direktes Label auf dem Root-Canvas
	Logger.log_debug("show_popup: '%s'" % text, LOG_CAT)