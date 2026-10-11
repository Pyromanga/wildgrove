class_name GroundVillageKind
extends VillageKind

## GroundVillageKind — das klassische Dorf auf dem Boden (Straßendorf mit Marktplatz, Höfen, Kapelle …).
## Reiner Adapter: Planung = VillageLayout, Rezepte = BuildingRecipes (dort liegt der Boden-Katalog).
## Rückfall-Art: wird gewählt, wenn keine Sonderart passt.

func id() -> String:
	return VillageKinds.KIND_GROUND

func icon() -> String:
	return "house"

func tier_radius(tier: String) -> float:
	return float(SettlementSites.TIER_RADIUS.get(tier, 58.0))

func tier_label(tier: String) -> String:
	return String(SettlementSites.TIER_LABEL.get(tier, ""))

func site_score(field: TerrainField, p: Vector2, radius: float) -> float:
	return SettlementSites.score_site(
		field, p, radius, SettlementSites.ALLOWED_BIOMES,
		SettlementSites.MIN_ALLOWED_FRACTION, SettlementSites.MAX_SITE_SPREAD)

func plan(field: TerrainField, site: Dictionary, incoming: Array) -> Dictionary:
	return VillageLayout.plan(field, site, incoming)

func catalog() -> Dictionary:
	return BuildingRecipes.CATALOG

func build_type(type_id: String, b: PartBatch, variant: int, slab_depth: float, info: Dictionary) -> void:
	BuildingRecipes.build(type_id, b, variant, slab_depth, info)
