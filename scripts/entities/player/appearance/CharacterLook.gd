class_name CharacterLook
extends RefCounted

## CharacterLook — Datenmodell + Katalog für das Aussehen eines Spielers.
##
## Ein "Look" ist ein flaches Dictionary  { feld: option_id }  — ausschließlich
## Strings. Das ist Absicht:
##   - speicherbar (SaveSystem) und über RPC sendbar ohne Sonderbehandlung,
##   - stabil gegen Katalog-Umbau: gespeichert wird die ID, nicht der Index.
##     Eine Option darf umsortiert oder eingefügt werden, ohne alte Spielstände
##     zu verändern.
##   - nie vertrauenswürdig: alles, was von außen kommt (Save, Netzwerk), läuft
##     durch `sanitize()`. Unbekannte Felder/IDs fallen auf Defaults zurück, es
##     gibt keinen Weg, rohe Farben oder Zahlen ins Rendering zu schmuggeln.
##
## Neue Option = ein Eintrag in CATALOG (+ ggf. Bauanleitung in
## CharacterPartBuilder). Neues Feld = Eintrag in FIELDS + CATALOG + DEFAULTS.
## Der Editor (AppearancePanelVisuals) liest editor_fields() und zeigt neue
## Körper-Felder automatisch an.
##
## KÖRPER vs. GETRAGENES: Felder mit `"worn": true` (Oberteil, Hose, Schuhe, Hut, Brille,
## Gürtel, Schal, Rücken, Beutel, Schulterplatten und die vier Rüstungs-Spiegel armor_*) sind
## KEINE Editor-Auswahl, sondern der aktuell GETRAGENE Zustand — echte, an- und ablegbare Items
## (siehe WearableCatalog / WearableDefinition). Der Look ist nur der repliz. Speicher dafür:
## Spieler-Clients können sie nicht setzen (sanitize_body()), die Autorität schreibt sie, wenn
## Items an- oder abgelegt werden (EquipmentService → CharacterCreationService.set_worn()).
## "none" bei Oberteil/Hose/Schuhe = nackt (Unterwäsche bzw. blanke Füße).
##
## Reine Daten + statische Helfer — kein Node, kein Zustand.

## Reihenfolge = Reihenfolge im Editor. `group` ist nur Überschrift.
const FIELDS: Array = [
	{"key": "sex",         "label": "Geschlecht",     "group": "Körper"},
	{"key": "skin",        "label": "Hautton",        "group": "Körper"},
	{"key": "build",       "label": "Statur",         "group": "Körper"},
	{"key": "height",      "label": "Größe",          "group": "Körper"},
	{"key": "hair_style",  "label": "Frisur",         "group": "Haare"},
	{"key": "hair_color",  "label": "Haarfarbe",      "group": "Haare"},
	{"key": "beard",       "label": "Bart",           "group": "Haare"},
	{"key": "eyes",        "label": "Augen",          "group": "Gesicht"},
	{"key": "eye_color",   "label": "Augenfarbe",     "group": "Gesicht"},
	{"key": "brows",       "label": "Brauen",         "group": "Gesicht"},
	{"key": "nose",        "label": "Nase",           "group": "Gesicht"},
	{"key": "mouth",       "label": "Mund",           "group": "Gesicht"},
	{"key": "ears",        "label": "Ohren",          "group": "Gesicht"},
	{"key": "face_detail", "label": "Gesichtsdetail", "group": "Gesicht"},
	# ── Getragenes (worn): echte Items, kein Editor-Feld ──
	{"key": "glasses",      "label": "Brille",         "group": "Kleidung", "worn": true},
	{"key": "hat",          "label": "Kopfbedeckung",  "group": "Kleidung", "worn": true},
	{"key": "hat_color",    "label": "Hutfarbe",       "group": "Kleidung", "worn": true},
	{"key": "scarf",        "label": "Schal",          "group": "Kleidung", "worn": true},
	{"key": "shirt",        "label": "Oberteil",       "group": "Kleidung", "worn": true},
	{"key": "shirt_style",  "label": "Schnitt",        "group": "Kleidung", "worn": true},
	{"key": "shoulders",    "label": "Schulterplatten", "group": "Kleidung", "worn": true},
	{"key": "back",         "label": "Rücken",         "group": "Kleidung", "worn": true},
	{"key": "belt",         "label": "Gürtel",         "group": "Kleidung", "worn": true},
	{"key": "pouch",        "label": "Beutel",         "group": "Kleidung", "worn": true},
	{"key": "pants",        "label": "Hose",           "group": "Kleidung", "worn": true},
	{"key": "pants_style",  "label": "Hosenlänge",     "group": "Kleidung", "worn": true},
	{"key": "shoes",        "label": "Schuhe",         "group": "Kleidung", "worn": true},
	# ── Rüstungs-Spiegel (Wahrheit: EquipmentService, hier nur zur Anzeige/Replikation) ──
	{"key": "armor_helmet", "label": "Helm",           "group": "Rüstung", "worn": true},
	{"key": "armor_chest",  "label": "Brustpanzer",    "group": "Rüstung", "worn": true},
	{"key": "armor_legs",   "label": "Beinschutz",     "group": "Rüstung", "worn": true},
	{"key": "armor_boots",  "label": "Stiefel",        "group": "Rüstung", "worn": true},
]

