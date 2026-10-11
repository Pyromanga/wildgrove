extends HarvestableEntity
class_name Cactus

## Cactus — Erntbare Wüstenpflanze (Foraging-Interaktion).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Round 76 — schließt die Lücke aus TODO-offene-probleme.md
## "BiomeRegistry/BiomeDefinition ist totes Datenmodell": desert.prop_chances
## enthält "cactus" bereits seit Round 74, WorldEntityRegistry.KNOWN_PROP_TYPES
## bisher ohne "cactus" (kein Entity-Typ vorhanden) → ChunkEntitySpawner hat
## den Eintrag stillschweigend gefiltert, nie gespawnt. Mit diesem Skript +
## Registrierung in WorldEntityRegistry.register_all() + KNOWN_PROP_TYPES
## spawnt Cactus jetzt tatsächlich im Wüsten-Biom — KEINE weitere Änderung an
## ChunkEntitySpawner/BiomeRegistry nötig, die Verdrahtung greift automatisch.
##
## Neuer Skill "foraging" (data/skills/foraging.tres) — vorher registriert,
## aber ohne Konsumenten (wie "farming", das nach wie vor keinen hat). Cactus
## ist der erste tatsächliche Foraging-Interaktionspunkt im Spiel.

func _get_entity_type_id() -> String:
	return "cactus"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id            = "harvest_cactus"
	d.label         = "Kaktus ernten"
	d.duration      = 2.5
	d.xp_type       = "foraging"
	d.xp_amount     = 15
	d.loot_table    = preload("res://data/loot_tables/loot_cactus.tres")
	d.yield_stat_id = "gathering_yield_foraging"
	d.inspect_text  = "Ein stacheliger Wüstenkaktus. Die fasrige Innenseite lässt sich zu robusten Fäden verarbeiten."
	return d

func _build_visuals() -> void:
	# Factory3D.create_cactus() liefert das gecachte Prefab (MeshCache "cactus") —
	# gleiches Muster wie OakTree._build_visuals(). Placeholder-Zylinder nur als
	# Fallback, falls Factory3D ausnahmsweise nicht verfügbar ist.
	var factory: Factory3D = _ctx.get_factory3d() if is_instance_valid(_ctx) else null
	if is_instance_valid(factory):
		factory.create_cactus(self)
	else:
		AppLogger.log_warn("Factory3D nicht verfügbar — Cactus Placeholder-Visual.", "cactus")
		_add_placeholder_cylinder(0.18, 1.6, Color(0.20, 0.45, 0.22))
