extends ServiceNode
# justified: ServiceTicker-Registrierung (add_child) und on_tick() brauchen Node-Lifecycle.
class_name AmbientSpawnService

## AmbientSpawnService — generisches Nachspawnen von Gegnern rund um
## registrierte, ORTSFESTE "Quellen" (Grabsteine, Lagerfeuer, ...), egal ob
## natürlich generiert (Gravestone.gd/GoblinCampfire.gd, per Welt-Chunk-
## Generierung, siehe ChunkEntitySpawner) oder von Spielern gebaut
## (BuildPiece.gd, ggf. freigeschaltet über Quest — siehe
## BuildPieceDefinition.ambient_spawn_type_id).
##
## HISTORIE (Refactoring, Wunsch "Analog für Goblins/Lagerfeuer bauen, dabei
## nachhaltig/clean architecture"): hieß ursprünglich GraveyardSpawnService
## und kannte nur EINEN hartcodierten Spawn-Typ ("skeleton"). Der Wunsch nach
## einem zweiten, unabhängigen Quellentyp (Lagerfeuer → Goblin) hätte sonst
## entweder Code-Duplikation (ein zweiter, fast identischer Dienst) oder
## Verzweigungen im bestehenden Dienst ("wenn Friedhof dann X, wenn Lager
## dann Y") erzwungen — beides schlecht wartbar. Stattdessen: JEDER
## registrierte Punkt trägt jetzt seinen eigenen `spawn_type_id` (siehe
## register_point()). Der Dienst selbst weiß nichts von "Friedhöfen" oder
## "Lagern" — das bleibt vollständig Sache der jeweiligen Entity
## (GraveyardGravestone.gd, GoblinCampfire.gd, BuildPiece.gd), die beim
## Registrieren sagt, WAS an ihrer Position nachwachsen soll. Neue
## Quellentypen (z.B. später ein Wolfsrudel-Bau) brauchen dadurch KEINE
## Änderung an diesem Dienst mehr, nur eine neue Entity-Klasse, die
## register_point() mit ihrem eigenen type_id aufruft.
##
## ABGRENZUNG ZU RespawnService (bewusst ZWEI Dienste statt einer):
## RespawnService respawnt GENAU DAS abgeerntete/getötete Objekt an SEINER
## EIGENEN Position, ausgelöst durch das entity_despawned-Signal (Baum
## fällt → derselbe Baum wächst später an derselben Stelle nach). Hier geht
## es um etwas grundsätzlich anderes: ein UNVERÄNDERLICH stehendes Objekt
## (Grabstein, Lagerfeuer) soll LAUFEND einen ANDEREN Entity-Typ (Skelett,
## Goblin) in seiner NÄHE erzeugen, unabhängig davon ob/wann die Quelle
## selbst je despawnt. Eine Erweiterung von RespawnService (dessen _configs
## rein typ-basiert sind, kein Konzept von "an einem Punkt X spawnt Typ Y")
## hätte dessen einfaches Modell verwässert — analog zur bestehenden
## Trennung ChunkEntitySpawner (Erstbesiedlung) vs. RespawnService
## (Nachwuchs nach Ernte): zwei verschiedene Probleme, zwei verschiedene
## Dienste.
##
## SPAWN-CALLBACK statt direkter EntityOrchestrator-Referenz: identisches
## Muster zu RespawnService (siehe dortiger Klassenkommentar
## "Abhängigkeitsproblem gelöst") — WorldService.on_ready() injiziert seine
## eigene spawn_entity()-Methode als Closure, kein zirkulärer DI-Graph.
##
## POPULATION-CAP PRO PUNKT (nicht global): verhindert, dass eine einzelne
## Quelle bei langer Serverlaufzeit eine Gegner-Armee anhäuft, ohne die
## übrigen Quellen der Karte zu drosseln. Zählt bewusst ALLE Gegner der
## Gruppe "enemies" in der Nähe (nicht nur den eigenen spawn_type_id) — eine
## Quelle neben einem bereits überlaufenen Fleck soll nicht zusätzlich
## draufsatteln, egal welcher Gegnertyp dort schon steht.

