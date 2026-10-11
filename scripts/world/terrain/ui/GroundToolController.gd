class_name GroundToolController
extends Node

## GroundToolController — "Graben", "Füllen" und "Leiter" mit der Schaufel im Werkzeug-Slot.
##
## Sichtbar nur, wenn die Schaufel im Werkzeug-Slot ausgerüstet ist. Ein Tipp startet eine
## normale Interaktion (Fortschrittsbalken, Spieler beschäftigt, Abbruch bei Bewegung — alles
## vom InteractionExecutor); erst NACH Ablauf wird der Wunsch als Event abgeschickt:
##   bus().world().emit_terrain_edit_requested(player_id, mode, target)
## Die Ausführung samt Prüfungen (Reichweite, Erde, Regeln, Solo) liegt beim WorldService.
##
## Zielpunkt: DIST Meter vor dem Spieler (Player.get_ground_target()). Kein Zielen nötig —
## per Touch der einfachste Weg; der Spieler richtet sich durch Laufen aus.
## "Leiter" stellt an der Wand vor dem Spieler eine Leiter auf (Wunsch ladder_place_requested,
## Ausführung: WorldService.request_ladder_place → LadderPlanner). Ohne Wand: Meldung.
## Der Schaufel-Tempo-Bonus kommt über action.speed_stat_id (ToolDefinition "dig_speed").
##
## VORSCHAU (Wunsch "wie beim Antippen highlighten, wo & wie viel gegraben/gefüllt wird"):
## solange die Schaufel ausgerüstet, keine Interaktion aktiv ist UND die jeweilige
## Einstellung an ist (SettingsService "dig_preview"/"fill_preview", Settings.gd-Panel),
## sitzen zwei TerrainEditGhost-Scheiben (Graben/Füllen getrennt togglebar) am selben
## Zielpunkt wie ein echter Grab-/Füllvorgang (get_ground_target) und zeigen per
## WorldService.preview_terrain_edit() dieselbe Fläche/Gültigkeit, die ein Tipp auf den
## jeweiligen Button gerade auslösen würde — reine Lese-Vorschau, keine Mutation.

const TOOL_ID: String = "tool_shovel"
## Sense (2026-10-06, "Gras mit einer Sense abbauen"): Knopf "Mähen" statt Graben/Füllen.
const SCYTHE_ID: String = "tool_scythe"
const MOW_DURATION: float = 1.1
const MOW_SPEED_STAT: String = "mow_speed"
const DURATION: float = 1.4
const LADDER_DURATION: float = 1.2
const TARGET_DISTANCE: float = 2.2
const SPEED_STAT: String = "dig_speed"
const LOG_CAT := "GroundTool"

const SETTING_DIG_PREVIEW: String = "dig_preview"
const SETTING_FILL_PREVIEW: String = "fill_preview"
## Getrennte Höhen-Offsets, damit sich Graben- und Füll-Geist bei identischer Pinselfläche
## nicht im selben Z-Buffer-Pixel beißen (Z-Fighting), auch wenn beide gleichzeitig sichtbar sind.
const PREVIEW_Y_DIG: float = 0.02
const PREVIEW_Y_FILL: float = 0.05
const PREVIEW_Y_PLANE: float = 0.12

## EBNEN-MODUS (Wunsch "Grab/Füllmodus, der auf eine planare Ebene abzielt"): Schalter "Ebene".
## Im Modus gibt es eine waagerechte Ebene (_plane_y, per ⌖ auf die Bodenhöhe am Zielpunkt
## gesetzt, per ▲▼ in PLANE_NUDGE-Schritten verschiebbar). "Abtragen"/"Auffüllen" (die
## Graben-/Füll-Knöpfe) bewegen den Boden nur zur Ebene hin und nie darüber hinaus, "Ebnen"
## macht beides in einem Zug. Der Wasserwagen (LevelGaugeOverlay) färbt dabei den Boden um den
## Zielpunkt nach Abweichung von der Ebene. Ausführung samt Material: WorldService.request_terrain_plane.
const PLANE_NUDGE: float = 0.25
## Halbkante des Wasserwagen-Netzes in Zellen (4 → ±8 m, deckt den Pinsel von 5 m ab).
const GAUGE_CELLS: int = 4

var _visuals: GroundToolVisuals
var _ctx: IUIContext
var _busy: bool = false
var _dig_ghost: TerrainEditGhost = null
var _fill_ghost: TerrainEditGhost = null
var _plane_ghost: TerrainEditGhost = null
var _gauge: LevelGaugeOverlay = null
var _plane_mode: bool = false
var _plane_y: float = NAN

