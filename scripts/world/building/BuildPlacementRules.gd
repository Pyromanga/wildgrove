class_name BuildPlacementRules
extends RefCounted

## BuildPlacementRules — EINE Quelle der Wahrheit dafür, ob/wie ein Bauteil platziert werden
## darf. Wird vom echten Platzieren (WorldBuildHandler.place()) UND von der Vorschau
## (Geist im Baumodus) benutzt — dadurch kann der Geist nie "grün" zeigen, wo das Bauen
## dann doch scheitert.
##
## Rein statisch und ohne Engine-Zugriff: Höhen kommen über ground_fn, alles andere über
## Parameter. Kostenprüfung/Reichweite sind bewusst NICHT hier (hängen an Inventar bzw.
## Spielerposition) sondern im WorldBuildHandler.
##
## Rückgabe von check():
##   {ok: bool, reason: String, key: String, y: float, snap: Dictionary, level: Dictionary}
##   reason (bei ok=false): "supports_others" (nur Abreißen) | "occupied" | "no_ground" | "too_steep" | "unsupported" | "player_in_way" | "in_water"
##   y:     Basis-Oberkante des Bauteils (Boden: Oberkante; Wand: Unterkante der sichtbaren Wand)
##   level: nur FLOOR — Plan zum Einebnen des Geländes {ok, changes, target_y}, sonst {}

## Abstand, den ein Spieler mindestens von einer neuen Wand haben muss (sonst steckt er fest).
const PLAYER_CLEARANCE: float = 0.7
## Boden liegt minimal über dem (eingeebneten) Gelände — vermeidet Z-Fighting der Oberflächen.
## Mindestens TerrainEditLayer.QUANTUM: die Delta-Schicht rundet auf dieses Raster, ein
## kleinerer Wert würde beim Einebnen wegquantisiert und Boden/Gelände wären wieder plan.
const FLOOR_LIFT: float = 0.05
## Maximaler Höhenunterschied zwischen den Wandenden bei freistehender Wand (ohne Boden).
const MAX_WALL_SLOPE: float = 1.5
## Bauhöhe muss mindestens so weit über dem Wasserspiegel liegen (kein Bauen im/am Wasser).
const MIN_DRY_CLEARANCE: float = 0.2

static func check(
	def: BuildPieceDefinition,
	snap: Dictionary,
	registry: BuildRegistry,
	ground_fn: Callable,
	edit_layer: TerrainEditLayer = null,
	player_pos: Vector3 = Vector3(NAN, NAN, NAN),
	water_level_fn: Callable = Callable()
) -> Dictionary:
	var key: String = snap["key"]
	var result := {"ok": false, "reason": "", "key": key, "y": 0.0, "snap": snap, "level": {}}

	if registry.has_key(key):
		result["reason"] = "occupied"
		return result

	var storey: int = int(snap.get("storey", 0))
	if def.is_floor():
		if storey > 0:
			return _check_floor_upper(snap, registry, result)
		return _check_floor(def, snap, registry, ground_fn, edit_layer, water_level_fn, result)
	if def.is_roof():
		return _check_roof(snap, registry, result)
	if def.is_stairs():
		return _check_stairs(snap, registry, ground_fn, water_level_fn, result)
	if def.is_target():
		return _check_target(snap, registry, ground_fn, water_level_fn, result)
	# WALL, DOOR, WINDOW: alle wandartig (dieselbe Zellkante, dieselben Regeln — siehe
	# BuildPieceDefinition.is_wall_like() / BuildGrid-Klassenkommentar).
	if storey > 0:
		return _check_wall_upper(snap, registry, player_pos, result)
	return _check_wall(def, snap, registry, ground_fn, player_pos, water_level_fn, result)

