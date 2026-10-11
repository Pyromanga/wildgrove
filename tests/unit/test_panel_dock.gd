# res://tests/unit/test_panel_dock.gd
extends GutTest

## Tests für PanelDock (Toolbar + Fenster-Exklusivität) und UIMetrics.
##
## Regeln, die hier abgesichert werden:
##   - SHEETs (Inventar, Skills, ...) sind untereinander exklusiv.
##   - MODALs (Shop, Bank, ...) schließen SHEETs; SHEETs lassen sich nicht öffnen, solange
##     ein MODAL offen ist; die Toolbar ist währenddessen ausgeblendet.
##   - sticky MODALs (Handel, Charaktererstellung) werden nie automatisch geschlossen —
##     stattdessen wird das neu geöffnete Fenster unterdrückt.
##   - SYSTEM (Pause-Menü) schließt SHEETs, aber keine sticky MODALs.
##   - Toggle-Buttons landen in der Toolbar und zeigen den Zustand ihres Panels.

var _canvas: CanvasLayer
var _dock: PanelDock

func before_each() -> void:
	_canvas = add_child_autofree(CanvasLayer.new())
	_dock = PanelDock.attach(_canvas)

func _make_panel(id: StringName, kind: int, button: Button = null, sticky: bool = false) -> Control:
	var panel := PanelContainer.new()
	panel.visible = false
	_canvas.add_child(panel)
	_dock.register(id, panel, kind, button, sticky)
	return panel

# ─────────────────────────────────────────────
# attach / find
# ─────────────────────────────────────────────

func test_find_returns_dock_after_attach() -> void:
	assert_eq(PanelDock.find(_canvas), _dock)

func test_find_returns_null_without_dock() -> void:
	var bare: CanvasLayer = add_child_autofree(CanvasLayer.new())
	assert_null(PanelDock.find(bare))

func test_find_returns_null_for_null_parent() -> void:
	assert_null(PanelDock.find(null))

func test_register_in_without_dock_still_parents_button() -> void:
	var bare: CanvasLayer = add_child_autofree(CanvasLayer.new())
	var panel := PanelContainer.new()
	bare.add_child(panel)
	var btn := Button.new()
	PanelDock.register_in(bare, &"x", panel, PanelDock.Kind.SHEET, btn)
	assert_eq(btn.get_parent(), bare, "Ohne Dock muss der Button wenigstens im Parent hängen (Fallback).")

# ─────────────────────────────────────────────
# SHEET-Exklusivität
# ─────────────────────────────────────────────

func test_opening_second_sheet_closes_first() -> void:
	var a := _make_panel(&"inventory", PanelDock.Kind.SHEET)
	var b := _make_panel(&"skills", PanelDock.Kind.SHEET)
	a.visible = true
	b.visible = true
	assert_false(a.visible, "Erstes Sheet muss zugehen.")
	assert_true(b.visible)

func test_only_last_of_many_sheets_stays_open() -> void:
	var panels: Array[Control] = []
	for id in [&"inventory", &"equipment", &"skills", &"quests", &"achievements", &"wiki"]:
		panels.append(_make_panel(id, PanelDock.Kind.SHEET))
	for p in panels:
		p.visible = true
	var open_count := 0
	for p in panels:
		if p.visible:
			open_count += 1
	assert_eq(open_count, 1)
	assert_true(panels[panels.size() - 1].visible)

func test_reopening_same_sheet_via_toggle_keeps_it_open() -> void:
	var a := _make_panel(&"inventory", PanelDock.Kind.SHEET)
	a.visible = true
	assert_true(a.visible)

# ─────────────────────────────────────────────
# MODAL
# ─────────────────────────────────────────────

func test_modal_closes_open_sheet() -> void:
	var sheet := _make_panel(&"inventory", PanelDock.Kind.SHEET)
	var modal := _make_panel(&"shop", PanelDock.Kind.MODAL)
	sheet.visible = true
	modal.visible = true
	assert_false(sheet.visible)
	assert_true(modal.visible)

func test_sheet_cannot_open_while_modal_open() -> void:
	var sheet := _make_panel(&"quests", PanelDock.Kind.SHEET)
	var modal := _make_panel(&"bank", PanelDock.Kind.MODAL)
	modal.visible = true
	sheet.visible = true
	assert_false(sheet.visible, "Sheet darf sich nicht über ein offenes Modal legen.")
	assert_true(modal.visible)

func test_toolbar_hidden_while_modal_open_and_back_after() -> void:
	var modal := _make_panel(&"shop", PanelDock.Kind.MODAL)
	assert_true(_dock.visible)
	modal.visible = true
	assert_false(_dock.visible)
	modal.visible = false
	assert_true(_dock.visible)

func test_new_modal_replaces_non_sticky_modal() -> void:
	var shop := _make_panel(&"shop", PanelDock.Kind.MODAL)
	var bank := _make_panel(&"bank", PanelDock.Kind.MODAL)
	shop.visible = true
	bank.visible = true
	assert_false(shop.visible)
	assert_true(bank.visible)

func test_sticky_modal_suppresses_new_modal() -> void:
	var trade := _make_panel(&"trade", PanelDock.Kind.MODAL, null, true)
	var shop := _make_panel(&"shop", PanelDock.Kind.MODAL)
	trade.visible = true
	shop.visible = true
	assert_true(trade.visible, "Laufende Trade-Session darf nie versteckt werden.")
	assert_false(shop.visible)

