class_name BuildPiece
extends StaticBody3D

## BuildPiece — die 3D-ANSICHT eines gebauten Bauteils (Boden, Wand, ...).
##
## Die Wahrheit über das Bauwerk sind die Records in BuildRegistry; dieser Node wird von
## WorldBuildHandler beim Laden des Chunks erzeugt und beim Entladen wieder entfernt. Er
## hält deshalb KEINEN eigenen Zustand — alles kommt aus der Spawn-Config und der
## BuildPieceDefinition. Dadurch ist er beliebig oft neu erzeugbar (Chunk-Streaming,
## Laden eines Spielstands).
##
## Spawn-Config: {piece_id: String, key: String, yaw: float}. Position = Basis-Oberkante
## des Bauteils (Böden: Oberkante; Wände: Boden, auf dem sie stehen).
##
## Geometrie: BuildPieceDefinition.get_box_size()/get_box_center() (gemeinsame Quelle mit dem
## Geist im Baumodus). skirt versteckt Lücken auf unebenem Boden.
## ERWEITERUNG: neue Bauteil-Arten (Dach, Tür, Fenster) → neuer Zweig in _build_geometry().
##
## Interaktion: "Abreißen" (Autorität) → EventBus build_remove_requested → WorldService.
## Schmiede-Stationen (BuildPieceDefinition.station_kind) haben zusätzlich "Benutzen" — eine
## zweite, koexistierende InteractableComponent (ADR-035-Muster, wie PlayerTrade). Siehe
## _on_station_used(): lokal öffnet das Panel, die Autorität bekommt den Zugang gemeldet.
## Nicht gepoolt (siehe EntityOrchestrator): Geometrie hängt an der Definition.

const LOG_CAT := "BuildPiece"
const ACTION_DISMANTLE: String = "dismantle_piece"
## Aktion "Benutzen" an einer Schmiede-Station (Hochofen/Amboss). Wie ACTION_DISMANTLE ein
## stabiler String, weil InteractableComponent die Aktion über data.id zurückmeldet.
const ACTION_USE_STATION: String = "use_station"
## Strukturnutzung (BuildPieceDefinition.use_*), z.B. Wasser schöpfen am Brunnen.
const ACTION_USE_STRUCTURE: String = "use_structure"
## Anzeigenamen der Stationen für Interaktions-Label/Panel-Titel (station_kind → Name).
const STATION_NAMES: Dictionary = {"furnace": "Hochofen", "anvil": "Amboss"}
const COL_MISSING := Color(0.85, 0.15, 0.15)
## Gruppe aller Licht spendenden Bauteile (Straßenlaternen) — Haken für einen Tag/Nacht-Zyklus.
const GROUP_NIGHT_LIGHTS: String = "night_lights"

var _ctx: IEntityContext = null
var _piece_key: String = ""
var _def: BuildPieceDefinition = null
var _interactable_comp: InteractableComponent = null
var _station_comp: InteractableComponent = null
var _use_comp: InteractableComponent = null
## Letzte Nutzung je Spieler (player_id -> ticks_msec) — Cooldown gegen Spam, nur Autorität (StructureUse).
var _last_use_msec: Dictionary = {}
## Bewegliche Teile des Brunnens (nur bei BuildPieceDefinition.has_well_bucket_animation()).
var _bucket_node: MeshInstance3D = null
var _rope_node: MeshInstance3D = null
var _use_tween: Tween = null

func _ready() -> void:
	# Autorität ist immer der Server (wie alle Welt-Entities). Name kommt vom Orchestrator
	# (deterministisch aus der Position) — nur ersetzen, wenn noch der Godot-Standardname.
	set_multiplayer_authority(1)
	if name == get_class() or name.begins_with("@"):
		name = "BuildPiece_%d" % (get_instance_id() % 9999)
	add_to_group("build_pieces")
	add_to_group("interactable")
	_setup_interactable()
	_apply_build_mode(BuildModeState.is_active())

