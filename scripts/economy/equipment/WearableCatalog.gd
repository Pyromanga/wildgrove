class_name WearableCatalog
extends RefCounted

## WearableCatalog — erzeugt die Kleidungs-Items (WearableDefinition) aus dem Look-Katalog und
## übersetzt zwischen Item, Slot und Look.
##
## WARUM EIN KATALOG STATT .tres-DATEIEN: Kleidung ist Kombination aus Schnitt × Farbe
## (Oberteil: 4 Schnitte × 10 Farben, Hosen, Hüte, ...). Das wären >100 handgepflegte Dateien,
## die bei jeder neuen Farbe im Look-Katalog nachgezogen werden müssten. Stattdessen entstehen die
## Items hier aus CharacterLook.CATALOG — neue Farbe/Schnitt dort = neues Item, automatisch.
##
## ITEM-IDs: "cl_<slot>_<wert1>[_<wert2>]" mit den Look-Werten in Feld-Reihenfolge, z.B.
##   cl_shirt_wald_tshirt · cl_pants_navy_long · cl_shoes_brown · cl_hat_cap_green · cl_back_cape_green
##
## SLOTS: Kleidung hat eigene Slots (SLOT_ORDER), getrennt von den Rüstungs-Slots helmet/chest/
## legs/boots (ArmorDefinition). Rüstung wird ÜBER der Kleidung gezeichnet (siehe WornGearBuilder).
##
## Rein statisch + ein Item-Cache.

const ITEM_PREFIX := "cl_"

## Kleidungs-Slots in Panel-Reihenfolge (oben → unten).
const SLOT_ORDER: Array = ["hat", "glasses", "scarf", "shoulders", "back", "shirt", "belt", "pouch", "pants", "shoes"]

## slot -> { label, icon, fields (Look-Felder; das ERSTE ist das Hauptfeld: "none" = nichts getragen), price }
const SLOTS: Dictionary = {
	"hat":       {"label": "Kopfbedeckung",   "icon": "🎩", "fields": ["hat", "hat_color"],       "price": 6},
	"glasses":   {"label": "Brille",          "icon": "👓", "fields": ["glasses"],                 "price": 10},
	"scarf":     {"label": "Schal",           "icon": "🧣", "fields": ["scarf"],                   "price": 5},
	"shoulders": {"label": "Schulterplatten", "icon": "🛡", "fields": ["shoulders"],               "price": 40},
	"back":      {"label": "Rücken",          "icon": "🎒", "fields": ["back"],                    "price": 15},
	"shirt":     {"label": "Oberteil",        "icon": "👕", "fields": ["shirt", "shirt_style"],    "price": 8},
	"belt":      {"label": "Gürtel",          "icon": "🪢", "fields": ["belt"],                    "price": 5},
	"pouch":     {"label": "Beutel",          "icon": "👛", "fields": ["pouch"],                   "price": 6},
	"pants":     {"label": "Hose",            "icon": "👖", "fields": ["pants", "pants_style"],    "price": 8},
	"shoes":     {"label": "Schuhe",          "icon": "👞", "fields": ["shoes"],                   "price": 6},
}

## Rüstungs-Slot -> Look-Feld des Rüstungs-Spiegels.
const ARMOR_LOOK_KEYS: Dictionary = {
	"helmet": "armor_helmet",
	"chest":  "armor_chest",
	"legs":   "armor_legs",
	"boots":  "armor_boots",
}

## Hüte, die eine feste Farbe haben (hat_color wird beim Zeichnen ignoriert).
const FIXED_HAT_COLORS: Dictionary = {"hardhat": "yellow", "tophat": "black"}
## Hüte mit frei wählbarer Farbe.
const COLORED_HATS: Array = ["cap", "beanie", "straw", "wizard"]

static var _items: Dictionary = {}

# ─────────────────────────────────────────────
# Katalog
# ─────────────────────────────────────────────

## { item_id: WearableDefinition } — alle Kleidungs-Items (Cache, nur lesen!).
static func all_items() -> Dictionary:
	if _items.is_empty():
		_build_all()
	return _items

static func get_item(item_id: String) -> WearableDefinition:
	return all_items().get(item_id, null) as WearableDefinition

