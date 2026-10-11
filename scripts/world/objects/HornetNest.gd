extends HarvestableEntity
class_name HornetNest

## HornetNest — Verlassenes Hornissennest (Skill "entomology" / Insektenkunde).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Echte Welt: "Drei Hornissenstiche töten einen Menschen" ist ein Mythos — Hornissengift ist
## nicht stärker als das von Wespen oder Bienen (Verbraucher- und Naturschutzquellen, siehe
## docs/nests.md). Allergien bleiben gefährlich, deshalb hält der Text Abstand zu BEWOHNTEN
## Nestern. Hornissen sind geschützt; wie beim Wespennest bergen Spieler nur das verlassene
## Nest. Spawnt in (toten) Wäldern, wo Baumhöhlen sind (BiomeRegistry). Respawn: siehe
## WorldService.configure().
##
## Der Bildungstext lebt in data/skills/entomology.tres + docs/nests.md.

func _get_entity_type_id() -> String:
	return "hornet_nest"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "harvest_hornet_nest"
	d.label        = "Verlassenes Nest bergen"
	d.duration     = 3.5
	d.xp_type      = "entomology"
	d.xp_amount    = 35
	d.loot_table   = preload("res://data/loot_tables/loot_hornet_nest.tres")
	d.inspect_text = "Ein großes, leeres Hornissennest. Wusstest du? \"Drei Stiche töten einen Menschen\" ist ein Mythos. Vor bewohnten Nestern trotzdem Abstand halten."
	return d

func _build_visuals() -> void:
	# Großer, bräunlicher Papierballon — Placeholder.
	_add_placeholder_ellipsoid(0.38, 0.8, Color(0.62, 0.50, 0.34), "bark", 0.1)
	AppLogger.log_debug("HornetNest Placeholder-Ellipsoid erstellt.", "hornet_nest")
