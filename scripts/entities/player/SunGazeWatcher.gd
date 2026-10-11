class_name SunGazeWatcher
extends Node

## SunGazeWatcher — Easter Egg "sun_gazer" (siehe AchievementService.gd
## Klassenkommentar "EASTER EGGS"): 5 Sekunden am Stück in Egoperspektive
## direkt in die Sonne schauen.
##
## Nur als Kind-Node am LOKAL gesteuerten Player.gd angehängt (siehe dortiger
## Spawn-Guard "_owner_peer_id == _local_peer_id") — für jeden anderen
## (Remote-)Player-Node wäre das sinnlos: deren Kamera-Ausrichtung/-Zoom ist
## rein lokaler Client-Zustand auf DEREN Maschine, hier nicht einsehbar.
##
## Reine Beobachtung, keine Autorität: prüft nur camera.is_first_person()
## und den Winkel zwischen Blickrichtung und Sonnenrichtung, meldet nach
## SUN_GAZE_SECONDS Sekunden ununterbrochenen Anschauens EINMAL über
## NetworkBridge.send_client_observed_achievement() (siehe dort für das
## Vertrauensmodell — der Server prüft das nicht nach, es gibt nichts, das
## er nachprüfen könnte).

const LOG_CAT := "SunGazeWatcher"

## Wie lange am Stück "in die Sonne geschaut" werden muss.
const SUN_GAZE_SECONDS: float = 5.0

## cos(6°) — enger Kegel um die exakte Sonnenrichtung. Eng genug, dass es
## sich nach einem gezielten "genau in die Sonne schauen" anfühlt, nicht nach
## einem beiläufigen "generell Richtung Himmel gucken".
const DOT_THRESHOLD: float = 0.995

const ACHIEVEMENT_ID := "sun_gazer"

var _camera: PlayerCamera = null
var _sun: DirectionalLight3D = null
var _network: NetworkBridge = null
var _player: Player = null

var _elapsed: float = 0.0
var _reported: bool = false

## camera/sun/network dürfen einzeln fehlen (z.B. Sun noch nicht geladen,
## Welt lädt noch) — _process() prüft jeden Zugriff einzeln ab, kein Crash,
## einfach kein Fortschritt in der Zwischenzeit. player: für die
## player_id-Auflösung beim Melden (siehe Player.get_local_player_uuid()).
func configure(camera: PlayerCamera, sun: DirectionalLight3D, network: NetworkBridge, player: Player) -> void:
	_camera = camera
	_sun = sun
	_network = network
	_player = player

func _process(delta: float) -> void:
	if _reported:
		set_process(false)  # fertig, kein weiterer Tick nötig
		return
	if not _looking_at_sun():
		_elapsed = 0.0
		return
	_elapsed += delta
	if _elapsed >= SUN_GAZE_SECONDS:
		_report()

func _looking_at_sun() -> bool:
	if not is_instance_valid(_camera) or not is_instance_valid(_camera.camera):
		return false
	if not _camera.is_first_person():
		return false
	if not is_instance_valid(_sun):
		return false

	# DirectionalLight3D "leuchtet" entlang seiner lokalen -Z-Achse (dorthin
	# wandert das Licht) — die Richtung VOM Spieler ZUR Sonne am Himmel ist
	# also die UMGEKEHRTE Achse, +Z.
	var to_sun: Vector3 = _sun.global_transform.basis.z.normalized()
	if to_sun.y < 0.05:
		return false  # Sonne (rechnerisch) unter dem Horizont -> nachts kein Sonne-Anschauen möglich

	# Camera3D blickt entlang seiner lokalen -Z-Achse.
	var looking_dir: Vector3 = -_camera.camera.global_transform.basis.z.normalized()
	return looking_dir.dot(to_sun) >= DOT_THRESHOLD

func _report() -> void:
	_reported = true
	if not is_instance_valid(_network) or not is_instance_valid(_player):
		AppLogger.log_warn("SunGazeWatcher: NetworkBridge/Player fehlt — kann Achievement nicht melden.", LOG_CAT)
		return
	var player_id := _player.get_local_player_uuid()
	if player_id.is_empty():
		AppLogger.log_warn("SunGazeWatcher: player_id nicht auflösbar — kann Achievement nicht melden.", LOG_CAT)
		return
	_network.send_client_observed_achievement(player_id, ACHIEVEMENT_ID)
	AppLogger.log_info("SunGazeWatcher: '%s' gemeldet." % ACHIEVEMENT_ID, LOG_CAT)
