class_name WorldBuildHandler
extends RefCounted

## WorldBuildHandler — Platzieren, Entfernen und Sichtbarmachen von Bauteilen.
##
## Kein Service, kein Node: Hilfsklasse von WorldService (Muster wie WorldSaveHandler).
## Alles Externe kommt über Callables — dadurch ohne SceneTree/Inventar testbar:
##   defs_cb(piece_id)                         -> BuildPieceDefinition | null
##   ground_fn(x, z)                           -> float (Geländehöhe, NAN = kein Boden; in Produktion
##                                                 TerrainField.get_height_at — kein Raycast nötig)
##   spawn_cb(type_id, pos, cfg)               -> Node3D | null
##   despawn_cb(node)                          -> void
##   can_afford(player_id, cost) / pay(player_id, cost) / refund(player_id, items)
##
## WAHRHEIT vs. ANSICHT: Die Bauteile leben als Records in BuildRegistry (WorldData, wird
## gespeichert). Die 3D-Nodes sind nur eine Ansicht: on_chunk_loaded() erzeugt sie, on_chunk_
## unloaded() entfernt sie wieder. So hängen keine Gebäude über einem entladenen (leeren)
## Chunk in der Luft, und nach dem Laden eines Spielstands erscheinen sie von selbst,
## sobald ihr Chunk geladen wird.

const LOG_CAT := "WorldBuild"
const ENTITY_TYPE: String = "build_piece"
## Maximale Entfernung Spieler → Bauplatz / Bauteil.
const REACH: float = 10.0

var _registry: BuildRegistry
var _editor: WorldTerrainEditor
var _defs_cb: Callable
var _ground_fn: Callable
var _spawn_cb: Callable
var _despawn_cb: Callable
var _chunk_size: float
## water_level_fn(x, z) -> float, i.d.R. TerrainField.get_water_level_at() — NICHT mehr eine
## einzelne Zahl, seit Flüsse je nach Ort einen eigenen Wasserspiegel haben (siehe
## BuildPlacementRules-Kommentar, BUGFIX 2026-09-20).
var _water_level_fn: Callable

var _can_afford: Callable = Callable()
var _pay: Callable = Callable()
var _refund: Callable = Callable()

## house_defs_cb(template_id) -> HouseTemplateDefinition | null — analog zu _defs_cb, aber für
## komplette Häuser (siehe "Häuser/Vorlagen" unten). Optional: ohne diese Callable liefern
## preview_house()/place_house() nur "unknown_house".
var _house_defs_cb: Callable = Callable()

## { key: Node3D } — aktuell existierende Ansichten.
var _nodes: Dictionary = {}

func _init(
	registry: BuildRegistry, editor: WorldTerrainEditor,
	defs_cb: Callable, ground_fn: Callable,
	spawn_cb: Callable, despawn_cb: Callable, chunk_size: float,
	water_level_fn: Callable = Callable()
) -> void:
	_registry = registry
	_editor = editor
	_defs_cb = defs_cb
	_ground_fn = ground_fn
	_spawn_cb = spawn_cb
	_despawn_cb = despawn_cb
	_chunk_size = chunk_size
	_water_level_fn = water_level_fn

## Materialkosten-Anbindung (WorldService: InventorySystem). Ohne diese Aufrufe ist Bauen
## kostenlos — nützlich für Tests, in Produktion IMMER setzen.
func set_inventory_ops(can_afford: Callable, pay: Callable, refund: Callable) -> void:
	_can_afford = can_afford
	_pay = pay
	_refund = refund

## Anbindung für komplette Häuser (WorldService: DataService.get_house_template()).
func set_house_defs(house_defs_cb: Callable) -> void:
	_house_defs_cb = house_defs_cb

# ─────────────────────────────────────────────
# Vorschau / Platzieren / Entfernen
# ─────────────────────────────────────────────

