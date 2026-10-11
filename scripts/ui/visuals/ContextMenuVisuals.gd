class_name ContextMenuVisuals
extends Node

## ContextMenuVisuals — baut das visuelle Kontext-Menü im HUD.
##
## FIX: extends Node statt nur RefCounted-Pattern — ContextMenuVisuals muss
##      selbst via parent.add_child(self) in den Tree eingefügt werden, damit
##      queue_free() korrekt funktioniert und Nodes sauber freigegeben werden.
##
## FIX 2: VBoxContainer mit korrekten Anchors für Centering in CanvasLayer.

signal action_triggered(action: InteractableAction)

var _container: PanelContainer

func setup(parent: HUD, actions: Array[InteractableAction]) -> void:
	add_to_group("context_menu")

	# Hintergrund-Panel — zentriert im HUD
	_container = PanelContainer.new()
	_container.name = "ContextMenuPanel"
	# BUGFIX (2026-09-20, "Kontextmenü schließt sich nicht mehr"): _container
	# wird unten als Sibling von 'self' unter 'parent' gehängt, nicht als Kind
	# von 'self'. destroy() räumt beide korrekt weg, aber die "altes Menü
	# aufräumen"-Logik in ContextMenuController._show_menu() iteriert nur über
	# die Gruppe "context_menu" (bisher nur 'self') und ließ das sichtbare
	# Panel dadurch verwaist im Tree hängen, sobald ein neues Menü geöffnet
	# wurde, bevor das alte uber destroy() geschlossen war. _container muss
	# deshalb ebenfalls in der Gruppe stehen, damit alte Panels zuverlässig
	# mitentfernt werden.
	_container.add_to_group("context_menu")

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.08, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	_container.add_theme_stylebox_override("panel", sb)

	# Anchor: vertikal zentriert, etwas über Mitte (Bildschirmunterhälfte für Joystick)
	_container.anchor_left = 0.5
	_container.anchor_right = 0.5
	_container.anchor_top = 0.3
	_container.anchor_bottom = 0.3
	_container.offset_left = -140
	_container.offset_right = 140
	_container.offset_top = 0
	# offset_bottom war nicht gesetzt → Panel hatte Höhe 0 → Buttons nicht sichtbar.
	# FIX: auf 0 gesetzt + PanelContainer wächst durch VBoxContainer automatisch.
	# SHRINK_BEGIN = Panel wächst nach unten (nicht nach oben).
	_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_container.add_child(vbox)

	for action in actions:
		if not action is InteractableAction:
			continue
		var btn := Button.new()
		btn.text = action.label
		btn.custom_minimum_size = Vector2(240, 72)
		# Capture action per Value damit die Lambda-Closure korrekt funktioniert
		var captured: InteractableAction = action
		btn.pressed.connect(func(): action_triggered.emit(captured))
		vbox.add_child(btn)

	parent.add_child(_container)
	parent.add_child(self)  # Self muss im Tree sein für sauberes queue_free()

func destroy() -> void:
	if is_instance_valid(_container):
		_container.queue_free()
	queue_free()
