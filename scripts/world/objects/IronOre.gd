extends Node3D
class_name IronOre

## IronOre.gd — Abbaubarer Erzblock (Mining-Interaktion).
##
## Lifecycle via EntityOrchestrator (identisches Muster wie OakTree):
##   1. EntityOrchestrator erstellt via IronOreScript.new()
##   2. world_root.add_child(ore) → _ready() feuert
##   3. EntityOrchestrator.on_spawn(config) feuert

const LOG_CAT := "IronOre"

var _interactable_comp: InteractableComponent = null


# ─────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────


func _ready() -> void:
	Logger.log_debug("IronOre _ready() bei Position %s." % str(position), LOG_CAT)
	_setup_visuals()
	_setup_interactable()

	Logger.log_info(
		"IronOre bereit. Label: '%s', XP: %d." % [
			_interactable_comp.data.label if _interactable_comp else "?",
			_interactable_comp.data.xp_amount if _interactable_comp else 0
		],
		LOG_CAT
	)


func on_spawn(config: Dictionary = {}) -> void:
	Logger.log_debug("IronOre.on_spawn() Config: %s" % str(config), LOG_CAT)
	# Zukunft: config["ore_quality"] → unterschiedliche Item-Drops / XP-Bonus
	# Zukunft: config["level_req"] → Mining-Level-Anforderung


func on_despawn() -> void:
	Logger.log_debug("IronOre.on_despawn() bei %s." % str(global_position), LOG_CAT)

	if is_instance_valid(Services.world) and is_instance_valid(Services.world.data):
		Services.world.data.mark_ore_harvested(global_position)
		Logger.log_info(
			"Erz-Position %s als abgebaut markiert." % str(global_position), LOG_CAT
		)


# ─────────────────────────────────────────────
# Interaktions-Callback (von InteractableComponent aufgerufen)
# ─────────────────────────────────────────────


func _on_interacted(action_id: String) -> void:
	Logger.log_info(
		"Interaktion abgeschlossen: '%s'. IronOre wird despawnt." % action_id, LOG_CAT
	)

	if action_id == "mine_iron":
		var uuid: String = get_meta("entity_uuid", "")
		if not uuid.is_empty() and is_instance_valid(Services.world):
			Services.world.despawn_entity(uuid)
		else:
			Logger.log_warn("Keine UUID oder WorldService — direkte queue_free().", LOG_CAT)
			on_despawn()
			queue_free()


# ─────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────


func _setup_visuals() -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.8, 0.8)
	m.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.5, 0.4)
	m.material_override = mat

	add_child(m)
	Logger.log_debug("Visuals erstellt (BoxMesh 0.8m).", LOG_CAT)


func _setup_interactable() -> void:
	var d := InteractableData.new()
	d.id = "mine_iron"
	d.label = "Eisenerz abbauen"
	d.duration = 4.0
	d.xp_type = "mining"
	d.xp_amount = 40
	d.drops = {"iron_ore": 1}

	_interactable_comp = InteractableComponent.new()
	_interactable_comp.data = d
	add_child(_interactable_comp)

	Logger.log_debug(
		"InteractableComponent erstellt: '%s', XP: %d mining." % [d.label, d.xp_amount],
		LOG_CAT
	)