## water_level_fn(x, z) -> float, wie TerrainField.get_water_level_at(): NICHT mehr überall
## derselbe Wert (Flüsse liegen je nach Ort unterschiedlich hoch, siehe BUGFIX 2026-09-20
## "Wasser/Flüsse & Seen sind alle auf einer Ebene"), also an der jeweiligen Bauposition
## abfragen statt einmal vorab als Zahl zu übergeben. Ungültiges Callable = keine
## Wasserprüfung (Default für Tests, wie vorher water_level = -INF).
static func _water_level_at(water_level_fn: Callable, x: float, z: float) -> float:
	return float(water_level_fn.call(x, z)) if water_level_fn.is_valid() else -INF

# ─────────────────────────────────────────────

static func _check_floor(
	_def: BuildPieceDefinition, snap: Dictionary, _registry: BuildRegistry,
	ground_fn: Callable, edit_layer: TerrainEditLayer, water_level_fn: Callable, result: Dictionary
) -> Dictionary:
	var cell: Vector2i = snap["cell"]
	var corners: Array[Vector2i] = BuildGrid.floor_corner_lattice(cell)

	var sum: float = 0.0
	var wx_sum: float = 0.0
	var wz_sum: float = 0.0
	for p in corners:
		var w: Vector2 = TerrainEditLayer.lattice_to_world(p)
		var h: float = float(ground_fn.call(w.x, w.y))
		if is_nan(h):
			result["reason"] = "no_ground"
			return result
		sum += h
		wx_sum += w.x
		wz_sum += w.y

	# Bauhöhe = gerundeter Mittelwert der Ecken. Das Gelände wird darunter auf diese Höhe
	# eingeebnet (minus FLOOR_LIFT) — Böden liegen also plan, auch am Hang.
	var y: float = BuildGrid.quantize_y(sum / float(corners.size()))
	result["y"] = y
	var water_here: float = _water_level_at(
		water_level_fn, wx_sum / float(corners.size()), wz_sum / float(corners.size())
	)
	if y < water_here + MIN_DRY_CLEARANCE:
		result["reason"] = "in_water"
		return result

	if edit_layer != null:
		var plan: Dictionary = edit_layer.plan_level(corners, y - FLOOR_LIFT, ground_fn)
		if not plan["ok"]:
			result["reason"] = plan["reason"]   # "too_steep" | "no_ground"
			return result
		plan["target_y"] = y - FLOOR_LIFT
		result["level"] = plan

	result["ok"] = true
	return result

static func _check_wall(
	_def: BuildPieceDefinition, snap: Dictionary, registry: BuildRegistry,
	ground_fn: Callable, player_pos: Vector3, water_level_fn: Callable, result: Dictionary
) -> Dictionary:
	var axis: int = snap["axis"]
	var cell: Vector2i = snap["cell"]

	# Bau-Reihenfolge-Schutz: nicht auf den Spieler bauen.
	if not is_nan(player_pos.x):
		var d: float = BuildGrid.distance_to_wall(Vector2(player_pos.x, player_pos.z), axis, cell.x, cell.y)
		if d < PLAYER_CLEARANCE:
			result["reason"] = "player_in_way"
			return result

	# Angrenzende Böden bestimmen die Basishöhe (Wand steht AUF dem Boden).
	var floors: Array[Dictionary] = registry.floors_adjacent_to_wall(axis, cell.x, cell.y)
	if not floors.is_empty():
		var top: float = -INF
		for rec in floors:
			top = maxf(top, float(rec.get("y", 0.0)))
		result["y"] = top
		result["ok"] = true
		return result

	# Freistehend: braucht Bodenkontakt und darf nicht zu schräg stehen.
	var ends: Array[Vector2] = BuildGrid.wall_endpoints(axis, cell.x, cell.y)
	var center: Vector2 = snap["center"]
	var samples: Array[Vector2] = [ends[0], ends[1], center]
	var lo: float = INF
	var hi: float = -INF
	for s in samples:
		var h: float = float(ground_fn.call(s.x, s.y))
		if is_nan(h):
			result["reason"] = "no_ground"
			return result
		lo = minf(lo, h)
		hi = maxf(hi, h)
	if hi - lo > MAX_WALL_SLOPE:
		result["reason"] = "too_steep"
		return result
	# Basis auf die HÖCHSTE Stelle: Lücken nach unten füllt der Skirt, ins Gelände
	# ragende Wand-Enden am Hang gibt es dadurch nicht.
	result["y"] = BuildGrid.quantize_y(hi)
	var water_here: float = _water_level_at(water_level_fn, center.x, center.y)
	if float(result["y"]) < water_here + MIN_DRY_CLEARANCE:
		result["reason"] = "in_water"
		return result
	result["ok"] = true
	return result