## Vorschau OHNE Mutation (Geist im Baumodus).
## Rückgabe: {ok, reason, key, y, yaw, center: Vector2, affordable: bool, storey: int}
## storey: Ebene (0 = Gelände, siehe BuildGrid).
func preview(
	player_id: String, piece_id: String, target: Vector3, rot_steps: int, player_pos: Vector3, storey: int = 0
) -> Dictionary:
	var def: BuildPieceDefinition = _get_def(piece_id)
	if def == null:
		return {"ok": false, "reason": "unknown_piece", "key": "", "y": 0.0, "yaw": 0.0,
			"center": Vector2.ZERO, "affordable": false, "storey": storey}
	var snap: Dictionary = BuildGrid.snap(def.kind, target, rot_steps, storey)
	var check: Dictionary = _run_rules(def, snap, player_pos)
	var out: Dictionary = {
		"ok": bool(check["ok"]), "reason": String(check["reason"]), "key": String(snap["key"]),
		"y": float(check["y"]), "yaw": float(snap["yaw"]), "center": snap["center"],
		"affordable": _affordable(player_id, def), "storey": int(snap["storey"]),
	}
	if out["ok"] and _too_far(player_pos, snap["center"]):
		out["ok"] = false
		out["reason"] = "too_far"
	return out

## Platziert ein Bauteil. Rückgabe: {ok, reason, key}
func place(
	player_id: String, piece_id: String, target: Vector3, rot_steps: int, player_pos: Vector3, storey: int = 0
) -> Dictionary:
	var def: BuildPieceDefinition = _get_def(piece_id)
	if def == null:
		return _fail("unknown_piece")

	var snap: Dictionary = BuildGrid.snap(def.kind, target, rot_steps, storey)
	if _too_far(player_pos, snap["center"]):
		return _fail("too_far")

	var check: Dictionary = _run_rules(def, snap, player_pos)
	if not check["ok"]:
		return _fail(String(check["reason"]))

	if not _affordable(player_id, def):
		return _fail("no_materials", def.cost)
	if _pay.is_valid() and not bool(_pay.call(player_id, def.cost)):
		return _fail("no_materials", def.cost)

	# Ab hier keine Ablehnung mehr — Material ist bezahlt.
	if def.is_floor() and not (check["level"] as Dictionary).is_empty():
		_editor.apply_level((check["level"] as Dictionary)["changes"])

	var center: Vector2 = snap["center"]
	var record: Dictionary = {
		"key": snap["key"], "piece_id": def.id, "kind": def.kind,
		"x": center.x, "y": float(check["y"]), "z": center.y,
		"yaw": float(snap["yaw"]), "owner": player_id, "storey": int(snap["storey"]),
	}
	if not _registry.add(record):
		# Sollte durch den occupied-Check unmöglich sein — Material sicherheitshalber zurück.
		AppLogger.log_error("place(): Record '%s' ließ sich nicht eintragen." % record["key"], LOG_CAT)
		_give_back(player_id, def.cost)
		return _fail("occupied")

	_spawn(record)
	AppLogger.log_info("'%s' gebaut bei %s (Spieler '%s')." % [def.id, str(center), player_id], LOG_CAT)
	return {"ok": true, "reason": "", "key": record["key"]}

## Reißt ein Bauteil ab und erstattet Material (refund_ratio der Definition).
func remove(player_id: String, key: String, player_pos: Vector3) -> Dictionary:
	var rec: Dictionary = _registry.get_record(key)
	if rec.is_empty():
		return _fail("unknown_piece")
	if _too_far(player_pos, Vector2(float(rec["x"]), float(rec["z"]))):
		return _fail("too_far")

	# Nichts unter etwas Getragenem wegreißen — sonst schweben Wände/Böden darüber.
	if _registry.has_dependents(key):
		return _fail("supports_others")

	_registry.remove(key)
	_despawn_key(key)

	var def: BuildPieceDefinition = _get_def(String(rec.get("piece_id", "")))
	if def != null:
		var items: Dictionary = {}
		for item_id: String in def.cost.keys():
			var qty: int = def.refund_for(item_id)
			if qty > 0:
				items[item_id] = qty
		if not items.is_empty():
			_give_back(player_id, items)
	return {"ok": true, "reason": "", "key": key}

# ─────────────────────────────────────────────
# Häuser/Vorlagen (HouseTemplateDefinition) — mehrere Bauteile als EINE atomare Operation.
#
# GRUNDIDEE: ein Haus ist nichts Neues gegenüber einem einzelnen Bauteil — es sind einfach
# mehrere Records, die in Bau-Reihenfolge (Boden → Wand/Tür/Fenster → Dach/Treppe) dieselben
# Prüfungen durchlaufen wie beim manuellen Bauen Stück für Stück (BuildPlacementRules.check()).
# preview_house() simuliert das GANZE Haus gegen eine Kopie der Registry (BuildRegistry.clone())
# BEVOR irgendetwas Echtes angefasst wird: schlägt EIN Teil fehl, ist die ganze Vorschau "nicht
# baubar" — nie ein halb gebautes Haus, nie verschwendetes Material.
# ─────────────────────────────────────────────

