extends ServiceNode
# justified: Thread-Ergebnisse via call_deferred auf Main-Thread; WorldScene als Child-Node.
class_name WorldGenerationService

## WorldGenerationService — Prozedurale Welt-Generierung.
##
## Verantwortung:
##   - Positionen für Entities (Bäume, Erze) generieren
##   - Seed-basiert und damit reproduzierbar (selber Seed = selbe Welt)
##   - Verhindert Überlappungen durch Mindestabstand-Prüfung
##
## Integration:
##   WorldSpawner._generate_positions() ruft generate_world_async(seed_value, data, height_cb)
##   auf und awaited generation_complete, wenn kein Savegame vorhanden ist.
##
## Abhängigkeiten (deps): [] — reine Logik, kein Service nötig

const LOG_CAT := "WorldGen"

## Registrierte type_ids (siehe EntityOrchestrator._configure_pool_sizes) — jede
## generierte Position bekommt zufällig einen dieser Typen zugewiesen statt
## pauschal "oak_tree"/"iron_ore" zu sein.
const TREE_TYPES: Array[String] = ["oak_tree", "willow_tree", "maple_tree"]
const ORE_TYPES:  Array[String] = ["iron_ore", "copper_ore"]

var world_half_size: float      = 30.0
var min_tree_distance: float    = 4.0
var min_ore_distance: float     = 5.0
var min_spawn_clearance: float  = 6.0
var tree_count: int             = 12
var ore_count: int              = 5

## Callback für Terrain-Höhe — wird pro Aufruf an _generate_world_data() übergeben.
## Kein persistentes Feld mehr: verhindert das Fenster, in dem der Service
## halbfertig konfiguriert ist (temporale Kopplung, Architekturplan 1.5).
var _active_height_cb: Callable = Callable()  # nur während einer laufenden Generierung gültig

signal generation_complete(data: WorldData)
signal generation_failed(reason: String)

var _thread:     Thread  = null
var _thread_seed: int    = 0
var _thread_data: WorldData = null
var _gen_timer_id: int   = -1  ## AppLogger.log_begin()-Handle, gültig während einer laufenden Generierung

func configure(_deps: ServiceDeps) -> void:
	AppLogger.log_debug("WorldGenerationService konfiguriert.", LOG_CAT)

func on_ready() -> void:
	AppLogger.log_info("WorldGenerationService bereit.", LOG_CAT)

## Reine Positions-Berechnung — KEIN AppLogger, KEIN Node-Zugriff.
## Läuft ausschließlich im Worker-Thread (siehe _thread_generate()) und ist
## deshalb strikt thread-safe zu halten: AppLogger/Node-APIs sind auf dem
## Main-Thread nicht reentrant und dürfen von hier aus nicht aufgerufen werden.
## Wenn data == null wird eine neue WorldData erstellt.
## height_cb: Callable(x: float, z: float) -> float — optional, Fallback y=0.
func _generate_world_data(seed_value: int, data: WorldData, height_cb: Callable) -> WorldData:
	if data == null:
		data = WorldData.new()
	_active_height_cb = height_cb

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Bäume generieren — reine Geometrie zuerst, dann Typ pro Position zuweisen.
	var tree_positions := _generate_positions(
		rng, tree_count, min_tree_distance, min_spawn_clearance, []
	)
	for pos in tree_positions:
		var type_id: String = TREE_TYPES[rng.randi() % TREE_TYPES.size()]
		data.add_typed_tree(type_id, pos)

	# Erze generieren — mit Abstand zu Bäumen
	var ore_positions := _generate_positions(
		rng, ore_count, min_ore_distance, min_spawn_clearance, tree_positions
	)
	for pos in ore_positions:
		var type_id: String = ORE_TYPES[rng.randi() % ORE_TYPES.size()]
		data.add_typed_ore(type_id, pos)

	return data

## Generiert einen deterministischen Seed aus einem String (z.B. Spieler-Name).
static func seed_from_string(s: String) -> int:
	var hash_val := 0
	for i in range(s.length()):
		hash_val = (hash_val * 31 + s.unicode_at(i)) & 0x7FFFFFFF
	return hash_val

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _generate_positions(
	rng:             RandomNumberGenerator,
	count:           int,
	min_dist:        float,
	spawn_clearance: float,
	avoid_positions: Array[Vector3]
) -> Array[Vector3]:
	## Platziert `count` Positionen innerhalb der Weltgrenzen.
	## Garantiert Mindestabstand zueinander und zu avoid_positions.
	## Bricht nach max_attempts ab um Endlosschleifen zu vermeiden.

	var placed: Array[Vector3] = []
	var max_attempts := count * 30  # 30 Versuche pro gewünschter Position
	var attempts     := 0

	while placed.size() < count and attempts < max_attempts:
		attempts += 1

		var x := rng.randf_range(-world_half_size, world_half_size)
		var z := rng.randf_range(-world_half_size, world_half_size)
		var candidate := Vector3(x, 0.0, z)

		# Spawn-Clearance prüfen (Abstand vom Ursprung)
		if candidate.length() < spawn_clearance:
			continue

		# Nicht ins Wasser spawnen — Terrain-Höhe prüfen
		if _active_height_cb.is_valid():
			var h: float = _active_height_cb.call(x, z)
			# water_level ≈ 0.8 — Entities sollen nur auf Land spawnen
			if h < 0.3:
				continue
			candidate.y = h
		
		# Abstand zu bereits platzierten Positionen
		if not _is_far_enough(candidate, placed, min_dist):
			continue

		# Abstand zu avoid_positions (z.B. Bäume wenn Erze platziert werden)
		if not _is_far_enough(candidate, avoid_positions, min_dist):
			continue

		placed.append(candidate)

	if placed.size() < count:
		AppLogger.log_warn(
			"Nur %d/%d Positionen platziert (max_attempts=%d erreicht)." % [
				placed.size(), count, max_attempts
			],
			LOG_CAT
		)

	return placed

