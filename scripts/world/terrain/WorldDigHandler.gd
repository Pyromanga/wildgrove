class_name WorldDigHandler
extends RefCounted

## WorldDigHandler — Leitern und Funde: Regeln, Mutation, Ansichten pro Chunk.
##
## Hilfsklasse von WorldService (Muster wie WorldBuildHandler). Kennt weder Inventar noch
## Spieler direkt — Material und Position kommen über Callables/Parameter vom Aufrufer.
## Die Wahrheit liegen in LadderRegistry/DigFindRegistry; die 3D-Nodes (Ladder, DigFind)
## sind Ansichten, die on_chunk_loaded() erzeugt und on_chunk_unloaded() wieder entfernt.

const LOG_CAT := "WorldDig"
const ENTITY_LADDER: String = "ladder"
const ENTITY_FIND: String = "dig_find"
## Maximale Entfernung Spieler → Leiterfuß beim Abbauen.
const REACH: float = 10.0
## Funde liegen knapp über dem Boden (kein Z-Fighting mit dem Gelände).
const FIND_LIFT: float = 0.15
## Mindestabstand zwischen zwei Funden (waagerecht).
const FIND_MIN_SPACING: float = 1.5
## Nach Geländeänderungen werden Funde in diesem Umkreis neu auf den Boden gesetzt.
const RESEAT_RADIUS: float = 7.0

var _ladders: LadderRegistry
var _finds: DigFindRegistry
var _ground_fn: Callable
var _spawn_cb: Callable
var _despawn_cb: Callable
var _chunk_size: float
var _can_afford: Callable = Callable()
var _pay: Callable = Callable()
var _refund: Callable = Callable()
var _rng := RandomNumberGenerator.new()
var _ladder_nodes: Dictionary = {}
var _find_nodes: Dictionary = {}

## ground_fn(x, z) -> float; spawn_cb(type_id, pos, cfg) -> Node3D; despawn_cb(node).
func _init(
	ladders: LadderRegistry, finds: DigFindRegistry, ground_fn: Callable,
	spawn_cb: Callable, despawn_cb: Callable, chunk_size: float
) -> void:
	_ladders = ladders
	_finds = finds
	_ground_fn = ground_fn
	_spawn_cb = spawn_cb
	_despawn_cb = despawn_cb
	_chunk_size = chunk_size
	_rng.randomize()

func set_inventory_ops(can_afford: Callable, pay: Callable, refund: Callable) -> void:
	_can_afford = can_afford
	_pay = pay
	_refund = refund

## Für Tests: deterministische Würfel.
func seed_rng(value: int) -> void:
	_rng.seed = value

# ─────────────────────────────────────────────
# Leitern
# ─────────────────────────────────────────────

## Stellt eine Leiter an die Wand vor `player_pos` (Blickrichtung `facing`).
## Rückgabe: {ok, reason, key, cost, length}
##   reason: "" | "no_ground" | "no_wall" | "too_long" | "occupied" | "no_materials"
func place_ladder(player_id: String, player_pos: Vector3, facing: Vector3) -> Dictionary:
	var join_fn: Callable = func(p: Vector3) -> bool:
		return _ladders.has_foot_near(p, LadderPlanner.JOIN_RADIUS, LadderPlanner.JOIN_DY)
	var plan: Dictionary = LadderPlanner.plan(player_pos, facing, _ground_fn, join_fn)
	if not bool(plan["ok"]):
		return {"ok": false, "reason": String(plan["reason"])}
	var rec: Dictionary = plan["record"]
	var key: String = String(rec["key"])
	if _ladders.has_key(key):
		return {"ok": false, "reason": "occupied"}
	var cost: Dictionary = plan["cost"]
	if _can_afford.is_valid() and not bool(_can_afford.call(player_id, cost)):
		return {"ok": false, "reason": "no_materials", "cost": cost}
	if _pay.is_valid() and not bool(_pay.call(player_id, cost)):
		return {"ok": false, "reason": "no_materials", "cost": cost}
	rec["owner"] = player_id
	if not _ladders.add(rec):
		if _refund.is_valid():
			_refund.call(player_id, cost)
		return {"ok": false, "reason": "occupied"}
	_spawn_ladder(rec)
	AppLogger.log_info("Leiter '%s' aufgestellt (%.1f m)." % [key, float(rec["len"])], LOG_CAT)
	return {"ok": true, "reason": "", "key": key, "cost": cost, "length": float(rec["len"])}

## Baut eine Leiter ab und erstattet das Material.
## reason: "" | "no_ladder" | "too_far"
func remove_ladder(player_id: String, key: String, player_pos: Vector3) -> Dictionary:
	var rec: Dictionary = _ladders.get_record(key)
	if rec.is_empty():
		return {"ok": false, "reason": "no_ladder"}
	var foot := Vector3(float(rec["x"]), float(rec["y"]), float(rec["z"]))
	if not is_nan(player_pos.x) and player_pos.distance_to(foot) > REACH:
		return {"ok": false, "reason": "too_far"}
	_ladders.remove(key)
	_despawn_view(_ladder_nodes, key)
	if _refund.is_valid():
		_refund.call(player_id, {LadderPlanner.LADDER_ITEM: int(rec.get("cost", 1))})
	return {"ok": true, "reason": ""}

