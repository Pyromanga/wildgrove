class_name UIEvents extends BaseEvents

## UIEvents.gd
## UI-spezifische Signale.
##
## request_context_menu — neu; wird von ContextButtonController gefeuert und
## von ContextMenuController empfangen. Vorher fehlte die Deklaration hier,
## was zur Laufzeit zu einem "Signal not found"-Fehler geführt hätte.

signal layout_requested(state: String)
signal menu_toggled(menu_name: String, is_visible: bool)
signal overlay_changed(overlay_type: String, active: bool)

signal joystick_moved(origin: Vector2, offset: Vector2)
signal joystick_toggled(is_active: bool, origin: Vector2)

## Wird von ContextButtonController gesendet, wenn der Spieler den Kontext-Button drückt.
## ContextMenuController empfängt es und öffnet das Menü mit den verfügbaren Aktionen.
signal request_context_menu


func _init() -> void:
	super._init("Events/UI")


# --- Logik-Emitter ---


func emit_layout_requested(state: String) -> void:
	_log("Layout Änderung angefordert: %s" % state)
	layout_requested.emit(state)


func emit_menu_toggled(menu_name: String, is_visible: bool) -> void:
	_log("Menü '%s' sichtbar: %s" % [menu_name, is_visible])
	menu_toggled.emit(menu_name, is_visible)


func emit_overlay_changed(overlay_type: String, active: bool) -> void:
	_log("Overlay '%s' Status: %s" % [overlay_type, active])
	overlay_changed.emit(overlay_type, active)


func emit_joystick_toggled(is_active: bool, origin: Vector2 = Vector2.ZERO) -> void:
	_log("Joystick aktiv: %s" % is_active)
	joystick_toggled.emit(is_active, origin)


func emit_joystick_moved(origin: Vector2, offset: Vector2) -> void:
	joystick_moved.emit(origin, offset)


func emit_request_context_menu() -> void:
	_log("Kontext-Menü angefordert.")
	request_context_menu.emit()