func setup(visuals: GroundToolVisuals, ctx: IUIContext) -> void:
	_visuals = visuals
	_ctx = ctx
	_visuals.dig_button.pressed.connect(_on_dig_pressed)
	_visuals.fill_button.pressed.connect(_on_fill_pressed)
	_visuals.ladder_button.pressed.connect(_on_ladder_pressed)
	_visuals.mow_button.pressed.connect(_on_mow_pressed)
	_visuals.plane_toggle_button.toggled.connect(_on_plane_toggled)
	_visuals.plane_set_button.pressed.connect(_on_plane_set_pressed)
	_visuals.plane_up_button.pressed.connect(_on_plane_nudge.bind(PLANE_NUDGE))
	_visuals.plane_down_button.pressed.connect(_on_plane_nudge.bind(-PLANE_NUDGE))
	_visuals.plane_level_button.pressed.connect(_on_plane_level_pressed)

func _ready() -> void:
	if not is_instance_valid(_ctx):
		return
	var eq: EquipmentService = _ctx.get_equipment()
	if is_instance_valid(eq) and not eq.equipment_changed.is_connected(_on_equipment_changed):
		eq.equipment_changed.connect(_on_equipment_changed)
	var bus: IEventBus = _ctx.bus()
	if bus != null:
		bus.world().interaction_started.connect(_on_interaction_started)
		bus.world().interaction_finished.connect(_on_interaction_ended)
		bus.world().interaction_cancelled.connect(_on_interaction_ended)
	_refresh()

func _exit_tree() -> void:
	if is_instance_valid(_dig_ghost):
		_dig_ghost.queue_free()
	if is_instance_valid(_fill_ghost):
		_fill_ghost.queue_free()
	if is_instance_valid(_plane_ghost):
		_plane_ghost.queue_free()
	if is_instance_valid(_gauge):
		_gauge.queue_free()
	if not is_instance_valid(_ctx):
		return
	var eq: EquipmentService = _ctx.get_equipment()
	if is_instance_valid(eq) and eq.equipment_changed.is_connected(_on_equipment_changed):
		eq.equipment_changed.disconnect(_on_equipment_changed)

func _process(_delta: float) -> void:
	_update_preview()

# ─────────────────────────────────────────────

func _on_mow_pressed() -> void:
	if _busy or not is_instance_valid(_ctx) or _ctx.bus() == null:
		return
	var player: Node3D = _ctx.get_local_player()
	if not is_instance_valid(player) or not player.has_method("get_ground_target"):
		return
	var target: Vector3 = player.call("get_ground_target", TARGET_DISTANCE)
	_ctx.bus().ui().emit_interaction_execute_requested(
		build_mow_action(target, _ctx.get_local_player_id(), _ctx.get_local_peer_id(), _ctx.bus())
	)

## Mäh-Aktion (statisch/rein, testbar ohne UI). Das Ergebnis entscheidet der WorldService.
static func build_mow_action(
	target: Vector3, player_id: String, peer_id: int, bus: IEventBus
) -> InteractableAction:
	var action := InteractableAction.new("mow_ground", "Mähen")
	action.duration = MOW_DURATION
	action.speed_stat_id = MOW_SPEED_STAT
	action.peer_id = peer_id
	action.on_complete = func(_completed_peer: int) -> void:
		bus.world().emit_grass_cut_requested(player_id, target)
	return action

func _on_dig_pressed() -> void:
	if _plane_mode:
		_start_plane(TerrainPlanePlanner.DIR_DOWN, "Abtragen")
		return
	_start(WorldTerrainEditor.MODE_DIG, "Graben")

func _on_fill_pressed() -> void:
	if _plane_mode:
		_start_plane(TerrainPlanePlanner.DIR_UP, "Auffüllen")
		return
	_start(WorldTerrainEditor.MODE_FILL, "Füllen")

# ─────────────────────────────────────────────
# Ebnen-Modus — siehe Klassenkommentar (EBNEN-MODUS)
# ─────────────────────────────────────────────

func _on_plane_toggled(on: bool) -> void:
	_plane_mode = on
	if is_instance_valid(_visuals):
		_visuals.set_plane_mode(on)
	if not on:
		_hide_plane_visuals()
	_update_plane_text()