const DEFAULTS: Dictionary = {
	"sex":         "male",
	"skin":        "sand",
	"build":       "normal",
	"height":      "medium",
	"hair_style":  "short",
	"hair_color":  "brown",
	"beard":       "none",
	"eyes":        "round",
	"eye_color":   "brown",
	"brows":       "soft",
	"nose":        "small",
	"mouth":       "smile",
	"ears":        "round",
	"face_detail": "none",
	"glasses":     "none",
	"hat":         "none",
	"hat_color":   "brown",
	"shirt":       "unbestimmt",
	"shirt_style": "tshirt",
	"belt":        "none",
	"pants":       "navy",
	"pants_style": "long",
	"shoes":       "brown",
	"scarf":        "none",
	"shoulders":    "none",
	"back":         "none",
	"pouch":        "none",
	"armor_helmet": "none",
	"armor_chest":  "none",
	"armor_legs":   "none",
	"armor_boots":  "none",
}

## Wahrscheinlichkeit, mit der random_look() bei diesen Feldern die Option "none"
## wählt (Bart/Brille/Hut/... sollen die Ausnahme sein, nicht die Regel).
const RANDOM_NONE_CHANCE: Dictionary = {
	"beard":       0.60,
	"face_detail": 0.55,
	"glasses":     0.80,
	"hat":         0.70,
	"belt":        0.50,
	# Zufalls-NPCs tragen nie Schal/Umhang/Rüstung — das bleibt handgemachten Presets vorbehalten.
	"scarf":        1.0,
	"shoulders":    1.0,
	"back":         1.0,
	"pouch":        1.0,
	"armor_helmet": 1.0,
	"armor_chest":  1.0,
	"armor_legs":   1.0,
	"armor_boots":  1.0,
}

## Zufalls-Looks sind immer bekleidet: bei diesen Feldern wird "none" (nackt) nie gewürfelt.
const RANDOM_NEVER_NONE: Array = ["shirt", "pants", "shoes"]

## Geschlechts-Parameter (Körperform). Alle Faktoren relativ zu "male" = 1.0.
##   shoulder_w  Breite von Rumpf/Schultern · hip_w  Breite von Becken/Beinabstand ·
##   limb_mul    Dicke Arme/Beine · neck_mul  Halsdicke · bust  Brust-Volumen (0 = keins) ·
##   height_mul  gleichmäßiger Größenfaktor (zusätzlich zu `height`).
const SEX_PARAMS: Dictionary = {
	"male":   {"shoulder_w": 1.00, "hip_w": 1.00, "limb_mul": 1.00, "neck_mul": 1.00, "bust": 0.0, "height_mul": 1.00},
	"female": {"shoulder_w": 0.90, "hip_w": 1.16, "limb_mul": 0.90, "neck_mul": 0.86, "bust": 1.0, "height_mul": 0.96},
}

