extends HarvestableEntity
class_name TermiteMound

## TermiteMound — Termitenhügel (Skill "entomology" / Insektenkunde).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Echte Welt: Termiten bauen ihre Hügel aus Erde, Speichel und Kot; die höchsten
## dokumentierten ragen rund 8 Meter auf (Guinness-Rekord, Kathedralen-Termiten in
## Australien). Spawnt nur in der Wüste (BiomeRegistry) — im Spiel das einzige
## trocken-warme Biom; echte Termitenhügel stehen in Savanne/Tropen. Respawn: siehe
## WorldService.configure().
##
## Der Bildungstext lebt in data/skills/entomology.tres + docs/nests.md.

func _get_entity_type_id() -> String:
	return "termite_mound"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "harvest_termite_mound"
	d.label        = "Termitenlehm abtragen"
	d.duration     = 3.5
	d.xp_type      = "entomology"
	d.xp_amount    = 25
	d.loot_table   = preload("res://data/loot_tables/loot_termite_mound.tres")
	d.inspect_text = "Ein Termitenturm, hart wie gebrannter Lehm. Wusstest du? Termiten bauen ihn aus Erde, Speichel und Kot – die höchsten gemessenen ragen rund 8 Meter auf."
	return d

func _build_visuals() -> void:
	# Hoher, schlanker Turm mit zwei kleinen Schloten — Placeholder.
	_add_placeholder_cone(0.5, 0.18, 1.5, Color(0.72, 0.52, 0.34), "sand")
	_add_placeholder_cone(0.16, 0.08, 0.5, Color(0.66, 0.47, 0.30), "sand", 1.35)
	AppLogger.log_debug("TermiteMound Placeholder-Turm erstellt.", "termite_mound")