const LOG_CAT := "AmbientSpawnService"
const DEFAULT_RADIUS: float        = 10.0
const DEFAULT_MAX_ALIVE: int       = 2
const DEFAULT_INTERVAL_SECS: float = 75.0
## Wunsch "sollen nur spawnen wenn man in der Nähe ist": kein Spieler
## innerhalb dieses Radius um den Punkt → on_tick() überspringt den Spawn-
## Versuch komplett (siehe _has_nearby_player()). Bewusst GRÖSSER als
## DEFAULT_RADIUS (der Radius, IN DEM gespawnt wird) — sonst würde der
## Gegner quasi auf dem Spieler erscheinen statt "in der Nähe, aber nicht
## direkt vor der Nase". Deutlich kleiner als die Chunk-Ladedistanz: eine
## registrierte Quelle in einem geladenen, aber weit entfernten Chunk
## (Multiplayer, mehrere Spieler weit auseinander) soll trotzdem still
## bleiben, bis wirklich jemand in Reichweite ist.
const DEFAULT_ACTIVATION_RADIUS: float = 40.0
## Verhindert, dass bei vielen registrierten Quellen alle im selben Tick fällig
## werden (z.B. wenn ein Chunk mit mehreren Quell-Punkten gleichzeitig lädt).
const CHECK_JITTER_SECS: float = 20.0

class _Point:
	var position: Vector3
	var spawn_type_id: String
	var radius: float
	var max_alive: int
	var interval_secs: float
	var activation_radius: float
	var next_check_at: float  ## Time.get_unix_time_from_system()

## key → _Point. key ist ein eindeutiger, stabiler Bezeichner der Quelle
## (entity_uuid für natürliche Entities, "buildpiece:"+piece_key für Bauteile
## — NICHT die Position: zwei Quellen könnten durch Spieler-Bau sehr nah
## beieinander stehen, eine Positions-Rundung wie bei WorldData.make_key()
## würde sie dann fälschlich zusammenlegen).
var _points: Dictionary = {}
## Callable(type_id: String, position: Vector3) -> Node3D — von WorldService.
## on_ready() injiziert, identisches Muster zu RespawnService._spawn_cb.
var _spawn_cb: Callable = Callable()
var _ticker: ServiceTicker = null
var _rng := RandomNumberGenerator.new()

# ─────────────────────────────────────────────
# Phase 4/5/7
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_ticker = deps.get_optional(ServiceKeys.TICKER) as ServiceTicker
	_rng.randomize()
	AppLogger.log_debug("AmbientSpawnService konfiguriert (wartet auf Callback-Injection).", LOG_CAT)

func on_ready() -> void:
	if is_instance_valid(_ticker):
		_ticker.register_service(self)
	AppLogger.log_info("AmbientSpawnService bereit.", LOG_CAT)

func on_cleanup() -> void:
	_points.clear()
	_spawn_cb = Callable()
	AppLogger.log_debug("AmbientSpawnService bereinigt.", LOG_CAT)

# ─────────────────────────────────────────────
# Callback-Injection (von WorldService.on_ready())
# ─────────────────────────────────────────────

## cb: Callable(type_id: String, position: Vector3) -> Node3D
func set_spawn_callback(cb: Callable) -> void:
	assert(cb.is_valid(), "AmbientSpawnService.set_spawn_callback: Callable ist ungültig!")
	_spawn_cb = cb
	AppLogger.log_debug("Spawn-Callback injiziert.", LOG_CAT)

# ─────────────────────────────────────────────
# Öffentliche API — von GraveyardGravestone.gd / GoblinCampfire.gd /
# BuildPiece.gd aufgerufen
# ─────────────────────────────────────────────