static func is_wearable_id(item_id: String) -> bool:
	return all_items().has(item_id)

## Trägt alle Kleidungs-Items in `target` ein ({ id: ItemDefinition }) — Aufruf durch DataService.
## Bereits vorhandene IDs werden nicht überschrieben (eine .tres hätte Vorrang).
static func register_into(target: Dictionary) -> void:
	var items := all_items()
	for id in items.keys():
		if not target.has(id):
			target[id] = items[id]

static func is_wear_slot(slot: String) -> bool:
	return SLOTS.has(slot)

static func slot_label(slot: String) -> String:
	return String((SLOTS.get(slot, {}) as Dictionary).get("label", slot))

static func slot_icon(slot: String) -> String:
	return String((SLOTS.get(slot, {}) as Dictionary).get("icon", "?"))

## Slot, in den `item` gehört: Kleidung → wear_slot, Rüstung → "helmet"/"chest"/..., sonst "".
static func slot_of_item(item: ItemDefinition) -> String:
	if item is WearableDefinition:
		return (item as WearableDefinition).wear_slot
	if item is ArmorDefinition:
		return (item as ArmorDefinition).get_slot_id()
	return ""

# ─────────────────────────────────────────────
# Look <-> Item
# ─────────────────────────────────────────────

## Item-ID, die `look` im Slot trägt ("" = nichts getragen). Hüte mit fester Farbe werden
## normalisiert (Zylinder ist immer schwarz, egal was hat_color sagt).
static func item_id_for_slot(slot: String, look: Dictionary) -> String:
	if not SLOTS.has(slot):
		return ""
	var fields: Array = (SLOTS[slot] as Dictionary)["fields"]
	var main: String = String(look.get(String(fields[0]), "none"))
	if main == "none" or main.is_empty():
		return ""
	var values: Array = []
	for f in fields:
		values.append(String(look.get(String(f), "")))
	if slot == "hat" and FIXED_HAT_COLORS.has(main):
		values[1] = String(FIXED_HAT_COLORS[main])
	var id := _make_id(slot, values)
	return id if all_items().has(id) else ""