func _get_house_def(template_id: String) -> HouseTemplateDefinition:
	if not _house_defs_cb.is_valid():
		return null
	return _house_defs_cb.call(template_id) as HouseTemplateDefinition

## Konkrete (def, snap)-Paare für ein Haus an `target`, um `rot_steps` gedreht, auf Ebene
## `storey` — in Baureihenfolge sortiert (Boden zuerst, dann Wand/Tür/Fenster, zuletzt Dach/
## Treppe), damit jedes Teil beim Simulieren/Platzieren bereits seinen Halt vorfindet (ein
## Dach braucht z.B. eine Wand DERSELBEN Vorlage, die weiter vorn in der Liste steht).
## Anker = die Zelle, die ein Boden an `target` bekäme (BuildGrid.cell_of) — alle dx/dz der
## Vorlage sind relativ dazu (siehe HouseTemplateDefinition-Klassenkommentar).
func _house_layout(house: HouseTemplateDefinition, target: Vector3, rot_steps: int, storey: int) -> Array[Dictionary]:
	var anchor: Vector2i = BuildGrid.cell_of(target.x, target.z)
	# Je Ebene eigene Gruppen: erst die tiefste Ebene (Boden → Wand/Tür/Fenster → Dach/Treppe/Requisite),
	# dann die nächsthöhere — obere Ebenen brauchen Halt von unten (Wehrgang auf der Mauer, Boden auf
	# der Wand darunter). Eintrag-Feld "storey" = Ebenen-Offset zur Ebene des Hauses (Default 0).
	var by_storey: Dictionary = {}
	for raw_entry: Dictionary in house.pieces:
		var def: BuildPieceDefinition = _get_def(String(raw_entry.get("piece_id", "")))
		if def == null:
			continue
		var entry_storey: int = clampi(storey + int(raw_entry.get("storey", 0)), 0, BuildGrid.MAX_STOREY)
		var rotated: Dictionary = BuildGrid.rotate_house_piece(raw_entry, rot_steps)
		var cx: int = anchor.x + int(rotated["dx"])
		var cz: int = anchor.y + int(rotated["dz"])
		var snap: Dictionary = BuildGrid.snap_from_cell(def.kind, int(rotated["axis"]), cx, cz, entry_storey)
		var item: Dictionary = {"def": def, "snap": snap}
		if not by_storey.has(entry_storey):
			by_storey[entry_storey] = {"floors": [], "walls": [], "tops": []}
		var group: Dictionary = by_storey[entry_storey]
		if def.is_floor():
			(group["floors"] as Array).append(item)
		elif def.is_wall_like():
			(group["walls"] as Array).append(item)
		else:
			(group["tops"] as Array).append(item)
	var levels: Array = by_storey.keys()
	levels.sort()
	var out: Array[Dictionary] = []
	for level: int in levels:
		var group: Dictionary = by_storey[level]
		for part: String in ["floors", "walls", "tops"]:
			for item: Dictionary in group[part]:
				out.append(item)
	return out

func _affordable_cost(player_id: String, cost: Dictionary) -> bool:
	if not _can_afford.is_valid():
		return true
	return bool(_can_afford.call(player_id, cost))