## Meldet einen Spawn-Punkt an. spawn_type_id: welcher Entity-Typ hier
## nachwachsen soll (z.B. "skeleton", "goblin") — siehe Klassenkommentar
## "HISTORIE" für die Design-Entscheidung, das hier statt fest im Dienst zu
## verankern. Aufgerufen aus on_spawn() (Autorität-Guard liegt beim
## Aufrufer, analog zu allen anderen request_*()-losen, rein additiven
## Registrierungs-Aufrufen in diesem Codebase, z.B.
## RespawnService.register_config()).
func register_point(
	key: String, position: Vector3, spawn_type_id: String,
	radius: float = DEFAULT_RADIUS, max_alive: int = DEFAULT_MAX_ALIVE,
	interval_secs: float = DEFAULT_INTERVAL_SECS,
	activation_radius: float = DEFAULT_ACTIVATION_RADIUS
) -> void:
	if key.is_empty():
		AppLogger.log_warn("register_point() ohne key ignoriert.", LOG_CAT)
		return
	if spawn_type_id.is_empty():
		AppLogger.log_warn("register_point('%s') ohne spawn_type_id ignoriert." % key, LOG_CAT)
		return
	var p := _Point.new()
	p.position      = position
	p.spawn_type_id = spawn_type_id
	p.radius        = radius
	p.max_alive     = max_alive
	p.interval_secs = interval_secs
	p.activation_radius = activation_radius
	# Jitter auf den ERSTEN Check (nicht erst ab dem zweiten) — sonst würden
	# alle Punkte eines gleichzeitig geladenen Chunks exakt interval_secs nach
	# dem Laden im selben Tick fällig.
	p.next_check_at = Time.get_unix_time_from_system() + _rng.randf_range(0.0, CHECK_JITTER_SECS)
	_points[key] = p
	AppLogger.log_debug(
		"Spawn-Punkt registriert: '%s' @ %s (Typ '%s')." % [key, str(position), spawn_type_id], LOG_CAT
	)

## Meldet einen Spawn-Punkt ab (Quelle despawnt/abgerissen). No-op wenn key
## unbekannt (z.B. doppeltes on_despawn() — siehe EntityPool-Reuse-Pattern).
func unregister_point(key: String) -> void:
	if _points.erase(key):
		AppLogger.log_debug("Spawn-Punkt entfernt: '%s'." % key, LOG_CAT)

func get_point_count() -> int:
	return _points.size()

# ─────────────────────────────────────────────
# Tick — fällige Punkte prüfen und ggf. spawnen
# ─────────────────────────────────────────────

func on_tick(_delta: float) -> void:
	if _points.is_empty() or not _spawn_cb.is_valid():
		return
	var now := Time.get_unix_time_from_system()
	# Tick-Budget: max. 1 Spawn pro Frame über ALLE Punkte hinweg. Enger als
	# RespawnService's Budget von 3 — jeder Spawn hier erzeugt einen
	# zusätzlichen, aktiv kämpfenden Gegner statt eines passiven Harvestables.
	var budget := 1
	for key in _points.keys():
		if budget <= 0:
			break
		var p: _Point = _points[key]
		if now < p.next_check_at:
			continue
		p.next_check_at = now + p.interval_secs + _rng.randf_range(-CHECK_JITTER_SECS * 0.3, CHECK_JITTER_SECS * 0.3)
		# Wunsch "nur spawnen wenn man in der Nähe ist": next_check_at wird
		# TROTZDEM neu gesetzt (nicht übersprungen/sofort erneut versucht) —
		# sonst würde eine lange unbesuchte Quelle beim ersten Tick nach
		# Spieler-Ankunft sofort spawnen UND der nächste reguläre Check direkt
		# hinterherkommen, was wie "wartet nur auf dich" wirkt statt natürlich.
		if not _has_nearby_player(p.position, p.activation_radius):
			continue
		if _count_nearby_enemies(p.position, p.radius) >= p.max_alive:
			continue
		var offset := Vector3(_rng.randf_range(-p.radius, p.radius), 0.0, _rng.randf_range(-p.radius, p.radius))
		var spawn_pos: Vector3 = p.position + offset
		var entity = _spawn_cb.call(p.spawn_type_id, spawn_pos)
		if is_instance_valid(entity):
			budget -= 1
			AppLogger.log_info(
				"Ambient-Spawn '%s' @ %s (Punkt '%s')." % [p.spawn_type_id, str(spawn_pos), key], LOG_CAT
			)

## Gruppe "player" (nicht "players") — siehe z.B. EntityOrchestrator.
## find_player_by_id() oder IEntityContext.get_local_player() für dasselbe
## Muster. Bricht beim ersten Treffer ab (reine Ja/Nein-Frage, kein Zählen
## nötig wie bei _count_nearby_enemies()).
func _has_nearby_player(position: Vector3, radius: float) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	for node in tree.get_nodes_in_group("player"):
		if node is Node3D and (node as Node3D).global_position.distance_to(position) <= radius:
			return true
	return false

func _count_nearby_enemies(position: Vector3, radius: float) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var n := 0
	for node in tree.get_nodes_in_group("enemies"):
		if node is Node3D and (node as Node3D).global_position.distance_to(position) <= radius:
			n += 1
	return n
