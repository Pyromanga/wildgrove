class_name CharacterGaze
extends Node

## CharacterGaze — lebendiger Blick für jede Figur, die mit CharacterPartBuilder gebaut wurde
## (Spieler UND NPCs).
##
## WAS ES TUT
##   1. FOKUS: Augen (und anteilig der Kopf) richten sich auf ein Ziel — ein Node3D
##      (`set_focus`), einen Weltpunkt (`set_focus_point`), das, was `focus_provider`
##      liefert (z. B. aktuelles Interaktionsziel) oder — automatisch — das nächste
##      interessante Wesen in Reichweite (Gruppen `interest_groups`).
##   2. IDLE: ohne Ziel wandert der Blick: kurze, schnelle Augenbewegungen (Sakkaden),
##      gelegentlich dreht sich der Kopf mit, Mikro-Zittern, mal zum Boden/in die Ferne.
##      Beim Laufen schaut die Figur überwiegend geradeaus.
##   3. BLINZELN: zufällig alle 2–6 s, manchmal doppelt, öfter nach großen Blickwechseln.
##      Beim Blick nach unten senken sich die Lider leicht mit.
##   4. ATMEN: kaum sichtbares Heben/Senken von Rumpf und Kopf.
##
## WIE (Details, damit man es anpassen kann)
##   - Die Blickrichtung wird als (yaw, pitch) im Koordinatensystem des Kopf-Elternknotens
##     ("Parts") berechnet. +yaw = nach +X (= `rotation.y` positiv), +pitch = nach oben
##     (= `rotation.x` NEGATIV, siehe _apply()).
##   - Aufteilung: der Kopf übernimmt einen Anteil (`head_share`) bis `HEAD_MAX`, die Augen
##     den Rest bis `EYE_MAX`. Augen sind schnell (EYE_SPEED), der Kopf träge (HEAD_SPEED)
##     → die Augen "springen" zuerst, der Kopf folgt: wirkt wie echtes Hinsehen.
##   - Augen = Verschiebung des "Gaze"-Knotens (Iris/Pupille/Glanzpunkt) innerhalb des
##     Augapfels, begrenzt auf `gaze_max` (Meta am Augenknoten). Pro Auge leichte
##     Konvergenz bei nahen Zielen (schielt nicht, aber "fokussiert").
##   - Rein kosmetisch und lokal: nichts davon wird synchronisiert oder gespeichert.
##
## EINBINDUNG
##   var gaze := CharacterGaze.new(); add_child(gaze)
##   gaze.bind(CharacterPartBuilder.build(look), head_slot)   # nach JEDEM Neuaufbau erneut
##   gaze.set_focus(some_node3d)  /  gaze.clear_focus()
##
## Headless (Dedicated Server) und unsichtbare Figuren (Ego-Perspektive) rechnen nichts.

const LOG_CAT := "CharacterGaze"

## Grenzen in Radiant (yaw, pitch). Kopf: ca. ±38° / +17° / −20°. Augen: ca. ±31° / ±22°.
const HEAD_YAW_MAX: float = 0.66
const HEAD_PITCH_UP_MAX: float = 0.30
const HEAD_PITCH_DOWN_MAX: float = 0.35
const EYE_YAW_MAX: float = 0.55
const EYE_PITCH_MAX: float = 0.38

## Glättung (1/s): je höher, desto schneller erreicht der Wert sein Ziel.
const HEAD_SPEED: float = 6.0
const EYE_SPEED: float = 24.0

## Augen-Abstand von der Kopfmitte (für Konvergenz) — entspricht CharacterPartBuilder.
const EYE_HALF_DISTANCE: float = 0.07
## Weiter entfernte Figuren (zur aktiven Kamera) werden nicht mehr animiert.
const MAX_ANIMATED_DISTANCE: float = 40.0
## Intervall der Zielsuche (s) — nicht jeden Frame über Gruppen iterieren.
const INTEREST_INTERVAL: float = 0.4

