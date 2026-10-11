extends RefCounted
class_name DraggableToggleController

## DraggableToggleController — wiederverwendbare Drag-Logik für schwebende Toggle-Buttons
## (LOG-Button, ADMIN-Button, ...).
##
## BUGFIX (2026-09-27, "Admin-Button soll wie der Log-Button verschiebbar sein"): aus
## TerminalController EXTRAHIERT statt dupliziert — dort steckte exakt diese Logik schon,
## inklusive der hart erarbeiteten BUG-25-Fixes (siehe Kommentar unten zu Mouse/Touch-
## Doppel-Events). TerminalController delegiert jetzt hierher (siehe dortige Datei), statt
## die Logik zweimal zu pflegen. Einziger Unterschied zu vorher: statt eines hartcodierten
## `_logic.toggle()`-Aufrufs nimmt dieser Controller ein beliebiges `on_tap`-Callable entgegen
## — AdminPanelUI übergibt dafür einfach sein eigenes Sichtbarkeits-Toggle.
##
## Extends RefCounted (nicht Node) damit _init() Argumente annehmen kann.

var _on_tap: Callable

var _is_dragging     := false
var _drag_offset     := Vector2.ZERO
var _drag_start_pos  := Vector2.ZERO
const DRAG_THRESHOLD := 15.0

# BUG-25: project.godot hat pointing/emulate_touch_from_mouse UND
# pointing/emulate_mouse_from_touch aktiv — pro physischer Berührung kommen
# hier also ZWEI Events an (z.B. InputEventScreenDrag + die dazu emulierte
# InputEventMouseMotion). Seit handle_button_input() beide Familien
# gleichzeitig verarbeitet (vorher nur Maus), wurde die Drag-Bewegung
# doppelt angewendet → Button "hakelig", praktisch nicht draggbar. Fix:
# die Familie, die den Press ausgelöst hat, wird für die Dauer der Geste
# gesperrt; das jeweils andere (emulierte) Event wird ignoriert.
var _active_family := ""  # "" | "mouse" | "touch"

## on_tap: wird aufgerufen wenn der Button ohne nennenswerte Bewegung
## (< DRAG_THRESHOLD) losgelassen wurde — also ein "echter" Tap statt eines Drags.
func _init(on_tap: Callable) -> void:
	_on_tap = on_tap

## InputEventScreenTouch/-Drag haben nur 'position' (Viewport-lokal), kein
## 'global_position' — das existiert ausschließlich auf Maus-Events. Einheitlicher
## Zugriff über diesen Helper statt direktem .global_position auf beiden Event-Familien.
func _event_position(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return event.global_position
	return event.position

func handle_button_input(event: InputEvent, button: Button) -> void:
	var family := ""
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		family = "mouse"
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		family = "touch"
	else:
		return

	if event is InputEventMouseButton or event is InputEventScreenTouch:
		var pos := _event_position(event)
		if event.pressed:
			if _active_family != "":
				return  # bereits eine Geste der anderen (emulierten) Familie aktiv
			_active_family  = family
			_is_dragging    = true
			_drag_start_pos = pos
			_drag_offset    = button.global_position - pos
		else:
			if family != _active_family:
				return  # emuliertes Release der inaktiven Familie ignorieren
			_active_family = ""
			_is_dragging = false
			# Nur tappen wenn kaum bewegt (kein Drag)
			if pos.distance_to(_drag_start_pos) < DRAG_THRESHOLD:
				_on_tap.call()

	if (event is InputEventMouseMotion or event is InputEventScreenDrag) and _is_dragging:
		if family != _active_family:
			return  # emulierte Bewegung der inaktiven Familie ignorieren
		button.global_position = _event_position(event) + _drag_offset