# ─────────────────────────────────────────────
# Funde
# ─────────────────────────────────────────────

## Nach einem Grabvorgang: Funde neu auf den Boden setzen, dann ggf. ein neuer Fund.
## center: Pinselmitte (x/z), depth: Grabtiefe dort in m (> 0 = gegraben).
## Rückgabe: {found: String ("" = nichts, sonst DigFindTable-Art), key: String}
func after_dig(center: Vector2, depth: float) -> Dictionary:
	reseat_finds(center)
	if not _finds.near(center.x, center.y, FIND_MIN_SPACING).is_empty():
		return {"found": ""}
	var kind: String = DigFindTable.roll(depth, _rng)
	if kind.is_empty():
		return {"found": ""}
	var y: float = float(_ground_fn.call(center.x, center.y))
	if is_nan(y):
		return {"found": ""}
	var rec: Dictionary = {
		"key": DigFindRegistry.make_key(center.x, center.y), "kind": kind,
		"x": center.x, "y": y + FIND_LIFT, "z": center.y,
	}
	if not _finds.add(rec):
		return {"found": ""}
	_spawn_find(rec)
	return {"found": kind, "key": String(rec["key"])}

## Setzt Funde um `center` auf die aktuelle Bodenhöhe (der Boden wurde gegraben/aufgeschüttet).
func reseat_finds(center: Vector2) -> void:
	for rec in _finds.near(center.x, center.y, RESEAT_RADIUS):
		var ground: float = float(_ground_fn.call(float(rec["x"]), float(rec["z"])))
		if is_nan(ground):
			continue
		var y: float = ground + FIND_LIFT
		if absf(y - float(rec["y"])) < 0.02:
			continue
		var key: String = String(rec["key"])
		_finds.set_height(key, y)
		var node: Variant = _find_nodes.get(key)
		if is_instance_valid(node):
			(node as Node3D).position = Vector3(float(rec["x"]), y, float(rec["z"]))

## Ein Fund wurde geborgen (aufgerufen von DigFind).
func remove_find(key: String) -> void:
	_finds.remove(key)
	_find_nodes.erase(key)

# ─────────────────────────────────────────────
# Chunk-Streaming
# ─────────────────────────────────────────────

func on_chunk_loaded(coord: Vector2i) -> void:
	for rec in _ladders.records_in_chunk(coord, _chunk_size):
		_spawn_ladder(rec)
	for rec in _finds.records_in_chunk(coord, _chunk_size):
		_spawn_find(rec)

func on_chunk_unloaded(coord: Vector2i) -> void:
	for rec in _ladders.records_in_chunk(coord, _chunk_size):
		_despawn_view(_ladder_nodes, String(rec["key"]))
	for rec in _finds.records_in_chunk(coord, _chunk_size):
		_despawn_view(_find_nodes, String(rec["key"]))

func get_view_count() -> int:
	var n: int = 0
	for node in _ladder_nodes.values():
		if is_instance_valid(node):
			n += 1
	for node in _find_nodes.values():
		if is_instance_valid(node):
			n += 1
	return n

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _spawn_ladder(rec: Dictionary) -> void:
	var key: String = String(rec["key"])
	if _ladder_nodes.has(key) and is_instance_valid(_ladder_nodes[key]):
		return
	if not _spawn_cb.is_valid():
		return
	var pos := Vector3(float(rec["x"]), float(rec["y"]), float(rec["z"]))
	var node: Node3D = _spawn_cb.call(ENTITY_LADDER, pos, {"key": key, "record": rec}) as Node3D
	if is_instance_valid(node):
		_ladder_nodes[key] = node

func _spawn_find(rec: Dictionary) -> void:
	var key: String = String(rec["key"])
	if _find_nodes.has(key) and is_instance_valid(_find_nodes[key]):
		return
	if not _spawn_cb.is_valid():
		return
	var pos := Vector3(float(rec["x"]), float(rec["y"]), float(rec["z"]))
	var node: Node3D = _spawn_cb.call(ENTITY_FIND, pos, {"key": key, "kind": String(rec["kind"])}) as Node3D
	if is_instance_valid(node):
		_find_nodes[key] = node

func _despawn_view(nodes: Dictionary, key: String) -> void:
	var node: Variant = nodes.get(key)
	nodes.erase(key)
	if is_instance_valid(node) and _despawn_cb.is_valid():
		_despawn_cb.call(node)

## Menschenlesbare Meldung zu einem reason-Code (nur die hier neuen Codes; "occupied",
## "no_materials", "too_far", "no_ground" kommen aus BuildPlacementRules).
static func reason_text(reason: String) -> String:
	match reason:
		"no_wall":   return "Hier gibt es keine Wand für eine Leiter."
		"too_long":  return "Die Wand ist zu hoch für eine Leiter."
		"no_ladder": return "Diese Leiter gibt es nicht mehr."
		_:           return "Das geht hier nicht."