## Aufgerufen vom EntityOrchestrator NACH add_child() und NACH _ready().
func on_spawn(cfg: Dictionary = {}, ctx: IEntityContext = null) -> void:
	_ctx = ctx
	_piece_key = String(cfg.get("key", ""))
	rotation.y = float(cfg.get("yaw", 0.0))

	var data: DataService = ctx.get_data() if is_instance_valid(ctx) else null
	_def = data.get_build_piece(String(cfg.get("piece_id", ""))) if is_instance_valid(data) else null

	if is_instance_valid(_interactable_comp):
		_interactable_comp.inject_context(_ctx)

	# Die Definition ist erst HIER bekannt (_ready() läuft davor) — deshalb wird die Stations-
	# Aktion in on_spawn() angehängt, nicht in _setup_interactable().
	_setup_station_interactable()
	if is_instance_valid(_station_comp):
		_station_comp.inject_context(_ctx)

	_setup_use_interactable()
	if is_instance_valid(_use_comp):
		_use_comp.inject_context(_ctx)
	var ui_bus: IEventBus = _ctx.get_event_bus() if is_instance_valid(_ctx) else null
	if ui_bus != null and not ui_bus.ui().build_mode_changed.is_connected(_apply_build_mode):
		ui_bus.ui().build_mode_changed.connect(_apply_build_mode)

	_clear_geometry()
	_build_geometry()
	_apply_build_mode(BuildModeState.is_active())

	# Wunsch "Spieler-Spawner-Bauteile" (Grabstein/Lagerfeuer, ggf. quest-
	# freigeschaltet): gleicher Dienst wie GraveyardGravestone.gd/
	# GoblinCampfire.gd (natürliche Quellen), aber _piece_key statt
	# entity_uuid als Registrierungs-Schlüssel — das ist bereits der stabile,
	# positionsbasierte Schlüssel dieses Bauteils (überlebt Chunk-Reload
	# identisch, siehe WorldBuildHandler), eine zusätzliche UUID wäre hier
	# nur Redundanz.
	if is_instance_valid(_def) and not _def.ambient_spawn_type_id.is_empty() and is_multiplayer_authority():
		var spawner: AmbientSpawnService = ctx.get_ambient_spawner() if is_instance_valid(ctx) else null
		if is_instance_valid(spawner):
			spawner.register_point("buildpiece:" + _piece_key, global_position, _def.ambient_spawn_type_id)

func on_despawn() -> void:
	if is_instance_valid(_ctx) and _ctx.get_event_bus() != null:
		var ui_events: UIEvents = _ctx.get_event_bus().ui()
		if ui_events.build_mode_changed.is_connected(_apply_build_mode):
			ui_events.build_mode_changed.disconnect(_apply_build_mode)
	if is_instance_valid(_use_tween):
		_use_tween.kill()
	if is_instance_valid(_use_comp):
		_use_comp.disconnect_world_events()
	if is_instance_valid(_interactable_comp):
		_interactable_comp.disconnect_world_events()
	if is_instance_valid(_station_comp):
		_station_comp.disconnect_world_events()
	if is_instance_valid(_def) and not _def.ambient_spawn_type_id.is_empty():
		var spawner: AmbientSpawnService = _ctx.get_ambient_spawner() if is_instance_valid(_ctx) else null
		if is_instance_valid(spawner):
			spawner.unregister_point("buildpiece:" + _piece_key)

func get_piece_key() -> String:
	return _piece_key

# ─────────────────────────────────────────────
# Geometrie
# ─────────────────────────────────────────────

func _build_geometry() -> void:
	if _def == null:
		# Fehlende Definition (Daten-Fehler): sichtbarer Platzhalter statt unsichtbarem Loch.
		AppLogger.log_error("BuildPiece '%s': keine BuildPieceDefinition — Platzhalter." % _piece_key, LOG_CAT)
		_add_box(Vector3(BuildGrid.CELL, 1.0, BuildGrid.CELL), Vector3(0, 0.5, 0), COL_MISSING)
		return

	# ERWEITERUNG: neue Bauteil-Arten mit eigener (nicht-Box-)Geometrie hier verzweigen.
	if _def.is_roof():
		_add_roof(_def)
		return
	if _def.is_stairs():
		_add_stairs(_def)
		return
	if _def.is_target():
		_add_target(_def)
		return
	if _def.is_door():
		_add_framed(_def, _def.get_door_boxes(BuildGrid.CELL))
		return
	if _def.is_window():
		_add_framed(_def, _def.get_window_boxes(BuildGrid.CELL))
		return
	if _def.has_crenellations():
		# Zinnenmauer: Mauerkörper + Zinnen als Einzel-Boxen (je eigene Kollision).
		_add_framed(_def, _def.get_wall_boxes(BuildGrid.CELL))
		return

	_add_box(_def.get_box_size(BuildGrid.CELL), _def.get_box_center(), _def.color)