## Ein-/Ausschalter für das ganze Verhalten.
var enabled: bool = true
## Zufälliges Umsehen, solange es kein Ziel gibt.
var idle_enabled: bool = true
## Automatische Zielwahl aus `interest_groups`.
var auto_focus_enabled: bool = true
var interest_groups: PackedStringArray = PackedStringArray(["player", "npcs"])
var interest_range: float = 7.0
## Halber Sichtwinkel für die automatische Zielwahl (rad, ab Körper-Vorwärts).
var interest_half_fov: float = 1.9
## Knoten, der sich NICHT selbst anschauen soll (Player-/NPC-Node).
var owner_exclude: Node = null
## Liefert optional ein Vorzugsziel (Node3D oder null), z. B. Player.get_closest_interactable.
var focus_provider: Callable = Callable()
## Anteil der Blickbewegung, den der Kopf übernimmt (x = yaw, y = pitch).
var head_share: Vector2 = Vector2(0.6, 0.45)
## Optional: Körperknoten, der sich bei Zielen weit außerhalb der Kopfreichweite mitdreht
## (NPCs). Beim Spieler NICHT setzen — dort dreht PlayerVisuals den Körper.
var turn_body: Node3D = null
var turn_speed: float = 1.8
## Aktuelle Bewegungsgeschwindigkeit (m/s) — PlayerVisuals setzt das. Beim Laufen
## wird der Idle-Blick eingeschränkt.
var movement_speed: float = 0.0
## Sanftes Atmen an/aus.
var breathing_enabled: bool = true

var head: Node3D = null
var _eyes: Array = []          # Array von Dictionaries, siehe _collect_eye()
var _torso: Node3D = null
var _head_slot: Node3D = null
var _ref: Node3D = null        # Koordinatenbezug (Elternknoten des Kopfes)

var _head_rest_pos: Vector3 = Vector3.ZERO
var _torso_rest_scale: Vector3 = Vector3.ONE
var _body_rest_yaw: float = 0.0

var _focus_node: Node3D = null
var _focus_point: Vector3 = Vector3.ZERO
var _has_focus_point: bool = false
var _auto_node: Node3D = null
var _interest_timer: float = 0.0

var _cur_head: Vector2 = Vector2.ZERO   # (yaw, pitch) des Kopfes
var _cur_eye: Vector2 = Vector2.ZERO    # (yaw, pitch) der Augen relativ zum Kopf
var _idle_total: Vector2 = Vector2.ZERO # Idle-Blickziel (yaw, pitch) im Elternsystem
var _idle_share: Vector2 = Vector2(0.5, 0.4)
var _idle_timer: float = 0.0
var _jitter: Vector2 = Vector2.ZERO
var _jitter_timer: float = 0.0
var _no_focus_time: float = 0.0

