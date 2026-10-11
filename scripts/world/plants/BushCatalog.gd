class_name BushCatalog
extends RefCounted

## BushCatalog — die vier wild wachsenden Sträucher: Brombeere, Haselnuss, Holunder, Heckenrose.
##
## Wunsch (2026-10-08): "Büsche auch abbauen können — vielleicht eine Mischung aus Sammeln und
## Holzfällerei". Jeder Strauch (WildBush) bietet ZWEI Aktionen:
##   • PFLÜCKEN  — Früchte/Nüsse, kurz, ohne Werkzeug, XP "foraging"
##   • RODEN     — Reisig bzw. Haselruten, länger, Axt-Tempobonus (gathering_speed_wood), XP "woodcutting"
## Beide verbrauchen den Strauch (wie Farn/Pilz: Despawn + Nachwachsen über den RespawnService).
## Ein Strauch, der nach dem Pflücken stehen bleibt und nur die Früchte nachwachsen lässt, bräuchte
## ein Netzwerk-Event für den Zustand (siehe docs/herbalism-and-gardening.md, Abschnitt Büsche).
##
## Fakten: ein Satz, kein Gesundheitsrat (docs/skill-writing-guide.md Abschnitte 2-3).
## Beleg-Stand je Strauch: docs/herbalism-and-gardening.md.

const ENTITY_PREFIX: String = "bush_"
const SKILL_PICK: String = "foraging"
const SKILL_CHOP: String = "woodcutting"
## Sträucher wachsen langsamer nach als Kräuter, schneller als Bäume.
const RESPAWN_SEC: float = 480.0

const BUSHES: Dictionary = {
	"blackberry": {
		"name": "Brombeerstrauch", "latin": "Rubus fruticosus agg.",
		"pick_item": "blackberries", "chop_item": "brushwood",
		"pick_xp": 12, "chop_xp": 14,
		"fact": "Brombeeren sind botanisch keine Beeren, sondern Sammelsteinfrüchte aus vielen kleinen Steinfrüchtchen.",
		"look": {"leaf": Color(0.14, 0.34, 0.10), "berry": Color(0.16, 0.05, 0.22), "height": 1.1, "width": 1.5, "rods": 0, "berries": 14, "berry_size": 0.045},
	},
	"hazel": {
		"name": "Haselnussstrauch", "latin": "Corylus avellana",
		"pick_item": "hazelnuts", "chop_item": "hazel_rods",
		"pick_xp": 12, "chop_xp": 18,
		"fact": "Haselruten sind so biegsam, dass man jahrhundertelang Flechtzäune und Körbe daraus gebaut hat.",
		"look": {"leaf": Color(0.26, 0.46, 0.13), "berry": Color(0.72, 0.55, 0.28), "height": 2.2, "width": 1.6, "rods": 7, "berries": 9, "berry_size": 0.05},
	},
	"elder": {
		"name": "Holunderstrauch", "latin": "Sambucus nigra",
		"pick_item": "elderberries", "chop_item": "brushwood",
		"pick_xp": 14, "chop_xp": 14,
		"fact": "Rohe Holunderbeeren sind leicht giftig – erst Erhitzen macht sie genießbar.",
		"look": {"leaf": Color(0.20, 0.42, 0.14), "berry": Color(0.12, 0.05, 0.18), "height": 2.4, "width": 1.9, "rods": 3, "berries": 16, "berry_size": 0.04},
	},
	"dogrose": {
		"name": "Heckenrose", "latin": "Rosa canina",
		"pick_item": "rosehips", "chop_item": "brushwood",
		"pick_xp": 14, "chop_xp": 14,
		"fact": "Die roten Hagebutten der Heckenrose enthalten deutlich mehr Vitamin C als Zitronen.",
		"look": {"leaf": Color(0.20, 0.40, 0.15), "berry": Color(0.86, 0.20, 0.10), "height": 1.5, "width": 1.7, "rods": 4, "berries": 12, "berry_size": 0.05},
	},
}

static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in BUSHES.keys():
		out.append(id)
	return out

static func get_bush(bush_id: String) -> Dictionary:
	return BUSHES.get(bush_id, {})

static func entity_type(bush_id: String) -> String:
	return ENTITY_PREFIX + bush_id

static func pick_loot_path(bush_id: String) -> String:
	return "res://data/loot_tables/loot_bush_%s_pick.tres" % bush_id

static func chop_loot_path(bush_id: String) -> String:
	return "res://data/loot_tables/loot_bush_%s_chop.tres" % bush_id

static func inspect_text(bush_id: String) -> String:
	var b: Dictionary = get_bush(bush_id)
	if b.is_empty():
		return ""
	return "%s (%s). Wusstest du? %s" % [b["name"], b["latin"], b["fact"]]
