extends Node3D
class_name OakTree

## OakTree.gd — Fällbarer Baum mit Holzfäll-Interaktion.
##
## Lifecycle via EntityOrchestrator:
##   1. EntityOrchestrator erstellt via OakScript.new()
##   2. world_root.add_child(tree) → _ready() feuert
##   3. EntityOrchestrator.on_spawn(config) feuert
##
## WICHTIG: Diese Klasse implementiert on_spawn() und on_despawn()
## für korrektes Object-Pooling über den EntityOrchestrator.
##
## Nach dem Fällen: WorldData.mark_tree_harvested() aufrufen damit
## die Position im Save-State als geerntet gilt.

const LOG_CAT := "OakTree"

var _interactable_comp: InteractableComponent = null


# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────


func _ready() -> void:
	Logger.log_debug(
		"OakTree _ready() bei Position %s." % str(position), LOG_CAT
	)
	_setup_visuals()
	_setup_interactable()

	Logger.log_info(
		"OakTree bereit. Label: '%s', Drops: %s." % [
			_interactable_comp.data.label if _interactable_comp else "?",
			str(_interactable_comp.data.drops) if _interactable_comp else "?"
		],
		LOG_CAT
	)


## Aufgerufen von EntityOrchestrator NACH add_child() und NACH _ready().
## Für parametrisierbare Konfiguration (z.B. Baum-Typ aus config).
func on_spawn(config: Dictionary = {}) -> void:
	Logger.log_debug(
		"OakTree.on_spawn() Config: %s" % str(config), LOG_CAT
	)
	# Zukunft: config["tree_type"] → unterschiedliche Holz-Arten / XP-Mengen
	# Zukunft: config["level_req"] → Woodcutting-Level-Anforderung


## Aufgerufen von EntityOrchestrator beim Despawn (vor queue_free oder Pool-Rückgabe).
## Wichtig für Save-State: Position als geerntet markieren.
func on_despawn() -> void:
	Logger.log_debug("OakTree.on_despawn() bei %s." % str(global_position), LOG_CAT)

	# Harvested-State im WorldData markieren
	if is_instance_valid(Services.world) and is_instance_valid(Services.world.data):
		Services.world.data.mark_tree_harvested(global_position)
		Logger.log_info(
			"Baum-Position %s als geerntet markiert." % str(global_position), LOG_CAT
		)


# ─────────────────────────────────────────────
# Interaktions-Callback (von InteractableComponent aufgerufen)
# ─────────────────────────────────────────────


func _on_interacted(action_id: String) -> void:
	Logger.log_info(
		"Interaktion abgeschlossen: '%s'. OakTree wird despawnt." % action_id, LOG_CAT
	)

	if action_id == "chop":
		var uuid: String = get_meta("entity_uuid", "")
		if not uuid.is_empty() and is_instance_valid(Services.world):
			# Sauberer Weg: EntityOrchestrator despawnt (markiert auch als geerntet via on_despawn)
			Services.world.despawn_entity(uuid)
		else:
			# Fallback wenn kein EntityOrchestrator verfügbar (z.B. in Tests)
			Logger.log_warn("Keine UUID oder WorldService — direkte queue_free().", LOG_CAT)
			on_despawn()
			queue_free()


# ─────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────


func _setup_visuals() -> void:
	# Factory3D ist jetzt in WorldService — kein eigener Service mehr
	if is_instance_valid(Services.world) and is_instance_valid(Services.world.factory3d):
		Services.world.factory3d.create_simple_tree(self)
		Logger.log_debug("Baum-Visuals via WorldService.factory3d erstellt.", LOG_CAT)
	else:
		Logger.log_warn("Factory3D nicht verfügbar — OakTree ohne Grafik.", LOG_CAT)
		_add_placeholder_visual()


func _add_placeholder_visual() -> void:
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = 2.0
	mesh_inst.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.25, 0.1)
	mesh_inst.material_override = mat
	mesh_inst.position.y = 1.0
	add_child(mesh_inst)
	Logger.log_debug("Placeholder-Visual hinzugefügt.", LOG_CAT)


func _setup_interactable() -> void:
	var d := InteractableData.new()
	d.id = "chop"
	d.label = "Eiche fällen"
	d.duration = 3.0
	d.xp_type = "woodcutting"
	d.xp_amount = 25
	d.drops = {"log_normal": 3}

	_interactable_comp = InteractableComponent.new()
	_interactable_comp.data = d
	add_child(_interactable_comp)

	Logger.log_debug(
		"InteractableComponent erstellt: '%s', XP: %d woodcutting." % [d.label, d.xp_amount],
		LOG_CAT
	)
