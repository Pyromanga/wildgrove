class_name CanopyVillageKind
extends VillageKind

## CanopyVillageKind — BAUMDORF: Wohnhütten auf Plattformen in gigantischen Bäumen (35–45 m), verbunden
## durch eine Rampe um den Stamm und Hängebrücken zwischen den Bäumen.
##
## Wächst in drei Stufen (je Dorfstufe, siehe CanopyLayout):
##   Weiler (Baumweiler) : 1 Baum, 2 Plattformen, 4 Hütten — der kleine Anfang.
##   Dorf   (Baumdorf)   : 3 Bäume, 2 Hängebrücken, Altbaum mit 3. Ebene + Versammlungshalle.
##   Stadt  (Baumstadt)  : 5 Bäume, Altbaum mit 4 Ebenen.
## Ausbauen heißt: Konstanten in CanopyLayout/CanopyTree ändern oder Stufen ergänzen (siehe docs/settlements.md).
##
## Gebäudetypen: der Altbaum (`canopy_elder`, Dorfmitte) und die Dorfbäume (`canopy_grove`). Ein Baum IST ein
## Gebäude (ein Mesh + ein Körper wie alle anderen); Rampe, Plattformen, Hütten, Brückenhälften gehören dazu.

const T_ELDER := "canopy_elder"
const T_GROVE := "canopy_grove"

const FOREST_BIOMES: Array[String] = ["forest", "dense_forest"]
const MIN_FOREST_FRACTION: float = 0.7
const MAX_SITE_SPREAD: float = 3.0
## Anteil der Standorte, auf denen zuerst ein Baumdorf versucht wird (nur im Wald; sonst Bodendorf).
const CHANCE: float = 0.3

const TIER_RADIUS: Dictionary = {TIER_HAMLET: 34.0, TIER_VILLAGE: 56.0, TIER_TOWN: 78.0}
const TIER_LABEL: Dictionary = {TIER_HAMLET: "Baumweiler", TIER_VILLAGE: "Baumdorf", TIER_TOWN: "Baumstadt"}
const SUFFIXES: Array[String] = ["wipfel", "krone", "horst", "hain", "laub", "ast", "himmel", "kamm"]

const _NPC_SETTLER := "settler_npc"
const _NPC_WATER := "water_carrier_npc"

## Grundstück 25 × 25 m (Rampe bis r ≈ 12.1 m). Keine Bodenplatte (kein `slab`): der Stamm wächst aus dem Boden.
const CATALOG: Dictionary = {
	T_ELDER: {
		"half": Vector2(12.5, 12.5), "max_spread": 3.0,
		"npcs": [[_NPC_SETTLER, Vector2(7.0, -2.0)], [_NPC_WATER, Vector2(-7.0, 2.5)], [_NPC_SETTLER, Vector2(2.0, 7.5)]],
	},
	T_GROVE: {
		"half": Vector2(12.5, 12.5), "max_spread": 2.6,
		"npcs": [[_NPC_SETTLER, Vector2(7.0, 0.5)]],
	},
}

func id() -> String:
	return VillageKinds.KIND_CANOPY

func chance() -> float:
	return CHANCE

func icon() -> String:
	return "tree"

func tier_radius(tier: String) -> float:
	return float(TIER_RADIUS.get(tier, 56.0))

func tier_label(tier: String) -> String:
	return String(TIER_LABEL.get(tier, ""))

func name_suffixes() -> Array[String]:
	return SUFFIXES

func site_score(field: TerrainField, p: Vector2, radius: float) -> float:
	var score: float = SettlementSites.score_site(field, p, radius, FOREST_BIOMES, MIN_FOREST_FRACTION, MAX_SITE_SPREAD)
	if score < 0.0:
		return -1.0
	# Der Altbaum muss in der Dorfmitte wirklich stehen können (Spreizung unter dem Grundstück).
	if VillageLayout.make_building(field, T_ELDER, p, 0.0, 0, "", 0, 0).is_empty():
		return -1.0
	return score

func plan(field: TerrainField, site: Dictionary, incoming: Array) -> Dictionary:
	return CanopyLayout.plan(field, site, incoming)

func catalog() -> Dictionary:
	return CATALOG

func build_type(type_id: String, b: PartBatch, variant: int, slab_depth: float, info: Dictionary) -> void:
	CanopyTree.build(b, "elder" if type_id == T_ELDER else "grove", variant, slab_depth, info)
