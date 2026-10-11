class_name WorldMapView
extends CanvasLayer

## WorldMapView — die Weltkarte, die beim extremen Herauszoomen über die Vogelperspektive blendet.
##
## ABLAUF (siehe PlayerCamera-Klassenkommentar für die Zoom-Stufen)
##   Kamera steigt + kippt senkrecht → ab MAP_ZOOM_START blendet diese Ansicht ein (Alpha =
##   camera.get_map_blend()) → ab MAP_ZOOM_FULL ist die Karte voll sichtbar und zoomt weiter
##   heraus. Heranzoomen blendet sie wieder aus; die Welt darunter ist nie weg.
##
## WAS GEZEICHNET WIRD (alles in _Canvas._draw, rein lokal, kein Netzwerk):
##   - Gelände-Kacheln aus WorldMapBaker (grob = weit, fein = nah), gedreht wie die Kamera —
##     die Karte dreht also mit, wenn man die Kamera dreht (Spieler bleibt Bildmitte).
##   - Spielerpfeil (Blickrichtung), andere Spieler (Punkte), NPCs (Rauten, mit Namen, solange
##     der Maßstab es zulässt).
##   - Kompass (Nord = Welt −Z), Maßstabsbalken, Koordinaten + Biom, "wird gezeichnet"-Hinweis.
##
## PERFORMANCE
##   - Zeichnen/Backen nur, solange die Karte sichtbar ist.
##   - Backen in Zeitscheiben (WorldMapBaker.step), grob zuerst.
##   - Ist die Karte voll sichtbar, wird das 3D-Rendering des Viewports abgeschaltet (Mobile!).
##     Wird in _exit_tree() IMMER wiederhergestellt.
##
## Liegt UNTER dem HUD (HUD.layer = 1) und schluckt keine Eingaben (mouse_filter = IGNORE).

const LOG_CAT := "WorldMapView"

const MAP_LAYER: int = -1
## Ab dieser halben Kartenhöhe (m) reicht die grobe Auflösung; darunter liegt die feine darüber.
const FINE_MAX_EXTENT_M: float = 260.0
## Zeitbudget fürs Backen pro Frame (ms).
const BAKE_BUDGET_MSEC: float = 6.0
## Neu anfordern, wenn der Spieler sich so weit bewegt hat (m) / der Radius so stark wächst.
const REQUEST_MOVE_M: float = 40.0
const REQUEST_INTERVAL: float = 0.35
## Ab diesem Blend-Wert wird das 3D-Rendering abgeschaltet.
const DISABLE_3D_BLEND: float = 0.999
## Namen von NPCs nur anzeigen, wenn die halbe Kartenhöhe kleiner ist.
const LABEL_MAX_EXTENT_M: float = 520.0

## Dörfer & Straßen: pro Frame höchstens so viele neue Makro-Zellen planen (Zeitscheiben wie beim Backen).
const SETTLEMENT_PREP_PER_FRAME: int = 1
## Obergrenze der Kantenlänge (m) des Bereichs, für den Dörfer/Straßen vorbereitet werden.
const SETTLEMENT_MAX_SPAN_M: float = 2400.0

const COL_VILLAGE_FILL := Color(1.0, 0.82, 0.40, 0.17)
const COL_VILLAGE_EDGE := Color(1.0, 0.86, 0.50, 0.85)
const COL_VILLAGE_ICON := Color(0.98, 0.93, 0.80, 1.0)
const COL_VILLAGE_ICON_EDGE := Color(0.25, 0.16, 0.08, 1.0)
const COL_ROAD_MAP := Color(0.90, 0.78, 0.52, 0.95)
const COL_ROAD_MAP_EDGE := Color(0.18, 0.12, 0.06, 0.70)
const COL_BG := Color(0.09, 0.11, 0.14)
const COL_NPC := Color(1.0, 0.86, 0.30)
const COL_PLAYER_OTHER := Color(0.45, 0.85, 1.0)
const COL_ARROW := Color(1.0, 1.0, 1.0)
const COL_ARROW_EDGE := Color(0.10, 0.10, 0.12)
const COL_TEXT := Color(1.0, 1.0, 1.0, 0.95)
const COL_TEXT_SHADOW := Color(0.0, 0.0, 0.0, 0.75)

var _camera: PlayerCamera = null
var _player: Node3D = null
var _heading_node: Node3D = null
var _terrain: TerrainField = null

