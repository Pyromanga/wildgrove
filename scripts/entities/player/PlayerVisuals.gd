extends Node3D
class_name PlayerVisuals

## PlayerVisuals — modularer Spielerkörper + Skeleton mit benannten Bones.
##
## AUFBAU
##   PlayerVisuals (Node3D, dreht sich in Laufrichtung)
##   └─ Skeleton3D                (Bones + BoneAttachments, skaliert = Körpergröße)
##      ├─ Attach_<bone> ...      (BoneAttachment3D je Bone — Waffen etc. hängen hier)
##      ├─ Slot_head / Slot_back  (leere Node3D — Hüte, Rucksäcke, Umhänge etc.)
##      └─ Parts                  (wird bei JEDER Look-Änderung neu gebaut)
##         ├─ Torso, Pelvis, Neck, Collar, Belt, TunicSkirt (je nach Look)
##         ├─ Head → Skull, EarR/L, Face (Augen/Brauen/Nase/Mund/Bart/Brille), Hair, Hat
##         ├─ ArmR/ArmL  (Drehpunkt an der Schulter → Sleeve, Forearm, Hand)
##         └─ LegR/LegL  (Drehpunkt an der Hüfte   → Leg, Shoe)
##
## Das Aussehen kommt aus einem `CharacterLook` (Dictionary aus IDs, siehe dort).
## `apply_look()` ist der EINE Weg, das Aussehen zu ändern; die Geometrie baut
## `CharacterPartBuilder`. Neue Körperteile/Optionen ändern also nur Katalog
## und Builder, nicht diese Klasse.
##
## Bone-Hierarchie (Indices sind stabil — nie umsortieren ohne WeaponVisual3D zu prüfen):
##   0  root       — Wurzel, sitzt auf Boden (y=0)
##   1  spine      — Rumpf-Mitte (~y=0.9)
##   2  head       — Kopf-Ansatz (~y=1.6)
##   3  hand_r     — Rechte Hand (+X) — Waffenhalte-Punkt
##   4  hand_l     — Linke Hand  (-X)
##
## Die Hand-Bones sitzen seit der Körper-Überarbeitung an der TATSÄCHLICHEN
## Handposition des Charakters (siehe `CharacterPartBuilder.hand_position()`,
## ~y=0.78, x≈±0.28 je nach Statur) statt wie früher bei y=1.1 in der
## Kapsel. Die Werte werden bei jedem `apply_look()` nachgezogen, weil die
## Statur die Schulterbreite ändert. Waffen-Offsets (WeaponDefinition.
## visual_offset) sind relativ zum Bone und müssen ggf. einmal nachjustiert
## werden.
##
## Neue Bones nur ANHÄNGEN (Godot: Parent-Index muss kleiner als Kind-Index sein).
##
## Warum Skeleton ohne Animation-Player:
##   WeaponVisual3D braucht einen stabilen world-space Attachment-Punkt.
##   BoneAttachment3D liefert genau das ohne eigene Animation zu benötigen.
##   Die einfache Lauf-Schwingung unten setzt nur Bone-Posen und ist abschaltbar
##   (`walk_animation_enabled`).
##
## get_bone_attachment(bone_name) gibt eine BoneAttachment3D zurück die
## bereits unter dem Skeleton hängt — Aufrufer fügen ihre Nodes dort ein.

const LOG_CAT := "PlayerVisuals"

## Lauf-Schwingung: Referenzgeschwindigkeit für volle Amplitude, maximaler
## Ausschlag (rad), Blend-Geschwindigkeit der Amplitude (rad/s) und
## Schrittfrequenz (rad Phase pro Meter).
const WALK_REF_SPEED: float = 6.0
const MAX_SWING: float = 0.65
const SWING_BLEND: float = 5.0
const STRIDE_PHASE_PER_METER: float = 2.6
## Bewegungen größer als das pro Frame gelten als Teleport (kein Laufen).
const TELEPORT_DIST: float = 2.0

const SLOT_HEAD := "head"
const SLOT_BACK := "back"

## Legacy-Feld: der Rumpf (Hemd-Material als material_override). Wird bei jedem
## apply_look() neu gesetzt — Referenz nicht dauerhaft cachen.
var mesh:     MeshInstance3D
var skeleton: Skeleton3D
var rotation_speed: float = 10.0
var walk_animation_enabled: bool = true

