extends SpringArm3D
class_name PlayerCamera

## PlayerCamera — Schulter-Kamera an einem SpringArm3D.
##
## FIX (2026-09-21, "Mauern/Decken übereinander schwer zu bauen"): vorher war
## der Pitch auf [-75°, 0°] geklemmt — der Spieler konnte nie nach OBEN sehen
## (0° war bereits die Obergrenze, waagerecht). Für Decken/hohe Wände musste
## man "blind" bauen. Jetzt bis MAX_PITCH_UP (positiv = Kamera schwenkt unter
## den Spieler und blickt hinauf) erweitert.
##
## FEATURE (First-Person-Zoom): Zoom-Untergrenze von 3.0 auf MIN_ZOOM_FIRST_PERSON
## gesenkt — nah genug heran, dass die Kamera praktisch an der Kopf-Position
## (position.y == 1.6, siehe _init()) sitzt. Damit lässt sich exakt anvisieren,
## wohin man baut (übereinanderliegende Wände/Decken), statt nur aus der
## Schulteransicht zu schätzen. Unterhalb von FIRST_PERSON_THRESHOLD wird das
## Player-Mesh ausgeblendet (first_person_changed-Signal) — sonst stünde das
## eigene Modell zwischen Kamera und Blickrichtung.

## FEATURE (Vogelperspektive + Karte): Wer weit über den normalen Zoom hinaus herauszoomt,
## fliegt die Kamera nach oben, kippt sie schrittweise in die Senkrechte (Vogelperspektive,
## echte Live-Welt darunter) und blendet ab MAP_ZOOM_START die gebackene Weltkarte ein
## (siehe WorldMapView/WorldMapBaker). Alle Zoom-Stufen sind reine Funktionen von `zoom`
## (statische Helfer unten → einzeln testbar):
##
##   zoom  0.4 … 1.2   Ego-Perspektive (wie bisher)
##   zoom  1.2 … 15    Schulterkamera (wie bisher, Spieler-Pitch)
##   zoom   15 … 35    Kamera kippt sanft in die Senkrechte (birds_eye_weight)
##   zoom   55 … 80    Karte blendet ein (map_blend); Kamera steigt bis MAX_CAMERA_HEIGHT
##   zoom   80 … 300   Kamera bleibt oben, die KARTE zoomt heraus (view_half_extent_m)
##
## Oberhalb von BIRDS_EYE_START ist die Spring-Arm-Kollision aus (Dächer/Bäume sollen die Sicht
## nach oben nicht abschneiden). Zoom-Schritte wachsen mit dem Zoom (zoom_step), damit man mit
## Mausrad/Pinch in vernünftiger Zeit von 15 auf 300 kommt, ohne das Gefühl im Nahbereich zu ändern.

const LOG_CAT := "Camera"

@export var touch_sensitivity: float = 0.006
@export var zoom_speed: float = 5.0
@export var rotation_speed: float = 10.0

const MIN_ZOOM_FIRST_PERSON: float = 0.4
## Normale Schulterkamera reicht bis hier; darüber beginnt die Vogelperspektive.
const MAX_ZOOM: float = 15.0
## Absolute Obergrenze (Karte maximal herausgezoomt).
const MAX_ZOOM_MAP: float = 300.0
const FIRST_PERSON_THRESHOLD: float = 1.2

## Vogelperspektive: ab hier kippt die Kamera, ab FULL ist sie senkrecht (smoothstep dazwischen).
const BIRDS_EYE_START: float = 15.0
const BIRDS_EYE_FULL: float = 35.0
## Karte: ab START blendet sie ein, ab FULL ist sie voll sichtbar (und die Kamera oben angekommen).
const MAP_ZOOM_START: float = 55.0
const MAP_ZOOM_FULL: float = 80.0
## Höhe der Kamera über dem Spieler, wenn die Karte voll sichtbar ist.
const MAX_CAMERA_HEIGHT: float = 80.0
## Pitch in der Vogelperspektive (nicht exakt -90°: vermeidet Gimbal-Sonderfälle).
const BIRDS_EYE_PITCH_DEG: float = -89.0
## Ab diesem Zoom nimmt der Zoom-Schritt proportional zu (siehe zoom_step()).
const ZOOM_STEP_LINEAR_UNTIL: float = 12.0

const MIN_PITCH_DEG: float = -75.0
const MAX_PITCH_UP_DEG: float = 65.0

var _target_zoom: float = 8.0
## Geglätteter "logischer" Zoom (läuft bis MAX_ZOOM_MAP). spring_length ist daran gekoppelt,
## aber bei MAX_CAMERA_HEIGHT gedeckelt.
var _zoom_smooth: float = 8.0
var _target_yaw: float = 0.0
var _target_pitch: float = deg_to_rad(-35.0)

## true während spring_length unter FIRST_PERSON_THRESHOLD liegt. Player.gd
## abonniert first_person_changed und blendet darüber das eigene Mesh aus/ein
## (siehe Klassenkommentar).
var _is_first_person: bool = false

## Wird gefeuert, sobald spring_length die FIRST_PERSON_THRESHOLD über- bzw.
## unterschreitet. Player.gd hält die Camera-Referenz bereits (siehe
## Player.on_spawn()) — kein EventBus nötig, rein lokale Subsystem-Kopplung
## wie touch_sensitivity/rotation_speed oben.
signal first_person_changed(active: bool)

## Wird gefeuert, wenn die Karte beginnt sichtbar zu werden (map_blend > 0) bzw. wieder verschwindet.
signal map_mode_changed(active: bool)
var _map_active: bool = false

var camera: Camera3D

