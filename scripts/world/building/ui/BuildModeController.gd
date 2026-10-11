class_name BuildModeController
extends Node

## BuildModeController — der Baumodus: Geist vor dem Spieler, Drehen, Bauen, Abbrechen.
##
## ABLAUF (Einzelteil): Bau-Menü → start(piece_id). Jeden Frame: Zielpunkt →
## WorldService.preview_build() (dieselben Regeln wie das echte Bauen, siehe
## BuildPlacementRules) → Geist rastet aufs Raster ein und färbt sich. ✔ schickt
## build_place_requested; der Modus bleibt aktiv (mehrere Teile hintereinander bauen). ✕ beendet.
##
## ABLAUF (Haus): Bau-Menü → start_house(template_id). Jeden Frame: derselbe Zielpunkt, aber
## ZWEI getrennte Abfragen — WorldService.house_ghost_pieces() (reine Geometrie, KEINE
## Regelprüfung) positioniert einen Geist PRO Bauteil der Vorlage, WorldService.
## preview_house_build() (die tatsächliche All-oder-Nichts-Prüfung, siehe WorldBuildHandler)
## bestimmt nur die gemeinsame Farbe/Baubarkeit aller Geister. Derselbe Grund für die Trennung
## wie bei house_ghost_pieces() selbst: die volle Prüfung klont die Registry und wäre für die
## reine Positionierung unnötig teuer. ✔ schickt build_house_place_requested (ein Event, das
## ganze Haus zusammen); Steuerkreuz/Ebene/Drehen wirken identisch wie im Einzelteil-Modus.
##
## ZIELEN (FIX 2026-09-21, "ich muss immer meinen Spieler bewegen"):
##   • Modus "Blick" (Standard): der Geist sitzt dort, wo die Bildschirmmitte das Gelände trifft
##     (Player.get_view_ray + BuildAim.ground_hit) — Umschauen genügt, Laufen nicht nötig.
##   • Steuerkreuz: ▲▼◀▶ verschieben um eine Rasterzelle (relativ zur Kamera, auf Weltachsen
##     gerastet), "Höher/Tiefer" wechselt die Ebene (Y). Der erste Schritt FIXIERT die Position:
##     danach kann man frei umherschauen/-laufen, der Geist bleibt stehen. "Blick" geht zurück.
##   • Die Ebene bleibt zwischen Bauteilen erhalten (erst Boden, dann Wände auf gleicher Ebene).
##
## Die UI liest nur (preview_build über ctx.get_world()) — alle Änderungen gehen als Event über
## den EventBus an den WorldService.

## Größte horizontale Zielentfernung im Blick-Modus (WorldBuildHandler.REACH = 10 m).
const MAX_AIM_DISTANCE: float = 9.0
## Wie weit über den Kopf-Punkt hinaus der Blickstrahl gegen das Gelände geprüft wird (Meter).
const AIM_MARGIN: float = 4.0
const LOG_CAT := "BuildMode"

var _visuals: BuildModeVisuals
var _ctx: IUIContext
var _piece_id: String = ""
var _house_id: String = ""
var _rot_steps: int = 0
var _ghost: BuildGhost = null
## Ein Geist pro Bauteil der aktiven Hausvorlage, Index-gleich mit HouseTemplateDefinition.pieces
## bzw. dem Rückgabe-Array von WorldService.house_ghost_pieces() (beide iterieren in derselben
## Reihenfolge und überspringen dieselben unbekannten piece_ids — siehe start_house()).
var _house_ghosts: Array[BuildGhost] = []
var _active: bool = false
var _last_preview: Dictionary = {}
var _last_house_preview: Dictionary = {}
var _last_target: Vector3 = Vector3.ZERO
var _storey: int = 0
var _locked: bool = false
var _locked_target: Vector3 = Vector3.ZERO
## WASSERWAGEN: Farbnetz auf dem Gelände um den Geist, relativ zur Höhe, auf die ein Boden hier
## eingeebnet würde (LevelGauge.reference_height). Bleibt zwischen Bauteilen/Bausitzungen an.
const GAUGE_CELLS: int = 6          # ±12 m — der ganze Bauplatz um den Geist
const GAUGE_STAT_RADIUS: float = 4.0  # Kennzahlen nur für die unmittelbare Umgebung des Geists
var _level_on: bool = false
var _gauge: LevelGaugeOverlay = null

