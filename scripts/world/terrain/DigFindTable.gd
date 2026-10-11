class_name DigFindTable
extends RefCounted

## DigFindTable — was man beim Graben findet, wie oft und ab welcher Tiefe.
##
## Reine Daten + Würfeln (kein Node, kein Service). Ein "Fund" ist ein sichtbares Erzstück
## oder ein Edelstein, der nach einem Spatenstich am Grubenboden freiliegt (Ansicht: DigFind,
## Wahrheit: DigFindRegistry) und per Interaktion geborgen wird.
##
## Ablauf: nach jedem erfolgreichen Graben würfelt WorldDigHandler.after_dig() erst, OB es
## einen Fund gibt (find_chance(): "hin und wieder", tiefer = etwas häufiger), dann WAS
## (roll_kind(): gewichtete Auswahl unter allen Funden, deren min_depth erreicht ist).
## Tiefe = wie weit der Boden an dieser Stelle unter das ursprüngliche Gelände gegraben ist.
## Seltenes liegt tief: Kupfer ab der ersten Schaufel, Diamanten erst ab ~24 m.
##
## NEUER FUND = ein Eintrag in KINDS + ein ItemDefinition-.tres (DataManifest.ITEMS). Kein
## weiterer Code nötig.

const DEFAULT_KIND: String = "copper_ore"

## Grundchance pro Spatenstich in der Tiefe 0 und Zuwachs pro Meter, nach oben gedeckelt.
const CHANCE_BASE: float = 0.06
const CHANCE_PER_METER: float = 0.006
const CHANCE_MAX: float = 0.24

## kind → Definition
##   item      ItemDefinition.id, das beim Bergen ins Inventar kommt
##   label     Anzeigename (Meldung, Interaktions-Text)
##   gem       true = Edelstein (Kristall-Optik), false = Erz (Gesteinsbrocken mit Adern)
##   min_depth ab dieser Grabtiefe (m) kann der Fund auftauchen
##   weight    relative Häufigkeit unter den bereits möglichen Funden
##   qty_min/qty_max  Stückzahl beim Bergen
##   xp        Bergbau-XP (Skill "mining")
##   color     Farbe des Erzes / Edelsteins
##   hint      Bildungstext beim Untersuchen
const KINDS: Dictionary = {
	"copper_ore": {
		"item": "copper_ore", "label": "Kupfererz", "gem": false,
		"min_depth": 0.0, "weight": 50.0, "qty_min": 1, "qty_max": 3, "xp": 15,
		"color": Color(0.78, 0.46, 0.22),
		"hint": "Kupfererz mit grünlichem Anflug. Kupfer war das erste Metall, das Menschen gezielt aus Erz gewonnen haben.",
	},
	"iron_ore": {
		"item": "iron_ore", "label": "Eisenerz", "gem": false,
		"min_depth": 2.0, "weight": 40.0, "qty_min": 1, "qty_max": 2, "xp": 20,
		"color": Color(0.56, 0.30, 0.24),
		"hint": "Rostrot schimmerndes Eisenerz. Die rote Farbe kommt vom Eisenoxid - dasselbe, das Rost so rot macht.",
	},
	"gem_amethyst": {
		"item": "gem_amethyst", "label": "Amethyst", "gem": true,
		"min_depth": 6.0, "weight": 8.0, "qty_min": 1, "qty_max": 1, "xp": 45,
		"color": Color(0.62, 0.36, 0.86),
		"hint": "Ein violetter Quarz. Sein Purpur stammt von winzigen Eisenspuren im Kristall.",
	},
	"silver_ore": {
		"item": "silver_ore", "label": "Silbererz", "gem": false,
		"min_depth": 8.0, "weight": 18.0, "qty_min": 1, "qty_max": 2, "xp": 35,
		"color": Color(0.80, 0.82, 0.86),
		"hint": "Silbererz, hell und metallisch. Silber leitet Strom und Wärme besser als jedes andere Metall.",
	},
	"gem_emerald": {
		"item": "gem_emerald", "label": "Smaragd", "gem": true,
		"min_depth": 10.0, "weight": 6.0, "qty_min": 1, "qty_max": 1, "xp": 55,
		"color": Color(0.14, 0.76, 0.42),
		"hint": "Ein grüner Beryll. Fast jeder Smaragd hat feine Einschlüsse - sie gelten als Echtheitsmerkmal.",
	},
	"gold_ore": {
		"item": "gold_ore", "label": "Golderz", "gem": false,
		"min_depth": 14.0, "weight": 9.0, "qty_min": 1, "qty_max": 2, "xp": 50,
		"color": Color(0.96, 0.78, 0.20),
		"hint": "Golderz. Gold rostet nicht und läuft nicht an - deshalb glänzt es noch nach Jahrtausenden.",
	},
	"gem_sapphire": {
		"item": "gem_sapphire", "label": "Saphir", "gem": true,
		"min_depth": 14.0, "weight": 5.0, "qty_min": 1, "qty_max": 1, "xp": 65,
		"color": Color(0.20, 0.36, 0.92),
		"hint": "Ein blauer Korund. Rubin und Saphir sind derselbe Stein, nur mit anderen Spuren im Kristall.",
	},
	"gem_ruby": {
		"item": "gem_ruby", "label": "Rubin", "gem": true,
		"min_depth": 18.0, "weight": 3.0, "qty_min": 1, "qty_max": 1, "xp": 80,
		"color": Color(0.86, 0.10, 0.16),
		"hint": "Ein roter Korund. Nach dem Diamanten gehört er zu den härtesten Edelsteinen.",
	},
	"gem_diamond": {
		"item": "gem_diamond", "label": "Diamant", "gem": true,
		"min_depth": 24.0, "weight": 1.5, "qty_min": 1, "qty_max": 1, "xp": 120,
		"color": Color(0.86, 0.95, 1.0),
		"hint": "Ein Diamant, das härteste natürliche Material. Er entsteht aus reinem Kohlenstoff unter enormem Druck tief in der Erde.",
	},
}