## Alles, was `look` an Kleidung trägt: { slot: item_id } (nur getragene Slots).
static func worn_outfit(look: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for slot in SLOT_ORDER:
		var id := item_id_for_slot(String(slot), look)
		if not id.is_empty():
			out[slot] = id
	return out

## Look-Felder, die gesetzt werden müssen, um `item_id` im Slot zu tragen.
## item_id "" = Slot leeren (Hauptfeld "none"). Unbekannte ID / falscher Slot -> {} (= ungültig).
static func look_patch(slot: String, item_id: String) -> Dictionary:
	if not SLOTS.has(slot):
		return {}
	var fields: Array = (SLOTS[slot] as Dictionary)["fields"]
	if item_id.is_empty():
		return {String(fields[0]): "none"}
	var item := get_item(item_id)
	if item == null or item.wear_slot != slot:
		return {}
	return item.look_values.duplicate()

## Neuer Look, in dem `item_id` getragen wird (für NPCs: lokal, ohne Inventar). Ungültig -> unverändert.
static func wear_in_look(look: Dictionary, item_id: String) -> Dictionary:
	var item := get_item(item_id)
	var out := look.duplicate()
	if item == null:
		return out
	for key in item.look_values.keys():
		out[key] = item.look_values[key]
	return out

## Neuer Look ohne das Teil im Slot (nackt/leer).
static func take_off_in_look(look: Dictionary, slot: String) -> Dictionary:
	var out := look.duplicate()
	var patch := look_patch(slot, "")
	for key in patch.keys():
		out[key] = patch[key]
	return out

## Look-Feld des Rüstungs-Spiegels für einen Rüstungs-Slot ("" wenn kein Rüstungs-Slot).
static func armor_look_key(armor_slot: String) -> String:
	return String(ARMOR_LOOK_KEYS.get(armor_slot, ""))

## Rüstungs-Slot, dessen Look-Katalog diese ArmorDefinition-ID kennt ("" wenn keine Rüstung).
static func armor_slot_of_id(item_id: String) -> String:
	if item_id.is_empty() or item_id == "none":
		return ""
	for slot in ARMOR_LOOK_KEYS.keys():
		if CharacterLook.option_ids(String(ARMOR_LOOK_KEYS[slot])).has(item_id):
			return String(slot)
	return ""

## Alles Getragene eines Looks — Kleidung UND Rüstung: { slot: item_id }.
static func full_outfit(look: Dictionary) -> Dictionary:
	var out := worn_outfit(look)
	for slot in ARMOR_LOOK_KEYS.keys():
		var id := String(look.get(String(ARMOR_LOOK_KEYS[slot]), "none"))
		if id != "none" and not id.is_empty():
			out[slot] = id
	return out

# ─────────────────────────────────────────────
# Intern: Erzeugung
# ─────────────────────────────────────────────

static func _build_all() -> void:
	_items = {}
	for slot in SLOT_ORDER:
		var fields: Array = (SLOTS[slot] as Dictionary)["fields"]
		for combo in _combos(String(slot), fields):
			var values: Array = []
			for f in fields:
				values.append(String((combo as Dictionary)[f]))
			var item := WearableDefinition.new()
			item.id = _make_id(String(slot), values)
			item.wear_slot = String(slot)
			item.look_values = (combo as Dictionary).duplicate()
			item.display_name = _display_name(String(slot), combo as Dictionary)
			item.max_stack = 99
			item.sell_price = int((SLOTS[slot] as Dictionary)["price"])
			_items[item.id] = item

static func _combos(slot: String, fields: Array) -> Array:
	var out: Array = []
	match slot:
		"hat":
			for style in COLORED_HATS:
				for color in CharacterLook.option_ids("hat_color"):
					out.append({"hat": style, "hat_color": color})
			for style in FIXED_HAT_COLORS.keys():
				out.append({"hat": style, "hat_color": FIXED_HAT_COLORS[style]})
		"shirt":
			for style in CharacterLook.option_ids("shirt_style"):
				for color in CharacterLook.option_ids("shirt"):
					if color != "none":
						out.append({"shirt": color, "shirt_style": style})
		"pants":
			for style in CharacterLook.option_ids("pants_style"):
				for color in CharacterLook.option_ids("pants"):
					if color != "none":
						out.append({"pants": color, "pants_style": style})
		_:
			var field := String(fields[0])
			for id in CharacterLook.option_ids(field):
				if id != "none":
					out.append({field: id})
	return out

static func _make_id(slot: String, values: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for v in values:
		parts.append(String(v))
	return "%s%s_%s" % [ITEM_PREFIX, slot, "_".join(parts)]

static func _display_name(slot: String, combo: Dictionary) -> String:
	match slot:
		"hat":
			var style := String(combo["hat"])
			var hat_label := CharacterLook.label_of("hat", style)
			if FIXED_HAT_COLORS.has(style):
				return hat_label
			return "%s (%s)" % [hat_label, CharacterLook.label_of("hat_color", String(combo["hat_color"]))]
		"shirt":
			return "Oberteil (%s, %s)" % [
				CharacterLook.label_of("shirt_style", String(combo["shirt_style"])),
				CharacterLook.label_of("shirt", String(combo["shirt"])),
			]
		"pants":
			return "Hose (%s, %s)" % [
				CharacterLook.label_of("pants_style", String(combo["pants_style"])),
				CharacterLook.label_of("pants", String(combo["pants"])),
			]
		"glasses":
			return "Brille (%s)" % CharacterLook.label_of("glasses", String(combo["glasses"]))
		"scarf":
			return "Schal (%s)" % CharacterLook.label_of("scarf", String(combo["scarf"]))
		"belt":
			return "Gürtel (%s)" % CharacterLook.label_of("belt", String(combo["belt"]))
		"shoes":
			return "Schuhe (%s)" % CharacterLook.label_of("shoes", String(combo["shoes"]))
		_:
			# back / pouch / shoulders: das Look-Label ist schon beschreibend ("Rucksack", "Umhang (Grün)").
			var field := String((SLOTS[slot] as Dictionary)["fields"][0])
			return CharacterLook.label_of(field, String(combo[field]))
