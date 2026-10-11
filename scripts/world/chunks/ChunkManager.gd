extends Node
class_name ChunkManager

## ChunkManager — Lädt/entlädt Terrain-Chunks basierend auf Spielerposition.
##
## ── KOORDINATEN-SYSTEM ────────────────────────────────────────────────────
## _chunk_to_world(coord) gibt das ZENTRUM des Chunks zurück. Die Chunk-Größe kommt aus
## TerrainConfig (via TerrainField) — es gibt keine zweite Kopie mehr.
##
## TICK-INTEGRATION:
##   Implementiert on_tick() statt _process() — konsistent mit allen anderen Services.
##   WorldService registriert ChunkManager beim ServiceTicker nach initialize().
##
## ASYNC LOAD-QUEUE (P2-Fix):
##   _load_chunk() ist teuer (Terrain sampeln + Mesh + Entity-Spawn = mehrere ms).
##   Bei Bewegung in neuen Chunk wurden früher alle benötigten Chunks synchron im selben
##   Frame geladen → Stotter-Frame bei 4–6 neuen Chunks gleichzeitig.
##   Jetzt: Neue Chunks landen in _pending_load (Queue). on_tick() arbeitet maximal
##   CHUNKS_PER_TICK Einträge pro Frame ab. Unload bleibt synchron (queue_free ist billig).
##
## MULTIPLAYER:
##   Tracked alle registrierten Spieler-Nodes. WorldService ruft add_player()/remove_player()
##   auf. Ein Chunk wird nur entladen wenn er für ALLE Spieler außer Reichweite ist.
##
## Delegiert:
##   Höhe/Wasser/Klima  → TerrainField (die eine Wahrheit, siehe dort)
##   Terrain-Nodes      → TerrainChunkBuilder (Mesh, Kollision, Wasseroberfläche)
##   Entity-Spawning    → ChunkEntitySpawner
##
## HOOKS: set_chunk_callbacks() meldet geladene/entladene Chunks (Bauteile werden pro Chunk
## als Ansicht erzeugt/entfernt, siehe WorldBuildHandler).

const LOG_CAT          := "ChunkManager"
## Radius in Chunks um den Spieler (4 → 9×9 Chunks = 576 m Kantenlänge).
## 2026-10-04: von 3 auf 4 erhöht — mit Gebirgen (bis ~95 m) endete die Welt sonst sichtbar als
## abgeschnittene Bergflanke ~190 m vor dem Spieler.
## UNLOAD_RADIUS immer > LOAD_RADIUS lassen (Hysterese, sonst Lade-/Entlade-Flackern).
const LOAD_RADIUS      := 4
const UNLOAD_RADIUS    := 5
## Maximale Anzahl Chunks die pro on_tick()-Aufruf geladen werden.
## Begrenzt Stotter-Frames wenn viele Chunks gleichzeitig benötigt werden.
## Wert 2: bei 60 fps sind 6 neue Chunks in ~3 Frames geladen (kaum sichtbar).
const CHUNKS_PER_TICK  := 2
## Zeitbudget pro on_tick() in Millisekunden (2026-10-05, Erosionsfilter): Berg-Chunks kosten
## deutlich mehr Rechenzeit als Flachland-Chunks (Erosion pro Vertex in GDScript). Nach dem
## ersten Chunk wird nur weitergeladen, solange das Budget nicht aufgebraucht ist — so landen nie
## zwei teure Chunks im selben Frame. Mindestens EIN Chunk pro Tick wird immer geladen.
const CHUNK_LOAD_BUDGET_MSEC := 10.0

## Stale-Referenz-Bereinigung alle N Sekunden statt jeden Frame.
## Bei 60 fps: alle 300 Frames statt 18.000x pro Minute.
const STALE_CLEANUP_INTERVAL := 5.0
## Gemähtes Gras/Blumen wachsen nach so vielen Sekunden nach (Spielzeit, nicht gespeichert).
const GRASS_REGROW_SEC := 420.0
## So oft (Sekunden) wird nach abgelaufenen Mähkreisen gesucht.
const REGROW_CHECK_INTERVAL := 10.0