## Dach: sichtbares Satteldach-Prisma (BuildPieceDefinition.build_roof_mesh — dieselbe Quelle
## wie BuildGhost), Kollision bleibt eine grobe Hüllbox (get_box_size/get_box_center), wie bei
## den anderen Bauteil-Arten auch (siehe Klassenkommentar "keine Trefferpunkte/Lastpfad").
func _add_roof(def: BuildPieceDefinition) -> void:
	var mesh: ArrayMesh = BuildPieceDefinition.build_roof_mesh(BuildGrid.CELL, def.height, def.roof_shape, def.roof_ridge)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = def.color
	mat.roughness = 0.9
	# Doppelseitig: die Winkelrichtung der Dreiecke aus build_roof_mesh() ist nicht für jede
	# der fünf Flächen garantiert konsistent zur Standard-Front-Face-Konvention — ohne
	# Renderer-Vorschau in dieser Sandbox lieber sichtbar von beiden Seiten als riskiert
	# unsichtbar.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Geom"
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

	var shape := BoxShape3D.new()
	shape.size = def.get_box_size(BuildGrid.CELL)
	var col := CollisionShape3D.new()
	col.name = "GeomCol"
	col.shape = shape
	col.position = def.get_box_center()
	add_child(col)

func _add_box(size: Vector3, center: Vector3, color: Color, suffix: String = "") -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	var mi := MeshInstance3D.new()
	mi.name = "Geom%s" % suffix
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	add_child(mi)

	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.name = "GeomCol%s" % suffix
	col.shape = shape
	col.position = center
	add_child(col)

## Tür/Fenster: mehrere Einzel-Boxen (Pfosten/Sturz/Brüstung, siehe BuildPieceDefinition.
## get_door_boxes()/get_window_boxes()) statt einer durchgehenden Wandbox — die Öffnung
## dazwischen bleibt frei (kein Mesh, keine Kollision), damit man wirklich hindurchgehen kann.
func _add_framed(def: BuildPieceDefinition, boxes: Array[Dictionary]) -> void:
	for i in boxes.size():
		var b: Dictionary = boxes[i]
		_add_box(b["size"], b["center"], def.color, "_%d" % i)

## Treppe: Sichtgeometrie als gestufte Prismen (BuildPieceDefinition.build_stairs_mesh),
## Kollision als eigene Stufen-Boxen (nicht eine geneigte Rampe — bei LEVEL_HEIGHT/CELL wäre
## das zu steil zum flüssigen Gehen; echte Stufen lassen sich mit dem üblichen "Step"-Verhalten
## einer CharacterBody3D hochlaufen). Beide teilen sich STAIR_STEPS, damit Optik und begehbare
## Fläche übereinstimmen.
func _add_stairs(def: BuildPieceDefinition) -> void:
	var mesh: ArrayMesh = BuildPieceDefinition.build_stairs_mesh(BuildGrid.CELL, def.height, def.stairs_shape)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = def.color
	mat.roughness = 0.9
	var mi := MeshInstance3D.new()
	mi.name = "Geom"
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

	if def.stairs_shape == BuildPieceDefinition.StairsShape.SPIRAL:
		_add_spiral_stairs_collision(def)
	else:
		_add_straight_stairs_collision(def)