## Blicksteuerung (Augen/Kopf folgen Zielen, Idle-Umschauen, Blinzeln, Atmen).
## Wird in _init() angelegt und nach jedem Neuaufbau der Körperteile neu gebunden.
var gaze: CharacterGaze

## Bone-Name → Index-Cache, gefüllt in _build_skeleton().
var _bone_index: Dictionary = {}

## Vorbelegte BoneAttachments, keyed by bone_name.
var _attachments: Dictionary = {}

## Slot-Name → Node3D (überleben Look-Wechsel, liegen nicht unter "Parts").
var _slots: Dictionary = {}

var _look: Dictionary = {}
var _parts: Dictionary = {}
var _parts_root: Node3D = null

var _last_global_pos: Vector3 = Vector3.ZERO
var _has_last_pos: bool = false
var _walk_phase: float = 0.0
var _swing_amp: float = 0.0
var _pose_dirty: bool = false

func _init() -> void:
	_build_skeleton()
	_build_slots()
	gaze = CharacterGaze.new()
	gaze.name = "Gaze"
	add_child(gaze)
	apply_look(CharacterLook.default_look())

# ─────────────────────────────────────────────
# Aufbau
# ─────────────────────────────────────────────

func _build_skeleton() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)

	# Bone 0: root — Basis, kein Parent
	var root_idx := skeleton.add_bone("root")
	skeleton.set_bone_rest(root_idx, Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)))

	# Bone 1: spine — Parent: root
	var spine_idx := skeleton.add_bone("spine")
	skeleton.set_bone_parent(spine_idx, root_idx)
	skeleton.set_bone_rest(spine_idx, Transform3D(Basis(), Vector3(0.0, 0.9, 0.0)))

	# Bone 2: head — Parent: spine
	var head_idx := skeleton.add_bone("head")
	skeleton.set_bone_parent(head_idx, spine_idx)
	skeleton.set_bone_rest(head_idx, Transform3D(Basis(), Vector3(0.0, 0.7, 0.0)))

	# Bone 3: hand_r — Parent: spine (Waffenhalte-Punkt). Position wird in
	# _apply_proportions() auf die echte Handposition gesetzt.
	var hand_r_idx := skeleton.add_bone("hand_r")
	skeleton.set_bone_parent(hand_r_idx, spine_idx)
	skeleton.set_bone_rest(hand_r_idx, Transform3D(Basis(), Vector3(0.28, -0.1, 0.0)))

	# Bone 4: hand_l — Parent: spine
	var hand_l_idx := skeleton.add_bone("hand_l")
	skeleton.set_bone_parent(hand_l_idx, spine_idx)
	skeleton.set_bone_rest(hand_l_idx, Transform3D(Basis(), Vector3(-0.28, -0.1, 0.0)))

	# Index-Cache füllen
	_bone_index = {
		"root":   root_idx,
		"spine":  spine_idx,
		"head":   head_idx,
		"hand_r": hand_r_idx,
		"hand_l": hand_l_idx,
	}

	# BoneAttachments vorbelegen — bereit für WeaponVisual3D etc.
	for bone_name in _bone_index:
		var att := BoneAttachment3D.new()
		att.name            = "Attach_" + bone_name
		att.bone_name       = bone_name
		att.use_external_skeleton = false
		skeleton.add_child(att)
		_attachments[bone_name] = att

	AppLogger.log_debug("Skeleton: %d Bones, %d Attachments." % [skeleton.get_bone_count(), _attachments.size()], LOG_CAT)

func _build_slots() -> void:
	_add_slot(SLOT_HEAD, Vector3(0.0, CharacterPartBuilder.HEAD_CENTER_Y + CharacterPartBuilder.HEAD_R, 0.0))
	_add_slot(SLOT_BACK, Vector3(0.0, CharacterPartBuilder.TORSO_CENTER_Y + 0.1, -0.2))

func _add_slot(slot_name: String, pos: Vector3) -> void:
	var slot := Node3D.new()
	slot.name = "Slot_" + slot_name
	slot.position = pos
	skeleton.add_child(slot)
	_slots[slot_name] = slot

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Gibt die BoneAttachment3D für einen Bone-Namen zurück.
## Aufrufer (z.B. WeaponVisual3D) hängen ihre Nodes dort als Child ein.
## Gibt null zurück wenn der Bone nicht existiert — Aufrufer prüfen mit is_instance_valid().
func get_bone_attachment(bone_name: String) -> BoneAttachment3D:
	if not _attachments.has(bone_name):
		AppLogger.log_warn("PlayerVisuals: unbekannter Bone '%s'." % bone_name, LOG_CAT)
		return null
	return _attachments[bone_name] as BoneAttachment3D

