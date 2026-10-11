class_name DigFind
extends HarvestableEntity

## DigFind — sichtbarer Erz- oder Edelstein-Fund am Grubenboden (Wahrheit: DigFindRegistry).
##
## Spawn-Config: {key: String, kind: String (DigFindTable-Art)}. Bergen läuft wie bei jedem
## Erz (InteractionResolver: Loot + Bergbau-XP), danach despawnt der Node. Anders als andere
## Erntegüter wird KEIN Harvest-Marker gesetzt (kein Respawn) — stattdessen wird der Record
## in der Registry gelöscht. on_despawn() tut das bewusst NICHT: es läuft auch beim
## Entladen der ganzen Welt, und dann müssen die Funde im Spielstand bleiben.

var _kind: String = DigFindTable.DEFAULT_KIND
var _find_key: String = ""

func _get_entity_type_id() -> String:
	return "dig_find"

func _build_interactable_data() -> InteractableData:
	return DigFindTable.build_interactable(DigFindTable.DEFAULT_KIND)

## Art VOR dem Aufbau setzen: HarvestableEntity.on_spawn() baut die Visuals sofort.
func on_spawn(config: Dictionary = {}, ctx: IEntityContext = null) -> void:
	_kind = String(config.get("kind", DigFindTable.DEFAULT_KIND))
	if not DigFindTable.is_known(_kind):
		_kind = DigFindTable.DEFAULT_KIND
	_find_key = String(config.get("key", ""))
	super.on_spawn(config, ctx)
	if is_instance_valid(_interactable_comp):
		_interactable_comp.data = DigFindTable.build_interactable(_kind)
		_interactable_comp.refresh_label()

func on_despawn() -> void:
	if is_instance_valid(_interactable_comp):
		_interactable_comp.disconnect_world_events()

func _on_interacted(action_id: String, peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var world: WorldService = _ctx.get_world() if is_instance_valid(_ctx) else null
	if is_instance_valid(world):
		world.remove_dig_find(_find_key)
	super._on_interacted(action_id, peer_id)

func _build_visuals() -> void:
	var def: Dictionary = DigFindTable.get_def(_kind)
	var col: Color = def["color"]
	if bool(def["gem"]):
		_build_gem(col)
	else:
		_build_ore(col)

## Edelstein: zwei aneinandergesetzte Vierkant-Pyramiden (Oktaeder), leicht leuchtend.
func _build_gem(col: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.1
	mat.metallic = 0.3
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.6
	for flip in [1.0, -1.0]:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.2
		cone.height = 0.22
		cone.radial_segments = 4
		cone.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = mat
		mi.position.y = 0.3 + 0.11 * flip
		if flip < 0.0:
			mi.rotation.x = PI
			mi.position.y = 0.3 - 0.11
		add_child(mi)
	_add_stone_base(Color(0.30, 0.28, 0.27), 0.28)

## Erz: dunkler Felsbrocken mit hellen Erzadern-Klötzchen.
func _build_ore(col: Color) -> void:
	_add_stone_base(Color(0.34, 0.31, 0.29), 0.42)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.6
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.25
	var spots: Array[Vector3] = [Vector3(0.14, 0.34, 0.10), Vector3(-0.12, 0.28, 0.16), Vector3(0.04, 0.24, -0.20)]
	for p in spots:
		var box := BoxMesh.new()
		box.size = Vector3(0.14, 0.11, 0.14)
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = mat
		mi.position = p
		mi.rotation = Vector3(0.5, p.x * 6.0, 0.3)
		add_child(mi)

func _add_stone_base(col: Color, size: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = size * 0.5
	sphere.height = size * 0.8
	sphere.radial_segments = 6
	sphere.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.position.y = size * 0.2
	add_child(mi)