## feld -> Array von { id, label, ... }. Die erste Option eines Feldes ist NICHT
## automatisch der Default — der steht in DEFAULTS.
## Hinweis zu den Shirt-IDs: "sonnig"/"wald"/"flut"/"asche"/"unbestimmt" sind
## bewusst identisch mit den Archetyp-IDs aus CharacterCreationService (dessen
## Farben müssen mit diesen Einträgen übereinstimmen — ein Test prüft das).
const CATALOG: Dictionary = {
	## Körperbau-Parameter stehen in SEX_PARAMS.
	"sex": [
		{"id": "male",   "label": "Männlich"},
		{"id": "female", "label": "Weiblich"},
	],
	"skin": [
		{"id": "porcelain", "label": "Porzellan", "color": Color(0.96, 0.83, 0.72)},
		{"id": "light",     "label": "Hell",      "color": Color(0.92, 0.76, 0.62)},
		{"id": "sand",      "label": "Sand",      "color": Color(0.86, 0.68, 0.52)},
		{"id": "gold",      "label": "Gold",      "color": Color(0.78, 0.58, 0.40)},
		{"id": "bronze",    "label": "Bronze",    "color": Color(0.65, 0.46, 0.32)},
		{"id": "copper",    "label": "Kupfer",    "color": Color(0.55, 0.37, 0.26)},
		{"id": "brown",     "label": "Braun",     "color": Color(0.42, 0.28, 0.20)},
		{"id": "dark",      "label": "Dunkel",    "color": Color(0.28, 0.19, 0.15)},
	],
	## torso_w: Breitenfaktor Rumpf/Schultern, limb: Dickenfaktor Arme/Beine.
	"build": [
		{"id": "slim",   "label": "Schlank", "torso_w": 0.88, "limb": 0.90},
		{"id": "normal", "label": "Normal",  "torso_w": 1.00, "limb": 1.00},
		{"id": "broad",  "label": "Kräftig", "torso_w": 1.14, "limb": 1.15},
	],
	## scale: gleichmäßiger Faktor auf den gesamten Körper.
	"height": [
		{"id": "short",  "label": "Klein", "scale": 0.93},
		{"id": "medium", "label": "Mittel", "scale": 1.00},
		{"id": "tall",   "label": "Groß",  "scale": 1.07},
	],
	"hair_style": [
		{"id": "bald",     "label": "Glatze"},
		{"id": "buzz",     "label": "Kurzgeschoren"},
		{"id": "short",    "label": "Kurz"},
		{"id": "bob",      "label": "Bob"},
		{"id": "long",     "label": "Lang"},
		{"id": "ponytail", "label": "Zopf"},
		{"id": "bun",      "label": "Dutt"},
		{"id": "spiky",    "label": "Stachelig"},
		{"id": "curly",    "label": "Lockig"},
		{"id": "mohawk",   "label": "Irokese"},
		{"id": "pigtails", "label": "Zöpfe"},
		{"id": "messy",    "label": "Wuschelig"},
	],
	"hair_color": [
		{"id": "black",      "label": "Schwarz",      "color": Color(0.08, 0.07, 0.07)},
		{"id": "darkbrown",  "label": "Dunkelbraun",  "color": Color(0.22, 0.14, 0.09)},
		{"id": "brown",      "label": "Braun",        "color": Color(0.38, 0.24, 0.13)},
		{"id": "chestnut",   "label": "Kastanie",     "color": Color(0.50, 0.27, 0.15)},
		{"id": "blond",      "label": "Blond",        "color": Color(0.85, 0.70, 0.38)},
		{"id": "lightblond", "label": "Hellblond",    "color": Color(0.93, 0.84, 0.60)},
		{"id": "red",        "label": "Rot",          "color": Color(0.66, 0.22, 0.12)},
		{"id": "gray",       "label": "Grau",         "color": Color(0.60, 0.60, 0.62)},
		{"id": "white",      "label": "Weiß",         "color": Color(0.92, 0.92, 0.93)},
		{"id": "blue",       "label": "Blau",         "color": Color(0.25, 0.40, 0.80)},
	],
	"eyes": [
		{"id": "round",  "label": "Rund"},
		{"id": "dot",    "label": "Punkte"},
		{"id": "narrow", "label": "Schmal"},
		{"id": "big",    "label": "Groß"},
		{"id": "sleepy", "label": "Verschlafen"},
		{"id": "lashes", "label": "Wimpern"},
	],
	"eye_color": [
		{"id": "brown",  "label": "Braun",    "color": Color(0.35, 0.22, 0.12)},
		{"id": "hazel",  "label": "Haselnuss", "color": Color(0.55, 0.40, 0.18)},
		{"id": "green",  "label": "Grün",     "color": Color(0.25, 0.55, 0.30)},
		{"id": "blue",   "label": "Blau",     "color": Color(0.25, 0.50, 0.85)},
		{"id": "gray",   "label": "Grau",     "color": Color(0.55, 0.60, 0.65)},
		{"id": "violet", "label": "Violett",  "color": Color(0.55, 0.35, 0.75)},
	],
	"brows": [
		{"id": "none",   "label": "Keine"},
		{"id": "soft",   "label": "Sanft"},
		{"id": "angled", "label": "Streng"},
		{"id": "thick",  "label": "Buschig"},
		{"id": "arched", "label": "Geschwungen"},
	],
	"nose": [
		{"id": "none",  "label": "Keine"},
		{"id": "small", "label": "Klein"},
		{"id": "round", "label": "Rund"},
		{"id": "long",  "label": "Lang"},
		{"id": "wide",  "label": "Breit"},
	],
	"mouth": [
		{"id": "smile",   "label": "Lächeln"},
		{"id": "neutral", "label": "Neutral"},
		{"id": "open",    "label": "Offen"},
		{"id": "smirk",   "label": "Schmunzeln"},
		{"id": "grin",    "label": "Grinsen"},
		{"id": "frown",   "label": "Missmutig"},
	],
	"beard": [
		{"id": "none",     "label": "Keiner"},
		{"id": "stubble",  "label": "Dreitagebart"},
		{"id": "mustache", "label": "Schnurrbart"},
		{"id": "goatee",   "label": "Ziegenbart"},
		{"id": "full",     "label": "Vollbart"},
	],
	"ears": [
		{"id": "round",   "label": "Rund"},
		{"id": "small",   "label": "Klein"},
		{"id": "pointed", "label": "Spitz"},
	],
	"face_detail": [
		{"id": "none",     "label": "Keins"},
		{"id": "freckles", "label": "Sommersprossen"},
		{"id": "blush",    "label": "Rosige Wangen"},
		{"id": "scar",     "label": "Narbe"},
	],
	"glasses": [
		{"id": "none",   "label": "Keine"},
		{"id": "round",  "label": "Rund"},
		{"id": "square", "label": "Eckig"},
		{"id": "shades", "label": "Sonnenbrille"},
	],
	"hat": [
		{"id": "none",   "label": "Keine"},
		{"id": "cap",    "label": "Schirmmütze"},
		{"id": "beanie", "label": "Mütze"},
		{"id": "straw",  "label": "Strohhut"},
		{"id": "wizard", "label": "Spitzhut"},
		# Feste Farben (hat_color wird ignoriert): Schutzhelm mit Stirnlampe, Zylinder.
		{"id": "hardhat", "label": "Schutzhelm"},
		{"id": "tophat",  "label": "Zylinder"},
	],
	"hat_color": [
		{"id": "brown", "label": "Braun",  "color": Color(0.40, 0.27, 0.15)},
		{"id": "tan",   "label": "Sand",   "color": Color(0.78, 0.65, 0.40)},
		{"id": "red",   "label": "Rot",    "color": Color(0.70, 0.20, 0.18)},
		{"id": "blue",  "label": "Blau",   "color": Color(0.22, 0.34, 0.62)},
		{"id": "green", "label": "Grün",   "color": Color(0.22, 0.45, 0.26)},
		{"id": "gray",  "label": "Grau",   "color": Color(0.45, 0.45, 0.48)},
		{"id": "black", "label": "Schwarz", "color": Color(0.12, 0.12, 0.14)},
		{"id": "yellow", "label": "Gelb",   "color": Color(0.92, 0.72, 0.15)},
	],
	"shirt": [
		{"id": "none",       "label": "Kein Oberteil"},
		{"id": "sonnig",     "label": "Sonnengelb",  "color": Color(0.95, 0.75, 0.25)},
		{"id": "wald",       "label": "Waldgrün",    "color": Color(0.25, 0.55, 0.25)},
		{"id": "flut",       "label": "Flutblau",    "color": Color(0.25, 0.45, 0.75)},
		{"id": "asche",      "label": "Aschviolett", "color": Color(0.55, 0.45, 0.60)},
		{"id": "unbestimmt", "label": "Grau",        "color": Color(0.60, 0.60, 0.60)},
		{"id": "red",        "label": "Rot",         "color": Color(0.75, 0.25, 0.22)},
		{"id": "white",      "label": "Weiß",        "color": Color(0.90, 0.90, 0.88)},
		{"id": "black",      "label": "Schwarz",     "color": Color(0.15, 0.15, 0.17)},
		{"id": "brown",      "label": "Braun",       "color": Color(0.45, 0.30, 0.18)},
		{"id": "teal",       "label": "Türkis",      "color": Color(0.20, 0.60, 0.60)},
	],
	## tshirt: kurze Ärmel · longsleeve: lange Ärmel · vest: ärmellos · tunic: lange
	## Ärmel + Saum über den Oberschenkeln.
	"shirt_style": [
		{"id": "tshirt",     "label": "Kurzarm"},
		{"id": "longsleeve", "label": "Langarm"},
		{"id": "vest",       "label": "Ärmellos"},
		{"id": "tunic",      "label": "Tunika"},
	],
	"belt": [
		{"id": "none",  "label": "Keiner"},
		{"id": "brown", "label": "Braun",    "color": Color(0.33, 0.21, 0.11)},
		{"id": "black", "label": "Schwarz",  "color": Color(0.10, 0.10, 0.12)},
		{"id": "red",   "label": "Rot",      "color": Color(0.62, 0.16, 0.14)},
	],
	"pants": [
		{"id": "none",  "label": "Keine Hose"},
		{"id": "navy",  "label": "Dunkelblau", "color": Color(0.18, 0.22, 0.38)},
		{"id": "brown", "label": "Braun",      "color": Color(0.36, 0.26, 0.16)},
		{"id": "black", "label": "Schwarz",    "color": Color(0.13, 0.13, 0.15)},
		{"id": "gray",  "label": "Grau",       "color": Color(0.42, 0.42, 0.45)},
		{"id": "olive", "label": "Oliv",       "color": Color(0.32, 0.36, 0.20)},
		{"id": "sand",  "label": "Sand",       "color": Color(0.72, 0.62, 0.44)},
	],
	"pants_style": [
		{"id": "long",   "label": "Lang"},
		{"id": "shorts", "label": "Kurz"},
	],
	"shoes": [
		{"id": "none",  "label": "Barfuß"},
		{"id": "brown", "label": "Braun",   "color": Color(0.24, 0.17, 0.12)},
		{"id": "black", "label": "Schwarz", "color": Color(0.10, 0.10, 0.11)},
		{"id": "white", "label": "Weiß",    "color": Color(0.88, 0.88, 0.86)},
		{"id": "red",   "label": "Rot",     "color": Color(0.62, 0.17, 0.15)},
		{"id": "gray",  "label": "Grau",    "color": Color(0.45, 0.45, 0.48)},
		{"id": "tan",   "label": "Sand",    "color": Color(0.60, 0.48, 0.32)},
	],
	"scarf": [
		{"id": "none",  "label": "Kein Schal"},
		{"id": "red",   "label": "Rot",   "color": Color(0.78, 0.22, 0.20)},
		{"id": "green", "label": "Grün",  "color": Color(0.22, 0.45, 0.26)},
		{"id": "blue",  "label": "Blau",  "color": Color(0.22, 0.34, 0.62)},
		{"id": "gray",  "label": "Grau",  "color": Color(0.45, 0.45, 0.48)},
	],
	## backpack: Reiserucksack mit Schlafrolle · cape_*: Umhang in der Farbe.
	"back": [
		{"id": "none",        "label": "Nichts"},
		{"id": "backpack",    "label": "Rucksack"},
		{"id": "cape_green",  "label": "Umhang (Grün)",    "color": Color(0.20, 0.38, 0.26)},
		{"id": "cape_violet", "label": "Umhang (Violett)", "color": Color(0.42, 0.38, 0.70)},
		{"id": "cape_red",    "label": "Umhang (Rot)",     "color": Color(0.62, 0.16, 0.14)},
		{"id": "cape_blue",   "label": "Umhang (Blau)",    "color": Color(0.22, 0.34, 0.62)},
		{"id": "cape_black",  "label": "Umhang (Schwarz)", "color": Color(0.12, 0.12, 0.14)},
	],
	"pouch": [
		{"id": "none",  "label": "Kein Beutel"},
		{"id": "brown", "label": "Lederbeutel"},
	],
	"shoulders": [
		{"id": "none",  "label": "Keine"},
		{"id": "steel", "label": "Stahl-Schulterplatten"},
	],
	## Rüstungs-Spiegel: IDs = ArmorDefinition-IDs (data/items/armor). `tier` bestimmt Farbe/Glanz.
	## Ein Test prüft, dass jede Rüstungs-.tres hier vorkommt.
	"armor_helmet": [
		{"id": "none",          "label": "Kein Helm"},
		{"id": "copper_helmet", "label": "Kupferhelm", "tier": "copper"},
		{"id": "iron_helmet",   "label": "Eisenhelm",  "tier": "iron"},
		{"id": "steel_helmet",  "label": "Stahlhelm",  "tier": "steel"},
	],
	"armor_chest": [
		{"id": "none",              "label": "Kein Brustpanzer"},
		{"id": "copper_chestplate", "label": "Kupferbrustpanzer", "tier": "copper"},
		{"id": "iron_chestplate",   "label": "Eisenbrustpanzer",  "tier": "iron"},
		{"id": "steel_chestplate",  "label": "Stahlbrustpanzer",  "tier": "steel"},
	],
	"armor_legs": [
		{"id": "none",           "label": "Kein Beinschutz"},
		{"id": "copper_greaves", "label": "Kupferbeinschienen", "tier": "copper"},
		{"id": "iron_greaves",   "label": "Eisenbeinschienen",  "tier": "iron"},
		{"id": "steel_greaves",  "label": "Stahlbeinschienen",  "tier": "steel"},
	],
	"armor_boots": [
		{"id": "none",         "label": "Keine Stiefel"},
		{"id": "copper_boots", "label": "Kupferstiefel", "tier": "copper"},
		{"id": "iron_boots",   "label": "Eisenstiefel",  "tier": "iron"},
		{"id": "steel_boots",  "label": "Stahlstiefel",  "tier": "steel"},
	],
}

