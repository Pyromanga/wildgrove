class_name PlantCatalog
extends RefCounted

## PlantCatalog — die Kräuter (Skill "herbalism") und Blumen (Skill "gardening") des Hains.
##
## EINE Tabelle für alles Pflanzliche: Anzeigenamen, Latein, Skill, Ernte-/Samen-Item, XP, Wachstum,
## Preis, "Wusstest du?"-Fakt und Aussehen. WildPlant (wilde Weltobjekte), FarmCropDefinition
## (Felder im Dorf), ShopService (Samen) und die Tests lesen alle hier — nur die .tres-Dateien
## (Items, LootTables, Crops) stehen separat in data/ und werden von test_plants_content.gd gegen
## diese Tabelle geprüft. Neue Pflanze: Eintrag hier + Daten (docs/herbalism-and-gardening.md).
##
## FAKTEN: ein Satz, überprüfbar, Regeln aus docs/skill-writing-guide.md Abschnitt 2-3. Kein
## Gesundheitsrat — die Fakten erklären, woher Dinge kommen, nicht, was man einnehmen soll.
## Der Beleg-Stand je Pflanze steht in docs/skill-writing-guide.md (Abschnitt 4).
##
## "wild": true = spawnt als Weltobjekt (Entity-Typ "plant_<id>"), siehe BiomeRegistry.
## "wild": false = Kulturpflanze, gibt es nur als Samen aus dem Shop und auf Feldern.

const SKILL_HERBALISM: String = "herbalism"
const SKILL_GARDENING: String = "gardening"
const ENTITY_PREFIX: String = "plant_"