func test_sticky_modal_closes_non_sticky_modal_when_opening() -> void:
	var shop := _make_panel(&"shop", PanelDock.Kind.MODAL)
	var trade := _make_panel(&"trade", PanelDock.Kind.MODAL, null, true)
	shop.visible = true
	trade.visible = true
	assert_false(shop.visible)
	assert_true(trade.visible)

# ─────────────────────────────────────────────
# SYSTEM (Pause-Menü)
# ─────────────────────────────────────────────

func test_system_closes_sheets() -> void:
	var sheet := _make_panel(&"wiki", PanelDock.Kind.SHEET)
	var pause := _make_panel(&"pause_menu", PanelDock.Kind.SYSTEM)
	sheet.visible = true
	pause.visible = true
	assert_false(sheet.visible)
	assert_true(pause.visible)

func test_sheet_closes_system() -> void:
	var pause := _make_panel(&"pause_menu", PanelDock.Kind.SYSTEM)
	var sheet := _make_panel(&"wiki", PanelDock.Kind.SHEET)
	pause.visible = true
	sheet.visible = true
	assert_false(pause.visible)
	assert_true(sheet.visible)

func test_system_does_not_close_sticky_modal() -> void:
	var trade := _make_panel(&"trade", PanelDock.Kind.MODAL, null, true)
	var pause := _make_panel(&"pause_menu", PanelDock.Kind.SYSTEM)
	trade.visible = true
	pause.visible = true
	assert_true(trade.visible)
	assert_true(pause.visible, "Pause-Menü selbst wird durch ein sticky Modal nicht unterdrückt.")

# ─────────────────────────────────────────────
# Toolbar / Buttons
# ─────────────────────────────────────────────

func test_toggle_button_is_moved_into_dock() -> void:
	var btn := Button.new()
	_canvas.add_child(btn)  # so wie es die Visuals früher direkt getan haben
	_make_panel(&"inventory", PanelDock.Kind.SHEET, btn)
	assert_true(_dock.is_ancestor_of(btn), "Button muss in der Toolbar liegen, nicht lose im HUD.")
	assert_true(btn.custom_minimum_size.x >= UIMetrics.TOOLBAR_BUTTON)

func test_toggle_button_pressed_state_follows_panel() -> void:
	var btn := Button.new()
	var panel := _make_panel(&"inventory", PanelDock.Kind.SHEET, btn)
	panel.visible = true
	assert_true(btn.button_pressed)
	panel.visible = false
	assert_false(btn.button_pressed)

func test_button_of_closed_sheet_is_released_when_other_sheet_opens() -> void:
	var btn_a := Button.new()
	var btn_b := Button.new()
	var a := _make_panel(&"inventory", PanelDock.Kind.SHEET, btn_a)
	var b := _make_panel(&"skills", PanelDock.Kind.SHEET, btn_b)
	a.visible = true
	b.visible = true
	assert_false(btn_a.button_pressed)
	assert_true(btn_b.button_pressed)

func test_toolbar_keeps_registration_order() -> void:
	var btns: Array[Button] = []
	for id in [&"inventory", &"equipment", &"skills"]:
		var btn := Button.new()
		btns.append(btn)
		_make_panel(id, PanelDock.Kind.SHEET, btn)
	for i in btns.size():
		assert_eq(btns[i].get_index(), i)

# ─────────────────────────────────────────────
# close_all
# ─────────────────────────────────────────────

func test_close_all_keeps_sticky() -> void:
	var sheet := _make_panel(&"quests", PanelDock.Kind.SHEET)
	var trade := _make_panel(&"trade", PanelDock.Kind.MODAL, null, true)
	sheet.visible = true
	_dock.close_all()
	assert_false(sheet.visible)
	trade.visible = true
	_dock.close_all()
	assert_true(trade.visible)

func test_is_any_open() -> void:
	var sheet := _make_panel(&"quests", PanelDock.Kind.SHEET)
	assert_false(_dock.is_any_open())
	sheet.visible = true
	assert_true(_dock.is_any_open())

# ─────────────────────────────────────────────
# UIMetrics
# ─────────────────────────────────────────────

func test_tap_raises_small_button_to_minimum() -> void:
	var btn := Button.new()
	autofree(btn)
	btn.custom_minimum_size = Vector2(32, 32)
	UIMetrics.tap(btn, 100.0)
	assert_eq(btn.custom_minimum_size, Vector2(100, UIMetrics.TAP_MIN))

func test_tap_never_shrinks() -> void:
	var btn := Button.new()
	autofree(btn)
	btn.custom_minimum_size = Vector2(300, 200)
	UIMetrics.tap(btn)
	assert_eq(btn.custom_minimum_size, Vector2(300, 200))

func test_place_sheet_starts_below_toolbar() -> void:
	var p := PanelContainer.new()
	autofree(p)
	UIMetrics.place_sheet(p, 400)
	assert_eq(p.offset_top, float(UIMetrics.SHEET_TOP))
	assert_true(UIMetrics.SHEET_TOP >= UIMetrics.MARGIN + UIMetrics.TOOLBAR_BUTTON,
		"Sheets dürfen nicht in die Toolbar ragen.")
	assert_eq(p.offset_right - p.offset_left, 400.0)

func test_place_modal_is_centered_and_grows_both_ways() -> void:
	var p := PanelContainer.new()
	autofree(p)
	UIMetrics.place_modal(p, 500)
	assert_eq(p.anchor_left, 0.5)
	assert_eq(p.offset_left, -250.0)
	assert_eq(p.offset_right, 250.0)
	assert_eq(p.grow_vertical, Control.GROW_DIRECTION_BOTH)