func _init() -> void:
	position = Vector3(0, 1.6, 0)
	spring_length = _target_zoom
	collision_mask = 1
	_build_camera()

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)

func handle_input(inp: TouchInput, delta: float) -> void:
	_process_rotation(inp, delta)
	_process_zoom(inp, delta)

func _process_rotation(inp: TouchInput, delta: float) -> void:
	var c_delta := inp.cam_delta
	inp.cam_delta = Vector2.ZERO
	if c_delta != Vector2.ZERO:
		_target_yaw -= c_delta.x * touch_sensitivity
		_target_pitch = clamp(
			_target_pitch - c_delta.y * touch_sensitivity,
			deg_to_rad(MIN_PITCH_DEG), deg_to_rad(MAX_PITCH_UP_DEG)
		)
	rotation.y = lerp_angle(rotation.y, _target_yaw, rotation_speed * delta)
	# Vogelperspektive: je weiter herausgezoomt, desto mehr Richtung senkrecht. Der vom Spieler
	# gewählte Pitch (_target_pitch) bleibt unangetastet und gilt beim Heranzoomen wieder.
	var pitch_goal: float = lerpf(_target_pitch, deg_to_rad(BIRDS_EYE_PITCH_DEG), birds_eye_weight(_zoom_smooth))
	rotation.x = lerp(rotation.x, pitch_goal, rotation_speed * delta)

func _process_zoom(inp: TouchInput, delta: float) -> void:
	var z_delta := inp.zoom_delta
	inp.zoom_delta = 0.0
	if z_delta != 0.0:
		_target_zoom = clamp(zoom_step(_target_zoom, z_delta), MIN_ZOOM_FIRST_PERSON, MAX_ZOOM_MAP)
	_zoom_smooth = lerpf(_zoom_smooth, _target_zoom, clampf(zoom_speed * delta, 0.0, 1.0))
	spring_length = camera_height(_zoom_smooth)

	# Spring-Arm-Kollision nur in der normalen Schulterkamera (siehe Klassenkommentar).
	var want_mask: int = 1 if _zoom_smooth <= BIRDS_EYE_START else 0
	if collision_mask != want_mask:
		collision_mask = want_mask

	var blend := map_blend(_zoom_smooth)
	var map_now := blend > 0.001
	if map_now != _map_active:
		_map_active = map_now
		map_mode_changed.emit(_map_active)

	var now_first_person := spring_length < FIRST_PERSON_THRESHOLD
	if now_first_person != _is_first_person:
		_is_first_person = now_first_person
		first_person_changed.emit(_is_first_person)

## Für PlayerSetup/Tests: aktuell First-Person aktiv?
func is_first_person() -> bool:
	return _is_first_person

# ─────────────────────────────────────────────
# Vogelperspektive / Karte — Abfragen (für WorldMapView) + reine Rechenfunktionen
# ─────────────────────────────────────────────

## Aktueller (geglätteter) Zoom, 0.4 … MAX_ZOOM_MAP.
func get_zoom() -> float:
	return _zoom_smooth

## 0 = keine Karte … 1 = Karte voll sichtbar.
func get_map_blend() -> float:
	return map_blend(_zoom_smooth)

func is_map_visible() -> bool:
	return _map_active

## Aktuelle Blickdrehung (rad) um die Hochachse — die Karte dreht mit der Kamera.
func get_yaw() -> float:
	return rotation.y

## Halbe sichtbare Höhe der Karte in Metern (bei aktueller Kamera).
func get_map_half_extent_m() -> float:
	var fov_deg: float = camera.fov if is_instance_valid(camera) else 75.0
	return view_half_extent_m(_zoom_smooth, fov_deg)

## Setzt den Zoom hart (z. B. Tests, "Karte öffnen"-Button). Keine Glättung.
func set_zoom_immediate(zoom: float) -> void:
	_target_zoom = clampf(zoom, MIN_ZOOM_FIRST_PERSON, MAX_ZOOM_MAP)
	_zoom_smooth = _target_zoom

## Neuer Ziel-Zoom nach einem Eingabe-Schritt. Bis ZOOM_STEP_LINEAR_UNTIL linear (wie bisher),
## darüber proportional zum Zoom — Mausrad-Raster und Pinch fühlen sich überall gleich an.
static func zoom_step(current: float, delta: float) -> float:
	var factor: float = maxf(1.0, current / ZOOM_STEP_LINEAR_UNTIL)
	return current + delta * factor

## Gewicht der Vogelperspektive: 0 (Schulterkamera) … 1 (senkrecht).
static func birds_eye_weight(zoom: float) -> float:
	return smoothstep(BIRDS_EYE_START, BIRDS_EYE_FULL, zoom)

## Sichtbarkeit der Karte: 0 … 1.
static func map_blend(zoom: float) -> float:
	return smoothstep(MAP_ZOOM_START, MAP_ZOOM_FULL, zoom)

## Kamerahöhe/Spring-Länge: folgt dem Zoom, aber nie über MAX_CAMERA_HEIGHT.
static func camera_height(zoom: float) -> float:
	return minf(zoom, MAX_CAMERA_HEIGHT)

## Halbe sichtbare Höhe (m) am Boden. Bis MAP_ZOOM_FULL entspricht das exakt dem, was die echte
## Kamera aus `zoom` m Höhe sieht (nahtloser Übergang Welt → Karte); darüber wächst es mit dem
## Zoom weiter (Kamera bleibt oben, die Karte zoomt heraus).
static func view_half_extent_m(zoom: float, fov_deg: float = 75.0) -> float:
	var t: float = tan(deg_to_rad(fov_deg) * 0.5)
	var h: float = camera_height(zoom)
	return h * t * maxf(1.0, zoom / MAP_ZOOM_FULL)
