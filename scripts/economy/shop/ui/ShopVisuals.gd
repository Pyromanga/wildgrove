class_name ShopVisuals

## ShopVisuals — reines UI-Building für das Shop-Panel (kein Verhalten,
## siehe QuestPanelVisuals-Konvention). ShopUIController hält die Logik.

var panel: PanelContainer
var title_label: Label
var gold_label: Label
var buy_list: VBoxContainer
var sell_list: VBoxContainer
var sell_all_button: Button
var _sell_all_confirm_pending: bool = false

func _init(parent: CanvasLayer) -> void:
	panel = PanelContainer.new()
	panel.name = "ShopPanel"
	panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.09, 0.95)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)

	UIMetrics.place_modal(panel, 480)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	title_label = Label.new()
	title_label.text = "Händler"
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(UIMetrics.TAP_MIN, UIMetrics.TAP_MIN)
	close_btn.pressed.connect(func(): close_requested.emit())
	header.add_child(close_btn)
	vbox.add_child(header)

	gold_label = Label.new()
	gold_label.text = "💰 Gold: 0"
	gold_label.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(gold_label)

	vbox.add_child(HSeparator.new())

	var buy_header := Label.new()
	buy_header.text = "Kaufen"
	buy_header.add_theme_font_size_override("font_size", 15)
	vbox.add_child(buy_header)

	var buy_scroll := ScrollContainer.new()
	buy_scroll.custom_minimum_size = Vector2(0, 120)
	buy_list = VBoxContainer.new()
	buy_list.add_theme_constant_override("separation", 4)
	buy_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_scroll.add_child(buy_list)
	vbox.add_child(buy_scroll)

	vbox.add_child(HSeparator.new())

	var sell_header_row := HBoxContainer.new()
	sell_header_row.add_theme_constant_override("separation", 8)
	var sell_header := Label.new()
	sell_header.text = "Verkaufen"
	sell_header.add_theme_font_size_override("font_size", 15)
	sell_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_header_row.add_child(sell_header)

	# QoL-Sammel-Button (Wunsch "so was wie alles verkaufen") — siehe
	# QolUnlocks für den Freischalt-Haken. Verkaufen ist (anders als
	# Einlagern) NICHT rückgängig zu machen, deshalb zusätzlich Tap-zum-
	# Bestätigen statt sofort auszulösen (siehe _on_sell_all_pressed()).
	sell_all_button = Button.new()
	sell_all_button.text = "💰 Alles verkaufen"
	UIMetrics.tap(sell_all_button, 170)
	sell_all_button.pressed.connect(_on_sell_all_pressed)
	sell_header_row.add_child(sell_all_button)
	vbox.add_child(sell_header_row)

	var sell_scroll := ScrollContainer.new()
	sell_scroll.custom_minimum_size = Vector2(0, 160)
	sell_list = VBoxContainer.new()
	sell_list.add_theme_constant_override("separation", 4)
	sell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_scroll.add_child(sell_list)
	vbox.add_child(sell_scroll)

	parent.add_child(panel)
	PanelDock.register_in(parent, &"shop", panel, PanelDock.Kind.MODAL)

signal close_requested
signal sell_all_requested

func open(display_name: String) -> void:
	title_label.text = display_name
	panel.visible = true

func close() -> void:
	panel.visible = false

func update_gold(amount: int) -> void:
	gold_label.text = "💰 Gold: %d" % amount

## Zwei-Tipp-Bestätigung statt sofortigem Verkauf — anders als "Alles
## einlagern" (jederzeit rückgängig über Auszahlen) ist ein versehentlicher
## Massenverkauf endgültig. Erster Tipp ändert nur den Button-Text und setzt
## einen 3s-Timer; zweiter Tipp INNERHALB dieser 3s löst tatsächlich aus.
## Ein weiterer Tipp danach (Timer schon abgelaufen) fängt wieder bei Schritt 1 an.
func _on_sell_all_pressed() -> void:
	if _sell_all_confirm_pending:
		_reset_sell_all_confirm()
		sell_all_requested.emit()
		return
	_sell_all_confirm_pending = true
	sell_all_button.text = "Sicher? (nochmal tippen)"
	var tree := sell_all_button.get_tree()
	if is_instance_valid(tree):
		tree.create_timer(3.0).timeout.connect(_reset_sell_all_confirm, CONNECT_ONE_SHOT)

func _reset_sell_all_confirm() -> void:
	_sell_all_confirm_pending = false
	if is_instance_valid(sell_all_button):
		sell_all_button.text = "💰 Alles verkaufen"

## Schaltet den "Alles verkaufen"-Button an/aus (siehe QolUnlocks) — bei
## disabled zusätzlich ein Tooltip mit `hint`.
func set_sell_all_enabled(enabled: bool, hint: String = "") -> void:
	sell_all_button.disabled = not enabled
	sell_all_button.tooltip_text = "" if enabled else hint
	sell_all_button.modulate = Color(1, 1, 1, 1.0) if enabled else Color(1, 1, 1, 0.5)

## entries: Array[Dictionary] mit {item_id, display_name, price}
func set_buy_entries(entries: Array[Dictionary], on_buy: Callable) -> void:
	_clear(buy_list)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "(nichts im Angebot)"
		empty.modulate = Color(1, 1, 1, 0.5)
		buy_list.add_child(empty)
		return
	for entry in entries:
		buy_list.add_child(_build_row(
			"%s — %d 💰" % [entry["display_name"], entry["price"]],
			"Kaufen",
			func(): on_buy.call(entry["item_id"])
		))
	UIMetrics.allow_scroll_through(buy_list)

## entries: Array[Dictionary] mit {item_id, display_name, quantity, price}
func set_sell_entries(entries: Array[Dictionary], on_sell: Callable) -> void:
	_clear(sell_list)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "(nichts zu verkaufen)"
		empty.modulate = Color(1, 1, 1, 0.5)
		sell_list.add_child(empty)
		return
	for entry in entries:
		sell_list.add_child(_build_row(
			"%s x%d — %d 💰/Stk." % [entry["display_name"], entry["quantity"], entry["price"]],
			"Verkaufen",
			func(): on_sell.call(entry["item_id"])
		))
	UIMetrics.allow_scroll_through(sell_list)

func _build_row(text: String, button_text: String, on_press: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	row.add_child(lbl)
	var btn := Button.new()
	btn.text = button_text
	btn.custom_minimum_size = Vector2(112, UIMetrics.TAP_MIN)
	btn.pressed.connect(on_press)
	row.add_child(btn)
	return row

func _clear(container: VBoxContainer) -> void:
	# BUGFIX (2026-09-21, "Object was freed while signal is being emitted"):
	# _clear() runs synchronously inside the very button-press signal chain
	# that triggers it (Button.pressed -> ShopService -> transaction signal ->
	# _refresh_buy_list()/_refresh_sell_list() -> set_*_entries() -> _clear()).
	# child.free() destroys the Button/Node while its own "pressed" signal is
	# still on the call stack, which Godot logs as an Engine error and can
	# leave the row only partially removed (stale rows with live closures
	# stick around and can fire the *_requested signal again on top of the
	# real one). queue_free() defers destruction to the end of the frame, so
	# it never collides with the signal that's still emitting.
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