## Gerade Treppe (StairsShape.STRAIGHT, bisheriges Verhalten): eine Box je Stufe, quer über die
## volle Zellbreite, jede von der Basis (y=0) bis zu ihrer Trittfläche — nicht nur die dünne
## Trittstufe selbst — sonst könnte der Spieler unter die Stufe rutschen.
func _add_straight_stairs_collision(def: BuildPieceDefinition) -> void:
	var steps: int = BuildPieceDefinition.STAIR_STEPS
	var cell: float = BuildGrid.CELL
	var step_h: float = maxf(def.height, 0.05) / float(steps)
	var step_d: float = cell / float(steps)
	var hc: float = cell * 0.5
	for i in steps:
		var shape := BoxShape3D.new()
		shape.size = Vector3(cell, step_h * float(i + 1), step_d)
		var col := CollisionShape3D.new()
		col.name = "GeomCol_%d" % i
		col.shape = shape
		col.position = Vector3(0.0, step_h * float(i + 1) * 0.5, -hc + step_d * (float(i) + 0.5))
		add_child(col)

## Wendeltreppe (StairsShape.SPIRAL): eine radial ausgerichtete Box je Stufe (Näherung an den
## echten Keil aus build_spiral_stairs_mesh() — für begehbare Kollision genau genug, siehe
## BuildPieceDefinition.SPIRAL_*-Kommentar), verteilt über SPIRAL_TURNS Umdrehungen, jede von der
## Basis (y=0) bis zur Trittfläche wie bei STRAIGHT. Rotation um lokal Y auf die Stufenmitte,
## Position auf dem mittleren Radius zwischen Mittelpfosten und Zellrand.
func _add_spiral_stairs_collision(def: BuildPieceDefinition) -> void:
	var steps: int = BuildPieceDefinition.STAIR_STEPS
	var cell: float = BuildGrid.CELL
	var hc: float = cell * 0.5
	var r_out: float = maxf(hc - BuildPieceDefinition.SPIRAL_MARGIN, BuildPieceDefinition.SPIRAL_NEWEL_RADIUS + 0.2)
	var r_in: float = BuildPieceDefinition.SPIRAL_NEWEL_RADIUS
	var r_mid: float = (r_in + r_out) * 0.5
	var step_h: float = maxf(def.height, 0.05) / float(steps)
	var step_angle: float = TAU * BuildPieceDefinition.SPIRAL_TURNS / float(steps)
	for i in steps:
		var a_mid: float = step_angle * (float(i) + 0.5)
		var y1: float = step_h * float(i + 1)
		var shape := BoxShape3D.new()
		# X = radiale Tiefe (Rand bis Pfosten), Z = tangentiale Breite der Stufe bei r_mid —
		# leicht großzügig (kein exakter Bogen), damit keine Lücke zwischen Stufen entsteht.
		shape.size = Vector3(r_out - r_in, y1, r_mid * step_angle * 1.15)
		var col := CollisionShape3D.new()
		col.name = "GeomCol_%d" % i
		col.shape = shape
		var basis := Basis(Vector3.UP, a_mid)
		var center := basis * Vector3(r_mid, 0.0, 0.0)
		col.transform = Transform3D(basis, Vector3(center.x, y1 * 0.5, center.z))
		add_child(col)

## Requisit (z.B. Zielscheibe, Kapelle, Laterne): sichtbare Geometrie aus
## BuildPieceDefinition.build_prop_mesh() (dieselbe Quelle wie BuildGhost). Jede Surface bekommt ihr
## Material aus build_prop_materials() (Hauptfarbe / Zweitfarbe / Leuchtfläche); einflächige
## Requisiten verhalten sich damit wie bisher. Kollision: normalerweise eine grobe Hüllbox
## (get_box_size/get_box_center, wie ROOF/STAIRS auch) — Requisiten mit
## get_prop_collision_boxes() (Kapelle) bekommen stattdessen ihre Einzelboxen, damit man
## hineingehen kann. Mit light_range > 0 kommt ein OmniLight3D dazu (Straßenlaterne).
func _add_target(def: BuildPieceDefinition) -> void:
	var animated_well := def.has_well_bucket_animation()
	var mesh: ArrayMesh = BuildPieceDefinition.build_well_mesh(def.height, false) \
		if animated_well else BuildPieceDefinition.build_prop_mesh(def.height, def.prop_shape)
	var mi := MeshInstance3D.new()
	mi.name = "Geom"
	mi.mesh = mesh
	var mats: Array[StandardMaterial3D] = def.build_prop_materials()
	for i in mini(mats.size(), mesh.get_surface_count()):
		mi.set_surface_override_material(i, mats[i])
	add_child(mi)

	var boxes: Array[Dictionary] = def.get_prop_collision_boxes()
	if boxes.is_empty():
		var shape := BoxShape3D.new()
		shape.size = def.get_box_size(BuildGrid.CELL)
		var col := CollisionShape3D.new()
		col.name = "GeomCol"
		col.shape = shape
		col.position = def.get_box_center()
		add_child(col)
	else:
		for i in boxes.size():
			var box_shape := BoxShape3D.new()
			box_shape.size = boxes[i]["size"]
			var box_col := CollisionShape3D.new()
			box_col.name = "GeomCol_%d" % i
			box_col.shape = box_shape
			box_col.position = boxes[i]["center"]
			add_child(box_col)

	if animated_well:
		_add_well_bucket(def)

	if def.has_light():
		_add_prop_light(def)

