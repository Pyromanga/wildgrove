extends Node3D
class_name WeaponVisual3D

## WeaponVisual3D — rendert eine Waffe ODER ein Werkzeug als Mesh am
## hand_r-Bone des Players.
##
## VERWENDUNG:
##   var wv := WeaponVisual3D.new()
##   wv.attach_to(player.visuals, item_def)      # hängt sich selbst ein
##   wv.detach()                                 # entfernt sich wieder
##
## DESIGN:
##   - Hängt als Child in die BoneAttachment3D "hand_r" von PlayerVisuals.
##   - weapon_offset / weapon_rotation sind @export — im Editor justierbar,
##     oder per WeaponDefinition/ToolDefinition.visual_offset überschreibbar
##     (Schritt 3).
##   - Kein eigenes Mesh-Asset bisher: erzeugt ein prozedurales BoxMesh als
##     Platzhalter. Echte Meshes kommen wenn Assets vorhanden sind.
##   - Singleton-Konvention: ein Player trägt immer nur eine Waffe/ein
##     Werkzeug gleichzeitig. attach_to() ruft zuerst detach() auf dem alten
##     Attachment auf.
##
## BUGFIX (2026-09-25, "Equipment wird nicht 3D gerendert (Axt/Spitzhacke/
## Schaufel)"): Parametertyp war bisher `WeaponDefinition` — ToolDefinition
## ist KEIN WeaponDefinition-Subtyp (beide erben nur unabhängig voneinander
## von ItemDefinition), ein `as WeaponDefinition`-Cast in EquipmentService.
## equip() lieferte für Werkzeuge deshalb still `null`, und `_build_mesh()`/
## `_get_mesh_size()` fielen auf den generischen Platzhalter zurück — der
## eigentliche Bug lag aber schon eine Ebene höher (equip() hängte für
## ToolDefinition gar kein WeaponVisual3D an, siehe dortiger Kommentar).
## Um Werkzeuge zusätzlich optisch von Waffen zu unterscheiden (statt beide
## auf denselben Platzhalter fallen zu lassen), akzeptiert diese Klasse jetzt
## `ItemDefinition` (Basisklasse beider) und branched intern per `is`-Check.

const LOG_CAT := "WeaponVisual3D"

## Offset relativ zum Bone-Attachment (justierbar per WeaponDefinition/ToolDefinition).
@export var weapon_offset:   Vector3 = Vector3(0.0, -0.15, 0.2)

## Rotation relativ zum Bone-Attachment.
@export var weapon_rotation: Vector3 = Vector3(0.0, 0.0, 0.0)

var _mesh_instance: MeshInstance3D = null
var _current_attachment: BoneAttachment3D = null

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## Hängt diesen WeaponVisual3D in den hand_r-Bone von PlayerVisuals ein
## und baut das Mesh aus der WeaponDefinition/ToolDefinition auf.
##
## [param visuals]   PlayerVisuals-Instanz des Players.
## [param item_def]  WeaponDefinition- oder ToolDefinition-Resource (darf
##                    null sein → Platzhalter-Mesh; jeder andere
##                    ItemDefinition-Subtyp fällt ebenfalls auf den
##                    Platzhalter zurück, siehe _build_mesh()).
func attach_to(visuals: PlayerVisuals, item_def: ItemDefinition = null) -> void:
	detach()

	var att := visuals.get_bone_attachment("hand_r")
	if not is_instance_valid(att):
		AppLogger.log_error("WeaponVisual3D: hand_r-Attachment nicht gefunden.", LOG_CAT)
		return

	_current_attachment = att
	att.add_child(self)

	# Offset + Rotation aus WeaponDefinition/ToolDefinition übernehmen wenn
	# vorhanden. Beide deklarieren visual_offset/visual_rotation unabhängig
	# voneinander (kein gemeinsamer Basistyp dafür) — .get() statt direktem
	# Property-Zugriff, damit ein beliebiger anderer ItemDefinition-Subtyp
	# ohne diese Felder nicht mit einem Skriptfehler abbricht.
	if is_instance_valid(item_def):
		var off: Variant = item_def.get("visual_offset")
		var rot: Variant = item_def.get("visual_rotation")
		if off is Vector3:
			weapon_offset = off
		if rot is Vector3:
			weapon_rotation = rot

	position = weapon_offset
	rotation_degrees = weapon_rotation

	_build_mesh(item_def)
	AppLogger.log_info("WeaponVisual3D eingehängt (Bone: hand_r, Item: %s)." % \
		(item_def.display_name if is_instance_valid(item_def) else "Platzhalter"), LOG_CAT)

