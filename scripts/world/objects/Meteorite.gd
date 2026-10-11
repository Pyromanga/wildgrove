extends HarvestableEntity
class_name Meteorite

## Meteorite — Vom Himmel gefallener "Sternenstein" (Skill "stargazing" / Sternkunde).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Echte Welt: Aus Meteoriteneisen wurden schon Klingen und Werkzeuge gefertigt,
## bevor Eisen aus Erz geschmolzen werden konnte. Meteoriten fallen überall,
## fallen aber vor allem auf hellem Untergrund (Eis, Wüste) auf — daher spawnt
## das Objekt in winter/desert/mountain (BiomeRegistry), selten.
## Respawn: siehe WorldService.configure().
##
## Der Bildungstext lebt in data/skills/stargazing.tres.

func _get_entity_type_id() -> String:
	return "meteorite"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "harvest_meteorite"
	d.label        = "Sternenstein untersuchen"
	d.duration     = 4.0
	d.xp_type      = "stargazing"
	d.xp_amount    = 40
	d.loot_table   = preload("res://data/loot_tables/loot_meteorite.tres")
	d.inspect_text = "Ein dunkler Stein, schwer wie Eisen – vom Himmel gefallen. Wusstest du? Aus Meteoriteneisen schmiedeten Menschen schon Klingen, bevor sie Eisen aus Erz gewinnen konnten."
	return d

func _build_visuals() -> void:
	_add_placeholder_box(Vector3(0.7, 0.55, 0.7), Color(0.22, 0.22, 0.26), "stone")
	AppLogger.log_debug("Meteorite Placeholder-Box erstellt.", "meteorite")