var _chunks:           Dictionary   = {}           # { Vector2i: Node3D | null }
var _world_root:       Node3D
var _field:            TerrainField
var _builder:          TerrainChunkBuilder
var _entity_spawner:   ChunkEntitySpawner
var _vegetation:       ChunkVegetationBuilder
## { Vector2i: Dictionary{"heights","water_levels"} } — Höhenraster geladener Chunks, damit die
## Vegetation nach dem Mähen ohne erneutes Terrain-Sampling neu gebaut werden kann (je ~9 KB).
var _grids:            Dictionary   = {}
## { Vector2i: Array[Vector4] } — gemähte Kreise (x = Welt-X, y = Welt-Z, z = Radius, w = Ablauf
## in Sekunden seit Spielstart). Bleibt über Chunk-Entladen erhalten (sonst wüchse das Gras beim
## Wegrennen und Zurückkommen sofort nach), wird aber NICHT gespeichert: nach einem Neustart ist
## die Wiese wieder voll — gewollt, "Gras wächst nach" ist hier reine Atmosphäre.
var _cut_zones:        Dictionary   = {}
var _regrow_timer:     float        = 0.0
## func(node: Node3D) -> void — gibt eine vom ChunkEntitySpawner erzeugte Entity frei.
var _unload_entity:    Callable = Callable()
## Bis initialize() der Default — die Koordinaten-Helfer sind so auch ohne Welt nutzbar (Tests).
var _chunk_size:       float = TerrainConfig.DEFAULT_CHUNK_SIZE

## Optionale Hooks (Callable(coord: Vector2i) -> void), siehe set_chunk_callbacks().
var _on_chunk_loaded:   Callable = Callable()
var _on_chunk_unloaded: Callable = Callable()

## Load-Queue: Chunks die noch nicht geladen wurden, werden hier zwischengepuffert.
## on_tick() arbeitet maximal CHUNKS_PER_TICK Einträge pro Frame ab.
var _pending_load: Array[Vector2i] = []

## Alle bekannten Spieler-Nodes. WorldService befüllt/bereinigt diese Liste.
var _tracked_players:  Array[Node3D] = []

## Cache: letzte bekannte Chunk-Position pro Spieler-Node.
## Verhindert _sync_chunks()-Aufruf wenn sich nichts geändert hat.
var _last_chunks:      Dictionary   = {}           # { Node3D: Vector2i }

## Akkumulierter Δt für periodische Stale-Bereinigung.
var _stale_cleanup_timer: float = 0.0

## `field` ist die Geländewahrheit (Config + world_seed + Spieler-Änderungen). Ihre Edit-
## Schicht muss VOR initialize() gesetzt sein — der Spawn-Chunk wird hier synchron gebaut.
##
## unload_entity_cb (func(node: Node3D)): räumt Entities eines entladenen Chunks ab — OHNE sie als
## "abgeerntet" zu markieren (WorldService: EntityOrchestrator.unload_entity). is_harvested_cb
## (func(type_id, pos) -> bool): bereits Abgeerntetes wird beim erneuten Laden nicht neu gespawnt.
func initialize(
	world_root: Node3D, field: TerrainField, spawn_entity_cb: Callable,
	unload_entity_cb: Callable = Callable(), is_harvested_cb: Callable = Callable()
) -> void:
	_world_root      = world_root
	_field           = field
	_chunk_size      = field.get_config().chunk_size
	_builder         = TerrainChunkBuilder.new(field)
	_unload_entity   = unload_entity_cb
	_entity_spawner  = ChunkEntitySpawner.new(_chunk_size, field.get_seed(), spawn_entity_cb, is_harvested_cb)
	_vegetation      = ChunkVegetationBuilder.new(field, field.get_seed())
	AppLogger.log_info(
		"ChunkManager initialisiert. Chunk-Größe: %.0fm, Radius: %d" % [_chunk_size, LOAD_RADIUS],
		LOG_CAT
	)

	# REFACTOR: (0,0) ist kein Sonderfall mehr (siehe _load_chunk), muss aber
	# SYNCHRON hier geladen werden statt über die async _pending_load-Queue —
	# sonst spawnt der Spieler ein paar Frames lang ohne Boden/Terrain-Physik,
	# bis die Queue (CHUNKS_PER_TICK pro Frame) ihn erreicht.
	_load_chunk(Vector2i(0, 0))