## Vorschau (Trockenlauf) für ein GANZES Haus, OHNE Mutation.
## Rückgabe: {ok, reason, pieces: [{key,y,yaw,center,kind,level}], total_cost, affordable}
##   pieces ist in Bau-Reihenfolge (siehe _house_layout()) — place_house() geht dieselbe
##   Reihenfolge nochmal (diesmal echt) durch.
func preview_house(
	player_id: String, template_id: String, target: Vector3, rot_steps: int, player_pos: Vector3, storey: int = 0
) -> Dictionary:
	var fail := {"ok": false, "reason": "unknown_house", "pieces": [], "total_cost": {}, "affordable": false}
	var house: HouseTemplateDefinition = _get_house_def(template_id)
	if house == null or house.pieces.is_empty():
		return fail

	var sim: BuildRegistry = _registry.clone()
	var layout: Array[Dictionary] = _house_layout(house, target, rot_steps, storey)
	if layout.is_empty():
		return fail

	var pieces: Array[Dictionary] = []
	var total_cost: Dictionary = {}
	for item: Dictionary in layout:
		var def: BuildPieceDefinition = item["def"]
		var snap: Dictionary = item["snap"]
		if _too_far(player_pos, snap["center"]):
			return {"ok": false, "reason": "too_far", "pieces": [], "total_cost": {}, "affordable": false}
		var check: Dictionary = BuildPlacementRules.check(
			def, snap, sim, _ground_fn, _editor.get_layer(), player_pos, _water_level_fn
		)
		if not check["ok"]:
			return {"ok": false, "reason": String(check["reason"]), "pieces": [], "total_cost": {}, "affordable": false}

		var center: Vector2 = snap["center"]
		# In die SIMULIERTE Registry eintragen: der nächste Teil (Wand auf diesem Boden, Dach
		# auf dieser Wand) findet dadurch seinen Halt — exakt wie ein Spieler, der Stück für
		# Stück baut, nur eben in einer Kopie statt am echten Bestand.
		sim.add({
			"key": snap["key"], "piece_id": def.id, "kind": def.kind,
			"x": center.x, "y": float(check["y"]), "z": center.y,
			"yaw": float(snap["yaw"]), "owner": player_id, "storey": int(snap["storey"]),
		})
		for item_id: String in def.cost.keys():
			total_cost[item_id] = int(total_cost.get(item_id, 0)) + int(def.cost[item_id])
		pieces.append({
			"key": String(snap["key"]), "y": float(check["y"]), "yaw": float(snap["yaw"]),
			"center": center, "kind": def.kind, "storey": int(snap["storey"]),
		})

	return {
		"ok": true, "reason": "", "pieces": pieces, "total_cost": total_cost,
		"affordable": _affordable_cost(player_id, total_cost),
	}

## Platziert ein GANZES Haus. All-or-nothing: erst preview_house() (Simulation), erst danach
## Material abziehen und ECHT bauen — Schritt für Schritt in derselben Reihenfolge nochmal
## gegen den echten Bestand (nicht nur die im Vorschau-Schritt zwischengespeicherten Werte
## übernehmen), damit z.B. das Einebnen eines Bodens sich sofort auf den nächsten Boden
## auswirkt, genau wie beim manuellen Bauen Stück für Stück. Schlägt ein Teil beim ECHTEN
## Bauen trotzdem fehl (sollte nach erfolgreicher Simulation nicht vorkommen), werden bereits
## platzierte Teile dieses Hauses wieder entfernt und das Material zurückerstattet.
## Rückgabe: {ok, reason, keys: [String]}
func place_house(
	player_id: String, template_id: String, target: Vector3, rot_steps: int, player_pos: Vector3, storey: int = 0
) -> Dictionary:
	var house: HouseTemplateDefinition = _get_house_def(template_id)
	if house == null or house.pieces.is_empty():
		return _fail("unknown_house")
	if _too_far(player_pos, Vector2(target.x, target.z)):
		return _fail("too_far")

	var preview: Dictionary = preview_house(player_id, template_id, target, rot_steps, player_pos, storey)
	if not bool(preview["ok"]):
		return _fail(String(preview["reason"]))

	var total_cost: Dictionary = preview["total_cost"]
	if not _affordable_cost(player_id, total_cost):
		return _fail("no_materials", total_cost)
	if _pay.is_valid() and not bool(_pay.call(player_id, total_cost)):
		return _fail("no_materials", total_cost)

	# Ab hier keine Ablehnung mehr geplant — Material ist bezahlt. Trotzdem robust bleiben:
	# jeder Schritt läuft nochmal durch _run_rules(), Rollback bei einem (eigentlich
	# unmöglichen) Fehlschlag.
	var layout: Array[Dictionary] = _house_layout(house, target, rot_steps, storey)
	var placed_keys: Array[String] = []
	for item: Dictionary in layout:
		var def: BuildPieceDefinition = item["def"]
		var snap: Dictionary = item["snap"]
		var check: Dictionary = _run_rules(def, snap, player_pos)
		if not check["ok"]:
			AppLogger.log_error(
				"place_house(): Teil '%s' scheiterte nach erfolgreicher Simulation (reason='%s') — Rollback." %
					[String(snap["key"]), String(check["reason"])], LOG_CAT
			)
			_rollback_house(placed_keys, player_id, total_cost)
			return _fail(String(check["reason"]))

		if def.is_floor() and not (check["level"] as Dictionary).is_empty():
			_editor.apply_level((check["level"] as Dictionary)["changes"])

		var center: Vector2 = snap["center"]
		var record: Dictionary = {
			"key": snap["key"], "piece_id": def.id, "kind": def.kind,
			"x": center.x, "y": float(check["y"]), "z": center.y,
			"yaw": float(snap["yaw"]), "owner": player_id, "storey": int(snap["storey"]),
		}
		if not _registry.add(record):
			AppLogger.log_error("place_house(): Record '%s' ließ sich nicht eintragen — Rollback." % record["key"], LOG_CAT)
			_rollback_house(placed_keys, player_id, total_cost)
			return _fail("occupied")

		placed_keys.append(String(record["key"]))
		_spawn(record)

	AppLogger.log_info(
		"Haus '%s' gebaut bei %s (Spieler '%s'), %d Teile." % [house.id, str(target), player_id, placed_keys.size()],
		LOG_CAT
	)
	return {"ok": true, "reason": "", "keys": placed_keys}