## Archetyp-ID (CharacterCreationService.APPEARANCE_ARCHETYPES) -> Überschreibungen
## auf den Default-Look. Hauttyp bleibt bewusst unangetastet — der ist eine
## persönliche Wahl, keine Charaktereigenschaft.
const ARCHETYPE_LOOKS: Dictionary = {
	"sonnig": {"shirt": "sonnig", "hair_style": "short",    "hair_color": "blond",     "eye_color": "blue",   "mouth": "smile",   "pants": "brown", "face_detail": "freckles"},
	"wald":   {"shirt": "wald",   "hair_style": "ponytail", "hair_color": "chestnut",  "eye_color": "green",  "mouth": "smile",   "pants": "olive", "belt": "brown", "shirt_style": "longsleeve"},
	"flut":   {"shirt": "flut",   "hair_style": "bob",      "hair_color": "darkbrown", "eye_color": "blue",   "mouth": "neutral", "pants": "navy", "shirt_style": "longsleeve"},
	"asche":  {"shirt": "asche",  "hair_style": "spiky",    "hair_color": "gray",      "eye_color": "violet", "mouth": "smirk",   "brows": "angled", "pants": "black", "belt": "black", "shoes": "black"},
}

# ─────────────────────────────────────────────
# Erzeugen / Validieren
# ─────────────────────────────────────────────