# ─────────────────────────────────────────────
# Spieler-Tracking API (Sprint G)
# ─────────────────────────────────────────────

## Registriert einen Spieler-Node für Chunk-Tracking.
## WorldService ruft dies nach spawn_entity("player", …) auf.
func add_player(player: Node3D) -> void:
	if not is_instance_valid(player):
		return
	if _tracked_players.has(player):
		return
	_tracked_players.append(player)
	_last_chunks[player] = Vector2i(999, 999)  # Sentinel → erzwingt sofortiges Update
	AppLogger.log_debug(
		"Spieler registriert für Chunk-Tracking. Gesamt: %d" % _tracked_players.size(),
		LOG_CAT
	)

## Entfernt einen Spieler-Node aus dem Chunk-Tracking.
## WorldService ruft dies vor/bei despawn_entity() auf.
func remove_player(player: Node3D) -> void:
	_tracked_players.erase(player)
	_last_chunks.erase(player)
	AppLogger.log_debug(
		"Spieler aus Chunk-Tracking entfernt. Gesamt: %d" % _tracked_players.size(),
		LOG_CAT
	)
	# Chunks sofort neu bewerten — nach Entfernen eines Spielers könnten
	# Chunks für verbleibende Spieler zu weit entfernt sein.
	if not _tracked_players.is_empty():
		_sync_chunks()

# ─────────────────────────────────────────────
# Hooks + Gelände-Änderungen (Umgraben / Bauen)
# ─────────────────────────────────────────────

## Meldet geladene/entladene Chunks. Jeder Callback: func(coord: Vector2i) -> void.
## Vor initialize() setzen, damit auch der synchron geladene Spawn-Chunk gemeldet wird.
func set_chunk_callbacks(on_loaded: Callable, on_unloaded: Callable) -> void:
	_on_chunk_loaded = on_loaded
	_on_chunk_unloaded = on_unloaded

## Baut Terrain-Mesh, Kollision und Wasser aller GELADENEN Chunks neu, die einen der Punkte
## als Vertex besitzen (nach Änderungen an der Edit-Schicht des TerrainField). Nicht geladene
## Chunks brauchen nichts — sie lesen das Feld beim nächsten Laden. Entities des Chunks
## bleiben unangetastet (kein Respawn!). Gibt die Anzahl neu gebauter Chunks zurück.
func refresh_terrain_points(points: Array[Vector2i]) -> int:
	var rebuilt: int = 0
	for coord in TerrainEditLayer.chunks_for_points(points, _chunk_size):
		if _rebuild_terrain(coord):
			rebuilt += 1
	return rebuilt

# ─────────────────────────────────────────────
# Tick
# ─────────────────────────────────────────────