## ⌖: Ebene auf die Bodenhöhe am Zielpunkt (Pinselmitte = Gitterpunkt) setzen.
func _on_plane_set_pressed() -> void:
	var world: WorldService = _ctx.get_world() if is_instance_valid(_ctx) else null
	var player: Node3D = _ctx.get_local_player() if is_instance_valid(_ctx) else null
	if not is_instance_valid(world) or not is_instance_valid(player) or not player.has_method("get_ground_target"):
		return
	var terrain: TerrainField = world.get_terrain()
	if terrain == null:
		return
	var target: Vector3 = player.call("get_ground_target", TARGET_DISTANCE)
	var center: Vector2 = TerrainEditLayer.lattice_to_world(TerrainEditLayer.world_to_lattice(target.x, target.z))
	_plane_y = terrain.get_height_at(center.x, center.y)
	_update_plane_text()

func _on_plane_nudge(delta: float) -> void:
	if is_nan(_plane_y):
		return
	_plane_y += delta
	_update_plane_text()

func _on_plane_level_pressed() -> void:
	_start_plane(TerrainPlanePlanner.DIR_BOTH, "Ebnen")

func _start_plane(direction: String, label: String) -> void:
	if _busy or not is_instance_valid(_ctx) or _ctx.bus() == null:
		return
	if is_nan(_plane_y):
		_ctx.bus().ui().emit_notification_requested(WorldTerrainEditor.reason_text("no_plane"))
		return
	var player: Node3D = _ctx.get_local_player()
	if not is_instance_valid(player) or not player.has_method("get_ground_target"):
		AppLogger.log_warn("GroundTool: kein lokaler Player mit get_ground_target().", LOG_CAT)
		return
	var target: Vector3 = player.call("get_ground_target", TARGET_DISTANCE)
	var action: InteractableAction = build_plane_action(
		direction, label, target, _plane_y,
		_ctx.get_local_player_id(), _ctx.get_local_peer_id(), _ctx.bus()
	)
	_ctx.bus().ui().emit_interaction_execute_requested(action)

## Interaktions-Aktion "Ebnen/Abtragen/Auffüllen" — rein/statisch, testbar ohne UI.
static func build_plane_action(
	direction: String, label: String, target: Vector3, plane_y: float,
	player_id: String, peer_id: int, bus: IEventBus
) -> InteractableAction:
	var action := InteractableAction.new("plane_%s_ground" % direction, label)
	action.duration = DURATION
	action.speed_stat_id = SPEED_STAT
	action.peer_id = peer_id
	action.on_complete = func(_completed_peer: int) -> void:
		bus.world().emit_terrain_plane_requested(player_id, target, plane_y, direction)
	return action

## "Ebene 3,20 m" (bzw. Hinweis, solange keine gesetzt ist) — Wasserwagen-Kennzahlen folgen
## laufend aus _update_plane_preview().
func _update_plane_text(gauge_text: String = "") -> void:
	if not is_instance_valid(_visuals):
		return
	if is_nan(_plane_y):
		_visuals.set_plane_text("Ebene festlegen: ⌖ setzt sie auf die Höhe am Ziel")
		return
	var text: String = "Ebene %s m" % ("%.2f" % _plane_y).replace(".", ",")
	_visuals.set_plane_text(text if gauge_text.is_empty() else "%s\n%s" % [text, gauge_text])

func _on_ladder_pressed() -> void:
	if _busy or not is_instance_valid(_ctx) or _ctx.bus() == null:
		return
	var player: Node3D = _ctx.get_local_player()
	if not is_instance_valid(player) or not player.has_method("get_facing_direction"):
		AppLogger.log_warn("GroundTool: kein lokaler Player mit get_facing_direction().", LOG_CAT)
		return
	var action: InteractableAction = build_ladder_action(
		player.global_position, player.call("get_facing_direction"),
		_ctx.get_local_player_id(), _ctx.get_local_peer_id(), _ctx.bus()
	)
	_ctx.bus().ui().emit_interaction_execute_requested(action)

## Interaktions-Aktion "Leiter aufstellen" — rein/statisch, testbar ohne UI.
static func build_ladder_action(
	origin: Vector3, facing: Vector3, player_id: String, peer_id: int, bus: IEventBus
) -> InteractableAction:
	var action := InteractableAction.new("place_ladder", "Leiter aufstellen")
	action.duration = LADDER_DURATION
	action.peer_id = peer_id
	action.on_complete = func(_completed_peer: int) -> void:
		bus.world().emit_ladder_place_requested(player_id, origin, facing)
	return action