static func get_def(kind: String) -> Dictionary:
	return KINDS.get(kind, KINDS[DEFAULT_KIND]) as Dictionary

static func is_known(kind: String) -> bool:
	return KINDS.has(kind)

static func get_label(kind: String) -> String:
	return String(get_def(kind)["label"])

## Chance auf einen Fund pro erfolgreichem Grabvorgang bei `depth` Metern Grabtiefe.
static func find_chance(depth: float) -> float:
	return clampf(CHANCE_BASE + CHANCE_PER_METER * maxf(depth, 0.0), CHANCE_BASE, CHANCE_MAX)

## Alle Funde, die bei `depth` möglich sind.
static func kinds_at_depth(depth: float) -> Array[String]:
	var out: Array[String] = []
	for kind: String in KINDS.keys():
		if depth >= float((KINDS[kind] as Dictionary)["min_depth"]):
			out.append(kind)
	return out

## Gewichtete Auswahl unter den bei `depth` möglichen Funden.
static func roll_kind(depth: float, rng: RandomNumberGenerator) -> String:
	var options: Array[String] = kinds_at_depth(depth)
	var total: float = 0.0
	for kind in options:
		total += float((KINDS[kind] as Dictionary)["weight"])
	if total <= 0.0:
		return DEFAULT_KIND
	var pick: float = rng.randf() * total
	for kind in options:
		pick -= float((KINDS[kind] as Dictionary)["weight"])
		if pick <= 0.0:
			return kind
	return options[options.size() - 1]

## Würfelt einen kompletten Grabvorgang: "" = kein Fund, sonst die Art des Fundes.
static func roll(depth: float, rng: RandomNumberGenerator) -> String:
	if rng.randf() >= find_chance(depth):
		return ""
	return roll_kind(depth, rng)

## Drop-Tabelle zum Bergen eines Fundes (immer genau das eine Item).
static func build_loot(kind: String) -> LootTable:
	var def: Dictionary = get_def(kind)
	var entry := LootEntry.new()
	entry.item_id = String(def["item"])
	entry.weight = 100.0
	entry.quantity_min = int(def["qty_min"])
	entry.quantity_max = int(def["qty_max"])
	var table := LootTable.new()
	table.max_rolls = 1
	table.entries.append(entry)
	return table

## InteractableData zum Bergen — dieselbe Form wie bei Erzblöcken (Bergbau-XP, Pickel-Tempo).
static func build_interactable(kind: String) -> InteractableData:
	var def: Dictionary = get_def(kind)
	var d := InteractableData.new()
	d.id = "collect_find"
	d.label = "%s bergen" % String(def["label"])
	d.duration = 2.4 if bool(def["gem"]) else 1.8
	d.xp_type = "mining"
	d.xp_amount = int(def["xp"])
	d.speed_stat_id = "gathering_speed_ore"
	d.loot_table = build_loot(kind)
	d.inspect_text = String(def["hint"])
	return d