## ITickable — aufgerufen vom ServiceTicker (statt _process).
func on_tick(delta: float) -> void:
	# Periodische Stale-Referenz-Bereinigung (alle STALE_CLEANUP_INTERVAL Sekunden).
	# Vorher: filter() lief jeden Frame = O(n) auch wenn sich nichts geändert hat.
	# Jetzt: läuft nur alle 5s — bei 8 Spielern 96% weniger filter()-Aufrufe.
	# Timer ist reine Zeit-Buchhaltung — läuft unabhängig davon ob gerade Spieler
	# getrackt werden oder ein world_root existiert (Chunk-Sync/-Laden weiter unten).
	_stale_cleanup_timer += delta
	if _stale_cleanup_timer >= STALE_CLEANUP_INTERVAL:
		_stale_cleanup_timer = 0.0
		var _still_valid: Array[Node3D] = []
		for p in _tracked_players:
			if is_instance_valid(p):
				_still_valid.append(p)
		_tracked_players = _still_valid

	_regrow_timer += delta
	if _regrow_timer >= REGROW_CHECK_INTERVAL:
		_regrow_timer = 0.0
		_regrow_expired_cuts()

	if _tracked_players.is_empty():
		return

	if not is_instance_valid(_world_root):
		return

	# Prüfe ob sich irgendein Spieler in einen neuen Chunk bewegt hat.
	var any_moved := false
	for player in _tracked_players:
		# BUGFIX (2026-09-14): is_instance_valid() allein reicht nicht — beim
		# Szenenwechsel (z.B. 'Zurück zum Hauptmenü') existiert der Player-
		# Node kurzzeitig noch im Speicher, ist aber schon aus dem SceneTree
		# entfernt. .global_position darauf löst 'Condition "!is_inside_tree()"
		# is_true. Returning: Transform3D()' aus, weil der Getter intern
		# get_global_transform() aufruft.
		if not is_instance_valid(player) or not player.is_inside_tree():
			continue
		var new_chunk := _world_to_chunk(player.global_position)
		if new_chunk != _last_chunks.get(player, Vector2i(999, 999)):
			_last_chunks[player] = new_chunk
			any_moved = true

	if any_moved:
		_sync_chunks()

	# Async Load-Queue: max CHUNKS_PER_TICK Chunks pro Frame laden.
	var loaded := 0
	var load_started_usec: int = Time.get_ticks_usec()
	while not _pending_load.is_empty() and loaded < CHUNKS_PER_TICK:
		if loaded > 0 and float(Time.get_ticks_usec() - load_started_usec) / 1000.0 > CHUNK_LOAD_BUDGET_MSEC:
			break
		var coord: Vector2i = _pending_load.pop_front()
		# BUGFIX (2026-09-19, "Welt besteht nur aus einem Chunk"): _sync_chunks()
		# trägt jeden ausstehenden Chunk als Platzhalter `_chunks[coord] = null`
		# ein. Die alte Prüfung `not _chunks.has(coord)` war damit für JEDEN
		# Queue-Eintrag false (has() ist bei einem null-Wert true) → kein einziger
		# Chunk außer dem synchron geladenen (0,0) wurde je gebaut. Richtig ist:
		# laden, wenn der Eintrag ein Platzhalter ist. Wurde er zwischenzeitlich
		# entladen (Key fehlt) oder schon geladen (gültiger Node), überspringen.
		if _is_pending(coord):
			_load_chunk(coord)
			loaded += 1

# ─────────────────────────────────────────────
# Chunk-Verwaltung
# ─────────────────────────────────────────────

## Berechnet die Vereinigung aller benötigten Chunks für alle Spieler
## und synchronisiert Laden/Entladen entsprechend.
func _sync_chunks() -> void:
	# Sammle alle benötigten Coords als Set (Dictionary-Keys für O(1)-Lookup).
	var needed: Dictionary = {}
	for player in _tracked_players:
		if not is_instance_valid(player):
			continue
		var pc: Vector2i = _last_chunks.get(player, _world_to_chunk(player.global_position))
		for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
				needed[Vector2i(pc.x + dx, pc.y + dz)] = true

	# Fehlende Chunks in die Load-Queue einreihen (async, max CHUNKS_PER_TICK/Frame).
	# Sofort als "bekannt" in _chunks markieren (Wert: null = ausstehend) damit
	# _sync_chunks() denselben Chunk nicht mehrfach in die Queue schreibt.
	for coord in needed:
		if not _chunks.has(coord):
			_chunks[coord] = null  # Placeholder: ausstehend
			if not _pending_load.has(coord):
				_pending_load.append(coord)

	# Nächste Chunks zuerst laden — der Boden unter/vor dem Spieler ist wichtiger
	# als der Horizont (sonst kann man bei schneller Bewegung ins Leere fallen).
	_sort_pending_by_player_distance()

	# Entlade Chunks die für KEINEN Spieler mehr in Reichweite sind.
	var to_unload: Array[Vector2i] = []
	for coord in _chunks:
		var in_range := false
		for player in _tracked_players:
			if not is_instance_valid(player):
				continue
			var pc: Vector2i = _last_chunks.get(player, _world_to_chunk(player.global_position))
			var dist: int = max(abs(coord.x - pc.x), abs(coord.y - pc.y))
			if dist <= UNLOAD_RADIUS:
				in_range = true
				break
		if not in_range:
			to_unload.append(coord)
	for coord in to_unload:
		_unload_chunk(coord)