## Warmes Punktlicht an der Leuchtfläche eines Requisits (Straßenlaterne). Ohne Schatten (billig,
## GL-Compatibility-tauglich). Gruppe GROUP_NIGHT_LIGHTS: Haken für einen späteren Tag/Nacht-
## Zyklus, der die Lichter nur nachts einschaltet — bisher leuchten sie immer.
func _add_prop_light(def: BuildPieceDefinition) -> void:
	var light := OmniLight3D.new()
	light.name = "GeomLight"
	light.light_color = BuildPieceDefinition.PROP_GLOW_COLOR
	light.light_energy = BuildPieceDefinition.PROP_LIGHT_ENERGY
	light.omni_range = def.light_range
	light.shadow_enabled = false
	light.position = BuildPieceDefinition.prop_light_offset(def.prop_shape, def.height)
	light.add_to_group(GROUP_NIGHT_LIGHTS)
	add_child(light)

func _clear_geometry() -> void:
	if is_instance_valid(_use_tween):
		_use_tween.kill()
	_bucket_node = null
	_rope_node = null
	for child in get_children():
		if child.name == "Geom" or child.name == "GeomCol" or child.name.begins_with("Geom"):
			remove_child(child)
			child.queue_free()

# ─────────────────────────────────────────────
# Interaktion (Abreißen)
# ─────────────────────────────────────────────

func _setup_interactable() -> void:
	var d := InteractableData.new()
	d.id           = ACTION_DISMANTLE
	d.label        = "Abreißen"
	d.duration     = 1.5
	d.xp_type      = "none"
	d.xp_amount    = 0
	d.loot_table   = null
	d.inspect_text = ""
	_interactable_comp = InteractableComponent.new()
	_interactable_comp.data = d
	add_child(_interactable_comp)
	_interactable_comp.interacted.connect(_on_interacted)

## Hängt für Schmiede-Stationen die zweite Aktion "Benutzen" an. Idempotent (on_spawn() kann bei
## einem Re-Spawn erneut laufen, ohne eine dritte Komponente zu erzeugen).
func _setup_station_interactable() -> void:
	if is_instance_valid(_station_comp) or not is_instance_valid(_def) or not _def.is_station():
		return
	var station_name: String = String(STATION_NAMES.get(_def.station_kind, _def.display_name))
	var d := InteractableData.new()
	d.id           = ACTION_USE_STATION
	d.label        = "%s benutzen" % station_name
	d.duration     = 0.3
	d.xp_type      = "none"
	d.xp_amount    = 0
	d.loot_table   = null
	d.inspect_text = "%s. Hier lassen sich Erz und Barren zu Waffen und Rüstung verarbeiten." % station_name
	_station_comp = InteractableComponent.new()
	_station_comp.name = "StationInteractable"
	_station_comp.data = d
	add_child(_station_comp)
	_station_comp.interacted.connect(_on_interacted)