# ─────────────────────────────────────────────
# Obere Ebenen (storey > 0) — Bauteile brauchen Halt von unten, kein Gelände-Bezug
# ─────────────────────────────────────────────

## Boden auf Ebene n: braucht eine Wand der Ebene n-1 auf einer seiner vier Kanten ODER (Auskragung/Balkon/Erker)
## eine lückenlose Bodenkette derselben Ebene bis BuildRegistry.FLOOR_CANTILEVER_REACH Zellen zu einem wandgetragenen
## Boden. Oberkante = Oberkante der tragenden Wand (Wandbasis + LEVEL_HEIGHT), bei mehreren die höchste bzw. die des
## nächsten tragenden Bodens. EIN Pfad: die Regel lebt in BuildRegistry.floor_support_top().
static func _check_floor_upper(snap: Dictionary, registry: BuildRegistry, result: Dictionary) -> Dictionary:
	var storey: int = int(snap["storey"])
	var top: float = registry.floor_support_top(snap["cell"], storey)
	if is_inf(top):
		result["reason"] = "unsupported"
		return result
	result["y"] = top
	result["ok"] = true
	return result

## Wand auf Ebene n: steht auf einem Boden derselben Ebene in einer Nachbarzelle ODER direkt
## auf der Wand darunter (gleiche Kante, Ebene n-1). Der Spieler-Abstand zählt nur, wenn er
## auf Höhe der Wand steht (sonst würde ein Spieler am Boden das Bauen über seinem Kopf sperren).
static func _check_wall_upper(
	snap: Dictionary, registry: BuildRegistry, player_pos: Vector3, result: Dictionary
) -> Dictionary:
	var storey: int = int(snap["storey"])
	var axis: int = snap["axis"]
	var cell: Vector2i = snap["cell"]

	var y: float = -INF
	for rec in registry.floors_adjacent_to_wall(axis, cell.x, cell.y, storey):
		y = maxf(y, float(rec.get("y", 0.0)))
	if is_inf(y):
		var below: Dictionary = registry.wall_at(axis, cell.x, cell.y, storey - 1)
		if below.is_empty():
			result["reason"] = "unsupported"
			return result
		y = float(below.get("y", 0.0)) + BuildGrid.LEVEL_HEIGHT

	if not is_nan(player_pos.x) and player_pos.y > y - 0.5 and player_pos.y < y + BuildGrid.LEVEL_HEIGHT:
		var d: float = BuildGrid.distance_to_wall(Vector2(player_pos.x, player_pos.z), axis, cell.x, cell.y)
		if d < PLAYER_CLEARANCE:
			result["reason"] = "player_in_way"
			return result

	result["y"] = y
	result["ok"] = true
	return result

# ─────────────────────────────────────────────
# Dach — schließt Wände DERSELBEN Ebene nach oben ab (kein eigener Halt "von unten" wie bei
# storey>0-Böden/Wänden: das Dach liegt AUF den Wänden seiner eigenen Ebene, nicht der Ebene
# darüber).
# ─────────────────────────────────────────────

