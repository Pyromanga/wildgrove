class_name UIMetrics
extends RefCounted

## UIMetrics — gemeinsame Maße und Platzierungs-Helfer für alle HUD-Elemente.
##
## WARUM ES DAS GIBT: Vorher hat jedes Panel seine Position und Button-Größe selbst
## festgelegt (mal Bruchteil-Anchors wie 0.02, mal Pixel-Offsets, mal fest 32/36 px
## hohe Buttons). Ergebnis: Toggle-Buttons lagen übereinander, alle Panels öffneten
## an fast derselben Stelle, Tap-Ziele waren winzig. Jetzt kommen Maße und
## Platzierung von hier — Änderungen an einer Stelle wirken auf das ganze HUD.
##
## Referenzauflösung: 1920×1080 (project.godot: stretch canvas_items / expand).
## Auf einem Handy sind 1080 px Höhe grob 65–70 mm → 64 px ≈ 4 mm, 88 px ≈ 5,5 mm.

const MARGIN: int = 16

## Toolbar (PanelDock) oben links.
const TOOLBAR_BUTTON: int = 88
const TOOLBAR_GAP: int = 10
const TOOLBAR_PADDING: int = 8

## Sheets (Seitenfenster: Inventar, Skills, Quests, ...) beginnen unterhalb der Toolbar.
const SHEET_LEFT: int = 16
const SHEET_TOP: int = MARGIN + TOOLBAR_BUTTON + 2 * TOOLBAR_PADDING + 12

## Mindestgrößen für Touch-Ziele innerhalb von Panels.
## (Wunsch "alles ist relativ klein" — vorher 64/56, auf dem Handy knapp.)
const TAP_MIN: int = 72
const FIELD_MIN: int = 64

## Schriftgrößen — EINE Stelle statt jede Panel-Datei mit eigenen Zahlen
## (vorher z.B. 20/18/15/12 wild gemischt über Inventar/Skills/Pets/Quests).
const FONT_TITLE: int = 24
const FONT_ROW: int = 20
const FONT_SUB: int = 15

## Standardbreite/-Scrollhöhe für Sheets — vorher hatte jede Datei ihre eigene
## Zahl (320/340/360, 420 Scrollhöhe). Panels, die mehr Breite brauchen
## (z.B. Pet-Menü mit 2-spaltigem Fähigkeiten-Grid), dürfen weiterhin einen
## eigenen Wert an place_sheet()/make_scrollable() übergeben.
const SHEET_WIDTH: float = 400.0
const SHEET_SCROLL_HEIGHT: float = 460.0

## Stellt sicher, dass ein Control mindestens TAP_MIN hoch (und optional min_width breit) ist.
static func tap(ctrl: Control, min_width: float = 0.0) -> void:
	var s: Vector2 = ctrl.custom_minimum_size
	ctrl.custom_minimum_size = Vector2(maxf(s.x, min_width), maxf(s.y, float(TAP_MIN)))

## Sheet: links oben unter der Toolbar. Höhe = Inhalt (wächst nach unten).
static func place_sheet(panel: Control, width: float) -> void:
	panel.anchor_left   = 0.0
	panel.anchor_right  = 0.0
	panel.anchor_top    = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left   = SHEET_LEFT
	panel.offset_right  = SHEET_LEFT + width
	panel.offset_top    = SHEET_TOP
	panel.offset_bottom = SHEET_TOP
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical   = Control.GROW_DIRECTION_END
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

## Modal: zentriert, Höhe = Inhalt. GROW_DIRECTION_BOTH hält das Fenster auch dann
## mittig, wenn der Inhalt (größere Buttons!) höher wird als früher fest verdrahtet.
static func place_modal(panel: Control, width: float) -> void:
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -width * 0.5
	panel.offset_right  = width * 0.5
	panel.offset_top    = 0.0
	panel.offset_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical   = Control.GROW_DIRECTION_BOTH

# ─────────────────────────────────────────────
# Einheitlicher Look (Wunsch "UI generell ansprechender machen/aufräumen") —
# vorher baute jede Panel-Datei ihre eigene StyleBoxFlat mit leicht
# abweichenden Werten (mal Radius 8, mal 10, nie ein Rand). Jetzt eine
# Anlaufstelle, Änderungen wirken auf alle Panels, die sie nutzen.
# ─────────────────────────────────────────────

