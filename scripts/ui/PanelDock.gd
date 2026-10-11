class_name PanelDock
extends PanelContainer

## PanelDock — Toolbar (oben links) + zentrale Fenster-Verwaltung fürs HUD.
##
## PROBLEM VORHER: Jedes Panel baute seinen eigenen Toggle-Button an eine selbst
## gewählte Stelle (die Buttons überlappten sich, Ausrüstung und Skills hatten
## dasselbe ⚔) und öffnete sein Fenster unabhängig von allen anderen → Inventar,
## Skills, Quests, Wiki, Shop, Bank ... konnten gleichzeitig übereinander offen sein.
##
## JETZT:
##   1. Toolbar: alle Toggle-Buttons stehen in EINER Reihe (gleiche Größe, gleicher
##      Abstand, eigener Hintergrund), Reihenfolge = Registrierungsreihenfolge
##      (siehe HUDBuilder.build_all()). Der Button zeigt den Zustand (gedrückt = offen).
##   2. Exklusivität: Jedes Panel registriert sich mit einer Art (Kind). Wird eines
##      sichtbar, schließt der Dock automatisch die Panels, die damit nicht
##      zusammen offen sein dürfen. Das läuft über `visibility_changed` — die
##      Controller/Visuals müssen dafür NICHTS Besonderes tun, egal ob sie
##      toggle(), open() oder direkt panel.visible = true benutzen.
##
## ARTEN:
##   SHEET  — Seitenfenster links (Inventar, Ausrüstung, Skills, Quests, Erfolge, Wiki).
##            Immer nur eines offen. Kann NICHT geöffnet werden, solange ein MODAL offen ist.
##   MODAL  — zentrale Fenster (Shop, Bank, Auktionshaus, Handel, Einstellungen,
##            Charaktererstellung). Schließt SHEETs; nur eines gleichzeitig.
##            Toolbar wird ausgeblendet, solange ein MODAL offen ist.
##   SYSTEM — Pause-Menü. Schließt SHEETs und nicht-sticky MODALs.
##
## STICKY: Ein sticky MODAL (Handel mit anderem Spieler, Charaktererstellung) wird
## nie automatisch geschlossen — dort hängt Zustand dran (laufende Trade-Session).
## Stattdessen wird das NEU geöffnete Fenster sofort wieder unterdrückt.
##
## OHNE DOCK (z.B. Unit-Tests mit nacktem CanvasLayer) passiert nichts von alledem:
## register_in() fällt auf "Button einfach in den Parent hängen" zurück.

enum Kind { SHEET, MODAL, SYSTEM }

const LOG_CAT: String = "PanelDock"
const META_KEY: StringName = &"panel_dock"

var _row: HBoxContainer
## { StringName: { "panel": Control, "kind": int, "button": Button|null, "sticky": bool } }
var _entries: Dictionary = {}

func _init() -> void:
	name = "PanelDock"
	anchor_left   = 0.0
	anchor_right  = 0.0
	anchor_top    = 0.0
	anchor_bottom = 0.0
	offset_left   = UIMetrics.MARGIN
	offset_right  = UIMetrics.MARGIN
	offset_top    = UIMetrics.MARGIN
	offset_bottom = UIMetrics.MARGIN
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical   = Control.GROW_DIRECTION_END
	mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(UIMetrics.TOOLBAR_PADDING)
	add_theme_stylebox_override("panel", sb)

	_row = HBoxContainer.new()
	_row.name = "Toolbar"
	_row.add_theme_constant_override("separation", UIMetrics.TOOLBAR_GAP)
	add_child(_row)

# ─────────────────────────────────────────────
# Statische Einstiegspunkte
# ─────────────────────────────────────────────

## Erzeugt den Dock als Kind von `hud` und merkt ihn per Meta, damit die Visuals ihn
## über ihren `parent` finden (find()), ohne dass jeder Konstruktor einen neuen
## Parameter bekommt. HUDBuilder.build_all() ruft das als Erstes auf.
static func attach(hud: Node) -> PanelDock:
	var dock := PanelDock.new()
	hud.add_child(dock)
	hud.set_meta(META_KEY, dock)
	return dock

## Liefert den Dock, der an `parent` hängt — oder null (z.B. im Unit-Test).
static func find(parent: Node) -> PanelDock:
	if parent == null or not parent.has_meta(META_KEY):
		return null
	var candidate: Variant = parent.get_meta(META_KEY)
	if is_instance_valid(candidate) and candidate is PanelDock:
		return candidate as PanelDock
	return null