const PLANTS: Dictionary = {
	"chamomile": {
		"name": "Kamille", "latin": "Matricaria chamomilla", "skill": "herbalism", "wild": true,
		"harvest_item": "chamomile_flowers", "seed_item": "chamomile_seed",
		"xp": 14, "field_xp": 10, "growth": 60.0, "shop_price": 4,
		"fact": "Kamillenöl ist tiefblau – doch in der frischen Blüte steckt der blaue Farbstoff noch nicht: Chamazulen entsteht erst beim Destillieren mit Wasserdampf.",
		"look": {"style": "daisy", "height": 0.38, "color": Color(0.96, 0.96, 0.94), "center": Color(0.95, 0.80, 0.15)},
	},
	"yarrow": {
		"name": "Schafgarbe", "latin": "Achillea millefolium", "skill": "herbalism", "wild": true,
		"harvest_item": "yarrow_herb", "seed_item": "yarrow_seed",
		"xp": 14, "field_xp": 10, "growth": 70.0, "shop_price": 4,
		"fact": "Der Gattungsname Achillea erinnert an Achilles, der in der Sage Wunden mit dieser Pflanze versorgt haben soll.",
		"look": {"style": "umbel", "height": 0.60, "color": Color(0.95, 0.93, 0.88), "center": Color(0.90, 0.85, 0.60)},
	},
	"nettle": {
		"name": "Brennnessel", "latin": "Urtica dioica", "skill": "herbalism", "wild": true,
		"harvest_item": "nettle_fiber", "seed_item": "nettle_seed",
		"xp": 14, "field_xp": 10, "growth": 60.0, "shop_price": 4,
		"fact": "Aus Nesselfasern lässt sich Stoff weben – im Ersten Weltkrieg wich Deutschland darauf aus, weil Baumwolle fehlte.",
		"look": {"style": "nettle", "height": 0.70, "color": Color(0.16, 0.38, 0.12), "center": Color(0.30, 0.50, 0.20)},
	},
	"dandelion": {
		"name": "Löwenzahn", "latin": "Taraxacum officinale", "skill": "herbalism", "wild": true,
		"harvest_item": "dandelion_root", "seed_item": "dandelion_seed",
		"xp": 12, "field_xp": 8, "growth": 45.0, "shop_price": 3,
		"fact": "Der Milchsaft des Russischen Löwenzahns enthält Naturkautschuk – Forschende prüfen ihn als Quelle für Reifengummi.",
		"look": {"style": "rosette", "height": 0.18, "color": Color(0.98, 0.85, 0.10), "center": Color(0.95, 0.75, 0.05)},
	},
	"thyme": {
		"name": "Thymian", "latin": "Thymus vulgaris", "skill": "herbalism", "wild": true,
		"harvest_item": "thyme_sprigs", "seed_item": "thyme_seed",
		"xp": 16, "field_xp": 12, "growth": 80.0, "shop_price": 5,
		"fact": "Thymian enthält Thymol, einen Duftstoff, der Keime hemmt – er steckt in manchen Mundspülungen.",
		"look": {"style": "cushion", "height": 0.20, "color": Color(0.22, 0.38, 0.20), "center": Color(0.82, 0.55, 0.75)},
	},
	"meadowsweet": {
		"name": "Mädesüß", "latin": "Filipendula ulmaria", "skill": "herbalism", "wild": true,
		"harvest_item": "meadowsweet_blossoms", "seed_item": "meadowsweet_seed",
		"xp": 18, "field_xp": 12, "growth": 90.0, "shop_price": 6,
		"fact": "Der Name Aspirin geht auf das Mädesüß zurück: A für Acetyl, spir für sein früheres Gattungswort Spiraea.",
		"look": {"style": "umbel", "height": 0.80, "color": Color(0.97, 0.95, 0.85), "center": Color(0.90, 0.88, 0.70)},
	},
	"poppy": {
		"name": "Klatschmohn", "latin": "Papaver rhoeas", "skill": "gardening", "wild": true,
		"harvest_item": "poppy_petals", "seed_item": "poppy_seed",
		"xp": 12, "field_xp": 8, "growth": 60.0, "shop_price": 5,
		"fact": "Mohnsamen können jahrzehntelang im Boden schlummern und keimen, sobald die Erde aufgewühlt wird (Samenbank).",
		"look": {"style": "cup", "height": 0.45, "color": Color(0.85, 0.12, 0.10), "center": Color(0.10, 0.08, 0.08)},
	},
	"cornflower": {
		"name": "Kornblume", "latin": "Centaurea cyanus", "skill": "gardening", "wild": true,
		"harvest_item": "cornflower_blossoms", "seed_item": "cornflower_seed",
		"xp": 12, "field_xp": 8, "growth": 60.0, "shop_price": 5,
		"fact": "Die Kornblume wuchs als Ackerwildkraut zwischen dem Getreide – mit moderner Landwirtschaft ist sie vielerorts selten geworden.",
		"look": {"style": "daisy", "height": 0.50, "color": Color(0.27, 0.38, 0.85), "center": Color(0.15, 0.12, 0.40)},
	},
	"calendula": {
		"name": "Ringelblume", "latin": "Calendula officinalis", "skill": "gardening", "wild": true,
		"harvest_item": "calendula_blossoms", "seed_item": "calendula_seed",
		"xp": 14, "field_xp": 10, "growth": 70.0, "shop_price": 5,
		"fact": "Ringelblumenblüten sind essbar und färbten früher Speisen gelb – man nannte sie auch Safran des armen Mannes.",
		"look": {"style": "daisy", "height": 0.35, "color": Color(0.98, 0.60, 0.10), "center": Color(0.60, 0.30, 0.05)},
	},
	"lavender": {
		"name": "Lavendel", "latin": "Lavandula angustifolia", "skill": "gardening", "wild": true,
		"harvest_item": "lavender_sprigs", "seed_item": "lavender_seed",
		"xp": 16, "field_xp": 12, "growth": 90.0, "shop_price": 6,
		"fact": "Lavendel gehört zu den Lippenblütlern, wie Thymian und Salbei – viele von ihnen duften durch ätherische Öle.",
		"look": {"style": "spike", "height": 0.45, "color": Color(0.55, 0.40, 0.80), "center": Color(0.40, 0.30, 0.60)},
	},
	"sunflower": {
		"name": "Sonnenblume", "latin": "Helianthus annuus", "skill": "gardening", "wild": false,
		"harvest_item": "sunflower_head", "seed_item": "sunflower_seed",
		"xp": 0, "field_xp": 14, "growth": 120.0, "shop_price": 5,
		"fact": "Nur junge Sonnenblumen folgen tagsüber der Sonne von Ost nach West – erwachsene Blüten schauen dauerhaft nach Osten (Heliotropismus).",
		"look": {"style": "daisy", "height": 0.90, "color": Color(0.98, 0.80, 0.10), "center": Color(0.35, 0.22, 0.08)},
	},
	"tulip": {
		"name": "Tulpe", "latin": "Tulipa", "skill": "gardening", "wild": false,
		"harvest_item": "tulip_blossoms", "seed_item": "tulip_bulb",
		"xp": 0, "field_xp": 16, "growth": 100.0, "shop_price": 8,
		"fact": "Im Winter 1636/37 schossen in den Niederlanden die Preise für Tulpenzwiebeln hoch – wie groß die Blase war, ist unter Historikern umstritten (Tulpenmanie).",
		"look": {"style": "cup", "height": 0.40, "color": Color(0.90, 0.20, 0.40), "center": Color(0.20, 0.10, 0.10)},
	},
}

static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in PLANTS.keys():
		out.append(id)
	return out

static func wild_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in PLANTS.keys():
		if bool(PLANTS[id]["wild"]):
			out.append(id)
	return out

static func get_plant(plant_id: String) -> Dictionary:
	return PLANTS.get(plant_id, {})

static func entity_type(plant_id: String) -> String:
	return ENTITY_PREFIX + plant_id

static func wild_loot_path(plant_id: String) -> String:
	return "res://data/loot_tables/loot_plant_%s.tres" % plant_id

static func field_loot_id(plant_id: String) -> String:
	return "loot_%s_field" % plant_id

## "Kamille (Matricaria chamomilla). Wusstest du? …" — Untersuchen-Text und Wiki-Basis.
static func inspect_text(plant_id: String) -> String:
	var p: Dictionary = get_plant(plant_id)
	if p.is_empty():
		return ""
	return "%s (%s). Wusstest du? %s" % [p["name"], p["latin"], p["fact"]]
