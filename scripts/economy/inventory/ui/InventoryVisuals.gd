class_name InventoryVisuals

## InventoryVisuals — Aufbau des 🎒-Inventar-Panels.
##
## BUG-FIX: Vorher nur ein einzelnes Label mit "Name ×Menge"-Textzeilen —
## komplett nicht-interaktiv, kein Weg Items aus diesem Panel heraus
## auszurüsten ("Equipment ist über das Inventar nicht ausrüstbar"). Jetzt:
## echte Zeilen (VBoxContainer) analog zu EquipmentUIController._refresh_inventory_tab(),
## damit InventoryUIController pro Zeile einen "Anlegen"-Button anhängen kann.

var panel: PanelContainer
var toggle_button: Button
var item_list: VBoxContainer
var gold_label: Label
var status_label: Label

func _init(parent: CanvasLayer) -> void:
	# ── Toggle-Button (landet in der PanelDock-Toolbar, Position/Größe: siehe PanelDock) ──
	toggle_button = Button.new()
	toggle_button.name = "InventoryToggleButton"
	toggle_button.text = "🎒"
	toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP

	# ── Inventar-Panel (initial versteckt) ──
	panel = PanelContainer.new()
	panel.name = "InventoryPanel"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", UIMetrics.panel_style())

	# Links oben unter der Toolbar (breit genug für Label + zwei 112-px-Buttons pro Zeile)
	UIMetrics.place_sheet(panel, 420)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	vbox.add_child(UIMetrics.build_header("🎒 Inventar", panel))

	# ADR-033/Round 88: Gold-Anzeige oben im Inventory-Panel — CurrencyService
	# hat kein eigenes Panel, Gold gehört gefühlsmäßig zum Inventar dazu.
	gold_label = Label.new()
	gold_label.text = "💰 Gold: 0"
	gold_label.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	gold_label.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(gold_label)

	# ADR-038: Status-Zeile für Schutz-Scroll-Anwendung ("Ziel wählen: …" /
	# Fehlgrund nach einem fehlgeschlagenen request_apply_protection()).
	# Leer/unsichtbar solange keine Scroll-Anwendung aktiv/gerade fehlgeschlagen ist.
	status_label = Label.new()
	status_label.text = ""
	status_label.visible = false
	status_label.modulate = Color(0.6, 0.85, 1.0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(status_label)

	item_list = VBoxContainer.new()
	item_list.name = "ItemList"
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.add_theme_constant_override("separation", 8)
	vbox.add_child(UIMetrics.make_scrollable(item_list, 360))

	parent.add_child(panel)

	# Button verbindet sich mit toggle()
	toggle_button.pressed.connect(toggle)
	PanelDock.register_in(parent, &"inventory", panel, PanelDock.Kind.SHEET, toggle_button)

## Leert die Liste — Controller baut sie danach über add_row()/add_empty_label() neu auf.
func clear() -> void:
	for child in item_list.get_children():
		item_list.remove_child(child)
		child.free()

func update_gold(amount: int) -> void:
	gold_label.text = "💰 Gold: %d" % amount

## Fügt eine Zeile mit Item-Text und optional einem Ausrüsten-Button hinzu.
## on_equip_pressed: leerer Callable wenn das Item nicht ausrüstbar ist.
## ADR-038: on_secondary_pressed/secondary_button_text — zweiter optionaler
## Button pro Zeile, genutzt für "📜 Anwenden" (Scroll auswählen) bzw.
## "🎯 Ziel" (Zielauswahl-Modus, siehe InventoryUIController). Bewusst als
## GENERISCHER zweiter Button gehalten (kein "scroll_button" benannt) — die
## Semantik (Anwenden vs. Ziel) entscheidet ausschließlich der Controller,
## diese Klasse kennt nur "Zeile mit bis zu zwei Buttons".
func add_row(
	text: String,
	on_equip_pressed: Callable = Callable(),
	button_text: String = "⚔ Anlegen",
	on_secondary_pressed: Callable = Callable(),
	secondary_button_text: String = ""
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	item_list.add_child(row)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", UIMetrics.FONT_ROW)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(lbl)

	if on_equip_pressed.is_valid():
		var btn := Button.new()
		btn.text = button_text
		UIMetrics.tap(btn, 120)
		btn.pressed.connect(on_equip_pressed)
		row.add_child(btn)

	if on_secondary_pressed.is_valid():
		var btn2 := Button.new()
		btn2.text = secondary_button_text
		UIMetrics.tap(btn2, 120)
		btn2.pressed.connect(on_secondary_pressed)
		row.add_child(btn2)

	# FIX (Wunsch "Scrollen geht häufig nicht"): siehe UIMetrics.allow_scroll_through()
	# — die gerade angehängten Buttons haben sonst STOP und blockieren jede
	# Wisch-Geste, die auf ihnen startet. add_row() baut Zeile für Zeile statt
	# alles auf einmal (siehe InventoryUIController), daher hier pro Zeile
	# statt einmalig nach einem Voll-Rebuild wie im Pet-/Skill-/Quest-Panel.
	UIMetrics.allow_scroll_through(row)

func add_empty_label(text: String = "(Leer)") -> void:
	var lbl := Label.new()
	lbl.text = text
	item_list.add_child(lbl)

## ADR-038: zeigt eine Statuszeile an (z.B. "Ziel wählen: …" oder einen
## Fehlgrund). Leerer text blendet die Zeile wieder aus statt eine leere
## Zeile stehen zu lassen.
func set_status(text: String) -> void:
	status_label.text = text
	status_label.visible = not text.is_empty()

func clear_status() -> void:
	set_status("")

func toggle() -> void:
	panel.visible = !panel.visible