## Ein Chunk ist "ausstehend", wenn er in _chunks als Platzhalter (null bzw.
## ungültiger Node) eingetragen ist, aber noch nicht gebaut wurde.
func _is_pending(coord: Vector2i) -> bool:
	return _chunks.has(coord) and not is_instance_valid(_chunks[coord])

func _sort_pending_by_player_distance() -> void:
	if _pending_load.size() < 2:
		return
	var centers: Array[Vector2i] = []
	for player in _tracked_players:
		if is_instance_valid(player) and _last_chunks.has(player):
			centers.append(_last_chunks[player])
	if centers.is_empty():
		return
	_pending_load.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _dist_sq_to_nearest(a, centers) < _dist_sq_to_nearest(b, centers)
	)

static func _dist_sq_to_nearest(coord: Vector2i, centers: Array[Vector2i]) -> int:
	var best: int = 1 << 30
	for c in centers:
		var dx: int = coord.x - c.x
		var dy: int = coord.y - c.y
		best = mini(best, dx * dx + dy * dy)
	return best

func _load_chunk(coord: Vector2i) -> void:
	# (0,0) ist kein Sonderfall: derselbe Pfad wie jeder andere Chunk (früher baute
	# WorldFactory dort ein eigenes Mesh — dadurch bekam nur der Spawn-Chunk Entities).
	var center := _chunk_to_world(coord)
	AppLogger.log_debug("Lade Chunk %s @ Zentrum %s" % [str(coord), str(center)], LOG_CAT)

	var chunk_node := Node3D.new()
	chunk_node.name     = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk_node.position = Vector3(center.x, 0.0, center.y)
	_world_root.add_child(chunk_node)

	var grid: Dictionary = _builder.build(coord, chunk_node)
	_chunks[coord] = chunk_node

	# Gebäude (samt NPCs) und Props zuerst — die Vegetation liest deren Freihaltezonen.
	_entity_spawner.spawn_for_chunk(coord, center, _field, chunk_node)
	_build_vegetation(coord, chunk_node, center, grid)
	if _on_chunk_loaded.is_valid():
		_on_chunk_loaded.call(coord)

## Ersetzt Terrain, Kollision und Wasser eines geladenen Chunks. false, wenn der Chunk
## nicht geladen ist (Platzhalter/fehlt).
func _rebuild_terrain(coord: Vector2i) -> bool:
	var chunk_node: Variant = _chunks.get(coord)
	if not is_instance_valid(chunk_node):
		return false
	var grid: Dictionary = _builder.rebuild(coord, chunk_node as Node3D)
	# Gras/Büsche folgen dem veränderten Gelände (sonst schweben sie über Gruben).
	_build_vegetation(coord, chunk_node as Node3D, _chunk_to_world(coord), grid)
	return true

func _build_vegetation(
	coord: Vector2i, chunk_node: Node3D, center: Vector2, grid: Dictionary,
	fresh_cut: Vector3 = Vector3(0.0, 0.0, -1.0)
) -> Dictionary:
	if _vegetation == null or grid.is_empty():
		return {"grass": 0, "flowers": 0}
	_grids[coord] = grid
	return _vegetation.build(
		coord, chunk_node, center,
		grid["heights"], grid["water_levels"],
		_field.get_config().get_resolution(), _chunk_size,
		_entity_spawner.get_clear_zones(coord), _active_cut_circles(coord), fresh_cut
	)

