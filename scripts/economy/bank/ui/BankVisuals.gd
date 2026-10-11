class_name BankVisuals

## BankVisuals — reines UI-Building für das Bank-Panel (ADR-034), analog
## ShopVisuals. Gold-Bereich mit Betrag-Eingabe (LineEdit), Item-Bereich mit
## zwei Listen (Inventar → Einlagern, Bank → Auszahlen).

var panel: PanelContainer
var title_label: Label
var carried_gold_label: Label
var bank_gold_label: Label
var gold_amount_input: LineEdit
var inventory_list: VBoxContainer
var bank_list: VBoxContainer
var deposit_all_button: Button

signal close_requested
signal deposit_gold_requested(amount: int)
signal withdraw_gold_requested(amount: int)
signal deposit_all_requested

func _init(parent: CanvasLayer) -> void:
	panel = PanelContainer.new()
	panel.name = "BankPanel"
	panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.95)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)

	UIMetrics.place_modal(panel, 520)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	title_label = Label.new()
	title_label.text = "Bank"
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(UIMetrics.TAP_MIN, UIMetrics.TAP_MIN)
	close_btn.pressed.connect(func(): close_requested.emit())
	header.add_child(close_btn)
	vbox.add_child(header)

	carried_gold_label = Label.new()
	carried_gold_label.text = "💰 Bei dir: 0"
	carried_gold_label.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(carried_gold_label)

	bank_gold_label = Label.new()
	bank_gold_label.text = "🏦 In der Bank: 0"
	bank_gold_label.modulate = Color(0.6, 0.85, 1.0)
	vbox.add_child(bank_gold_label)

	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 6)
	gold_amount_input = LineEdit.new()
	gold_amount_input.text = "10"
	gold_amount_input.custom_minimum_size = Vector2(90, UIMetrics.FIELD_MIN)
	gold_row.add_child(gold_amount_input)
	var deposit_btn := Button.new()
	deposit_btn.text = "Einzahlen →"
	deposit_btn.custom_minimum_size = Vector2(0, UIMetrics.TAP_MIN)
	deposit_btn.pressed.connect(func(): deposit_gold_requested.emit(_parsed_amount()))
	gold_row.add_child(deposit_btn)
	var withdraw_btn := Button.new()
	withdraw_btn.text = "← Auszahlen"
	withdraw_btn.custom_minimum_size = Vector2(0, UIMetrics.TAP_MIN)
	withdraw_btn.pressed.connect(func(): withdraw_gold_requested.emit(_parsed_amount()))
	gold_row.add_child(withdraw_btn)
	vbox.add_child(gold_row)

	vbox.add_child(HSeparator.new())

	var inv_header_row := HBoxContainer.new()
	inv_header_row.add_theme_constant_override("separation", 8)
	var inv_header := Label.new()
	inv_header.text = "Dein Inventar — einlagern"
	inv_header.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	inv_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_header_row.add_child(inv_header)

	# QoL-Sammel-Button (Wunsch "so was wie alles einlagern") — siehe
	# QolUnlocks für den Freischalt-Haken. set_deposit_all_enabled() schaltet
	# ihn von außen (Controller kennt QolUnlocks/den Spieler) an/aus.
	deposit_all_button = Button.new()
	deposit_all_button.text = "📥 Alles einlagern"
	UIMetrics.tap(deposit_all_button, 170)
	deposit_all_button.pressed.connect(func(): deposit_all_requested.emit())
	inv_header_row.add_child(deposit_all_button)
	vbox.add_child(inv_header_row)

	var inv_scroll := ScrollContainer.new()
	inv_scroll.custom_minimum_size = Vector2(0, 130)
	inventory_list = VBoxContainer.new()
	inventory_list.add_theme_constant_override("separation", 4)
	inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(inventory_list)
	vbox.add_child(inv_scroll)

	vbox.add_child(HSeparator.new())

	var bank_header := Label.new()
	bank_header.text = "In der Bank — auszahlen"
	bank_header.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	vbox.add_child(bank_header)

	var bank_scroll := ScrollContainer.new()
	bank_scroll.custom_minimum_size = Vector2(0, 130)
	bank_list = VBoxContainer.new()
	bank_list.add_theme_constant_override("separation", 4)
	bank_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bank_scroll.add_child(bank_list)
	vbox.add_child(bank_scroll)

	parent.add_child(panel)
	PanelDock.register_in(parent, &"bank", panel, PanelDock.Kind.MODAL)

func _parsed_amount() -> int:
	var v := int(gold_amount_input.text)
	return max(0, v)

func open(display_name: String) -> void:
	title_label.text = display_name
	panel.visible = true

func close() -> void:
	panel.visible = false

func update_gold(carried: int, banked: int) -> void:
	carried_gold_label.text = "💰 Bei dir: %d" % carried
	bank_gold_label.text = "🏦 In der Bank: %d" % banked

## Schaltet den "Alles einlagern"-Button an/aus (siehe QolUnlocks) — bei
## disabled zusätzlich ein Tooltip mit `hint` statt den Button einfach
## verschwinden zu lassen (Spieler soll sehen, DASS es das Feature gibt und
## WARUM es gerade nicht geht — "Spieler lieben es, Dinge freizuschalten").
func set_deposit_all_enabled(enabled: bool, hint: String = "") -> void:
	deposit_all_button.disabled = not enabled
	deposit_all_button.tooltip_text = "" if enabled else hint
	deposit_all_button.modulate = Color(1, 1, 1, 1.0) if enabled else Color(1, 1, 1, 0.5)

## entries: Array[Dictionary] mit {item_id, display_name, quantity}
func set_inventory_entries(entries: Array[Dictionary], on_deposit: Callable) -> void:
	_fill(inventory_list, entries, "Einlagern", on_deposit)

func set_bank_entries(entries: Array[Dictionary], on_withdraw: Callable) -> void:
	_fill(bank_list, entries, "Auszahlen", on_withdraw)

func _fill(container: VBoxContainer, entries: Array[Dictionary], button_text: String, on_press: Callable) -> void:
	_clear(container)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "(leer)"
		empty.modulate = Color(1, 1, 1, 0.5)
		container.add_child(empty)
		return
	for entry in entries:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s x%d" % [entry["display_name"], entry["quantity"]]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = button_text
		btn.custom_minimum_size = Vector2(112, UIMetrics.TAP_MIN)
		btn.pressed.connect(func(): on_press.call(entry["item_id"]))
		row.add_child(btn)
		container.add_child(row)

	# FIX (Wunsch "Scrollen geht häufig nicht"): siehe UIMetrics.allow_scroll_through().
	UIMetrics.allow_scroll_through(container)

func _clear(container: VBoxContainer) -> void:
	# BUGFIX (2026-09-13): .free() statt .queue_free() zerstörte den Node
	# SOFORT, auch wenn er (z.B. der gerade geklickte Deposit/Withdraw-
	# Button) noch mitten in der Verarbeitung seines eigenen 'pressed'-
	# Signals war -> 'Object was freed or unreferenced while a signal is
	# being emitted from it.' .queue_free() verschiebt die Freigabe ans
	# Frame-Ende, wenn die Signal-Verarbeitung sicher abgeschlossen ist.
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
