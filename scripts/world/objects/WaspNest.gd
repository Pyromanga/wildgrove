extends HarvestableEntity
class_name WaspNest

## WaspNest — Verlassenes Wespennest (Skill "entomology" / Insektenkunde).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Echte Welt: Wespen kauen Holzfasern mit Speichel zu Brei und bauen daraus Papier. Beim
## Beobachten kam Réaumur um 1720 auf die Idee, Papier aus Holz statt aus Lumpen zu machen.
## In unserem Klima nutzen Wespenvölker ein Nest nur eine Saison — deshalb "bergen" Spieler
## im Spiel ausschließlich das VERLASSENE Nest (kein Eingriff in ein bewohntes).
## Spawnt auf Wiese und im Wald (BiomeRegistry). Respawn: siehe WorldService.configure().
##
## Der Bildungstext lebt in data/skills/entomology.tres + docs/nests.md.

func _get_entity_type_id() -> String:
	return "wasp_nest"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "harvest_wasp_nest"
	d.label        = "Verlassenes Nest bergen"
	d.duration     = 3.0
	d.xp_type      = "entomology"
	d.xp_amount    = 25
	d.loot_table   = preload("res://data/loot_tables/loot_wasp_nest.tres")
	d.inspect_text = "Ein papierner Ballon, still und leer: ein altes Wespennest. Wusstest du? Wespen kauen Holz zu Brei und bauen daraus Papier – das gab Réaumur um 1720 eine Idee."
	return d

func _build_visuals() -> void:
	# Grau-beiger Papierballon — Placeholder.
	_add_placeholder_ellipsoid(0.26, 0.5, Color(0.78, 0.74, 0.62), "bark", 0.15)
	AppLogger.log_debug("WaspNest Placeholder-Ellipsoid erstellt.", "wasp_nest")