var _fine: WorldMapBaker = WorldMapBaker.new(4.0, 64)
var _coarse: WorldMapBaker = WorldMapBaker.new(12.0, 64)
var _canvas: _Canvas = null

var _request_timer: float = 0.0
var _last_request_center: Vector2 = Vector2(INF, INF)
var _last_request_radius: float = 0.0
var _3d_disabled: bool = false

func _init() -> void:
	layer = MAP_LAYER
	name = "WorldMapView"
	_canvas = _Canvas.new()
	_canvas.view = self
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_canvas.visible = false
	add_child(_canvas)

## camera/player = lokaler Spieler. `heading_node` = Knoten, dessen +Z die Blickrichtung des
## Modells ist (PlayerVisuals); null → Spieler-Node. `terrain` darf null sein (Karte bleibt dann
## dunkel, Marker/Kompass funktionieren trotzdem).
func setup(camera: PlayerCamera, player: Node3D, heading_node: Node3D, terrain: TerrainField) -> void:
	_camera = camera
	_player = player
	_heading_node = heading_node if is_instance_valid(heading_node) else player
	_terrain = terrain
	_fine.setup(terrain)
	_coarse.setup(terrain)
	_last_request_center = Vector2(INF, INF)

func _exit_tree() -> void:
	_restore_3d()

func _process(delta: float) -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(_player):
		_canvas.visible = false
		_restore_3d()
		return
	var blend := _camera.get_map_blend()
	var map_visible := blend > 0.001
	_canvas.visible = map_visible
	if not map_visible:
		_restore_3d()
		return
	_canvas.modulate.a = blend
	_set_3d_disabled(blend >= DISABLE_3D_BLEND)
	_update_baking(delta)
	_canvas.queue_redraw()

# ─────────────────────────────────────────────
# Backen
# ─────────────────────────────────────────────

func _update_baking(delta: float) -> void:
	if _terrain == null:
		return
	_request_timer -= delta
	var center := _player_xz()
	var radius := visible_radius_m(_camera.get_map_half_extent_m(), _canvas.size) * 1.08
	var moved := center.distance_to(_last_request_center) > REQUEST_MOVE_M
	var grew := radius > _last_request_radius * 1.15
	if _request_timer <= 0.0 or moved or grew:
		_request_timer = REQUEST_INTERVAL
		_last_request_center = center
		_last_request_radius = radius
		_coarse.request_area(center, radius)
		if _camera.get_map_half_extent_m() <= FINE_MAX_EXTENT_M:
			_fine.request_area(center, radius)
	# Grob zuerst (Untergrund), dann fein.
	if _coarse.pending_count() > 0:
		_coarse.step(BAKE_BUDGET_MSEC)
	elif _fine.pending_count() > 0:
		_fine.step(BAKE_BUDGET_MSEC)

func is_baking() -> bool:
	return _coarse.pending_count() > 0 or _fine.pending_count() > 0

func _player_xz() -> Vector2:
	return Vector2(_player.global_position.x, _player.global_position.z)

func _heading_world() -> Vector2:
	var b := _heading_node.global_transform.basis.z
	var v := Vector2(b.x, b.z)
	return v.normalized() if v.length_squared() > 0.0001 else Vector2(0.0, 1.0)

# ─────────────────────────────────────────────
# 3D-Rendering sparen
# ─────────────────────────────────────────────

func _set_3d_disabled(disabled: bool) -> void:
	if disabled == _3d_disabled:
		return
	if not is_inside_tree():
		return
	_3d_disabled = disabled
	get_viewport().disable_3d = disabled

func _restore_3d() -> void:
	if _3d_disabled:
		_3d_disabled = false
		if is_inside_tree():
			get_viewport().disable_3d = false

# ─────────────────────────────────────────────
# Reine Hilfsfunktionen (statisch → testbar)
# ─────────────────────────────────────────────

## Weltpunkt (x, z) → Bildschirmpunkt. Die Karte ist um `yaw` gedreht (Kamera), `center_world`
## liegt auf `screen_center`.
static func world_to_screen(world: Vector2, center_world: Vector2, yaw: float, ppm: float, screen_center: Vector2) -> Vector2:
	return screen_center + (world - center_world).rotated(yaw) * ppm

static func screen_to_world(screen: Vector2, center_world: Vector2, yaw: float, ppm: float, screen_center: Vector2) -> Vector2:
	return center_world + ((screen - screen_center) / ppm).rotated(-yaw)

