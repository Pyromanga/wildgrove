class_name UIEvents extends BaseEvents

## UIEvents.gd
## UI-spezifische Signale.
## Zentraler Hub für Layout-Änderungen und UI-Zustände.

signal layout_requested(state: String)
signal menu_toggled(menu_name: String, is_visible: bool)
signal overlay_changed(overlay_type: String, active: bool)

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