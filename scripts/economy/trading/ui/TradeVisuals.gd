class_name TradeVisuals

## TradeVisuals — reines UI-Building für den Handshake-Handel (ADR-035),
## analog BankVisuals/ShopVisuals (kein Verhalten, TradeUIController hält die
## Logik). Zwei unabhängige Panels:
##
## - invite_panel: kleines Popup bei eingehender Handelsanfrage
##   (Annehmen/Ablehnen) — unabhängig vom Session-Panel, weil eine Einladung
##   VOR jeder Session existiert (siehe TradeService.invite_received).
## - panel: das eigentliche Session-Panel (Angebot bauen, Ready, Bestätigen),
##   erst sichtbar sobald TradeService.session_started gefeuert hat.

signal invite_accept_requested
signal invite_decline_requested
signal close_requested
signal add_item_requested(item_id: String)
signal remove_item_requested(item_id: String)
signal set_gold_requested(amount: int)
signal ready_toggled(ready: bool)
signal confirm_pressed

var panel: PanelContainer
var title_label: Label
var partner_ready_label: Label
var their_header: Label
var my_ready_label: Label
var my_offer_list: VBoxContainer
var their_offer_list: VBoxContainer
var inventory_list: VBoxContainer
var gold_amount_input: LineEdit
var carried_gold_label: Label
var ready_btn: Button
var confirm_btn: Button
var status_label: Label

var invite_panel: PanelContainer
var invite_label: Label

var _is_ready: bool = false

func _init(parent: CanvasLayer) -> void:
	_build_invite_panel(parent)
	_build_session_panel(parent)

# ─────────────────────────────────────────────
# Einladungs-Popup
# ─────────────────────────────────────────────

func _build_invite_panel(parent: CanvasLayer) -> void:
	invite_panel = PanelContainer.new()
	invite_panel.name = "TradeInvitePanel"
	invite_panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.04, 0.95)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	invite_panel.add_theme_stylebox_override("panel", sb)

	invite_panel.anchor_left   = 0.5
	invite_panel.anchor_right  = 0.5
	invite_panel.anchor_top    = 0.3
	invite_panel.anchor_bottom = 0.3
	invite_panel.offset_left   = -150
	invite_panel.offset_right  = 150
	invite_panel.offset_top    = 0
	invite_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	invite_panel.add_child(vbox)

	invite_label = Label.new()
	invite_label.text = "Handelsanfrage"
	invite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	invite_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(invite_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var accept_btn := Button.new()
	accept_btn.text = "Annehmen"
	accept_btn.custom_minimum_size = Vector2(0, UIMetrics.TAP_MIN)
	accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept_btn.pressed.connect(func(): invite_accept_requested.emit())
	row.add_child(accept_btn)
	var decline_btn := Button.new()
	decline_btn.text = "Ablehnen"
	decline_btn.custom_minimum_size = Vector2(0, UIMetrics.TAP_MIN)
	decline_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decline_btn.pressed.connect(func(): invite_decline_requested.emit())
	row.add_child(decline_btn)
	vbox.add_child(row)

	parent.add_child(invite_panel)

func open_invite(from_display_name: String) -> void:
	invite_label.text = "%s bietet dir einen Handel an." % from_display_name
	invite_panel.visible = true

func close_invite() -> void:
	invite_panel.visible = false

# ─────────────────────────────────────────────
# Session-Panel
# ─────────────────────────────────────────────

func _build_session_panel(parent: CanvasLayer) -> void:
	panel = PanelContainer.new()
	panel.name = "TradePanel"
	panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.95)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)

	UIMetrics.place_modal(panel, 720)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	title_label = Label.new()
	title_label.text = "Handel"
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(UIMetrics.TAP_MIN, UIMetrics.TAP_MIN)
	close_btn.pressed.connect(func(): close_requested.emit())
	header.add_child(close_btn)
	vbox.add_child(header)

	# Zwei Angebots-Spalten nebeneinander.
	var offers_row := HBoxContainer.new()
	offers_row.add_theme_constant_override("separation", 10)
	vbox.add_child(offers_row)

	var my_col := VBoxContainer.new()
	my_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers_row.add_child(my_col)
	var my_header := Label.new()
	my_header.text = "Dein Angebot"
	my_header.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	my_col.add_child(my_header)
	my_ready_label = Label.new()
	my_ready_label.text = "Nicht bereit"
	my_ready_label.modulate = Color(1, 1, 1, 0.6)
	my_col.add_child(my_ready_label)
	var my_scroll := ScrollContainer.new()
	my_scroll.custom_minimum_size = Vector2(0, 110)
	my_offer_list = VBoxContainer.new()
	my_offer_list.add_theme_constant_override("separation", 4)
	my_offer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_scroll.add_child(my_offer_list)
	my_col.add_child(my_scroll)

	offers_row.add_child(VSeparator.new())

	var their_col := VBoxContainer.new()
	their_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers_row.add_child(their_col)
	their_header = Label.new()
	their_header.text = "Angebot von Gegenpartei"
	their_header.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	their_col.add_child(their_header)
	partner_ready_label = Label.new()
	partner_ready_label.text = "Nicht bereit"
	partner_ready_label.modulate = Color(1, 1, 1, 0.6)
	their_col.add_child(partner_ready_label)
	var their_scroll := ScrollContainer.new()
	their_scroll.custom_minimum_size = Vector2(0, 110)
	their_offer_list = VBoxContainer.new()
	their_offer_list.add_theme_constant_override("separation", 4)
	their_offer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	their_scroll.add_child(their_offer_list)
	their_col.add_child(their_scroll)

	vbox.add_child(HSeparator.new())

	carried_gold_label = Label.new()
	carried_gold_label.text = "💰 Bei dir: 0"
	carried_gold_label.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(carried_gold_label)

	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 6)
	var gold_lbl := Label.new()
	gold_lbl.text = "Gold anbieten:"
	gold_row.add_child(gold_lbl)
	gold_amount_input = LineEdit.new()
	gold_amount_input.text = "0"
	gold_amount_input.custom_minimum_size = Vector2(90, UIMetrics.FIELD_MIN)
	gold_row.add_child(gold_amount_input)
	var gold_set_btn := Button.new()
	gold_set_btn.text = "Setzen"
	gold_set_btn.custom_minimum_size = Vector2(112, UIMetrics.TAP_MIN)
	gold_set_btn.pressed.connect(func(): set_gold_requested.emit(_parsed_gold()))
	gold_row.add_child(gold_set_btn)
	vbox.add_child(gold_row)

	var inv_header := Label.new()
	inv_header.text = "Dein Inventar — hinzufügen"
	inv_header.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	vbox.add_child(inv_header)

	var inv_scroll := ScrollContainer.new()
	inv_scroll.custom_minimum_size = Vector2(0, 110)
	inventory_list = VBoxContainer.new()
	inventory_list.add_theme_constant_override("separation", 4)
	inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(inventory_list)
	vbox.add_child(inv_scroll)

	vbox.add_child(HSeparator.new())

	status_label = Label.new()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.modulate = Color(0.75, 0.85, 1.0)
	vbox.add_child(status_label)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	ready_btn = Button.new()
	ready_btn.text = "Bereit"
	ready_btn.custom_minimum_size = Vector2(0, UIMetrics.TAP_MIN)
	ready_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ready_btn.pressed.connect(func():
		_is_ready = not _is_ready
		ready_toggled.emit(_is_ready)
	)
	action_row.add_child(ready_btn)
	confirm_btn = Button.new()
	confirm_btn.text = "Bestätigen"
	confirm_btn.custom_minimum_size = Vector2(0, UIMetrics.TAP_MIN)
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.disabled = true
	confirm_btn.pressed.connect(func(): confirm_pressed.emit())
	action_row.add_child(confirm_btn)
	vbox.add_child(action_row)

	parent.add_child(panel)
	# sticky: laufende Trade-Session darf nie von einem anderen Fenster versteckt werden.
	PanelDock.register_in(parent, &"trade", panel, PanelDock.Kind.MODAL, null, true)