func setup(visuals: BuildModeVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx = ctx
	_visuals.rotate_button.pressed.connect(_on_rotate_pressed)
	_visuals.place_button.pressed.connect(_on_place_pressed)
	_visuals.cancel_button.pressed.connect(_on_cancel_pressed)
	_visuals.forward_button.pressed.connect(_on_nudge.bind(BuildAim.Dir.FORWARD))
	_visuals.back_button.pressed.connect(_on_nudge.bind(BuildAim.Dir.BACK))
	_visuals.left_button.pressed.connect(_on_nudge.bind(BuildAim.Dir.LEFT))
	_visuals.right_button.pressed.connect(_on_nudge.bind(BuildAim.Dir.RIGHT))
	_visuals.up_button.pressed.connect(_on_storey_pressed.bind(1))
	_visuals.down_button.pressed.connect(_on_storey_pressed.bind(-1))
	_visuals.follow_button.pressed.connect(_on_follow_pressed)
	_visuals.level_button.toggled.connect(_on_level_toggled)
	set_process(false)

func is_active() -> bool:
	return _active

## Startet den Baumodus für ein Bauteil (Aufruf aus BuildPanelController.piece_selected).
func start(piece_id: String) -> void:
	stop()
	var data: DataService = _ctx.get_data() if is_instance_valid(_ctx) else null
	var def: BuildPieceDefinition = data.get_build_piece(piece_id) if is_instance_valid(data) else null
	var player: Node3D = _ctx.get_local_player() if is_instance_valid(_ctx) else null
	if def == null or not is_instance_valid(player):
		AppLogger.log_warn("Baumodus: Definition '%s' oder Spieler fehlt." % piece_id, LOG_CAT)
		return
	_piece_id = piece_id
	_house_id = ""
	_rot_steps = 0
	_ghost = BuildGhost.new()
	_ghost.configure(def)
	_visuals.set_status(_storey, _locked)
	_visuals.set_level_on(_level_on)
	# In die Spielwelt hängen (Elternknoten des Spielers), nicht ins HUD.
	player.get_parent().add_child(_ghost)
	_active = true
	BuildModeState.set_source(BuildModeState.SOURCE_PLACING, true, _ctx.bus())
	_visuals.set_active(true)
	set_process(true)

## Startet den Baumodus für eine komplette Hausvorlage (Aufruf aus BuildPanelController.
## house_selected). Ein BuildGhost pro Bauteil der Vorlage — dieselbe Geometrie-Quelle
## (BuildPieceDefinition, über configure()) wie beim Einzelteil, nur eben mehrfach.
func start_house(template_id: String) -> void:
	stop()
	var data: DataService = _ctx.get_data() if is_instance_valid(_ctx) else null
	var house: HouseTemplateDefinition = data.get_house_template(template_id) if is_instance_valid(data) else null
	var player: Node3D = _ctx.get_local_player() if is_instance_valid(_ctx) else null
	if house == null or house.pieces.is_empty() or not is_instance_valid(player):
		AppLogger.log_warn("Baumodus: Hausvorlage '%s' oder Spieler fehlt." % template_id, LOG_CAT)
		return
	_house_id = template_id
	_piece_id = ""
	_rot_steps = 0
	var parent: Node = player.get_parent()
	for raw_entry: Dictionary in house.pieces:
		var def: BuildPieceDefinition = data.get_build_piece(String(raw_entry.get("piece_id", "")))
		if def == null:
			continue
		var g := BuildGhost.new()
		g.configure(def)
		parent.add_child(g)
		_house_ghosts.append(g)
	_visuals.set_status(_storey, _locked)
	_visuals.set_level_on(_level_on)
	_active = true
	BuildModeState.set_source(BuildModeState.SOURCE_PLACING, true, _ctx.bus())
	_visuals.set_active(true)
	set_process(true)

func stop() -> void:
	_active = false
	BuildModeState.set_source(BuildModeState.SOURCE_PLACING, false, _ctx.bus() if is_instance_valid(_ctx) else null)
	set_process(false)
	_last_preview = {}
	_last_house_preview = {}
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	for g in _house_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_house_ghosts = []
	_piece_id = ""
	_house_id = ""
	if is_instance_valid(_gauge):
		_gauge.queue_free()
	_gauge = null
	if is_instance_valid(_visuals):
		_visuals.set_active(false)
		_visuals.set_reason("")

func _exit_tree() -> void:
	if is_instance_valid(_gauge):
		_gauge.queue_free()
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	for g in _house_ghosts:
		if is_instance_valid(g):
			g.queue_free()

func _process(_delta: float) -> void:
	if not _active:
		return
	if not _house_id.is_empty():
		_process_house()
	else:
		_process_piece()

func _process_piece() -> void:
	var player: Node3D = _ctx.get_local_player()
	var world: WorldService = _ctx.get_world()
	if not is_instance_valid(player) or not is_instance_valid(world) or not is_instance_valid(_ghost):
		stop()
		return

	_last_target = _locked_target if _locked else _aim_target(player, world)
	_last_preview = world.preview_build(_ctx.get_local_player_id(), _piece_id, _last_target, _rot_steps, _storey)

	var center: Vector2 = _last_preview["center"]
	var y: float = float(_last_preview["y"]) if bool(_last_preview["ok"]) else _ground_y(world, center) + float(_storey) * BuildGrid.LEVEL_HEIGHT
	_ghost.apply_state(Vector3(center.x, y, center.y), float(_last_preview["yaw"]), BuildGhost.state_from_preview(_last_preview))
	_update_gauge(player, world, center)

	var ok: bool = bool(_last_preview["ok"])
	var affordable: bool = bool(_last_preview["affordable"])
	_visuals.set_place_enabled(ok and affordable)
	if not ok:
		_visuals.set_reason(BuildPlacementRules.reason_text(String(_last_preview["reason"])))
	elif not affordable:
		_visuals.set_reason(BuildPlacementRules.reason_text("no_materials"))
	else:
		_visuals.set_reason("")

## Wie _process_piece(), aber für eine ganze Hausvorlage: Geometrie (house_ghost_pieces, jeden
## Frame, billig) und Baubarkeit (preview_house_build, klont die Registry, siehe Klassenkommentar
## oben) kommen aus getrennten Aufrufen — ALLE Geister teilen sich trotzdem eine gemeinsame
## Farbe/einen gemeinsamen Grund, das Haus wird als Ganzes gebaut oder gar nicht.
func _process_house() -> void:
	var player: Node3D = _ctx.get_local_player()
	var world: WorldService = _ctx.get_world()
	if not is_instance_valid(player) or not is_instance_valid(world) or _house_ghosts.is_empty():
		stop()
		return

	_last_target = _locked_target if _locked else _aim_target(player, world)
	_last_house_preview = world.preview_house_build(
		_ctx.get_local_player_id(), _house_id, _last_target, _rot_steps, _storey
	)
	var geometry: Array[Dictionary] = world.house_ghost_pieces(_house_id, _last_target, _rot_steps, _storey)

	var state: int = BuildGhost.state_from_preview(_last_house_preview)
	for i in mini(_house_ghosts.size(), geometry.size()):
		var g: BuildGhost = _house_ghosts[i]
		if not is_instance_valid(g):
			continue
		var pos: Vector3 = geometry[i]["pos"]
		g.apply_state(pos, float(geometry[i]["yaw"]), state)
	_update_gauge(player, world, Vector2(_last_target.x, _last_target.z))

	var ok: bool = bool(_last_house_preview.get("ok", false))
	var affordable: bool = bool(_last_house_preview.get("affordable", false))
	_visuals.set_place_enabled(ok and affordable)
	if not ok:
		_visuals.set_reason(BuildPlacementRules.reason_text(String(_last_house_preview.get("reason", ""))))
	elif not affordable:
		_visuals.set_reason(BuildPlacementRules.reason_text("no_materials"))
	else:
		_visuals.set_reason("")

## Zielpunkt im Blick-Modus: Bildschirmmitte ↔ Gelände, auf MAX_AIM_DISTANCE um den Spieler begrenzt.
## Ohne Geländetreffer (Blick zum Horizont/Himmel): maximale Entfernung in Blickrichtung.
func _aim_target(player: Node3D, world: WorldService) -> Vector3:
	var ray: Dictionary = player.call("get_view_ray")
	var origin: Vector3 = ray["origin"]
	var dir: Vector3 = ray["dir"]
	var ppos: Vector3 = player.global_position
	var terrain: TerrainField = world.get_terrain()

	var hit: Variant = null
	if terrain != null and dir.length_squared() > 0.000001:
		# Nur der Bereich um den Spieler zählt: ab kurz vor dem Kopf-Punkt bis Reichweite + Rand.
		var t_head: float = maxf(0.0, (ppos + Vector3(0.0, 1.6, 0.0) - origin).dot(dir.normalized()))
		hit = BuildAim.ground_hit(origin, dir, terrain.get_height_at,
			maxf(0.0, t_head - 2.0), t_head + MAX_AIM_DISTANCE + AIM_MARGIN)

	var target: Vector3
	if hit is Vector3:
		target = hit
	else:
		var flat := Vector3(dir.x, 0.0, dir.z)
		flat = flat.normalized() if flat.length_squared() > 0.000001 else Vector3.FORWARD
		target = ppos + flat * MAX_AIM_DISTANCE
	return BuildAim.clamp_to_reach(target, ppos, MAX_AIM_DISTANCE)

## Steuerkreuz: eine Rasterzelle in Kamerarichtung. Der erste Schritt fixiert den Geist an der
## aktuellen Position (kein Nachlaufen mehr) — sonst würde jeder Blickwechsel den Schritt zunichte machen.
func _on_nudge(direction: int) -> void:
	if not _active or not is_instance_valid(_ctx):
		return
	var player: Node3D = _ctx.get_local_player()
	if not is_instance_valid(player):
		return
	var view_dir: Vector3 = (player.call("get_view_ray") as Dictionary)["dir"]
	if not _locked:
		_locked = true
		_locked_target = _last_target
	_locked_target += BuildAim.nudge_vector(view_dir, direction) * BuildGrid.CELL
	_visuals.set_status(_storey, _locked)

func _on_storey_pressed(delta: int) -> void:
	_storey = clampi(_storey + delta, 0, BuildGrid.MAX_STOREY)
	_visuals.set_status(_storey, _locked)

func _on_level_toggled(on: bool) -> void:
	_level_on = on
	_visuals.set_level_on(on)
	if not on and is_instance_valid(_gauge):
		_gauge.hide_view()

## Wasserwagen: Farbnetz um `center` relativ zur Einebnungshöhe dieser Zelle + Kennzahlen im HUD.
func _update_gauge(player: Node3D, world: WorldService, center: Vector2) -> void:
	if not _level_on:
		return
	var terrain: TerrainField = world.get_terrain()
	if terrain == null:
		return
	if not is_instance_valid(_gauge):
		_gauge = LevelGaugeOverlay.new()
		player.get_parent().add_child(_gauge)
	var ref_y: float = LevelGauge.reference_height(terrain.get_height_at, center)
	var stats: Dictionary = _gauge.update_view(terrain.get_height_at, center, ref_y, GAUGE_CELLS, GAUGE_STAT_RADIUS)
	_visuals.set_level_text(LevelGauge.summary_text(stats))

func _on_follow_pressed() -> void:
	_locked = false
	_visuals.set_status(_storey, _locked)

## ✕ beendet den Baumodus UND setzt Ebene/Fixierung zurück (stop() allein behält sie, damit ein
## Wechsel des Bauteils im Menü — start() → stop() — die Ebene nicht verliert).
func _on_cancel_pressed() -> void:
	_storey = 0
	_locked = false
	stop()

func _on_rotate_pressed() -> void:
	_rot_steps = posmod(_rot_steps + 1, 4)

func _on_place_pressed() -> void:
	if not _active:
		return
	if not _house_id.is_empty():
		_place_house()
	else:
		_place_piece()

func _place_piece() -> void:
	if _last_preview.is_empty():
		return
	if not (bool(_last_preview["ok"]) and bool(_last_preview["affordable"])):
		return
	var bus: IEventBus = _ctx.bus()
	if bus == null:
		return
	bus.world().emit_build_place_requested(_ctx.get_local_player_id(), _piece_id, _last_target, _rot_steps, _storey)

## Schickt das GANZE Haus als eine Anfrage (build_house_place_requested) — WorldBuildHandler.
## place_house() platziert es serverseitig ebenfalls all-or-nothing, siehe dortiger
## Klassenkommentar "Häuser/Vorlagen". Der Modus bleibt aktiv (dieselbe Vorlage nochmal bauen),
## wie im Einzelteil-Modus.
func _place_house() -> void:
	if _last_house_preview.is_empty():
		return
	if not (bool(_last_house_preview.get("ok", false)) and bool(_last_house_preview.get("affordable", false))):
		return
	var bus: IEventBus = _ctx.bus()
	if bus == null:
		return
	bus.world().emit_build_house_place_requested(_ctx.get_local_player_id(), _house_id, _last_target, _rot_steps, _storey)

func _ground_y(world: WorldService, center: Vector2) -> float:
	var terrain: TerrainField = world.get_terrain()
	return terrain.get_height_at(center.x, center.y) if terrain != null else 0.0