## Entfernt diesen Node vom Bone-Attachment.
func detach() -> void:
	if is_instance_valid(_current_attachment) and get_parent() == _current_attachment:
		_current_attachment.remove_child(self)
		AppLogger.log_debug("WeaponVisual3D ausgehängt.", LOG_CAT)
	_current_attachment = null

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _build_mesh(item_def: ItemDefinition) -> void:
	if is_instance_valid(_mesh_instance):
		_mesh_instance.queue_free()

	_mesh_instance      = MeshInstance3D.new()
	_mesh_instance.name = "WeaponMesh"

	var box        := BoxMesh.new()
	box.size        = _get_mesh_size(item_def)
	_mesh_instance.mesh = box

	# Material: Farbe je nach Typ für sofort erkennbare Unterscheidung.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	mat.metallic = 0.85
	mat.roughness = 0.2
	if item_def is WeaponDefinition:
		match (item_def as WeaponDefinition).weapon_type:
			WeaponDefinition.WeaponType.DAGGER:
				mat.albedo_color = Color(0.6, 0.85, 0.6)   # Grünstich → Gift
				mat.metallic = 0.7
			WeaponDefinition.WeaponType.SWORD:
				mat.albedo_color = Color(0.78, 0.78, 0.88)  # Silber
			WeaponDefinition.WeaponType.AXE:
				mat.albedo_color = Color(0.65, 0.45, 0.25)  # Braun/Stahl
			WeaponDefinition.WeaponType.STAFF:
				mat.albedo_color = Color(0.5, 0.3, 0.7)     # Lila/Magisch
				mat.emission_enabled = true
				mat.emission = Color(0.3, 0.1, 0.5) * 0.4
			_:
				mat.albedo_color = Color(0.7, 0.7, 0.7)
	elif item_def is ToolDefinition:
		match (item_def as ToolDefinition).tool_type:
			ToolDefinition.ToolType.AXE:
				mat.albedo_color = Color(0.55, 0.4, 0.22)   # Holzstiel-Braun
			ToolDefinition.ToolType.PICKAXE:
				mat.albedo_color = Color(0.55, 0.55, 0.6)   # Stahlgrau
			ToolDefinition.ToolType.SHOVEL:
				mat.albedo_color = Color(0.72, 0.6, 0.35)   # Holz/Metall hell
			ToolDefinition.ToolType.TONGS:
				mat.albedo_color = Color(0.32, 0.32, 0.36)  # dunkles, geschwärztes Eisen
			ToolDefinition.ToolType.HAMMER:
				mat.albedo_color = Color(0.42, 0.42, 0.48)  # Hammerkopf-Stahl
			ToolDefinition.ToolType.SCYTHE:
				mat.albedo_color = Color(0.62, 0.62, 0.58)  # Klinge/Stiel hell, Stahl-Holz-Mix
			_:
				mat.albedo_color = Color(0.6, 0.6, 0.6)
	else:
		mat.albedo_color = Color(0.5, 0.5, 0.5)
	_mesh_instance.material_override = mat

	add_child(_mesh_instance)

## Gibt eine Mesh-Größe zurück die zum Waffen-/Werkzeugtyp passt.
func _get_mesh_size(item_def: ItemDefinition) -> Vector3:
	if not is_instance_valid(item_def):
		return Vector3(0.05, 0.3, 0.05)   # Generischer Platzhalter

	if item_def is WeaponDefinition:
		match (item_def as WeaponDefinition).weapon_type:
			WeaponDefinition.WeaponType.DAGGER:
				return Vector3(0.04, 0.25, 0.04)
			WeaponDefinition.WeaponType.SWORD:
				return Vector3(0.06, 0.55, 0.06)
			WeaponDefinition.WeaponType.AXE:
				return Vector3(0.14, 0.40, 0.06)
			WeaponDefinition.WeaponType.STAFF:
				return Vector3(0.05, 0.90, 0.05)
			_:
				return Vector3(0.05, 0.30, 0.05)
	elif item_def is ToolDefinition:
		match (item_def as ToolDefinition).tool_type:
			ToolDefinition.ToolType.AXE:
				return Vector3(0.14, 0.45, 0.06)    # breiter Kopf, wie Kampf-Axt
			ToolDefinition.ToolType.PICKAXE:
				return Vector3(0.05, 0.55, 0.05)     # schlank, länger
			ToolDefinition.ToolType.SHOVEL:
				return Vector3(0.16, 0.50, 0.03)     # breites, flaches Blatt
			ToolDefinition.ToolType.TONGS:
				return Vector3(0.08, 0.38, 0.03)     # zwei lange, flache Backen
			ToolDefinition.ToolType.HAMMER:
				return Vector3(0.12, 0.34, 0.07)     # kurzer Stiel, schwerer Kopf
			ToolDefinition.ToolType.SCYTHE:
				return Vector3(0.28, 0.80, 0.03)     # langer Stiel + breite, flache Klinge (Box-Näherung)
			_:
				return Vector3(0.05, 0.30, 0.05)
	else:
		return Vector3(0.05, 0.30, 0.05)