func _parsed_gold() -> int:
	return max(0, int(gold_amount_input.text))

func open(partner_display_name: String) -> void:
	their_header.text = "Angebot von %s" % partner_display_name
	_is_ready = false
	status_label.text = ""
	panel.visible = true

func close() -> void:
	panel.visible = false
	_is_ready = false
	ready_btn.text = "Bereit"
	confirm_btn.disabled = true

func set_status(text: String) -> void:
	status_label.text = text

func update_carried_gold(amount: int) -> void:
	carried_gold_label.text = "💰 Bei dir: %d" % amount

## ready_states: {mine: bool, theirs: bool}. confirmable: ob "Bestätigen"
## gedrückt werden darf (beide bereit UND noch nicht bestätigt).
func update_ready_state(mine: bool, theirs: bool, confirmable: bool) -> void:
	_is_ready = mine
	ready_btn.text = "Bereit ✓" if mine else "Bereit"
	my_ready_label.text = "Bereit ✓" if mine else "Nicht bereit"
	my_ready_label.modulate = Color(0.6, 1.0, 0.6) if mine else Color(1, 1, 1, 0.6)
	partner_ready_label.text = "Bereit ✓" if theirs else "Nicht bereit"
	partner_ready_label.modulate = Color(0.6, 1.0, 0.6) if theirs else Color(1, 1, 1, 0.6)
	confirm_btn.disabled = not confirmable

## entries: Array[Dictionary] mit {item_id, display_name, quantity}, gold: int
func set_my_offer(entries: Array[Dictionary], gold: int, on_remove: Callable) -> void:
	_fill_offer(my_offer_list, entries, gold, "Entfernen", on_remove)

func set_their_offer(entries: Array[Dictionary], gold: int) -> void:
	_fill_offer(their_offer_list, entries, gold, "", Callable())

func _fill_offer(container: VBoxContainer, entries: Array[Dictionary], gold: int, button_text: String, on_press: Callable) -> void:
	_clear(container)
	if gold > 0:
		var gold_row := HBoxContainer.new()
		var gold_lbl := Label.new()
		gold_lbl.text = "💰 %d Gold" % gold
		gold_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gold_row.add_child(gold_lbl)
		container.add_child(gold_row)
	if entries.is_empty() and gold <= 0:
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
		if on_press.is_valid():
			var btn := Button.new()
			btn.text = button_text
			btn.custom_minimum_size = Vector2(UIMetrics.TAP_MIN, UIMetrics.TAP_MIN)
			var item_id: String = entry["item_id"]
			btn.pressed.connect(func(): on_press.call(item_id))
			row.add_child(btn)
		container.add_child(row)
	UIMetrics.allow_scroll_through(container)

## entries: Array[Dictionary] mit {item_id, display_name, quantity}
func set_inventory_entries(entries: Array[Dictionary], on_add: Callable) -> void:
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
		btn.text = "+"
		btn.custom_minimum_size = Vector2(UIMetrics.TAP_MIN, UIMetrics.TAP_MIN)
		var item_id: String = entry["item_id"]
		btn.pressed.connect(func(): on_add.call(item_id))
		row.add_child(btn)
		inventory_list.add_child(row)
	UIMetrics.allow_scroll_through(inventory_list)

func _clear(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()
