extends HarvestableEntity
class_name IceCrystal

## IceCrystal — Erntbare Winter-Formation (Foraging-Interaktion, gleicher
## Skill wie Cactus — auf Wunsch, Round 77).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Anders als PineTree/Cactus: es gibt in Factory3D noch KEIN fertiges
## Prefab für Eiskristalle (kein create_ice_crystal() — geprüft, siehe
## Factory3D.gd; nur create_pine_tree/create_cactus/create_fern/
## create_fallen_tree/create_mushroom_cluster/create_rock_boulder
## existieren). Deshalb hier ein Placeholder-Visual nach IronOre-Muster
## (kein Factory3D-Aufruf, direkter Primitiv-Mesh) statt dem
## Factory3D-Fallback-Pattern von Cactus/PineTree. Sobald ein echtes
## Prefab existiert, hier auf factory.create_ice_crystal(self) umstellen.
##
## "winter.prop_chances" (BiomeRegistry.gd) hatte bisher keinen
## "ice_crystal"-Eintrag — mit diesem Entity-Typ ergänzt (Round 77),
## analog zum cactus/desert-Muster aus Round 74/75.

func _get_entity_type_id() -> String:
	return "ice_crystal"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id            = "harvest_ice_crystal"
	d.label         = "Eiskristall ernten"
	d.duration      = 2.5
	d.xp_type       = "foraging"
	d.xp_amount     = 15
	d.loot_table    = preload("res://data/loot_tables/loot_ice_crystal.tres")
	d.yield_stat_id = "gathering_yield_foraging"
	d.inspect_text  = "Eine scharfkantige Eisformation. Das Innere schimmert bläulich — lässt sich zu feinem Kristallstaub verarbeiten."
	return d

func _build_visuals() -> void:
	# Kein Factory3D-Prefab vorhanden (siehe Klassenkommentar) — Placeholder
	# bleibt hier bewusst die endgültige Lösung, bis create_ice_crystal()
	# existiert. Kein "Factory3D nicht verfügbar"-Fallback-Log wie bei
	# Cactus/PineTree, da es hier keine bessere Alternative gäbe.
	_add_placeholder_box(Vector3(0.5, 0.9, 0.5), Color(0.95, 0.97, 1.0), "ice")
	AppLogger.log_debug("IceCrystal BoxMesh 0.5x0.9x0.5m erstellt (kein Factory3D-Prefab).", "ice_crystal")