static func default_look() -> Dictionary:
	return DEFAULTS.duplicate()

## Look für einen Archetyp (oder Default bei unbekannter/"unbestimmt"-ID).
static func from_archetype(preset_id: String) -> Dictionary:
	var look := default_look()
	var overrides: Variant = ARCHETYPE_LOOKS.get(preset_id, null)
	if overrides is Dictionary:
		for key in (overrides as Dictionary).keys():
			look[key] = (overrides as Dictionary)[key]
	return look

## Zufälliger, immer gültiger Look. `rng` optional (deterministisch, wenn mit festem
## Seed übergeben — NPCLook nutzt das, damit ein NPC auf jedem Client gleich aussieht).
static func random_look(rng: RandomNumberGenerator = null) -> Dictionary:
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var out: Dictionary = {}
	for field in FIELDS:
		var key: String = String((field as Dictionary)["key"])
		var ids := option_ids(key)
		if ids.is_empty():
			out[key] = DEFAULTS[key]
			continue
		# Zufallszahl wird IMMER gezogen, damit die Reihenfolge der Ziehungen (und damit
		# das Ergebnis bei festem Seed) nicht davon abhängt, ob ein Feld "none" kennt.
		var none_roll: float = r.randf()
		var pick_ids: Array = ids
		if RANDOM_NEVER_NONE.has(key):
			pick_ids = ids.filter(func(i: Variant) -> bool: return String(i) != "none")
		var idx: int = r.randi_range(0, pick_ids.size() - 1)
		if RANDOM_NONE_CHANCE.has(key) and ids.has("none") and none_roll < float(RANDOM_NONE_CHANCE[key]):
			out[key] = "none"
		else:
			out[key] = pick_ids[idx]
	# Zufällige Frauen tragen keinen Bart (handgemachte Looks/Editor bleiben frei).
	if String(out.get("sex", "")) == "female":
		out["beard"] = "none"
	return sanitize(out)

