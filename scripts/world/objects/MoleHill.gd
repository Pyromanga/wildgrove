extends HarvestableEntity
class_name MoleHill

## MoleHill — Maulwurfshügel (Skill "digging" / Graben, bestehender Skill).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Echte Welt: Der Hügel ist der Aushub der unterirdischen Gänge und dient zugleich der
## Belüftung des Baus (NABU). Die feinkrümelige Erde gilt Gärtnern als gute Anzuchterde.
## Maulwürfe sind in Deutschland besonders geschützt — im Spiel wird nur Erde vom Hügel
## genommen. Spawnt auf Wiese und im Wald (BiomeRegistry). Respawn: siehe
## WorldService.configure().
##
## Der Bildungstext lebt in data/skills/digging.tres (Erdschichten) + docs/nests.md.

func _get_entity_type_id() -> String:
	return "mole_hill"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "harvest_mole_hill"
	d.label        = "Maulwurferde sammeln"
	d.duration     = 2.0
	d.xp_type      = "digging"
	d.xp_amount    = 15
	d.loot_table   = preload("res://data/loot_tables/loot_mole_hill.tres")
	d.inspect_text = "Ein frischer Maulwurfshügel, die Erde noch locker. Wusstest du? Er ist der Aushub der Gänge darunter und sorgt zugleich für frische Luft im Bau."
	return d

func _build_visuals() -> void:
	# Niedriger, weicher Erdhaufen — Placeholder.
	_add_placeholder_cone(0.4, 0.1, 0.28, Color(0.30, 0.20, 0.12), "dirt")
	AppLogger.log_debug("MoleHill Placeholder-Kegel erstellt.", "mole_hill")