## Dach: braucht mindestens eine Wand derselben Ebene auf einer der vier Kanten der Zelle.
## Basis (Traufe) = höchste Wandoberkante (Wandbasis-y + LEVEL_HEIGHT) rund um die Zelle.
## ÜBERHANG (Wunsch "nicht jedes Dachstück braucht eine tragende Wand", erweitert auf Reichweite 3): eine
## Zelle OHNE eigene Wand darf überdacht werden, wenn über eine zusammenhängende Kette bereits stehender Dächer
## (Nachbarzellen derselben Ebene) höchstens ROOF_OVERHANG_REACH Zellen entfernt ein Dach liegt, das SELBST von
## einer Wand getragen wird. Das Dach ragt dann bis zu drei Zellen weit über — Kirchenschiffe, Hallen, offene
## Pavillons und Kolonnaden brauchen nur noch Wände am Rand. Die Traufhöhe übernimmt das nächste tragende
## Dach (bei mehreren gleich nahen das höchste). Die Kette muss lückenlos aus Dächern bestehen: ein Dach ohne
## Dach-Nachbarn hat weiter keinen Halt. Ein EINZIGER Pfad — keine Sonderfälle je Bauteil.
const ROOF_OVERHANG_REACH: int = 3

static func _check_roof(snap: Dictionary, registry: BuildRegistry, result: Dictionary) -> Dictionary:
	var storey: int = int(snap["storey"])
	var cell: Vector2i = snap["cell"]
	var walls: Array[Dictionary] = registry.walls_around_cell(cell, storey)
	if not walls.is_empty():
		var top: float = -INF
		for rec in walls:
			top = maxf(top, float(rec.get("y", 0.0)) + BuildGrid.LEVEL_HEIGHT)
		result["y"] = top
		result["ok"] = true
		return result

	var overhang_y: float = _roof_overhang_eave(cell, storey, registry)
	if is_inf(overhang_y):
		result["reason"] = "unsupported"
		return result
	result["y"] = overhang_y
	result["ok"] = true
	return result

## Traufhöhe des NÄCHSTEN wandgetragenen Dachs in einer lückenlosen Dachkette (Breitensuche über die vier
## Nachbarzellen, höchstens ROOF_OVERHANG_REACH Schritte); -INF, wenn keins erreichbar ist.
static func _roof_overhang_eave(cell: Vector2i, storey: int, registry: BuildRegistry) -> float:
	var seen: Dictionary = {cell: true}
	var frontier: Array[Vector2i] = [cell]
	for _step in ROOF_OVERHANG_REACH:
		var next: Array[Vector2i] = []
		var best: float = -INF
		for c: Vector2i in frontier:
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n_cell: Vector2i = c + offset
				if seen.has(n_cell):
					continue
				seen[n_cell] = true
				var rec: Dictionary = registry.get_record(BuildGrid.roof_key(n_cell, storey))
				if rec.is_empty():
					continue
				if registry.walls_around_cell(n_cell, storey).is_empty():
					next.append(n_cell)   # hängt selbst im Überhang → Kette läuft weiter
				else:
					best = maxf(best, float(rec.get("y", 0.0)))
		if not is_inf(best):
			return best
		frontier = next
	return -INF

# ─────────────────────────────────────────────
# Treppe — belegt wie ein Boden eine ganze Zelle, verbindet aber Ebene n mit n+1 begehbar.
# Ebene 0: braucht wie ein Boden festen, nicht zu steilen Untergrund (kein Einebnen — die
#   Treppe folgt dem Gelände nicht, sie überbrückt seine Höhe). Ebene n>0: wie ein oberer
#   Boden, braucht eine Wand der Ebene n-1 an einer Zellkante als Auflager.
# ─────────────────────────────────────────────