## Haupt-Panel-Hintergrund (Sheets/Modals) — dezenter heller Rand + Schlagschatten
## sorgen dafür, dass sich das Panel von der 3D-Welt/anderen Panels abhebt statt
## als reine Volltonfläche flach zu wirken.
static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.11, 0.95)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(16)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.shadow_size = 10
	sb.shadow_color = Color(0, 0, 0, 0.35)
	return sb

## Zeilen-/Karten-Hintergrund innerhalb eines Panels (z.B. eine Pet- oder
## Item-Zeile) — etwas heller als der Panel-Hintergrund, damit sich Zeilen
## optisch voneinander trennen (vorher: nur Abstand, keine echte Kontur).
static func row_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.06)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	return sb

## Kopfzeile mit Titel + ✕-Schließen-Button (Wunsch "QoL Buttons") — vorher
## ließ sich ein Sheet NUR über seinen eigenen (oft längst aus dem Blick
## gescrollten) Toolbar-Button wieder schließen. `panel` wird beim Klick
## direkt unsichtbar geschaltet (PanelDock reagiert über visibility_changed,
## siehe dortiger Kommentar — kein Rückruf zum Dock nötig).
static func build_header(title_text: String, panel: Control) -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "Header"

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	tap(close_btn, 44.0)
	close_btn.pressed.connect(func() -> void: panel.visible = false)
	header.add_child(close_btn)

	return header

## Baut einen ScrollContainer fester Maximalhöhe für Panel-Inhalte, die über
## die Zeit wachsen (Zeilen kommen erst nach und nach dazu) — vorher hatte
## jede Datei dieselben 6 Zeilen dupliziert (custom_minimum_size, disabled
## horizontal scroll, ...). `rows` wird als Kind eingehängt.
##
## WICHTIG: nach JEDEM (Neu-)Befüllen von `rows` erneut allow_scroll_through(rows)
## aufrufen (siehe dortiger Kommentar) — neu hinzugekommene Buttons haben sonst
## wieder das Standard-STOP und blockieren Scroll-Gesten, die auf ihnen starten.
static func make_scrollable(rows: Control, height: float = SHEET_SCROLL_HEIGHT) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "%sScroll" % rows.name
	scroll.custom_minimum_size = Vector2(0, height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(rows)
	# Breitere Scrollbar (Godot-Default ~12px) — mit dem Finger leichter zu treffen.
	var vbar := scroll.get_v_scroll_bar()
	if is_instance_valid(vbar):
		vbar.custom_minimum_size = Vector2(20, 0)
	return scroll

## FIX ("Scrollen fühlt sich nicht gut an / geht häufig nicht, z.B. Pet-Menü
## brutal"): Button.mouse_filter ist standardmäßig STOP — ein STOP-Control
## verschluckt JEDES Input-Event inkl. Wisch-/Zieh-Bewegungen; sein
## Eltern-Chain (hier: der umgebende ScrollContainer) bekommt das Event nie zu
## sehen. Bei einer Liste aus reinen Labels/ProgressBars fällt das nicht auf
## (kein STOP-Control im Weg) — sobald aber, wie im Pet-Menü oder jeder
## Item-/Zeilen-Liste mit Buttons, ein Großteil der Zeilenfläche von Buttons
## bedeckt ist, startet praktisch jede Wisch-Geste auf einem Button und das
## Scrollen wirkt komplett kaputt.
##
## FIX: PASS statt STOP auf allen direkten/indirekten Button-Kindern von
## `content` — ein PASS-Control verarbeitet den Klick weiterhin ganz normal
## (PASS unterdrückt nichts), gibt das Event danach aber ZUSÄTZLICH an
## dahinterliegende/übergeordnete Controls weiter, sodass der ScrollContainer
## dieselbe Drag-Geste ebenfalls bekommt und scrollt.
##
## Rekursiv (Zeilen sind oft mehrfach verschachtelt, z.B. Zeile → Grid → Button)
## und idempotent — beliebig oft erneut aufrufbar (siehe make_scrollable()-Hinweis).
static func allow_scroll_through(content: Control) -> void:
	for child in content.get_children():
		if child is Control:
			var c := child as Control
			if c.mouse_filter == Control.MOUSE_FILTER_STOP:
				c.mouse_filter = Control.MOUSE_FILTER_PASS
			allow_scroll_through(c)