func _start(mode: String, label: String) -> void:
	if _busy or not is_instance_valid(_ctx) or _ctx.bus() == null:
		return
	var player: Node3D = _ctx.get_local_player()
	if not is_instance_valid(player) or not player.has_method("get_ground_target"):
		AppLogger.log_warn("GroundTool: kein lokaler Player mit get_ground_target().", LOG_CAT)
		return
	var target: Vector3 = player.call("get_ground_target", TARGET_DISTANCE)
	var action: InteractableAction = build_action(
		mode, label, target, _ctx.get_local_player_id(), _ctx.get_local_peer_id(), _ctx.bus()
	)
	_ctx.bus().ui().emit_interaction_execute_requested(action)

## Baut die Interaktions-Aktion. Statisch/rein, damit testbar ohne UI.
## on_complete schickt den Wunsch ab — die Welt entscheidet, ob er gelingt.
static func build_action(
	mode: String, label: String, target: Vector3,
	player_id: String, peer_id: int, bus: IEventBus
) -> InteractableAction:
	var action := InteractableAction.new("%s_ground" % mode, label)
	action.duration = DURATION
	action.speed_stat_id = SPEED_STAT
	action.peer_id = peer_id
	action.on_complete = func(_completed_peer: int) -> void:
		bus.world().emit_terrain_edit_requested(player_id, mode, target)
	return action

# ─────────────────────────────────────────────
# Vorschau (TerrainEditGhost) — siehe Klassenkommentar
# ─────────────────────────────────────────────

func _update_preview() -> void:
	if _busy or not _shovel_equipped():
		_hide_ghosts()
		return
	var player: Node3D = _ctx.get_local_player() if is_instance_valid(_ctx) else null
	var world: WorldService = _ctx.get_world() if is_instance_valid(_ctx) else null
	if not is_instance_valid(player) or not is_instance_valid(world) or not player.has_method("get_ground_target"):
		_hide_ghosts()
		return
	_ensure_ghosts(player)
	var target: Vector3 = player.call("get_ground_target", TARGET_DISTANCE)
	if _plane_mode:
		# Im Ebnen-Modus ersetzen Ebenen-Geist + Wasserwagen die Graben-/Füll-Scheiben.
		_dig_ghost.visible = false
		_fill_ghost.visible = false
		_update_plane_preview(world, player, target)
		return
	_hide_plane_visuals()
	_update_one_preview(_dig_ghost, world, WorldTerrainEditor.MODE_DIG, target, PREVIEW_Y_DIG, SETTING_DIG_PREVIEW)
	_update_one_preview(_fill_ghost, world, WorldTerrainEditor.MODE_FILL, target, PREVIEW_Y_FILL, SETTING_FILL_PREVIEW)

## Ebenen-Geist (Fläche/Gültigkeit des nächsten Ebnen-Zugs) + Wasserwagen um den Pinselmittelpunkt,
## relativ zur Ebene. Ohne gesetzte Ebene: nichts anzeigen.
func _update_plane_preview(world: WorldService, player: Node3D, target: Vector3) -> void:
	var terrain: TerrainField = world.get_terrain()
	if is_nan(_plane_y) or terrain == null:
		_hide_plane_visuals()
		return
	var center: Vector2 = TerrainEditLayer.lattice_to_world(TerrainEditLayer.world_to_lattice(target.x, target.z))
	var preview: Dictionary = world.preview_terrain_plane(_ctx.get_local_player_id(), target, _plane_y)
	if String(preview.get("reason", "")) in ["coop_unsupported", "no_player", "too_far"]:
		_hide_plane_visuals()
		return
	if not is_instance_valid(_plane_ghost):
		_plane_ghost = TerrainEditGhost.new()
		_plane_ghost.configure(WorldTerrainEditor.BRUSH_RADIUS, WorldTerrainEditor.CORE_RADIUS, TerrainEditGhost.Mode.PLANE)
		player.get_parent().add_child(_plane_ghost)
	if not is_instance_valid(_gauge):
		_gauge = LevelGaugeOverlay.new()
		player.get_parent().add_child(_gauge)
	_plane_ghost.visible = true
	_plane_ghost.apply_state(
		Vector3(center.x, terrain.get_height_at(center.x, center.y) + PREVIEW_Y_PLANE, center.y),
		bool(preview.get("ok", false)))
	var stats: Dictionary = _gauge.update_view(
		terrain.get_height_at, center, _plane_y, GAUGE_CELLS, WorldTerrainEditor.BRUSH_RADIUS)
	_update_plane_text(LevelGauge.summary_text(stats))