static func _is_far_enough(candidate: Vector3, others: Array[Vector3], min_dist: float) -> bool:
	for other in others:
		if candidate.distance_to(other) < min_dist:
			return false
	return true

# ─────────────────────────────────────────────
# ─────────────────────────────────────────────

## Einziger öffentlicher Einstiegspunkt für Welt-Generierung.
## Startet die Berechnung im Hintergrund-Thread und emittiert generation_complete(data)
## wenn fertig, bzw. generation_failed(reason) bei Fehler.
##
## Aufrufer awaiten generation_complete (siehe WorldSpawner._generate_positions()):
##   _world_gen.generate_world_async(seed, data, height_cb)
##   var result: WorldData = await _world_gen.generation_complete
##
## height_cb: Callable(x: float, z: float) -> float — direkt übergeben,
## kein persistentes Feld mehr (verhindert temporale Kopplung via set_height_callback).
func generate_world_async(seed_value: int, data: WorldData = null, height_cb: Callable = Callable()) -> void:
	if is_instance_valid(_thread) and _thread.is_started():
		AppLogger.log_error(
			"generate_world_async(): Thread läuft bereits — überlappende Aufrufe sind ein Bug beim Aufrufer.",
			LOG_CAT
		)
		generation_failed.emit("generation_already_in_progress")
		return

	_thread_seed = seed_value
	_thread_data = data if data != null else WorldData.new()
	_active_height_cb = height_cb

	# Ohne validen height_cb entfällt die Wasser-Vermeidung in _generate_positions()
	# komplett (Bäume/Erze können im Wasser landen) — hier statt dort loggen, weil
	# _generate_world_data() im Worker-Thread läuft und dort kein AppLogger-Aufruf
	# erlaubt ist (siehe _thread_generate()).
	if not height_cb.is_valid():
		AppLogger.log_warn(
			"generate_world_async(): kein valider height_cb übergeben — Wasser-Vermeidung wird für diese Generierung übersprungen.",
			LOG_CAT
		)

	_gen_timer_id = AppLogger.log_begin("WorldGenerationService.generate_world_async(seed=%d)" % seed_value, LOG_CAT)

	_thread = Thread.new()
	_thread.start(_thread_generate.bind(_thread_seed, _thread_data, height_cb))
	AppLogger.log_info("Welt-Generierung gestartet (Thread, seed=%d)." % seed_value, LOG_CAT)

## Wird aufgerufen wenn der Thread fertig ist (via call_deferred).
## Läuft auf dem Main-Thread — Logging + signal emission sind hier sicher.
func _on_thread_done(result: WorldData) -> void:
	# Thread joinen bevor wir den Pointer freigeben
	if is_instance_valid(_thread):
		_thread.wait_to_finish()
		_thread = null

	if _gen_timer_id != -1:
		AppLogger.log_end("WorldGenerationService.generate_world_async()", _gen_timer_id, LOG_CAT)
		_gen_timer_id = -1

	if is_instance_valid(result):
		AppLogger.log_info(
			"Welt generiert (Seed %d): %d Bäume, %d Erze." % [
				_thread_seed, result.get_tree_count(), result.get_ore_count()
			],
			LOG_CAT
		)
		generation_complete.emit(result)
	else:
		var reason := "WorldData ist null nach Thread-Ausführung."
		AppLogger.log_error(reason, LOG_CAT)
		generation_failed.emit(reason)

## Thread-Arbeiter — läuft NICHT auf dem Main-Thread.
## WICHTIG: Kein AppLogger-Aufruf (nicht thread-safe), kein Node-Zugriff.
## Ruft ausschließlich die reine _generate_world_data()-Berechnung auf.
func _thread_generate(seed_value: int, data: WorldData, height_cb: Callable) -> void:
	var result: WorldData = _generate_world_data(seed_value, data, height_cb)
	# call_deferred: zurück auf Main-Thread für Logging + signal emission
	call_deferred("_on_thread_done", result)

## Phase 7: Cleanup — Thread sauber joinen falls noch aktiv.
func on_cleanup() -> void:
	if is_instance_valid(_thread) and _thread.is_started():
		AppLogger.log_warn("on_cleanup(): Thread noch aktiv — warte auf Finish.", LOG_CAT)
		_thread.wait_to_finish()
	_thread = null
	AppLogger.log_debug("WorldGenerationService bereinigt.", LOG_CAT)