## Pixel pro Meter, wenn die halbe Bildschirmhöhe `half_extent_m` Meter zeigt.
static func pixels_per_meter(half_extent_m: float, screen_height_px: float) -> float:
	return (screen_height_px * 0.5) / maxf(half_extent_m, 0.001)

## Radius (m) des Kreises um die Bildmitte, der den ganzen Bildschirm abdeckt.
static func visible_radius_m(half_extent_m: float, screen_size: Vector2) -> float:
	var aspect: float = screen_size.x / maxf(screen_size.y, 1.0)
	return half_extent_m * sqrt(1.0 + aspect * aspect)

## Bildschirmrichtung von Nord (Welt −Z) bei Kamera-Yaw.
static func north_on_screen(yaw: float) -> Vector2:
	return Vector2(0.0, -1.0).rotated(yaw)

## "Schöne" Länge (m) für den Maßstabsbalken, die höchstens `max_px` Pixel breit wird.
static func scale_bar_meters(ppm: float, max_px: float) -> float:
	var steps: Array[float] = [5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0]
	var best: float = steps[0]
	for s in steps:
		if s * ppm <= max_px:
			best = s
	return best

# ─────────────────────────────────────────────
# Zeichnen
# ─────────────────────────────────────────────

class _Canvas extends Control:
	var view: WorldMapView = null

	func _draw() -> void:
		if view == null or not is_instance_valid(view._camera) or not is_instance_valid(view._player):
			return
		view._paint(self)

func _paint(c: Control) -> void:
	var size_px: Vector2 = c.size
	var screen_center := size_px * 0.5
	var center_world := _player_xz()
	var yaw := _camera.get_yaw()
	var extent := _camera.get_map_half_extent_m()
	var ppm := pixels_per_meter(extent, size_px.y)
	var radius := visible_radius_m(extent, size_px)

	c.draw_rect(Rect2(Vector2.ZERO, size_px), COL_BG)

	# Gelände (in Weltmetern relativ zur Spielerposition, gedreht + skaliert).
	c.draw_set_transform(screen_center, yaw, Vector2(ppm, ppm))
	_draw_tiles(c, _coarse, center_world, radius)
	if extent <= FINE_MAX_EXTENT_M:
		_draw_tiles(c, _fine, center_world, radius)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_settlements(c, size_px, screen_center, center_world, yaw, ppm, extent, radius)
	_draw_markers(c, size_px, screen_center, center_world, yaw, ppm, extent)
	_draw_player_arrow(c, screen_center, yaw)
	_draw_hud(c, size_px, yaw, ppm, center_world)

func _draw_tiles(c: Control, baker: WorldMapBaker, center_world: Vector2, radius: float) -> void:
	for coord in baker.tiles_in_radius(center_world, radius):
		var tex := baker.get_tile_texture(coord)
		if tex == null:
			continue
		var r := baker.tile_rect(coord)
		# +0.5 m Überlappung gegen Haarlinien zwischen Kacheln.
		c.draw_texture_rect(tex, Rect2(r.position - center_world - Vector2(0.25, 0.25), r.size + Vector2(0.5, 0.5)), false)

