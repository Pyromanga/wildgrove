class_name WorkAnimator
extends Node

## WorkAnimator — Arbeitsbewegung eines Berufs-NPCs (nur Optik, lokal, nie gespeichert).
##
## Kippt den "Visual"-Knoten des NPCs leicht (rotation.x/.z) und hebt ihn minimal an. rotation.y
## gehört CharacterGaze (Umsehen) und bleibt unberührt. pose() ist rein/statisch → testbar.
## Läuft nur, solange `active` und der NPC sichtbar ist; entfernte NPCs (> CULL_DIST) rechnen nicht.

const STYLES: Array[String] = [
	"hammer", "stir", "weave", "write", "knead", "scrape", "press", "fish", "carve", "blow", "rake",
]
const CULL_DIST: float = 45.0
const CHECK_SEC: float = 0.5

var style: String = "stir"
var active: bool = false : set = set_active
var phase_offset: float = 0.0   ## je NPC verschieden, damit nicht alle im Gleichtakt arbeiten

var _visual: Node3D = null
var _base_y: float = 0.0
var _t: float = 0.0
var _check: float = 0.0
var _near: bool = true

## → {pitch, roll, lift} in rad/rad/m. pitch>0 = Oberkörper nach vorn.
static func pose(work_style: String, t: float) -> Dictionary:
	var s := sin(t * TAU)
	match work_style:
		"hammer":
			var strike: float = pow(maxf(0.0, sin(t * TAU * 1.3)), 2.0)
			return {"pitch": 0.06 + 0.14 * strike, "roll": 0.0, "lift": 0.0}
		"stir":
			return {"pitch": 0.08 + 0.04 * cos(t * TAU * 0.5), "roll": 0.07 * sin(t * TAU * 0.5), "lift": 0.0}
		"weave":
			return {"pitch": 0.05, "roll": 0.10 * sin(t * TAU * 0.8), "lift": 0.0}
		"write":
			return {"pitch": 0.18 + 0.02 * s, "roll": 0.02 * sin(t * TAU * 0.3), "lift": 0.0}
		"knead":
			return {"pitch": 0.15 + 0.08 * sin(t * TAU * 1.1), "roll": 0.0, "lift": -0.015 * absf(sin(t * TAU * 1.1))}
		"scrape":
			return {"pitch": 0.20 + 0.10 * sin(t * TAU * 0.9), "roll": 0.03 * sin(t * TAU * 0.45), "lift": 0.0}
		"press":
			return {"pitch": 0.10 + 0.12 * maxf(0.0, sin(t * TAU * 0.4)), "roll": 0.0, "lift": 0.0}
		"fish":
			return {"pitch": 0.04, "roll": 0.03 * sin(t * TAU * 0.3), "lift": 0.0}
		"carve":
			return {"pitch": 0.12, "roll": 0.06 * sin(t * TAU * 1.6), "lift": 0.0}
		"blow":
			return {"pitch": -0.08 + 0.10 * sin(t * TAU * 0.35), "roll": 0.0, "lift": 0.0}
		"rake":
			return {"pitch": 0.10 + 0.06 * sin(t * TAU * 0.6), "roll": 0.04 * sin(t * TAU * 0.3), "lift": 0.0}
		_:
			return {"pitch": 0.0, "roll": 0.0, "lift": 0.0}

func set_active(on: bool) -> void:
	active = on
	set_process(on)
	if not on:
		_reset()

func _ready() -> void:
	set_process(active)

func _process(delta: float) -> void:
	_t += delta
	_check += delta
	if _check >= CHECK_SEC:
		_check = 0.0
		_near = _is_near()
		if not _near:
			_reset()
	if not _near:
		return
	_apply(_t + phase_offset)

func _apply(t: float) -> void:
	var v := _find_visual()
	if v == null:
		return
	var p: Dictionary = pose(style, t)
	v.rotation.x = float(p["pitch"])
	v.rotation.z = float(p["roll"])
	v.position.y = _base_y + float(p["lift"])

func _reset() -> void:
	if is_instance_valid(_visual):
		_visual.rotation.x = 0.0
		_visual.rotation.z = 0.0
		_visual.position.y = _base_y

## "Visual" wird bei wear()/take_off() neu gebaut → bei Bedarf neu suchen.
func _find_visual() -> Node3D:
	if is_instance_valid(_visual) and _visual.is_inside_tree():
		return _visual
	var parent := get_parent()
	if parent == null:
		return null
	_visual = parent.get_node_or_null("Visual") as Node3D
	if _visual != null:
		_base_y = _visual.position.y
	return _visual

func _is_near() -> bool:
	if not is_inside_tree() or not (get_parent() is Node3D):
		return true
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return true
	return cam.global_position.distance_to((get_parent() as Node3D).global_position) <= CULL_DIST
