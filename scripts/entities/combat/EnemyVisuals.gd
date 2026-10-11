class_name EnemyVisuals
extends RefCounted

## EnemyVisuals — Baut das visuelle Erscheinungsbild eines EnemyNPC.
## Extrahiert aus EnemyNPC.gd damit die KI-Logik dort nicht von Mesh-Code überwuchert wird.
##
## Wunsch "Gegner bessere Modelle": bisher war JEDER Gegnertyp exakt dieselbe eine Kapsel, nur
## anders eingefärbt (_color) — Goblin und Skelett waren geometrisch ununterscheidbar, nur am
## Namensschild/Farbe zu erkennen. _build_body() baut jetzt eine echte kleine Figur aus
## Kopf/Rumpf/Armen/Beinen (einfache Primitive, kein Skinning nötig — MeshInstance3D-Kinder wie
## bisher, nur mehrere statt einer), plus pro Typ 2-3 unterscheidende Accessoires
## (_add_goblin_accents()/_add_skeleton_accents()), ausgewählt über den neuen `type_id`-Parameter
## (EnemyNPC._type_id — "goblin"/"skeleton", schon vorhanden, bisher nur fürs Kill-Signal
## genutzt). Gesamthöhe bewusst nah an der bisherigen Kapsel gehalten (Kollisionskapsel in
## EnemyNPC._build_collision() bleibt unverändert, Health-Bar/Label-Höhen ebenso) — reine
## Optik-Erweiterung, keine Gameplay-/Hitbox-Änderung.

const LOG_CAT := "EnemyVisuals"

## Körpermaße — Gesamthöhe (Fuß bis Kopfoberkante) bewusst ~1.16, nah an der alten Kapsel
## (radius 0.30, height 1.0, Position y=0.7 → Oberkante ~1.2), damit Health-Bar (y=1.6) und
## Namensschild (y=1.85) ohne Anpassung weiter gut über dem Kopf schweben.
const LEG_LENGTH: float = 0.42
const LEG_RADIUS: float = 0.065
const TORSO_HEIGHT: float = 0.5
const TORSO_RADIUS: float = 0.18
const TORSO_OVERLAP: float = 0.03   ## Rumpf überlappt die Beine leicht, keine sichtbare Lücke.
const ARM_LENGTH: float = 0.38
const ARM_RADIUS: float = 0.05
const ARM_GAP: float = 0.02         ## Abstand Rumpfaußenkante → Armachse.
const ARM_DROP: float = 0.03        ## Arme hängen leicht unter Schulterhöhe.
const HEAD_RADIUS: float = 0.13
const HEAD_GAP: float = 0.01

var _health_bar: MeshInstance3D

func build(parent: Node3D, color: Color, max_health: int, label_text: String, type_id: String = "") -> void:
	_build_body(parent, color, type_id)
	_build_health_bar(parent)
	_build_label(parent, label_text)

func update_health_bar(current: int, maximum: int) -> void:
	if not is_instance_valid(_health_bar):
		return
	var ratio: float = float(current) / float(maximum)
	_health_bar.scale.x = maxf(0.05, ratio)
	var mat := _health_bar.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(1.0 - ratio, ratio * 0.8, 0.1)

## Baut Beine, Rumpf, Arme und Kopf aus einfachen Primitiven (statt einer einzelnen Kapsel) und
## hängt danach die typ-spezifischen Accessoires an (siehe Klassenkommentar).
func _build_body(parent: Node3D, color: Color, type_id: String) -> void:
	var mat := _make_material(color)

	var leg_mesh := CapsuleMesh.new()
	leg_mesh.radius = LEG_RADIUS
	leg_mesh.height = LEG_LENGTH
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.mesh = leg_mesh
		leg.material_override = mat
		leg.position = Vector3(side * (LEG_RADIUS + 0.02), LEG_LENGTH * 0.5, 0.0)
		parent.add_child(leg)

	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = TORSO_RADIUS
	torso_mesh.height = TORSO_HEIGHT
	torso.mesh = torso_mesh
	torso.material_override = mat
	torso.position = Vector3(0.0, LEG_LENGTH + TORSO_HEIGHT * 0.5 - TORSO_OVERLAP, 0.0)
	parent.add_child(torso)
	var torso_top: float = torso.position.y + TORSO_HEIGHT * 0.5

	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = ARM_RADIUS
	arm_mesh.height = ARM_LENGTH
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		arm.mesh = arm_mesh
		arm.material_override = mat
		arm.position = Vector3(
			side * (TORSO_RADIUS + ARM_RADIUS + ARM_GAP),
			torso_top - ARM_LENGTH * 0.5 - ARM_DROP,
			0.0)
		arm.rotation_degrees = Vector3(0.0, 0.0, side * 8.0)   # leicht nach außen abgespreizt
		parent.add_child(arm)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = HEAD_RADIUS
	head_mesh.height = HEAD_RADIUS * 2.0
	head.mesh = head_mesh
	head.material_override = mat
	head.position = Vector3(0.0, torso_top + HEAD_RADIUS + HEAD_GAP, 0.0)
	parent.add_child(head)

	match type_id:
		"goblin":
			_add_goblin_accents(parent, head.position, color)
		"skeleton":
			_add_skeleton_accents(parent, head.position, torso.position, color)
		_:
			# Unbekannter/leerer type_id (z.B. künftige Gegnertypen ohne eigene Accessoires
			# noch) — bleibt bei der reinen Grundfigur, kein Fehler.
			pass