## Reine GEOMETRIE eines ganzen Hauses (KEINE Regelprüfung, keine Registry-Abfrage, kein
## Materialcheck) — für den Geist im Baumodus. preview_house() bleibt die einzige Quelle der
## Wahrheit für Baubarkeit/Kosten (klont die Registry, prüft jedes Teil gegen
## BuildPlacementRules); das wäre jeden Frame für ein ganzes Haus unnötig teuer, nur um zu
## wissen, WO die Geister-Teile hinzeichnen sind. Diese Methode liefert nur die Positionen,
## deshalb zeigt der Geist auch dann noch etwas Sinnvolles, wenn preview_house() gerade
## "nicht baubar" meldet (der Spieler soll sehen, WAS er falsch positioniert hat, nicht nur
## DASS es nicht geht).
##
## HÖHE (Näherung, bewusst ohne Gelände-Einebnung/Registry-Stützen wie preview_house()):
## eine einzelne Bodenprobe am Zielpunkt legt die Ebene fest — Boden/Wand/Tür/Fenster/Treppe
## sitzen auf dieser Ebene, ein Dach eine LEVEL_HEIGHT höher (auf der "Traufe"). Reicht für
## eine Vorschau; das exakte Ergebnis (inkl. Einebnen, Nachbarhöhen) kommt beim echten Bauen
## aus place_house()/_house_layout().
##
## Rückgabe: [{piece_id, kind: int, pos: Vector3, yaw: float}] — Reihenfolge wie
## HouseTemplateDefinition.pieces (UNsortiert, anders als _house_layout()/preview_house()
## — für reine Darstellung spielt die Baureihenfolge keine Rolle).
func house_ghost_pieces(template_id: String, target: Vector3, rot_steps: int, storey: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var house: HouseTemplateDefinition = _get_house_def(template_id)
	if house == null:
		return out

	storey = clampi(storey, 0, BuildGrid.MAX_STOREY)
	var anchor: Vector2i = BuildGrid.cell_of(target.x, target.z)
	var ground: float = float(_ground_fn.call(target.x, target.z)) if _ground_fn.is_valid() else 0.0
	if is_nan(ground):
		ground = 0.0
	var base_y: float = BuildGrid.quantize_y(ground)

	for raw_entry: Dictionary in house.pieces:
		var def: BuildPieceDefinition = _get_def(String(raw_entry.get("piece_id", "")))
		if def == null:
			continue
		# Ebenen-Offset je Eintrag (HouseTemplateDefinition: Feld "storey"), wie in _house_layout().
		var entry_storey: int = clampi(storey + int(raw_entry.get("storey", 0)), 0, BuildGrid.MAX_STOREY)
		var floor_y: float = base_y + float(entry_storey) * BuildGrid.LEVEL_HEIGHT
		var eave_y: float = floor_y + BuildGrid.LEVEL_HEIGHT
		var rotated: Dictionary = BuildGrid.rotate_house_piece(raw_entry, rot_steps)
		var cx: int = anchor.x + int(rotated["dx"])
		var cz: int = anchor.y + int(rotated["dz"])
		var snap: Dictionary = BuildGrid.snap_from_cell(def.kind, int(rotated["axis"]), cx, cz, entry_storey)
		var center: Vector2 = snap["center"]
		var y: float = eave_y if def.is_roof() else floor_y
		out.append({
			"piece_id": def.id, "kind": def.kind,
			"pos": Vector3(center.x, y, center.y), "yaw": float(snap["yaw"]),
		})
	return out

## Entfernt bereits platzierte Teile eines fehlgeschlagenen Hausbaus wieder und erstattet das
## GESAMTE Material der Vorlage (nicht refund_ratio-gemindert — der Bau ist ja gescheitert,
## das ist kein normales Abreißen, siehe remove()).
func _rollback_house(placed_keys: Array[String], player_id: String, total_cost: Dictionary) -> void:
	for key in placed_keys:
		_registry.remove(key)
		_despawn_key(key)
	_give_back(player_id, total_cost)

# ─────────────────────────────────────────────
# Chunk-Ansichten
# ─────────────────────────────────────────────

func on_chunk_loaded(coord: Vector2i) -> void:
	for rec in _registry.records_in_chunk(coord, _chunk_size):
		_spawn(rec)

func on_chunk_unloaded(coord: Vector2i) -> void:
	for rec in _registry.records_in_chunk(coord, _chunk_size):
		_despawn_key(String(rec["key"]))

## Anzahl aktuell existierender Ansichten (für Tests/Debug).
func get_view_count() -> int:
	var n: int = 0
	for node in _nodes.values():
		if is_instance_valid(node):
			n += 1
	return n

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _get_def(piece_id: String) -> BuildPieceDefinition:
	if not _defs_cb.is_valid():
		return null
	return _defs_cb.call(piece_id) as BuildPieceDefinition

func _run_rules(def: BuildPieceDefinition, snap: Dictionary, player_pos: Vector3) -> Dictionary:
	return BuildPlacementRules.check(def, snap, _registry, _ground_fn, _editor.get_layer(), player_pos, _water_level_fn)

func _affordable(player_id: String, def: BuildPieceDefinition) -> bool:
	if not _can_afford.is_valid():
		return true
	return bool(_can_afford.call(player_id, def.cost))

func _give_back(player_id: String, items: Dictionary) -> void:
	if _refund.is_valid():
		_refund.call(player_id, items)

## true, wenn die Position bekannt (nicht NAN) UND weiter als REACH entfernt ist.
func _too_far(player_pos: Vector3, target_xz: Vector2) -> bool:
	if is_nan(player_pos.x):
		return false
	return Vector2(player_pos.x, player_pos.z).distance_to(target_xz) > REACH

## cost: bei reason "no_materials" der vollständige Kosten-Dictionary (item_id -> benötigte
## Menge), damit die UI genau sagen kann, was und wie viel fehlt (siehe WorldService._notify_fail).
func _fail(reason: String, cost: Dictionary = {}) -> Dictionary:
	if reason == "no_materials" and not cost.is_empty():
		return {"ok": false, "reason": reason, "key": "", "cost": cost}
	return {"ok": false, "reason": reason, "key": ""}

func _spawn(record: Dictionary) -> void:
	var key: String = String(record["key"])
	if _nodes.has(key) and is_instance_valid(_nodes[key]):
		return
	if not _spawn_cb.is_valid():
		return
	var pos := Vector3(float(record["x"]), float(record["y"]), float(record["z"]))
	var cfg: Dictionary = {
		"piece_id": String(record["piece_id"]), "key": key, "yaw": float(record.get("yaw", 0.0)),
	}
	var node: Node3D = _spawn_cb.call(ENTITY_TYPE, pos, cfg) as Node3D
	if is_instance_valid(node):
		_nodes[key] = node

func _despawn_key(key: String) -> void:
	var node: Variant = _nodes.get(key)
	_nodes.erase(key)
	if is_instance_valid(node) and _despawn_cb.is_valid():
		_despawn_cb.call(node)