## Gibt den Bone-Index zurück (-1 wenn nicht vorhanden).
func get_bone_index(bone_name: String) -> int:
	return _bone_index.get(bone_name, -1)

## Leerer Anker für Zubehör ("head" = Scheitelpunkt, "back" = Rücken). null bei
## unbekanntem Namen. Slots überleben Look-Wechsel.
func get_slot(slot_name: String) -> Node3D:
	return _slots.get(slot_name, null) as Node3D

## Lässt die Figur ein Ziel anschauen (Node3D) bzw. wieder frei umherschauen.
## Rein kosmetisch/lokal — wird nicht synchronisiert.
func set_gaze_target(target: Node3D) -> void:
	if is_instance_valid(gaze):
		gaze.set_focus(target)

func clear_gaze_target() -> void:
	if is_instance_valid(gaze):
		gaze.clear_focus()

## Richtet die Blicksteuerung für einen Besitzer-Node ein: `owner_node` schaut sich nie
## selbst an; `focus_provider` (optional, z. B. Player.get_closest_interactable) liefert
## ein Vorzugsziel, das vor der automatischen Zielwahl gilt.
func configure_gaze(owner_node: Node, focus_provider: Callable = Callable()) -> void:
	if not is_instance_valid(gaze):
		return
	gaze.owner_exclude = owner_node
	gaze.focus_provider = focus_provider

## Setzt das gesamte Aussehen. `look` = CharacterLook-Dictionary; unvollständige
## oder ungültige Einträge werden durch Defaults ersetzt (sanitize()). Baut die
## Körperteile nur neu, wenn sich der Look tatsächlich geändert hat.
func apply_look(look: Dictionary) -> void:
	var clean := CharacterLook.sanitize(look)
	if is_instance_valid(_parts_root) and clean == _look:
		return
	_look = clean
	_rebuild_parts()

## Aktueller (bereinigter) Look — Kopie.
func get_look() -> Dictionary:
	return _look.duplicate()

## Haare ausblenden (z. B. später für Helme, die die Frisur ersetzen).
func set_hair_visible(value: bool) -> void:
	var hair := _parts.get("hair", null) as Node3D
	if is_instance_valid(hair):
		hair.visible = value

func handle_rotation(direction: Vector3, delta: float) -> void:
	if direction.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), rotation_speed * delta)

## Visuelles Feedback für verschiedene Events.
func play_effect(effect_name: String) -> void:
	match effect_name:
		"interrupted":
			var tween := create_tween()
			tween.tween_property(self, "position:x",  0.15, 0.05)
			tween.tween_property(self, "position:x", -0.15, 0.05)
			tween.tween_property(self, "position:x",  0.0,  0.05)

## Round 105 (ADR-048, CharacterCreationService): färbt das Oberteil (Rumpf +
## Ärmel teilen sich ein Material). Schnelle Einfärbung OHNE Neuaufbau — wird
## NICHT in den Look geschrieben und beim nächsten apply_look() wieder durch
## die Farbe aus dem Look ersetzt. Für dauerhafte Änderungen apply_look().
func apply_appearance(color: Color) -> void:
	if not is_instance_valid(mesh):
		return
	var mat := mesh.material_override as StandardMaterial3D
	if not is_instance_valid(mat):
		mat = StandardMaterial3D.new()
		mesh.material_override = mat
	mat.albedo_color = color