## Bequemer Aufruf für die Visuals: registriert beim Dock, falls vorhanden; sonst
## wird der Toggle-Button (falls einer da ist) wenigstens in den Parent gehängt.
static func register_in(
	parent: Node, id: StringName, panel: Control, kind: int,
	button: Button = null, sticky: bool = false
) -> void:
	var dock := find(parent)
	if dock != null:
		dock.register(id, panel, kind, button, sticky)
	elif button != null and button.get_parent() == null and parent != null:
		parent.add_child(button)

# ─────────────────────────────────────────────
# Registrierung / API
# ─────────────────────────────────────────────

func register(
	id: StringName, panel: Control, kind: int,
	button: Button = null, sticky: bool = false
) -> void:
	if not is_instance_valid(panel):
		return
	_entries[id] = {"panel": panel, "kind": kind, "button": button, "sticky": sticky}
	if button != null:
		_add_toolbar_button(button)
	panel.visibility_changed.connect(_on_visibility_changed.bind(id))
	_refresh()

## Schließt alles, was nicht sticky ist.
func close_all() -> void:
	for id: StringName in _entries.keys():
		if not bool(_entries[id]["sticky"]):
			_hide(id)

func is_open(id: StringName) -> bool:
	return _is_open(id)

func is_any_open() -> bool:
	for id: StringName in _entries.keys():
		if _is_open(id):
			return true
	return false

## Zurück/ESC schließt offene SHEETs (das Pause-Menü behandelt ESC selbst).
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var closed := false
	for id: StringName in _entries.keys():
		if int(_entries[id]["kind"]) == Kind.SHEET and _is_open(id):
			_hide(id)
			closed = true
	if closed:
		get_viewport().set_input_as_handled()

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _add_toolbar_button(button: Button) -> void:
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(UIMetrics.TOOLBAR_BUTTON, UIMetrics.TOOLBAR_BUTTON)
	button.add_theme_font_size_override("font_size", 36)
	var old_parent := button.get_parent()
	if old_parent != null:
		old_parent.remove_child(button)
	_row.add_child(button)

func _on_visibility_changed(id: StringName) -> void:
	if _entries.has(id) and _is_open(id):
		_resolve_open(id)
	_refresh()

## Panel `id` ist (eigenes visible-Flag) sichtbar geworden → Konflikte auflösen.
func _resolve_open(id: StringName) -> void:
	var kind: int = _entries[id]["kind"]

	# Opener wird unterdrückt, wenn etwas Höherrangiges schon offen ist.
	if kind == Kind.SHEET and _any_open_of_kind(Kind.MODAL):
		_hide(id)
		return
	if kind == Kind.MODAL and _any_sticky_open(id):
		_hide(id)
		return

	# Sonst schließt der Opener alles, was mit ihm nicht zusammen offen sein darf.
	for other_id: StringName in _entries.keys():
		if other_id == id or not _is_open(other_id):
			continue
		var other: Dictionary = _entries[other_id]
		if _should_close(kind, int(other["kind"]), bool(other["sticky"])):
			_hide(other_id)

static func _should_close(opener_kind: int, other_kind: int, other_sticky: bool) -> bool:
	if other_sticky:
		return false
	if opener_kind == Kind.SHEET:
		# SHEETs schließen andere SHEETs und das Pause-Menü (MODALs verhindern das Öffnen schon vorher).
		return other_kind != Kind.MODAL
	# MODAL und SYSTEM schließen alles Nicht-Sticky.
	return true

func _hide(id: StringName) -> void:
	var panel: Variant = _entries[id]["panel"]
	if is_instance_valid(panel):
		(panel as Control).visible = false

func _is_open(id: StringName) -> bool:
	if not _entries.has(id):
		return false
	var panel: Variant = _entries[id]["panel"]
	return is_instance_valid(panel) and (panel as Control).visible

func _any_open_of_kind(kind: int) -> bool:
	for id: StringName in _entries.keys():
		if int(_entries[id]["kind"]) == kind and _is_open(id):
			return true
	return false

func _any_sticky_open(except_id: StringName) -> bool:
	for id: StringName in _entries.keys():
		if id != except_id and bool(_entries[id]["sticky"]) and _is_open(id):
			return true
	return false

func _refresh() -> void:
	for id: StringName in _entries.keys():
		var btn: Variant = _entries[id]["button"]
		if is_instance_valid(btn):
			(btn as Button).set_pressed_no_signal(_is_open(id))
	# Solange ein zentrales Fenster offen ist, gibt es nichts für die Toolbar zu tun.
	visible = not _any_open_of_kind(Kind.MODAL)