var _blink_timer: float = 2.0
var _blink_t: float = -1.0
var _blink_queued: bool = false
var _blink_value: float = 0.0
var _breath_phase: float = 0.0

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_breath_phase = _rng.randf() * TAU
	_blink_timer = _rng.randf_range(1.0, 4.0)
	# Dedicated Server hat kein Bild — nichts zu animieren.
	if DisplayServer.get_name() == "headless" or Engine.is_editor_hint():
		set_process(false)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Verbindet den Controller mit frisch gebauten Körperteilen (Rückgabe von
## CharacterPartBuilder.build()). Muss nach JEDEM Neuaufbau erneut aufgerufen werden,
## weil die alten Knoten dann freigegeben sind. `head_slot` (optional): Zubehör-Anker,
## der dem Kopf folgen soll (PlayerVisuals "Slot_head").
func bind(parts: Dictionary, head_slot: Node3D = null) -> void:
	unbind()
	var h: Variant = parts.get("head", null)
	if not (h is Node3D) or not is_instance_valid(h):
		return
	head = h as Node3D
	_ref = head.get_parent() as Node3D
	_head_slot = head_slot
	_head_rest_pos = head.position
	var torso: Variant = parts.get("torso", null)
	_torso = torso as Node3D if torso is Node3D else null
	if _torso != null:
		_torso_rest_scale = _torso.scale
	for key in ["eye_r", "eye_l"]:
		var e: Variant = parts.get(key, null)
		if e is Node3D and is_instance_valid(e):
			_eyes.append(_collect_eye(e as Node3D))
	_cur_head = Vector2.ZERO
	_cur_eye = Vector2.ZERO
	_idle_timer = _rng.randf_range(0.3, 1.5)
	if is_instance_valid(turn_body):
		_body_rest_yaw = turn_body.rotation.y

## Löst alle Referenzen (z. B. vor Neuaufbau). Setzt den Kopf NICHT zurück — die alten
## Knoten werden ohnehin freigegeben.
func unbind() -> void:
	head = null
	_ref = null
	_torso = null
	_head_slot = null
	_eyes.clear()

func is_bound() -> bool:
	return is_instance_valid(head) and is_instance_valid(_ref)

## Blickziel = Node (bevorzugt vor Weltpunkt/Automatik). null löscht es.
func set_focus(target: Node3D) -> void:
	_focus_node = target
	_has_focus_point = false

## Blickziel = fester Weltpunkt.
func set_focus_point(world_point: Vector3) -> void:
	_focus_point = world_point
	_has_focus_point = true
	_focus_node = null

func clear_focus() -> void:
	_focus_node = null
	_has_focus_point = false

## Hat die Figur gerade irgendein Ziel (manuell, Provider oder automatisch)?
func has_focus() -> bool:
	return is_instance_valid(_focus_node) or _has_focus_point or is_instance_valid(_auto_node)

## Sofort blinzeln (z. B. bei Treffer/Überraschung).
func blink_now() -> void:
	if _blink_t < 0.0:
		_blink_t = 0.0

## Aktueller Kopfwinkel (yaw, pitch) — für Tests/Debug.
func get_head_angles() -> Vector2:
	return _cur_head

## Aktueller Augenwinkel relativ zum Kopf — für Tests/Debug.
func get_eye_angles() -> Vector2:
	return _cur_eye

## Aktueller Lidschluss durch Blinzeln (0 offen … 1 zu) — für Tests/Debug.
func get_blink_value() -> float:
	return _blink_value

# ─────────────────────────────────────────────
# Reine Rechenfunktionen (statisch → einzeln testbar)
# ─────────────────────────────────────────────

## Richtung → (yaw, pitch). +Z = vorn, +X = yaw positiv, +Y = pitch positiv.
static func angles_to(local_dir: Vector3) -> Vector2:
	if local_dir.length_squared() < 0.000001:
		return Vector2.ZERO
	var horizontal := sqrt(local_dir.x * local_dir.x + local_dir.z * local_dir.z)
	return Vector2(atan2(local_dir.x, local_dir.z), atan2(local_dir.y, horizontal))

## Teilt einen Gesamtblickwinkel auf Kopf und Augen auf. Rückgabe {"head": Vector2,
## "eye": Vector2}. Der Kopf bekommt `share` (komponentenweise) bis zu seinen Grenzen,
## die Augen den Rest bis zu den ihren. Was darüber hinausgeht, wird abgeschnitten
## (die Figur "schaut so weit sie kann").
static func split_gaze(total: Vector2, share: Vector2) -> Dictionary:
	var head_yaw := clampf(total.x * share.x, -HEAD_YAW_MAX, HEAD_YAW_MAX)
	var head_pitch := clampf(total.y * share.y, -HEAD_PITCH_DOWN_MAX, HEAD_PITCH_UP_MAX)
	var eye_yaw := clampf(total.x - head_yaw, -EYE_YAW_MAX, EYE_YAW_MAX)
	var eye_pitch := clampf(total.y - head_pitch, -EYE_PITCH_MAX, EYE_PITCH_MAX)
	return {"head": Vector2(head_yaw, head_pitch), "eye": Vector2(eye_yaw, eye_pitch)}

## Augenwinkel → Verschiebung der Iris in der Augenebene (m), kreisförmig auf `max_offset`
## begrenzt (Iris verlässt nie den Augapfel).
static func eye_offset(eye_angles: Vector2, max_offset: float) -> Vector2:
	var o := Vector2(
		clampf(eye_angles.x / EYE_YAW_MAX, -1.0, 1.0),
		clampf(eye_angles.y / EYE_PITCH_MAX, -1.0, 1.0)
	) * max_offset
	if o.length() > max_offset:
		o = o.normalized() * max_offset
	return o

## Lidschluss 0..1 aus Grundschluss, Blinzel-Wert und Augen-Pitch (Blick nach unten
## senkt die Lider leicht mit).
static func lid_coverage(base: float, blink: float, eye_pitch: float) -> float:
	var look_down := maxf(-eye_pitch, 0.0) * 0.45
	return clampf(maxf(base + look_down, blink), 0.0, 1.0)

## Blinzel-Kurve: t 0..1 → 0..1..0 (schnell zu, etwas langsamer auf), geglättet.
static func blink_curve(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	var v := x / 0.4 if x < 0.4 else 1.0 - (x - 0.4) / 0.6
	return smoothstep(0.0, 1.0, clampf(v, 0.0, 1.0))

## Konvergenzwinkel eines Auges (rad) für ein Ziel in `distance` Metern. `side` = +1 für
## das Auge bei +X. Positiv = Drehung zur Nase (also von +X-Auge nach −yaw).
static func vergence(distance: float, side: float) -> float:
	return side * atan(EYE_HALF_DISTANCE / clampf(distance, 0.35, 30.0))

## Zufälliges Idle-Blickziel (yaw, pitch) im Elternsystem. Mitte wird bevorzugt
## (Mittelwert zweier Zufallszahlen), gelegentlich Boden oder Ferne.
static func pick_idle_target(rng: RandomNumberGenerator, yaw_range: float = 0.55) -> Vector2:
	var yaw := (rng.randf_range(-1.0, 1.0) + rng.randf_range(-1.0, 1.0)) * 0.5 * yaw_range
	var pitch := rng.randf_range(-0.14, 0.10)
	var roll := rng.randf()
	if roll < 0.12:
		pitch = rng.randf_range(-0.34, -0.2)   # Blick zum Boden
	elif roll < 0.20:
		pitch = rng.randf_range(0.14, 0.26)    # Blick in die Ferne/nach oben
	return Vector2(yaw, pitch)

# ─────────────────────────────────────────────
# Laufzeit
# ─────────────────────────────────────────────

func _process(delta: float) -> void:
	if not enabled or delta <= 0.0 or not is_bound():
		return
	if not head.is_visible_in_tree():
		return  # z. B. Ego-Perspektive: eigener Körper ausgeblendet
	var cam: Camera3D = null
	if is_inside_tree():
		cam = get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_squared_to(head.global_position) > MAX_ANIMATED_DISTANCE * MAX_ANIMATED_DISTANCE:
		return

	_update_interest(delta)
	var total_and_share := _resolve_target(delta)
	var has_target: bool = total_and_share["has_target"]
	var total: Vector2 = total_and_share["total"]
	var share: Vector2 = total_and_share["share"]
	var dist: float = total_and_share["dist"]

	var split := split_gaze(total, share)
	var head_target: Vector2 = split["head"]
	_cur_head = _cur_head.lerp(head_target, 1.0 - exp(-HEAD_SPEED * delta))

	# Augen gleichen den noch hinterherhinkenden Kopf aus (wie der vestibulo-okuläre
	# Reflex): Blick bleibt auf dem Ziel, während der Kopf nachzieht.
	var eye_target := Vector2(
		clampf(total.x - _cur_head.x, -EYE_YAW_MAX, EYE_YAW_MAX),
		clampf(total.y - _cur_head.y, -EYE_PITCH_MAX, EYE_PITCH_MAX)
	)
	if not has_target:
		eye_target += _update_jitter(delta)
	_cur_eye = _cur_eye.lerp(eye_target, 1.0 - exp(-EYE_SPEED * delta))

	_update_body_turn(total, has_target, delta)
	_update_blink(delta)
	_apply(dist if has_target else 0.0)
	if breathing_enabled:
		_apply_breath(delta)

## Ermittelt (Gesamtwinkel, Kopfanteil, Entfernung) für diesen Frame.
func _resolve_target(delta: float) -> Dictionary:
	var world_point: Variant = _current_focus_point()
	if world_point != null:
		_no_focus_time = 0.0
		var local: Vector3 = _ref.to_local(world_point as Vector3) - head.position
		return {
			"has_target": true,
			"total": angles_to(local),
			"share": head_share,
			"dist": local.length(),
		}

	_no_focus_time += delta
	if not idle_enabled:
		return {"has_target": false, "total": Vector2.ZERO, "share": head_share, "dist": 0.0}

	var walking := movement_speed > 1.0
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		var yaw_range := 0.18 if walking else 0.55
		var previous := _idle_total
		_idle_total = pick_idle_target(_rng, yaw_range)
		# Meist wandern nur die Augen; ab und zu dreht sich der Kopf deutlich mit.
		var head_turn := not walking and _rng.randf() < 0.28
		_idle_share = Vector2(0.75, 0.6) if head_turn else Vector2(0.18, 0.15)
		_idle_timer = _rng.randf_range(0.9, 3.8)
		if (_idle_total - previous).length() > 0.35 and _rng.randf() < 0.4:
			blink_now()
	return {"has_target": false, "total": _idle_total, "share": _idle_share, "dist": 0.0}

## Weltpunkt des aktuellen Ziels oder null. Reihenfolge: manueller Node → manueller
## Punkt → focus_provider → automatisches Ziel.
func _current_focus_point() -> Variant:
	if is_instance_valid(_focus_node):
		return gaze_point_of(_focus_node)
	if _has_focus_point:
		return _focus_point
	if focus_provider.is_valid():
		var provided: Variant = focus_provider.call()
		if provided is Node3D and is_instance_valid(provided) and provided != owner_exclude:
			return gaze_point_of(provided as Node3D)
	if auto_focus_enabled and is_instance_valid(_auto_node):
		return gaze_point_of(_auto_node)
	return null

## Wohin schaut man bei diesem Node? Hook `get_gaze_point()` (falls vorhanden), sonst
## Kamera = Kamerapunkt, Spieler/NPC = Kopfhöhe, alles andere = Objektmitte (~0,8 m).
static func gaze_point_of(node: Node3D) -> Vector3:
	if node.has_method("get_gaze_point"):
		var custom: Variant = node.call("get_gaze_point")
		if custom is Vector3:
			return custom
	if node is Camera3D:
		return node.global_position
	if node.is_in_group("player") or node.is_in_group("npcs"):
		return node.global_position + Vector3(0.0, 1.6, 0.0)
	return node.global_position + Vector3(0.0, 0.8, 0.0)

func _update_interest(delta: float) -> void:
	if not auto_focus_enabled:
		_auto_node = null
		return
	_interest_timer -= delta
	if _interest_timer > 0.0:
		return
	_interest_timer = INTEREST_INTERVAL + _rng.randf() * 0.15
	_auto_node = _find_interest()

func _find_interest() -> Node3D:
	if not is_inside_tree():
		return null
	var origin := head.global_position
	var forward := _ref.global_transform.basis.z
	var best: Node3D = null
	var best_score := INF
	for group in interest_groups:
		for n in get_tree().get_nodes_in_group(group):
			if n == owner_exclude or not (n is Node3D) or not is_instance_valid(n):
				continue
			var node3d := n as Node3D
			# Eigene Kind-/Elternknoten (z. B. Player ↔ PlayerVisuals) überspringen.
			if owner_exclude != null and (owner_exclude.is_ancestor_of(node3d) or node3d.is_ancestor_of(owner_exclude)):
				continue
			var to := gaze_point_of(node3d) - origin
			var d := to.length()
			var limit := interest_range * (1.15 if node3d == _auto_node else 1.0)  # Hysterese
			if d > limit or d < 0.05:
				continue
			var flat := Vector3(to.x, 0.0, to.z)
			var ang := 0.0
			if flat.length_squared() > 0.0001:
				ang = flat.normalized().angle_to(Vector3(forward.x, 0.0, forward.z).normalized())
			if ang > interest_half_fov:
				continue
			var score := d + ang * 2.0
			if node3d == _auto_node:
				score -= 1.0  # beim aktuellen Ziel bleiben, kein Flackern
			if score < best_score:
				best_score = score
				best = node3d
	return best

func _update_jitter(delta: float) -> Vector2:
	_jitter_timer -= delta
	if _jitter_timer <= 0.0:
		_jitter = Vector2(_rng.randf_range(-0.03, 0.03), _rng.randf_range(-0.02, 0.02))
		_jitter_timer = _rng.randf_range(0.2, 0.7)
	return _jitter

func _update_body_turn(total: Vector2, has_target: bool, delta: float) -> void:
	if turn_body == null or not is_instance_valid(turn_body):
		return
	if has_target:
		# Komfortbereich: Kopf + halbe Augenreichweite. Darüber hinaus dreht sich der Körper nach.
		var comfort := HEAD_YAW_MAX + EYE_YAW_MAX * 0.5
		if absf(total.x) > comfort:
			var excess := total.x - signf(total.x) * comfort
			turn_body.rotation.y += clampf(excess, -turn_speed * delta, turn_speed * delta)
	elif _no_focus_time > 3.0:
		# Lange kein Ziel: zurück in die Ausgangsrichtung.
		var diff := wrapf(_body_rest_yaw - turn_body.rotation.y, -PI, PI)
		turn_body.rotation.y += clampf(diff, -turn_speed * 0.4 * delta, turn_speed * 0.4 * delta)

func _update_blink(delta: float) -> void:
	if _blink_t >= 0.0:
		_blink_t += delta / 0.17
		if _blink_t >= 1.0:
			_blink_t = -1.0
			_blink_value = 0.0
			if _blink_queued:
				_blink_queued = false
				_blink_t = 0.0
		else:
			_blink_value = blink_curve(_blink_t)
		return
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_t = 0.0
		_blink_queued = _rng.randf() < 0.15  # Doppelblinzeln
		_blink_timer = _rng.randf_range(2.0, 6.0)

## Schreibt die berechneten Winkel in die Knoten.
func _apply(distance: float) -> void:
	# Kopf: pitch nach oben = rotation.x NEGATIV (Godot: +x neigt die +Z-Achse nach unten).
	head.rotation = Vector3(-_cur_head.y, _cur_head.x, 0.0)
	if is_instance_valid(_head_slot):
		# Zubehör-Anker (Hut-Slot) folgt der Kopfdrehung um die Kopfmitte.
		_head_slot.rotation = head.rotation
		_head_slot.position = head.position + head.basis * Vector3(0.0, CharacterPartBuilder.HEAD_R, 0.0)

	for e in _eyes:
		var eye: Node3D = e["node"]
		if not is_instance_valid(eye):
			continue
		var gaze_node: Node3D = e["gaze"]
		var side: float = e["side"]
		var angles := _cur_eye
		if distance > 0.0:
			angles.x -= vergence(distance, side)
		var off := eye_offset(angles, e["max_off"])
		if is_instance_valid(gaze_node):
			gaze_node.position = Vector3(off.x, off.y, 0.0)

		var cover := lid_coverage(e["lid_base"], _blink_value, _cur_eye.y)
		var lid: Node3D = e["lid"]
		if is_instance_valid(lid):
			lid.scale = Vector3(1.0, maxf(cover, CharacterPartBuilder.LID_OPEN), 1.0)
			lid.visible = cover > 0.02
		elif is_instance_valid(gaze_node):
			# Augen ohne Lid ("Punkte"): Blinzeln = Pupille flachdrücken.
			gaze_node.scale = Vector3(1.0, lerpf(1.0, 0.1, _blink_value), 1.0)

func _apply_breath(delta: float) -> void:
	_breath_phase = fmod(_breath_phase + delta * 1.7, TAU)
	var s := sin(_breath_phase)
	if is_instance_valid(_torso):
		_torso.scale = Vector3(_torso_rest_scale.x, _torso_rest_scale.y * (1.0 + 0.010 * s), _torso_rest_scale.z * (1.0 + 0.006 * s))
	head.position = _head_rest_pos + Vector3(0.0, 0.0035 * s, 0.0)

func _collect_eye(eye: Node3D) -> Dictionary:
	return {
		"node": eye,
		"gaze": eye.get_node_or_null("Gaze"),
		"lid": eye.get_node_or_null("Lid"),
		"max_off": float(eye.get_meta("gaze_max", 0.01)),
		"lid_base": float(eye.get_meta("lid_base", 0.0)),
		"side": float(eye.get_meta("eye_side", 1.0)),
	}