static func _check_stairs(
	snap: Dictionary, registry: BuildRegistry, ground_fn: Callable, water_level_fn: Callable, result: Dictionary
) -> Dictionary:
	var storey: int = int(snap["storey"])
	if storey > 0:
		return _check_floor_upper(snap, registry, result)

	var cell: Vector2i = snap["cell"]
	var corners: Array[Vector2i] = BuildGrid.floor_corner_lattice(cell)
	var lo: float = INF
	var hi: float = -INF
	var wx_sum: float = 0.0
	var wz_sum: float = 0.0
	for p in corners:
		var w: Vector2 = TerrainEditLayer.lattice_to_world(p)
		var h: float = float(ground_fn.call(w.x, w.y))
		if is_nan(h):
			result["reason"] = "no_ground"
			return result
		lo = minf(lo, h)
		hi = maxf(hi, h)
		wx_sum += w.x
		wz_sum += w.y
	if hi - lo > MAX_WALL_SLOPE:
		result["reason"] = "too_steep"
		return result

	# Basis auf die NIEDRIGSTE Ecke (wie ein Boden am Hangfuß) — die Treppe steigt von dort
	# über ihre volle Höhe auf, ohne unter das Gelände zu ragen.
	var y: float = BuildGrid.quantize_y(lo)
	result["y"] = y
	var water_here: float = _water_level_at(water_level_fn, wx_sum / float(corners.size()), wz_sum / float(corners.size()))
	if y < water_here + MIN_DRY_CLEARANCE:
		result["reason"] = "in_water"
		return result
	result["ok"] = true
	return result

# ─────────────────────────────────────────────
# Requisit (TARGET) — belegt wie ein Boden eine ganze Zelle, braucht aber KEINEN Halt (keine
# angrenzende Wand/kein Boden nötig): steht frei auf dem Gelände, wie eine Treppe auf Ebene 0,
# nur ohne Steigungsprüfung und ohne Einebnen (eine Zielscheibe muss dem Gelände nicht folgen,
# nur "irgendwo fest draufstehen"). Ebene n>0: wie ein oberer Boden, braucht eine Wand der
# Ebene n-1 an einer Zellkante als Auflager.
# ─────────────────────────────────────────────

static func _check_target(
	snap: Dictionary, registry: BuildRegistry, ground_fn: Callable, water_level_fn: Callable, result: Dictionary
) -> Dictionary:
	var storey: int = int(snap["storey"])
	if storey > 0:
		return _check_floor_upper(snap, registry, result)

	var cell: Vector2i = snap["cell"]
	var corners: Array[Vector2i] = BuildGrid.floor_corner_lattice(cell)
	var sum: float = 0.0
	var wx_sum: float = 0.0
	var wz_sum: float = 0.0
	for p in corners:
		var w: Vector2 = TerrainEditLayer.lattice_to_world(p)
		var h: float = float(ground_fn.call(w.x, w.y))
		if is_nan(h):
			result["reason"] = "no_ground"
			return result
		sum += h
		wx_sum += w.x
		wz_sum += w.y

	# Bauhöhe = gerundeter Mittelwert der Ecken (wie bei einem Boden) — aber OHNE das Gelände
	# einzuebnen: eine Requisite ist Dekoration/Funktionsobjekt, kein tragendes Bauteil.
	var y: float = BuildGrid.quantize_y(sum / float(corners.size()))
	result["y"] = y
	var water_here: float = _water_level_at(
		water_level_fn, wx_sum / float(corners.size()), wz_sum / float(corners.size())
	)
	if y < water_here + MIN_DRY_CLEARANCE:
		result["reason"] = "in_water"
		return result
	result["ok"] = true
	return result

## Menschenlesbare Meldung zu einem reason-Code (für Benachrichtigungen).
static func reason_text(reason: String) -> String:
	match reason:
		"occupied":      return "Hier steht schon etwas."
		"no_ground":     return "Kein fester Boden gefunden."
		"too_steep":     return "Das Gelände ist hier zu uneben."
		"unsupported":   return "Hier hat das Bauteil keinen Halt."
		"supports_others": return "Darauf steht noch etwas."
		"player_in_way": return "Du stehst im Weg."
		"in_water":      return "Im Wasser kann man nicht bauen."
		"too_far":       return "Zu weit entfernt."
		"no_materials":  return "Dir fehlen Materialien."
		"unknown_piece": return "Unbekanntes Bauteil."
		"unknown_house": return "Unbekannte Bauvorlage."
		"coop_unsupported": return "Bauen und Graben sind vorerst nur im Solo-Modus möglich."
		_:               return "Bauen nicht möglich."
