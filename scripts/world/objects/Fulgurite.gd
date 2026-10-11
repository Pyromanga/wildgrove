extends HarvestableEntity
class_name Fulgurite

## Fulgurite — Blitzglas im Wüstensand (Skill "stormlore" / Sturmkunde).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Echte Welt: Schlägt ein Blitz in Sand ein, schmilzt er ihn zu einer glasigen
## Röhre — Fulgurit. Passend dazu spawnt das Objekt nur im Wüsten-Biom
## (BiomeRegistry._make_desert()). Respawn: siehe WorldService.configure().
##
## Der Bildungstext lebt in data/skills/stormlore.tres (Zwei-Ebenen-Regel,
## docs/skill-writing-guide.md) — inspect_text hier wiederholt ihn kurz.

func _get_entity_type_id() -> String:
	return "fulgurite"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "harvest_fulgurite"
	d.label        = "Blitzglas bergen"
	d.duration     = 3.0
	d.xp_type      = "stormlore"
	d.xp_amount    = 30
	d.loot_table   = preload("res://data/loot_tables/loot_fulgurite.tres")
	d.inspect_text = "Eine glasige Röhre im Sand, noch leicht grün schimmernd. Wusstest du? Schlägt ein Blitz in Sand ein, schmilzt er ihn zu Glas – Fulgurit."
	return d

func _build_visuals() -> void:
	# Dünne, helle Glasröhre (Placeholder, gleiches Muster wie IronOre/CopperOre).
	_add_placeholder_cylinder(0.09, 0.9, Color(0.85, 1.0, 0.92), "glass")
	AppLogger.log_debug("Fulgurite Placeholder-Zylinder erstellt.", "fulgurite")
