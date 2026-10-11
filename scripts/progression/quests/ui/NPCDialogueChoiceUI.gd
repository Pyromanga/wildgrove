extends CanvasLayer
class_name NPCDialogueChoiceUI

## NPCDialogueChoiceUI — Auswahlliste des DialogueTreeController. Zeigt die gerade
## sichtbaren Antworten eines Dialog-Knotens als Buttons (bei genau einer sichtbaren
## Antwort wird sie gar nicht erst erzeugt: kein unnötiger Klick-Umweg).
##
## Wird PRO INTERAKTION neu erzeugt (nicht dauerhaft pro NPC gehalten) —
## queue_free() direkt nach der Auswahl (siehe present()), analog zum
## bewusst kurzlebigen Kontext-Menü (ContextMenuController._show_menu())
## statt einer dauerhaft existierenden, meist verborgenen Instanz pro NPC.
##
## Kein HUD-/IUIContext-Coupling wie ContextMenuController — bewusst so
## simpel wie möglich gehalten (gleiches Grundprinzip wie AdminPanelUI.gd),
## weil Stufe 2 laut ADR-051 explizit NUR eine einfache Auswahlliste sein
## soll, kein eigenständiges Dialogsystem (das ist Stufe 3).

const LAYER_ORDER := 130  # über AdminPanelUI (129) und SimpleTerminalUI (128)
const PANEL_WIDTH := 420
const BTN_MIN_SIZE := Vector2(0, 72)

var _panel: Panel

func _ready() -> void:
	layer = LAYER_ORDER

## options: Kurzbeschriftungen pro Antwort. on_chosen wird mit dem
## Index des gewählten Themas aufgerufen, sobald der Spieler tippt; danach
## räumt sich diese UI selbst weg (queue_free()) — der Aufrufer muss nichts
## aufräumen. title optional (ADR-051 Stufe 3, DialogueTreeController):
## zeigt den tatsächlichen NPC-Sprechtext als Überschrift statt der
## generischen Stufe-2-Frage — Default unverändert für Stufe-2-Aufrufer.
func present(options: Array[String], on_chosen: Callable, title: String = "Worüber möchtest du reden?") -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	_panel.add_child(vbox)

	var title_label := Label.new()
	title_label.text = title
	vbox.add_child(title_label)

	for i in options.size():
		var btn := Button.new()
		btn.text = options[i]
		btn.custom_minimum_size = BTN_MIN_SIZE
		var idx := i
		btn.pressed.connect(func() -> void:
			on_chosen.call(idx)
			queue_free()
		)
		vbox.add_child(btn)
