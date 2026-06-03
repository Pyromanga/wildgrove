class_name ContextMenuVisuals
extends Node

## ContextMenuVisuals — baut das visuelle Kontext-Menü im HUD.
##
## FIX 1: "Identifier ContextMenuVisuals not declared" —
##   Der Fehler tritt auf wenn eine Klasse sich in _init() selbst per class_name
##   referenziert (z.B. als Typ-Annotation) BEVOR die Klasse vollständig geladen ist.
##   Lösung: Selbstreferenz im _init()-Parameter-Typ entfernt, plain Node-Typ genutzt.
##
## FIX 2: Kernel.builder → Services.builder (in ContextMenuController erledigt,
##   hier wird nur noch emit aufgerufen).

signal action_triggered(action: InteractableAction)

var _container: Control

# FIX: Parameter-Typ war ContextMenuVisuals (Selbstreferenz) → einfach weggelassen.
# _init() braucht keinen Typ-Hint auf sich selbst.
func _init(parent: HUD, actions: Array) -> void:
	add_to_group("context_menu")

	_container = Control.new()
	_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	var vbox := VBoxContainer.new()
	_container.add_child(vbox)

	for action in actions:
		if not action is InteractableAction:
			continue
		var btn := Button.new()
		btn.text = action.label
		btn.custom_minimum_size = Vector2(200, 55)
		# Capture action per Value damit die Lambda-Closure korrekt funktioniert
		var captured: InteractableAction = action
		btn.pressed.connect(func(): action_triggered.emit(captured))
		vbox.add_child(btn)

	parent.add_child(_container)

func destroy() -> void:
	if is_instance_valid(_container):
		_container.queue_free()
	queue_free()