func _hide_plane_visuals() -> void:
	if is_instance_valid(_plane_ghost):
		_plane_ghost.visible = false
	if is_instance_valid(_gauge):
		_gauge.hide_view()

## Legt die beiden Geister beim ersten Gebrauch an — erst hier, weil der lokale Spieler
## (Elternknoten der Geister, analog BuildGhost) bei _ready() noch nicht existieren muss
## (Welt evtl. noch nicht geladen).
func _ensure_ghosts(player: Node3D) -> void:
	if is_instance_valid(_dig_ghost) and is_instance_valid(_fill_ghost):
		return
	var parent: Node = player.get_parent()
	if not is_instance_valid(_dig_ghost):
		_dig_ghost = TerrainEditGhost.new()
		_dig_ghost.configure(WorldTerrainEditor.BRUSH_RADIUS, WorldTerrainEditor.CORE_RADIUS, TerrainEditGhost.Mode.DIG)
		parent.add_child(_dig_ghost)
	if not is_instance_valid(_fill_ghost):
		_fill_ghost = TerrainEditGhost.new()
		_fill_ghost.configure(WorldTerrainEditor.BRUSH_RADIUS, WorldTerrainEditor.CORE_RADIUS, TerrainEditGhost.Mode.FILL)
		parent.add_child(_fill_ghost)

func _update_one_preview(
	ghost: TerrainEditGhost, world: WorldService, mode: String, target: Vector3,
	y_offset: float, setting_key: String
) -> void:
	if not is_instance_valid(ghost):
		return
	if not _get_bool_setting(setting_key):
		ghost.visible = false
		return
	var preview: Dictionary = world.preview_terrain_edit(_ctx.get_local_player_id(), mode, target)
	# "coop_unsupported"/"no_player"/"too_far": kein sinnvoller Ort (Vector2.ZERO) — lieber
	# gar nichts zeigen, als einen Geist im Weltursprung aufblitzen zu lassen.
	if String(preview.get("reason", "")) in ["coop_unsupported", "no_player", "too_far"]:
		ghost.visible = false
		return
	var center: Vector2 = preview.get("center", Vector2(target.x, target.z))
	var terrain: TerrainField = world.get_terrain()
	var ground_y: float = terrain.get_height_at(center.x, center.y) if terrain != null else target.y
	ghost.visible = true
	ghost.apply_state(Vector3(center.x, ground_y + y_offset, center.y), bool(preview.get("ok", false)))

func _hide_ghosts() -> void:
	if is_instance_valid(_dig_ghost):
		_dig_ghost.visible = false
	if is_instance_valid(_fill_ghost):
		_fill_ghost.visible = false
	_hide_plane_visuals()

func _get_bool_setting(key: String) -> bool:
	if not is_instance_valid(_ctx):
		return true
	var settings: SettingsService = _ctx.get_settings()
	return bool(settings.get_setting(key)) if is_instance_valid(settings) else true

# ─────────────────────────────────────────────

func _on_equipment_changed(_slot: String, _item: ItemDefinition, player_id: String) -> void:
	if is_instance_valid(_ctx) and player_id == _ctx.get_local_player_id():
		_refresh()

func _on_interaction_started(_id: String, _label: String, _duration: float) -> void:
	_busy = true
	_refresh()

func _on_interaction_ended(_id: String, _label: String) -> void:
	_busy = false
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(_visuals):
		return
	_visuals.set_active(_shovel_equipped())
	_visuals.set_mow_active(_scythe_equipped())
	_visuals.set_busy(_busy)

func _shovel_equipped() -> bool:
	if not is_instance_valid(_ctx):
		return false
	var eq: EquipmentService = _ctx.get_equipment()
	if not is_instance_valid(eq):
		return false
	var item: ItemDefinition = eq.get_equipped(EquipmentService.SLOT_TOOL, _ctx.get_local_player_id())
	return is_instance_valid(item) and item.id == TOOL_ID

func _scythe_equipped() -> bool:
	if not is_instance_valid(_ctx):
		return false
	var eq: EquipmentService = _ctx.get_equipment()
	if not is_instance_valid(eq):
		return false
	var item: ItemDefinition = eq.get_equipped(EquipmentService.SLOT_TOOL, _ctx.get_local_player_id())
	return is_instance_valid(item) and item.id == SCYTHE_ID