## Dörfer (Fläche + Haus-Symbol + Name + Typ) und Fernstraßen. Immer sichtbar, in jedem Maßstab —
## Dörfer sollen auf der Karte als solche erkennbar sein. Wird progressiv geplant (siehe
## SETTLEMENT_PREP_PER_FRAME); was schon berechnet ist, erscheint sofort.
func _draw_settlements(
	c: Control, size_px: Vector2, screen_center: Vector2, center_world: Vector2,
	yaw: float, ppm: float, extent: float, radius_m: float
) -> void:
	if _terrain == null:
		return
	var reg: SettlementRegistry = _terrain.get_settlements()
	var r: float = minf(radius_m, SETTLEMENT_MAX_SPAN_M * 0.5)
	var rect := Rect2(center_world - Vector2(r, r), Vector2(r, r) * 2.0)
	reg.prepare_edges_in_rect(rect.grow(SettlementSites.CELL * 0.25), SETTLEMENT_PREP_PER_FRAME)
	var screen_rect := Rect2(Vector2(-40, -40), size_px + Vector2(80, 80))

	# Straßen unter den Dörfern.
	for pts: PackedVector2Array in reg.known_roads_in_rect(rect.grow(40.0)):
		var line := PackedVector2Array()
		for wp: Vector2 in pts:
			line.append(world_to_screen(wp, center_world, yaw, ppm, screen_center))
		if line.size() >= 2:
			c.draw_polyline(line, COL_ROAD_MAP_EDGE, 5.0, true)
	for pts: PackedVector2Array in reg.known_roads_in_rect(rect.grow(40.0)):
		var line2 := PackedVector2Array()
		for wp2: Vector2 in pts:
			line2.append(world_to_screen(wp2, center_world, yaw, ppm, screen_center))
		if line2.size() >= 2:
			c.draw_polyline(line2, COL_ROAD_MAP, 2.5, true)

	var font := ThemeDB.fallback_font
	for site: Dictionary in reg.known_sites_in_rect(rect.grow(120.0)):
		var p: Vector2 = world_to_screen(site["center"] as Vector2, center_world, yaw, ppm, screen_center)
		var r_px: float = maxf(float(site["radius"]) * ppm, 10.0)
		if not screen_rect.grow(r_px).has_point(p):
			continue
		c.draw_circle(p, r_px, COL_VILLAGE_FILL)
		c.draw_arc(p, r_px, 0.0, TAU, 48, COL_VILLAGE_EDGE, 2.0, true)
		var tier: String = site["tier"]
		var s: float = 6.0 if tier == SettlementSites.TIER_HAMLET else (8.0 if tier == SettlementSites.TIER_VILLAGE else 11.0)
		_draw_site_icon(c, p, s, VillageKinds.kind_of_site(site).icon())
		var name_text: String = site["name"]
		var fs: int = 18 if tier != SettlementSites.TIER_HAMLET else 16
		var w: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		var label_y: float = minf(r_px, 60.0) + s + 8.0
		_draw_text(c, font, p + Vector2(-w * 0.5, label_y), name_text, fs)
		if extent <= 900.0:
			var tier_text: String = VillageKinds.tier_label(site)
			var tw: float = font.get_string_size(tier_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x
			_draw_text(c, font, p + Vector2(-tw * 0.5, label_y + 16.0), tier_text, 13)

## Dorf-Symbol je Dorf-Art (VillageKind.icon()). Neue Art → neuen Zweig ergänzen; unbekannte Symbole = Haus.
func _draw_site_icon(c: Control, p: Vector2, s: float, icon: String) -> void:
	if icon == "tree":
		var crown := PackedVector2Array([
			p + Vector2(-s, s * 0.2), p + Vector2(0.0, -s * 1.05), p + Vector2(s, s * 0.2),
		])
		c.draw_colored_polygon(crown, COL_VILLAGE_ICON)
		c.draw_polyline(PackedVector2Array([crown[0], crown[1], crown[2], crown[0]]), COL_VILLAGE_ICON_EDGE, 1.6, true)
		var trunk := PackedVector2Array([
			p + Vector2(-s * 0.18, s * 0.2), p + Vector2(s * 0.18, s * 0.2),
			p + Vector2(s * 0.18, s * 0.95), p + Vector2(-s * 0.18, s * 0.95),
		])
		c.draw_colored_polygon(trunk, COL_VILLAGE_ICON)
		return
	var house := PackedVector2Array([
		p + Vector2(-s, s * 0.1), p + Vector2(0.0, -s * 0.95), p + Vector2(s, s * 0.1),
		p + Vector2(s * 0.7, s * 0.1), p + Vector2(s * 0.7, s * 0.9), p + Vector2(-s * 0.7, s * 0.9),
		p + Vector2(-s * 0.7, s * 0.1),
	])
	c.draw_colored_polygon(house, COL_VILLAGE_ICON)
	c.draw_polyline(PackedVector2Array([house[0], house[1], house[2], house[3], house[4], house[5], house[6], house[0]]), COL_VILLAGE_ICON_EDGE, 1.6, true)

func _draw_markers(c: Control, size_px: Vector2, screen_center: Vector2, center_world: Vector2, yaw: float, ppm: float, extent: float) -> void:
	var font := ThemeDB.fallback_font
	var show_labels := extent <= LABEL_MAX_EXTENT_M
	var screen_rect := Rect2(Vector2(-20, -20), size_px + Vector2(40, 40))

	for n in get_tree().get_nodes_in_group("npcs"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var p := world_to_screen(Vector2((n as Node3D).global_position.x, (n as Node3D).global_position.z), center_world, yaw, ppm, screen_center)
		if not screen_rect.has_point(p):
			continue
		_draw_diamond(c, p, 7.0, COL_NPC)
		if show_labels:
			var label := _npc_label(n)
			if not label.is_empty():
				_draw_text(c, font, p + Vector2(10.0, 5.0), label, 15)

	for n in get_tree().get_nodes_in_group("player"):
		if n == _player or not (n is Node3D) or not is_instance_valid(n):
			continue
		var p2 := world_to_screen(Vector2((n as Node3D).global_position.x, (n as Node3D).global_position.z), center_world, yaw, ppm, screen_center)
		if not screen_rect.has_point(p2):
			continue
		c.draw_circle(p2, 6.0, COL_ARROW_EDGE)
		c.draw_circle(p2, 4.5, COL_PLAYER_OTHER)

func _npc_label(n: Node) -> String:
	var v: Variant = n.get("npc_display_name")
	return String(v) if v != null else ""

func _draw_diamond(c: Control, p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	c.draw_colored_polygon(pts, col)
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	c.draw_polyline(outline, COL_ARROW_EDGE, 1.5, true)

func _draw_player_arrow(c: Control, p: Vector2, yaw: float) -> void:
	# Blickrichtung des Modells auf dem Bildschirm; Pfeilspitze zeigt dorthin.
	var dir := _heading_world().rotated(yaw)
	var ang := dir.angle() + PI * 0.5   # Pfeil ist nach oben (0,-1) modelliert
	var base := PackedVector2Array([Vector2(0, -13), Vector2(9, 10), Vector2(0, 5), Vector2(-9, 10)])
	var pts := PackedVector2Array()
	for v in base:
		pts.append(p + v.rotated(ang))
	c.draw_colored_polygon(pts, COL_ARROW)
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	c.draw_polyline(outline, COL_ARROW_EDGE, 2.0, true)

func _draw_hud(c: Control, size_px: Vector2, yaw: float, ppm: float, center_world: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var margin := 16.0

	# Titel + Koordinaten + Biom (oben links).
	_draw_text(c, font, Vector2(margin, margin + 18.0), "Karte", 22)
	var coords := "X %d   Z %d" % [roundi(center_world.x), roundi(center_world.y)]
	_draw_text(c, font, Vector2(margin, margin + 40.0), coords, 15)
	if _terrain != null:
		var biome: BiomeDefinition = _terrain.get_biome_at(center_world.x, center_world.y)
		if is_instance_valid(biome) and not biome.display_name.is_empty():
			_draw_text(c, font, Vector2(margin, margin + 60.0), biome.display_name, 15)

	# Kompass (oben rechts): Kreis + N-Marke in Nordrichtung.
	var comp_c := Vector2(size_px.x - margin - 34.0, margin + 40.0)
	c.draw_circle(comp_c, 30.0, Color(0, 0, 0, 0.45))
	c.draw_arc(comp_c, 30.0, 0.0, TAU, 40, Color(1, 1, 1, 0.6), 1.5, true)
	var north := north_on_screen(yaw)
	c.draw_line(comp_c - north * 8.0, comp_c + north * 20.0, Color(0.95, 0.35, 0.30), 3.0, true)
	_draw_text(c, font, comp_c + north * 36.0 + Vector2(-5.0, 6.0), "N", 16)

	# Maßstabsbalken (unten links).
	var meters := scale_bar_meters(ppm, minf(size_px.x * 0.3, 220.0))
	var bar_px := meters * ppm
	var by := size_px.y - margin - 22.0
	c.draw_line(Vector2(margin, by), Vector2(margin + bar_px, by), COL_TEXT, 3.0)
	c.draw_line(Vector2(margin, by - 6.0), Vector2(margin, by + 6.0), COL_TEXT, 2.0)
	c.draw_line(Vector2(margin + bar_px, by - 6.0), Vector2(margin + bar_px, by + 6.0), COL_TEXT, 2.0)
	var unit := "%d m" % int(meters) if meters < 1000.0 else "%.1f km" % (meters / 1000.0)
	_draw_text(c, font, Vector2(margin, by - 10.0), unit, 14)

	if is_baking():
		_draw_text(c, font, Vector2(margin, size_px.y - margin - 44.0), "Karte wird gezeichnet …", 13)
	_draw_text(c, font, Vector2(size_px.x * 0.5 - 90.0, size_px.y - margin), "Heranzoomen zum Schließen", 13)

func _draw_text(c: Control, font: Font, pos: Vector2, text: String, font_size: int) -> void:
	c.draw_string(font, pos + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, COL_TEXT_SHADOW)
	c.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, COL_TEXT)