## Deterministischer Look aus einem Text (z. B. NPC-Name).
static func from_seed(seed_text: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	return random_look(rng)

## Macht aus BELIEBIGEM Input einen vollständigen, gültigen Look.
## Pro Feld: gültiger String aus `raw` -> sonst Wert aus `base` (falls gültig)
## -> sonst Default. Unbekannte Schlüssel in `raw` werden verworfen. `raw` darf
## alles sein (auch null / kein Dictionary) — das ist der Eingangsfilter für
## Save-Daten und RPC-Payloads.
static func sanitize(raw: Variant, base: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	var source: Dictionary = raw as Dictionary if raw is Dictionary else {}
	for field in FIELDS:
		var key: String = String((field as Dictionary)["key"])
		var chosen: String = _valid_id(key, source.get(key, null))
		if chosen.is_empty():
			chosen = _valid_id(key, base.get(key, null))
		if chosen.is_empty():
			chosen = String(DEFAULTS[key])
		out[key] = chosen
	return out

## Wie sanitize(), aber für Eingaben von SPIELERN (Editor-RPC): Körper-Felder kommen aus `raw`,
## alle getragenen Felder (worn) bleiben bei `base`. So kann kein Client Kleidung/Rüstung per
## Look-Update umgehen (anziehen geht nur über EquipmentService mit Inventar-Prüfung).
static func sanitize_body(raw: Variant, base: Dictionary = {}) -> Dictionary:
	var clean_base := sanitize(base)
	var out := sanitize(raw, clean_base)
	for key in worn_keys():
		out[key] = clean_base[key]
	return out

## Zykliert `field` um `delta` Schritte (±1) und liefert einen NEUEN Look.
static func step(look: Dictionary, field: String, delta: int) -> Dictionary:
	var clean := sanitize(look)
	var ids := option_ids(field)
	if ids.is_empty():
		return clean
	var idx: int = ids.find(clean[field])
	if idx < 0:
		idx = 0
	clean[field] = ids[posmod(idx + delta, ids.size())]
	return clean

# ─────────────────────────────────────────────
# Katalog-Abfragen
# ─────────────────────────────────────────────

static func option_ids(field: String) -> Array:
	var ids: Array = []
	for entry in (CATALOG.get(field, []) as Array):
		ids.append((entry as Dictionary)["id"])
	return ids

## Vollständiger Katalogeintrag ({} wenn Feld/ID unbekannt).
static func get_entry(field: String, id: String) -> Dictionary:
	for entry in (CATALOG.get(field, []) as Array):
		if (entry as Dictionary)["id"] == id:
			return (entry as Dictionary).duplicate()
	return {}

static func label_of(field: String, id: String) -> String:
	return String(get_entry(field, id).get("label", id))

## Felder, die der Editor anzeigt (alles außer getragenen Items).
static func editor_fields() -> Array:
	var out: Array = []
	for f in FIELDS:
		if not bool((f as Dictionary).get("worn", false)):
			out.append(f)
	return out

## Schlüssel aller getragenen Felder (Kleidung + Rüstungs-Spiegel).
static func worn_keys() -> Array:
	var out: Array = []
	for f in FIELDS:
		if bool((f as Dictionary).get("worn", false)):
			out.append(String((f as Dictionary)["key"]))
	return out

static func is_worn_key(key: String) -> bool:
	return worn_keys().has(key)

static func field_label(field: String) -> String:
	for f in FIELDS:
		if (f as Dictionary)["key"] == field:
			return String((f as Dictionary)["label"])
	return field

## Farbe eines Farb-Feldes (skin/hair_color/eye_color/shirt/pants). Unbekannte
## ID -> Farbe der Default-Option, nie ein Fehler.
static func color_of(field: String, id: String) -> Color:
	var entry := get_entry(field, id)
	if entry.has("color"):
		return entry["color"] as Color
	var fallback := get_entry(field, String(DEFAULTS.get(field, "")))
	return fallback.get("color", Color.MAGENTA) as Color

static func height_scale(id: String) -> float:
	return float(get_entry("height", id).get("scale", 1.0))

static func torso_width(id: String) -> float:
	return float(get_entry("build", id).get("torso_w", 1.0))

static func limb_scale(id: String) -> float:
	return float(get_entry("build", id).get("limb", 1.0))

## Geschlecht des Looks ("male"/"female"); unbekannt -> "male".
static func sex_of(look: Dictionary) -> String:
	var s := String(look.get("sex", "male"))
	return s if SEX_PARAMS.has(s) else "male"

## Körperform-Faktor des Geschlechts (siehe SEX_PARAMS); unbekannt -> 1.0 (bust: 0.0).
static func sex_param(sex_id: String, key: String) -> float:
	var params: Dictionary = SEX_PARAMS.get(sex_id, SEX_PARAMS["male"])
	return float(params.get(key, 0.0 if key == "bust" else 1.0))

## Gesamt-Größenfaktor: Größenstufe × Geschlecht (Frauen sind im Schnitt etwas kleiner).
static func body_scale(look: Dictionary) -> float:
	return height_scale(String(look.get("height", "medium"))) * sex_param(sex_of(look), "height_mul")

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

## Gibt `value` als String zurück, wenn es eine gültige Option von `field` ist,
## sonst "". Akzeptiert nur String/StringName (kein implizites Casting von
## Zahlen o. ä. aus Netzwerk-Payloads).
static func _valid_id(field: String, value: Variant) -> String:
	if not (value is String or value is StringName):
		return ""
	var s := String(value)
	for entry in (CATALOG.get(field, []) as Array):
		if (entry as Dictionary)["id"] == s:
			return s
	return ""
