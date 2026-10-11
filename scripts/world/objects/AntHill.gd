extends HarvestableEntity
class_name AntHill

## AntHill — Waldameisenhügel (Skill "entomology" / Insektenkunde).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Echte Welt: Ameisensäure heißt so, weil man sie 1671 (John Ray) erstmals aus
## destillierten Ameisen gewann — lat. formica = Ameise. Rote Waldameisen stehen in
## Deutschland unter besonderem Schutz; im Spiel "sammelt" man deshalb nur einen
## Tropfen, der Hügel bleibt als Weltobjekt nach Respawn-Zeit wieder stehen.
## Spawnt im Wald (BiomeRegistry). Respawn: siehe WorldService.configure().
##
## Der Bildungstext lebt in data/skills/entomology.tres + docs/nests.md.

func _get_entity_type_id() -> String:
	return "ant_hill"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "harvest_ant_hill"
	d.label        = "Ameisensäure sammeln"
	d.duration     = 3.0
	d.xp_type      = "entomology"
	d.xp_amount    = 20
	d.loot_table   = preload("res://data/loot_tables/loot_ant_hill.tres")
	d.inspect_text = "Ein Ameisenhügel aus Nadeln und Zweigen, überall wuselt es. Wusstest du? Ameisensäure heißt so, weil man sie 1671 erstmals aus Ameisen gewann (lat. formica)."
	return d

func _build_visuals() -> void:
	# Nadelhügel: breiter, flacher Kegel + kleiner Aufsatz — Placeholder, gleiches Muster wie CharcoalKiln.
	_add_placeholder_cone(0.55, 0.12, 0.55, Color(0.45, 0.32, 0.18), "bark")
	_add_placeholder_cone(0.22, 0.06, 0.2, Color(0.38, 0.27, 0.15), "bark", 0.45)
	AppLogger.log_debug("AntHill Placeholder-Kegel erstellt.", "ant_hill")