## Station benutzt. InteractableComponent ruft diesen Hook für einen Nicht-Host-Spieler ZWEIMAL auf
## (siehe QuestNPC._on_interacted(), BUG-26): einmal lokal auf dem Client, einmal auf der
## Autorität. Deshalb zwei getrennte Wirkungen:
##   - Panel öffnen: nur auf dem Peer des Spielers selbst (sonst öffnete sich das Panel des Hosts
##     bzw. würde auf dem Server ins Leere laufen, wenn ein Client den Ofen benutzt).
##   - Zugang melden: nur auf der Autorität — SmithingService verlangt serverseitig, dass der
##     Spieler die Station kürzlich benutzt hat, bevor er Rezepte dieser Station ausführen darf.
func _on_station_used(peer_id: int) -> void:
	if not is_instance_valid(_def) or not _def.is_station() or not is_instance_valid(_ctx):
		return
	var bus: IEventBus = _ctx.get_event_bus()
	if bus == null:
		AppLogger.log_warn("_on_station_used(): kein EventBus — Station '%s' ohne Wirkung." % _piece_key, LOG_CAT)
		return
	if multiplayer.get_unique_id() == peer_id:
		var station_name: String = String(STATION_NAMES.get(_def.station_kind, _def.display_name))
		bus.ui().emit_smithing_opened(_def.station_kind, station_name)
	if is_multiplayer_authority():
		var network: NetworkBridge = _ctx.get_network_bridge()
		var player_id: String = network.get_player_id_for_peer(peer_id) if is_instance_valid(network) else ""
		if player_id.is_empty():
			AppLogger.log_warn("_on_station_used(): kein player_id für peer %d — Zugang nicht gemeldet." % peer_id, LOG_CAT)
			return
		bus.smithing().emit_smithing_station_used(player_id, _def.station_kind)

# ─────────────────────────────────────────────
# Bau-Modus: "Abreißen" nur dort sichtbar/anwählbar
# ─────────────────────────────────────────────

## Schaltet "Abreißen" je nach lokalem Bau-Modus (BuildModeState) und hält die Gruppe
## "interactable" aktuell: ohne einzige aktive Aktion ist das Bauteil kein Interaktionsziel mehr
## (kein Label, keine Hervorhebung, nicht antippbar). Stationen und Nutzaktionen bleiben immer aktiv.
func _apply_build_mode(active: bool) -> void:
	if is_instance_valid(_interactable_comp):
		_interactable_comp.set_enabled(active)
	var any_enabled := false
	for comp in [_interactable_comp, _station_comp, _use_comp]:
		if is_instance_valid(comp) and (comp as InteractableComponent).enabled:
			any_enabled = true
	if any_enabled:
		add_to_group("interactable")
	elif is_in_group("interactable"):
		remove_from_group("interactable")

# ─────────────────────────────────────────────
# Strukturnutzung (z.B. Brunnen: Wasser schöpfen)
# ─────────────────────────────────────────────

func _setup_use_interactable() -> void:
	if is_instance_valid(_use_comp) or not is_instance_valid(_def) or not _def.has_use():
		return
	var d := InteractableData.new()
	d.id           = ACTION_USE_STRUCTURE
	d.label        = _def.use_label
	d.duration     = _def.use_duration
	d.xp_type      = "none"
	d.xp_amount    = 0
	d.loot_table   = null
	d.inspect_text = ""
	_use_comp = InteractableComponent.new()
	_use_comp.name = "UseInteractable"
	_use_comp.data = d
	add_child(_use_comp)
	_use_comp.interacted.connect(_on_interacted)
	_use_comp.progress_started.connect(_on_use_progress_started)

## Zwei Aufrufe pro Nutzung durch einen Nicht-Host-Spieler (lokal + Autorität, siehe
## InteractableComponent._handle_completion()). Deshalb getrennt:
##   - Rückmeldung (Hinweis bei fehlenden Zutaten): nur auf dem Peer des Spielers selbst, aus dem
##     lokalen Inventar — reine Komfort-Vorprüfung.
##   - Wirkung (Zutaten weg, Ergebnis dazu): nur auf der Autorität, mit eigener Prüfung inkl.
##     Cooldown und Inventarplatz (StructureUse.use()).
func _on_structure_used(peer_id: int) -> void:
	if not is_instance_valid(_def) or not _def.has_use() or not is_instance_valid(_ctx):
		return
	var network: NetworkBridge = _ctx.get_network_bridge()
	var player_id: String = network.get_player_id_for_peer(peer_id) if is_instance_valid(network) else ""
	var bus: IEventBus = _ctx.get_event_bus()
	var is_local: bool = multiplayer.get_unique_id() == peer_id
	var inventory: InventorySystem = _ctx.get_inventory()
	if is_local:
		var hint := StructureUse.check(_def, player_id, inventory)
		if not hint.is_empty() and bus != null:
			bus.ui().emit_notification_requested(StructureUse.reason_text(hint, _def, _ctx.get_data()))
			return
	if not is_multiplayer_authority():
		return
	var now := Time.get_ticks_msec()
	var reason := StructureUse.use(_def, player_id, inventory, int(_last_use_msec.get(player_id, 0)), now)
	if reason.is_empty():
		_last_use_msec[player_id] = now
		if is_local and bus != null:
			bus.ui().emit_floating_loot_text_requested("💧 %s" % _def.use_label)
	elif is_local and bus != null:
		bus.ui().emit_notification_requested(StructureUse.reason_text(reason, _def, _ctx.get_data()))