## Goblin-Accessoires: zwei spitze Ohren seitlich am Kopf (Kegel) und eine grob geschnitzte
## Keule in der Hand — macht auf den ersten Blick "wilder Angreifer" erkennbar.
func _add_goblin_accents(parent: Node3D, head_pos: Vector3, skin_color: Color) -> void:
	var ear_mat := _make_material(skin_color.darkened(0.1))
	var ear_mesh := CylinderMesh.new()
	ear_mesh.top_radius = 0.0
	ear_mesh.bottom_radius = 0.05
	ear_mesh.height = 0.12
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		ear.mesh = ear_mesh
		ear.material_override = ear_mat
		ear.position = head_pos + Vector3(side * HEAD_RADIUS * 0.9, 0.02, 0.0)
		ear.rotation_degrees = Vector3(0.0, 0.0, side * -55.0)
		parent.add_child(ear)

	var club_mat := _make_material(Color(0.35, 0.22, 0.1))
	var club_mesh := CylinderMesh.new()
	club_mesh.top_radius = 0.05
	club_mesh.bottom_radius = 0.03
	club_mesh.height = 0.32
	var club := MeshInstance3D.new()
	club.mesh = club_mesh
	club.material_override = club_mat
	club.position = head_pos + Vector3(HEAD_RADIUS * 1.7, -0.5, 0.05)
	club.rotation_degrees = Vector3(65.0, 0.0, 15.0)
	parent.add_child(club)

## Skelett-Accessoires: zwei leuchtende Augen (emissiv, wie die Warmlicht-Requisiten in
## BuildPieceDefinition) und drei dünne Rippenbänder auf dem Rumpf — macht auf den ersten Blick
## "untot" statt nur "bläulich gefärbter Goblin" erkennbar.
func _add_skeleton_accents(parent: Node3D, head_pos: Vector3, torso_pos: Vector3, base_color: Color) -> void:
	var eye_mat := _make_material(Color(0.9, 0.15, 0.1))
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.9, 0.1, 0.05)
	eye_mat.emission_energy_multiplier = 2.0
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.02
	eye_mesh.height = 0.04
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = head_pos + Vector3(side * 0.06, 0.0, HEAD_RADIUS * 0.9)
		parent.add_child(eye)

	var rib_mat := _make_material(base_color.darkened(0.2))
	var rib_mesh := BoxMesh.new()
	rib_mesh.size = Vector3(TORSO_RADIUS * 1.7, 0.03, 0.06)
	for i in 3:
		var rib := MeshInstance3D.new()
		rib.mesh = rib_mesh
		rib.material_override = rib_mat
		rib.position = torso_pos + Vector3(0.0, 0.15 - float(i) * 0.14, TORSO_RADIUS * 0.6)
		parent.add_child(rib)

func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat

func _build_health_bar(parent: Node3D) -> void:
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(0.8, 0.06, 0.04)
	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color   = Color(0.9, 0.1, 0.1)
	bar_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_health_bar = MeshInstance3D.new()
	_health_bar.mesh = bar_mesh
	_health_bar.material_override = bar_mat
	_health_bar.position.y = 1.6
	parent.add_child(_health_bar)

func _build_label(parent: Node3D, text: String) -> void:
	var lbl := Label3D.new()
	lbl.text       = text
	lbl.font_size  = 40
	lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate   = Color(1, 0.4, 0.4)
	lbl.position.y = 1.85
	parent.add_child(lbl)