## Mäht einen Kreis (Welt-X/Z + Radius) Gras und Blumen ab. Gibt zurück, wie viele Büschel/Blumen
## dabei weggefallen sind ({"grass": n, "flowers": m}) — der WorldService macht daraus den Ertrag.
## Betroffen sind alle geladenen Chunks, die der Kreis berührt; der Kreis bleibt für
## GRASS_REGROW_SEC vermerkt, auch für Chunks, die gerade nicht geladen sind.
func cut_vegetation(world_xz: Vector2, radius: float) -> Dictionary:
	var total: Dictionary = {"grass": 0, "flowers": 0}
	var circle := Vector3(world_xz.x, world_xz.y, radius)
	var expires: float = float(Time.get_ticks_msec()) / 1000.0 + GRASS_REGROW_SEC
	var lo: Vector2i = _world_to_chunk(Vector3(world_xz.x - radius, 0.0, world_xz.y - radius))
	var hi: Vector2i = _world_to_chunk(Vector3(world_xz.x + radius, 0.0, world_xz.y + radius))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var coord := Vector2i(cx, cz)
			var node: Variant = _chunks.get(coord, null)
			if is_instance_valid(node) and _grids.has(coord):
				var res: Dictionary = _build_vegetation(coord, node as Node3D, _chunk_to_world(coord), _grids[coord], circle)
				total["grass"] += int(res.get("grass", 0))
				total["flowers"] += int(res.get("flowers", 0))
			var list: Array = _cut_zones.get(coord, [])
			list.append(Vector4(circle.x, circle.y, circle.z, expires))
			_cut_zones[coord] = list
	return total

## Aktive (nicht abgelaufene) Mähkreise des Chunks als Vector3 (x, z, Radius).
func _active_cut_circles(coord: Vector2i) -> Array:
	var out: Array = []
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for z: Vector4 in _cut_zones.get(coord, []):
		if z.w > now:
			out.append(Vector3(z.x, z.y, z.z))
	return out

## Entfernt abgelaufene Mähkreise; betroffene geladene Chunks bekommen ihr Gras zurück.
func _regrow_expired_cuts() -> void:
	if _cut_zones.is_empty():
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for coord: Vector2i in _cut_zones.keys():
		var list: Array = _cut_zones[coord]
		var kept: Array = []
		for z: Vector4 in list:
			if z.w > now:
				kept.append(z)
		if kept.size() == list.size():
			continue
		if kept.is_empty():
			_cut_zones.erase(coord)
		else:
			_cut_zones[coord] = kept
		var node: Variant = _chunks.get(coord, null)
		if is_instance_valid(node) and _grids.has(coord):
			_build_vegetation(coord, node as Node3D, _chunk_to_world(coord), _grids[coord])

func _unload_chunk(coord: Vector2i) -> void:
	if not _chunks.has(coord):
		return
	var chunk_node = _chunks[coord]
	_chunks.erase(coord)
	_grids.erase(coord)
	# Aus Load-Queue entfernen falls Chunk entladen wird bevor er geladen wurde.
	_pending_load.erase(coord)
	if is_instance_valid(chunk_node):
		# Hook VOR dem Freigeben: Ansichten (Bauteile) dieses Chunks verschwinden mit ihm.
		if _on_chunk_unloaded.is_valid():
			_on_chunk_unloaded.call(coord)
		# Bäume, Erze, Tiere, Gegner dieses Chunks abräumen — sonst schweben sie ohne Boden im
		# Nichts und entstehen beim Zurückkehren ein zweites Mal.
		if _entity_spawner != null:
			_entity_spawner.despawn_for_chunk(coord, _unload_entity)
		chunk_node.queue_free()
	AppLogger.log_debug("Chunk %s entladen." % str(coord), LOG_CAT)

# ─────────────────────────────────────────────
# Koordinaten-Helpers
# ─────────────────────────────────────────────

func _world_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / _chunk_size), roundi(pos.z / _chunk_size))

func _chunk_to_world(coord: Vector2i) -> Vector2:
	return Vector2(coord.x * _chunk_size, coord.y * _chunk_size)