func _on_use_progress_started(_action_id: String, duration: float) -> void:
	if _def != null and _def.has_well_bucket_animation():
		play_well_bucket_animation(duration)

## Eimer-Verlauf über die Dauer der Aktion: t 0..1 → Absenktiefe 0..1 (Sinken, kurz unten, Hochziehen).
static func bucket_drop_fraction(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	if x < 0.4:
		return smoothstep(0.0, 1.0, x / 0.4)
	if x < 0.55:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (x - 0.55) / 0.45)

## Rein visuell: Eimer sinkt, Seil streckt sich, Eimer kommt wieder hoch.
func play_well_bucket_animation(duration: float) -> void:
	if not is_instance_valid(_bucket_node) or not is_instance_valid(_rope_node) or _def == null:
		return
	if is_instance_valid(_use_tween):
		_use_tween.kill()
	var geo := BuildPieceDefinition.well_bucket_geometry(_def.height)
	var rest_y: float = geo["rest_y"]
	var rope_len: float = geo["rope_len"]
	var drop: float = geo["drop"]
	var bucket := _bucket_node
	var rope := _rope_node
	_use_tween = create_tween()
	_use_tween.tween_method(func(t: float) -> void:
		if not is_instance_valid(bucket) or not is_instance_valid(rope):
			return
		var d: float = bucket_drop_fraction(t) * drop
		bucket.position.y = rest_y - d
		rope.scale.y = (rope_len + d) / rope_len
	, 0.0, 1.0, maxf(duration, 0.1))

func _add_well_bucket(def: BuildPieceDefinition) -> void:
	var geo := BuildPieceDefinition.well_bucket_geometry(def.height)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = def.accent_color
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rope_node = MeshInstance3D.new()
	_rope_node.name = "GeomRope"
	_rope_node.mesh = BuildPieceDefinition.build_well_rope_mesh(def.height)
	_rope_node.material_override = mat
	_rope_node.position = Vector3(0.0, float(geo["anchor_y"]), 0.0)
	add_child(_rope_node)
	_bucket_node = MeshInstance3D.new()
	_bucket_node.name = "GeomBucket"
	_bucket_node.mesh = BuildPieceDefinition.build_well_bucket_mesh()
	_bucket_node.material_override = mat
	_bucket_node.position = Vector3(0.0, float(geo["rest_y"]), 0.0)
	add_child(_bucket_node)

func _on_interacted(action_id: String, peer_id: int) -> void:
	if action_id == ACTION_USE_STRUCTURE:
		_on_structure_used(peer_id)
		return
	if action_id == ACTION_USE_STATION:
		_on_station_used(peer_id)
		return
	if action_id != ACTION_DISMANTLE:
		return
	if not is_multiplayer_authority():
		return
	if not is_instance_valid(_ctx):
		AppLogger.log_error("_on_interacted(): kein EntityContext gespeichert.", LOG_CAT)
		return
	var network: NetworkBridge = _ctx.get_network_bridge()
	var player_id: String = network.get_player_id_for_peer(peer_id) if is_instance_valid(network) else ""
	var bus: IEventBus = _ctx.get_event_bus()
	if player_id.is_empty() or bus == null:
		AppLogger.log_warn("_on_interacted(): player_id/EventBus nicht verfügbar — Abreißen verweigert.", LOG_CAT)
		return
	bus.world().emit_build_remove_requested(player_id, _piece_key)
