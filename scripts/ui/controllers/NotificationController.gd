# scripts/ui/controllers/notification_controller.gd
class_name NotificationController

var _visuals: NotificationVisuals
var _ctx: IUIContext

## BUGFIX (2026-09-20, "Popups erscheinen mehrfach nach Welt-Reload"): siehe
## identischer Kommentar in InventoryUIController._is_setup. NotificationController
## hat ebenfalls kein `extends Node` (reines RefCounted) — `show` ist zwar eine
## direkt gebundene Methode statt einer Lambda, aber die Signalverbindung auf
## dem langlebigen EventBus hält trotzdem eine harte Referenz auf `self` und
## verhindert damit, dass dieser Controller je freigegeben wird. Jeder
## HUD-Rebuild (world_scene_ready) fügt einen weiteren dauerhaft lauschenden
## Zombie hinzu → derselbe Text wird N-fach angezeigt/geloggt, N = Anzahl der
## bisherigen HUD-Rebuilds. Fix: disconnect in teardown(), von HUDManager vor
## dem Verwerfen des alten Controllers aufgerufen.
var _is_setup: bool = false

func setup(visuals: NotificationVisuals, ctx: IUIContext) -> void:
	if _is_setup:
		AppLogger.log_warn(
			"setup() erneut aufgerufen — vorherige Verbindung wird zuerst getrennt (teardown()).",
			"UI/Notification"
		)
		teardown()
	_visuals = visuals
	_ctx = ctx
	_ctx.bus().ui().notification_requested.connect(show)
	# War vorher eine Sonderbehandlung direkt in HUDManager (dort auch schon
	# disconnectet, aber eben NUR dieses eine Signal, nicht notification_requested
	# oben — daher der halbe Fix vor diesem Bugfix). Gehört inhaltlich hierher:
	# "worüber zeigt NotificationController Popups an" ist Sache dieses
	# Controllers, nicht von HUDManager.
	_ctx.bus().world().interaction_reward_text.connect(show)
	_is_setup = true

## MUSS von HUDManager vor dem Verwerfen dieses Controllers aufgerufen werden
## (siehe HUDManager._on_world_scene_ready()) — sonst bleibt dieser Controller
## als Zombie-Listener am Leben (siehe Klassenkommentar zu _is_setup oben).
func teardown() -> void:
	if is_instance_valid(_ctx) and is_instance_valid(_ctx.bus()):
		if _ctx.bus().ui().notification_requested.is_connected(show):
			_ctx.bus().ui().notification_requested.disconnect(show)
		if _ctx.bus().world().interaction_reward_text.is_connected(show):
			_ctx.bus().world().interaction_reward_text.disconnect(show)
	_is_setup = false

func show(text: String) -> void:
	_visuals.show_popup(text)
	AppLogger.log_debug("Popup angezeigt: " + text, "UI/Notification")