## Schwingt Arme und Beine gegengleich; angle in rad (0 = Ruhepose,
## + = "_r"-Arm nach vorn). Hand-Bones folgen den Armen, damit eine Waffe in
## der Hand mitschwingt. Öffentlich, damit Animationen/Tests es direkt setzen
## können — `_process` ruft es aus der gemessenen Geschwindigkeit auf.
func apply_walk_pose(angle: float) -> void:
	if not is_instance_valid(_parts_root):
		return
	_set_rot_x(_parts.get("arm_r", null), -angle)
	_set_rot_x(_parts.get("arm_l", null), angle)
	_set_rot_x(_parts.get("leg_r", null), angle)
	_set_rot_x(_parts.get("leg_l", null), -angle)
	_pose_hand("hand_r", 1.0, -angle)
	_pose_hand("hand_l", -1.0, angle)
	_pose_dirty = not is_zero_approx(angle)

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _rebuild_parts() -> void:
	if is_instance_valid(_parts_root):
		skeleton.remove_child(_parts_root)
		_parts_root.queue_free()
	_parts = CharacterPartBuilder.build(_look)
	_parts_root = _parts["root"] as Node3D
	skeleton.add_child(_parts_root)
	mesh = _parts["torso"] as MeshInstance3D
	_apply_proportions()
	# Kopf-Slot zurück auf Ruheposition, dann Blicksteuerung an die NEUEN Knoten binden.
	var head_slot := get_slot(SLOT_HEAD)
	if is_instance_valid(head_slot):
		head_slot.rotation = Vector3.ZERO
		head_slot.position = Vector3(0.0, CharacterPartBuilder.HEAD_CENTER_Y + CharacterPartBuilder.HEAD_R, 0.0)
	if is_instance_valid(gaze):
		gaze.bind(_parts, head_slot)

## Körpergröße (Skeleton-Skalierung) + Hand-Bones auf die aktuelle Handposition.
func _apply_proportions() -> void:
	# Größenstufe × Geschlecht (Frauen sind im Schnitt etwas kleiner), siehe CharacterLook.body_scale().
	var h := CharacterLook.body_scale(_look)
	skeleton.scale = Vector3(h, h, h)
	var spine_y: float = skeleton.get_bone_rest(int(_bone_index["spine"])).origin.y
	for pair in [["hand_r", 1.0], ["hand_l", -1.0]]:
		var hand := CharacterPartBuilder.hand_position(_look, float(pair[1]))
		var rest_pos := Vector3(hand.x, hand.y - spine_y, hand.z)
		skeleton.set_bone_rest(int(_bone_index[pair[0]]), Transform3D(Basis(), rest_pos))
	skeleton.reset_bone_poses()
	_pose_dirty = false
	_swing_amp = 0.0

func _set_rot_x(node: Variant, angle: float) -> void:
	if node is Node3D and is_instance_valid(node):
		(node as Node3D).rotation.x = angle

## Hand-Bone auf die Handposition eines um die Schulter gedrehten Arms setzen.
## Rechnet relativ zum Parent (spine) und dreht die Hand um dieselbe X-Achse
## wie den Arm (Rx(θ): Vektor (0,-L,0) → (0, -L·cosθ, -L·sinθ)).
func _pose_hand(bone_name: String, side: float, angle: float) -> void:
	var idx: int = int(_bone_index.get(bone_name, -1))
	if idx < 0:
		return
	var spine_y: float = skeleton.get_bone_rest(int(_bone_index["spine"])).origin.y
	var shoulder := CharacterPartBuilder.shoulder_position(_look, side)
	var arm := CharacterPartBuilder.ARM_LEN
	var pos := Vector3(shoulder.x, shoulder.y - spine_y - arm * cos(angle), -arm * sin(angle))
	skeleton.set_bone_pose_position(idx, pos)
	skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.RIGHT, angle))

## Lauf-Schwingung aus der gemessenen Weltgeschwindigkeit des Visual-Nodes
## (für lokale UND entfernte Spieler gleich — der RemotePlayerInterpolator
## bewegt genau diesen Node geglättet). Unsichtbar (Ego-Perspektive) → nichts.
func _process(delta: float) -> void:
	if not walk_animation_enabled or delta <= 0.0 or not is_visible_in_tree():
		return
	var pos := global_position
	var speed := 0.0
	if _has_last_pos:
		var step := pos - _last_global_pos
		step.y = 0.0
		var dist := step.length()
		if dist < TELEPORT_DIST:
			speed = dist / delta
	_last_global_pos = pos
	_has_last_pos = true
	if is_instance_valid(gaze):
		gaze.movement_speed = speed

	var target := 0.0
	if speed > 0.3:
		target = clampf(speed / WALK_REF_SPEED, 0.0, 1.0) * MAX_SWING
	_swing_amp = move_toward(_swing_amp, target, SWING_BLEND * delta)

	if _swing_amp > 0.001:
		_walk_phase = fmod(_walk_phase + speed * STRIDE_PHASE_PER_METER * delta, TAU)
		apply_walk_pose(sin(_walk_phase) * _swing_amp)
	elif _pose_dirty:
		apply_walk_pose(0.0)
