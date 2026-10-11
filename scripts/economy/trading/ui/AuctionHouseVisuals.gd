class_name AuctionHouseVisuals

## AuctionHouseVisuals — reines UI-Building für das Auktionshaus-Panel
## (ADR-035), analog BankVisuals/ShopVisuals (kein Verhalten,
## AuctionHouseUIController hält die Logik).
##
## Listen-Formular nutzt EIN geteiltes Menge/Preis-Eingabepaar für alle
## Inventar-Zeilen (analog Banks geteiltem Gold-Betragsfeld) statt eines
## Eingabefelds pro Item — klickt man "Listen" bei einer Inventar-Zeile,
## gelten die aktuell eingetragenen Werte für genau dieses Item.

signal close_requested
signal buy_requested(listing_id: String)
signal cancel_requested(listing_id: String)
signal list_requested(item_id: String, quantity: int, price: int)

var panel: PanelContainer
var title_label: Label
var carried_gold_label: Label
var listings_list: VBoxContainer
var inventory_list: VBoxContainer
var quantity_input: LineEdit
var price_input: LineEdit

func _init(parent: CanvasLayer) -> void:
	panel = PanelContainer.new()
	panel.name = "AuctionHousePanel"
	panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.1, 0.95)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)

	UIMetrics.place_modal(panel, 560)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	title_label = Label.new()
	title_label.text = "Auktionshaus"
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

	var listings_header := Label.new()
	listings_header.text = "Angebote"
	listings_header.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	vbox.add_child(listings_header)

	var listings_scroll := ScrollContainer.new()
	listings_scroll.custom_minimum_size = Vector2(0, 160)
	listings_list = VBoxContainer.new()
	listings_list.add_theme_constant_override("separation", 4)
	listings_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	listings_scroll.add_child(listings_list)
	vbox.add_child(listings_scroll)

	vbox.add_child(HSeparator.new())

	var form_header := Label.new()
	form_header.text = "Selbst listen — Menge & Preis, dann bei der Zeile \"Listen\""
	form_header.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	form_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(form_header)

	var form_row := HBoxContainer.new()
	form_row.add_theme_constant_override("separation", 6)
	var qty_lbl := Label.new()
	qty_lbl.text = "Menge:"
	form_row.add_child(qty_lbl)
	quantity_input = LineEdit.new()
	quantity_input.text = "1"
	quantity_input.custom_minimum_size = Vector2(70, UIMetrics.FIELD_MIN)
	form_row.add_child(quantity_input)
	var price_lbl := Label.new()
	price_lbl.text = "Preis:"
	form_row.add_child(price_lbl)
	price_input = LineEdit.new()
	price_input.text = "10"
	price_input.custom_minimum_size = Vector2(90, UIMetrics.FIELD_MIN)
	form_row.add_child(price_input)
	vbox.add_child(form_row)

	var inv_scroll := ScrollContainer.new()
	inv_scroll.custom_minimum_size = Vector2(0, 120)
	inventory_list = VBoxContainer.new()
	inventory_list.add_theme_constant_override("separation", 4)
	inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(inventory_list)
	vbox.add_child(inv_scroll)

	parent.add_child(panel)
	PanelDock.register_in(parent, &"auction_house", panel, PanelDock.Kind.MODAL)

func _parsed_quantity() -> int:
	return max(1, int(quantity_input.text))

func _parsed_price() -> int:
	return max(1, int(price_input.text))

func open(display_name: String) -> void:
	title_label.text = display_name
	panel.visible = true

func close() -> void:
	panel.visible = false

func update_carried_gold(amount: int) -> void:
	carried_gold_label.text = "💰 Bei dir: %d" % amount

## entries: Array[Dictionary] mit {listing_id, item_name, quantity, price,
## seller_id, is_own (bool)}
func set_listings(entries: Array[Dictionary]) -> void:
	_clear(listings_list)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "(keine Angebote)"
		empty.modulate = Color(1, 1, 1, 0.5)
		listings_list.add_child(empty)
		return
	for entry in entries:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		var is_own: bool = entry["is_own"]
		lbl.text = "%s x%d — %d 💰%s" % [
			entry["item_name"], entry["quantity"], entry["price"],
			" (dein Angebot)" if is_own else ""
		]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
		row.add_child(lbl)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, UIMetrics.TAP_MIN)
		var listing_id: String = entry["listing_id"]
		if is_own:
			btn.text = "Stornieren"
			btn.pressed.connect(func(): cancel_requested.emit(listing_id))
		else:
			btn.text = "Kaufen"
			btn.pressed.connect(func(): buy_requested.emit(listing_id))
		row.add_child(btn)
		listings_list.add_child(row)
	UIMetrics.allow_scroll_through(listings_list)

## entries: Array[Dictionary] mit {item_id, display_name, quantity}
func set_inventory_entries(entries: Array[Dictionary]) -> void:
	_clear(inventory_list)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "(leer)"
		empty.modulate = Color(1, 1, 1, 0.5)
		inventory_list.add_child(empty)
		return
	for entry in entries:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s x%d" % [entry["display_name"], entry["quantity"]]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
		row.add_child(lbl)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(112, UIMetrics.TAP_MIN)
		btn.text = "Listen"
		var item_id: String = entry["item_id"]
		btn.pressed.connect(func(): list_requested.emit(item_id, _parsed_quantity(), _parsed_price()))
		row.add_child(btn)
		inventory_list.add_child(row)
	UIMetrics.allow_scroll_through(inventory_list)

func _clear(container: VBoxContainer) -> void:
	# BUGFIX (2026-09-21, "Object was freed while signal is being emitted" /
	# duplicate list_requested emissions): same root cause and fix as
	# ShopVisuals._clear() — this runs synchronously from inside the pressed
	# signal of one of the very rows it's clearing (e.g. list_requested ->
	# AuctionHouseService -> transaction signal -> _refresh_inventory_list()
	# -> set_inventory_entries() -> _clear()). child.free() while that signal
	# is still emitting corrupts the removal (Engine error) and can leave old
	# rows with live button closures behind, which then re-fire on later
	# clicks and produce repeated "item_not_owned" failures and duplicated
	# popups. queue_free() defers destruction past the current signal.
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
