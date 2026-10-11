class_name NPCLook
extends RefCounted

## NPCLook — Aussehen von NPCs (gleiches Datenmodell wie Spieler: CharacterLook).
##
## Jeder NPC wird mit demselben CharacterPartBuilder gebaut wie ein Spieler — also mit
## Gesicht, Haaren, Kleidung und lebendigem Blick (CharacterGaze). Hier steht nur,
## WIE ein bestimmter NPC aussieht:
##
##   1. PRESETS: handgemachte Looks für die Story-NPCs (Erik, Wei, Talia, ...). Zugeordnet
##      wird über GANZE WÖRTER des Anzeigenamens (kleingeschrieben) — "Wegweiser Mira" und
##      "Bergarbeiterin Mira" bekommen so verschiedene Looks, obwohl beide "Mira" heißen.
##   2. Kein Preset → deterministischer Zufallslook aus dem Namen (CharacterLook.from_seed):
##      jeder unbekannte NPC sieht anders aus, aber auf JEDEM Client gleich.
##   3. `explicit_look` (Parameter von NPCVisualBuilder.build) überschreibt einzelne Felder.
##
## Neuer Story-NPC = ein Eintrag in PRESETS. Fehlende Felder fallen auf CharacterLook.DEFAULTS.
##
## GETRAGENES: Kleidung, Zubehör und Rüstung eines NPCs sind echte Items (WearableCatalog /
## ArmorDefinition-IDs) im Look — z. B. Talias Helm = "armor_helmet": "steel_helmet", Rasmus'
## Umhang = "back": "cape_green". NPCVisualBuilder.wear()/take_off() zieht sie zur Laufzeit an
## und aus (derselbe Mechanismus wie beim Spieler, nur ohne Inventar).
##
## Farben: Die Rumpf-/Hemdfarbe kommt weiterhin aus `_get_body_color()` des NPC (rückwärts-
## kompatibel). Nur wenn ein NPC die Standardfarbe nutzt, darf ein Preset `shirt_color`
## in "overrides" vorgeben. Overrides sind NUR lokal (nie Save/Netzwerk) — siehe
## CharacterPartBuilder.build().

const DEFAULT_BODY_COLOR: Color = Color(0.25, 0.40, 0.65)

## Felder pro Eintrag:
##   words      Ganze Wörter des Anzeigennamens (klein), die diesen Eintrag auswählen.
##   look       CharacterLook-IDs (fehlende Felder = Defaults).
##   overrides  Freie Farben (skin_color/hair_color/shirt_color/pants_color/hat_color).
##              NPCs mit eigener _get_body_color() behalten diese Farbe als Oberteil.
##   prop       Handrequisit, siehe NPCProps.
##   extras     (Legacy) Zubehör ohne Item-Entsprechung, siehe NPCProps. Presets nutzen stattdessen
##              die Look-Felder hat/scarf/back/pouch/shoulders/armor_*.
##   cape       (Legacy) Umhangfarbe (Color) — Presets nutzen "back": "cape_*".
##   ghost      true = halbtransparent/leuchtend; hover = Schwebehöhe in m.
const PRESETS: Array = [
	{	# Bergarbeiterin Mira — ocker Arbeitsjacke, Schutzhelm mit Stirnlampe, Spitzhacke.
		"words": ["bergarbeiterin"],
		"look": {
			"sex": "female", "hat": "hardhat", "hat_color": "yellow",
			"skin": "copper", "hair_style": "ponytail", "hair_color": "darkbrown", "eyes": "round",
			"eye_color": "hazel", "brows": "thick", "mouth": "smirk", "face_detail": "freckles",
			"shirt_style": "longsleeve", "belt": "brown", "pants": "gray", "shoes": "black",
		},
		"prop": "pickaxe",
	},
	{	# Wegweiser Mira — freundlich, bunt: gelbe Tunika, roter Schal, Karte.
		"words": ["wegweiser"],
		"look": {
			"sex": "female", "scarf": "red",
			"skin": "light", "build": "slim", "hair_style": "bun", "hair_color": "blond", "eyes": "big",
			"eye_color": "green", "brows": "soft", "mouth": "smile", "face_detail": "blush",
			"shirt_style": "tunic", "belt": "brown", "pants": "sand", "shoes": "tan",
		},
		"overrides": {"shirt_color": Color(0.90, 0.72, 0.28)},
		"prop": "scroll",
	},
	{	# Waldläufer Erik — Vollbart, grüne Kappe, Axt (blaues Hemd bleibt Eriks Markenzeichen).
		"words": ["erik"],
		"look": {
			"skin": "gold", "build": "broad", "height": "tall", "hair_style": "short",
			"hair_color": "chestnut", "beard": "full", "eye_color": "green", "brows": "thick",
			"nose": "round", "mouth": "neutral", "face_detail": "scar", "hat": "cap",
			"hat_color": "green", "shirt_style": "longsleeve", "belt": "brown", "pants": "olive",
			"shoes": "brown",
		},
		"prop": "axe",
	},
	{	# Kampfmeisterin Wei — rote Tunika, schwarzer Gürtel, Dutt, Kampfstab.
		"words": ["kampfmeisterin", "wei"],
		"look": {
			"sex": "female",
			"skin": "light", "build": "slim", "hair_style": "bun", "hair_color": "black",
			"eyes": "narrow", "eye_color": "brown", "brows": "angled", "mouth": "neutral",
			"shirt_style": "tunic", "belt": "black", "pants": "black", "shoes": "black",
		},
		"prop": "staff",
	},
	{	# Wächterin Talia — Helm mit Kamm, Schulterplatten, Speer, grüne Uniform.
		"words": ["talia", "wächterin"],
		"look": {
			"sex": "female", "armor_helmet": "steel_helmet", "shoulders": "steel",
			"skin": "bronze", "height": "tall", "hair_style": "ponytail", "hair_color": "darkbrown",
			"eye_color": "gray", "brows": "angled", "mouth": "neutral", "shirt_style": "longsleeve",
			"belt": "black", "pants": "gray", "shoes": "black",
		},
		"prop": "spear",
	},
	{	# Dorfältester Rasmus — weiser Rauschebart, runde Brille, Gehstock, grüner Umhang.
		"words": ["rasmus", "dorfältester"],
		"look": {
			"back": "cape_green",
			"skin": "light", "height": "short", "hair_style": "short", "hair_color": "white",
			"beard": "full", "eyes": "sleepy", "eye_color": "gray", "brows": "thick", "nose": "long",
			"mouth": "smile", "glasses": "round", "shirt_style": "tunic", "belt": "brown",
			"pants": "brown", "shoes": "brown",
		},
		"prop": "cane",
	},
	{	# Ahnengeist Babatunde — durchscheinend, leuchtender Stab, wallender Umhang, schwebt.
		"words": ["babatunde", "ahnengeist"],
		"look": {
			"back": "cape_violet",
			"skin": "dark", "build": "slim", "height": "tall", "hair_style": "bald",
			"hair_color": "white", "beard": "goatee", "eyes": "sleepy", "eye_color": "violet",
			"brows": "arched", "mouth": "neutral", "ears": "pointed", "shirt_style": "tunic",
			"pants": "gray", "shoes": "gray",
		},
		"overrides": {"skin_color": Color(0.66, 0.64, 0.80), "hair_color": Color(0.90, 0.90, 1.00)},
		"prop": "orb_staff",
		"ghost": true,
		"hover": 0.14,
	},
	{	# Kräuterkundige Senna — Strohhut, rotes Haar, Sommersprossen, Kräuterkorb.
		"words": ["senna", "kräuterkundige"],
		"look": {
			"sex": "female",
			"skin": "sand", "build": "slim", "hair_style": "long", "hair_color": "red",
			"eyes": "lashes", "eye_color": "green", "brows": "arched", "mouth": "smile",
			"face_detail": "freckles", "hat": "straw", "hat_color": "tan", "shirt_style": "tunic",
			"belt": "brown", "pants": "olive", "shoes": "tan",
		},
		"prop": "basket",
	},
	{	# Bankier Aurelius — Zylinder, Schnurrbart, eckige Brille, dunkler Anzug, Hauptbuch.
		"words": ["aurelius", "bankier"],
		"look": {
			"hat": "tophat", "hat_color": "black", "pouch": "brown",
			"skin": "porcelain", "build": "slim", "height": "tall", "hair_style": "short",
			"hair_color": "gray", "beard": "mustache", "eyes": "narrow", "eye_color": "gray",
			"brows": "arched", "nose": "long", "mouth": "neutral", "glasses": "square",
			"shirt_style": "longsleeve", "belt": "black", "pants": "black", "shoes": "black",
		},
		"overrides": {"shirt_color": Color(0.12, 0.16, 0.30)},
		"prop": "ledger",
	},
	{	# Marktschreierin Odile — rote Weste, wilde Locken, Megafon, breites Grinsen.
		"words": ["odile", "marktschreierin"],
		"look": {
			"sex": "female",
			"skin": "brown", "hair_style": "curly", "hair_color": "black", "eyes": "big",
			"eye_color": "hazel", "brows": "arched", "mouth": "grin", "face_detail": "blush",
			"shirt_style": "vest", "belt": "red", "pants": "sand", "shoes": "red",
		},
		"overrides": {"shirt_color": Color(0.82, 0.30, 0.22)},
		"prop": "megaphone",
	},
	{	# Händler Toma — Schirmmütze, Dreitagebart, Weste, Reiserucksack mit Schlafrolle.
		"words": ["toma", "händler"],
		"look": {
			"back": "backpack", "pouch": "brown",
			"skin": "gold", "build": "broad", "hair_style": "messy", "hair_color": "brown",
			"beard": "stubble", "eye_color": "brown", "brows": "thick", "mouth": "smirk",
			"hat": "cap", "hat_color": "tan", "shirt_style": "vest", "belt": "brown",
			"pants": "brown", "shoes": "brown",
		},
		"overrides": {"shirt_color": Color(0.20, 0.46, 0.62)},
	},
	{	# Förster Holgar — grauer Vollbart, braune Kappe, Setzling in der Hand.
		"words": ["holgar", "förster"],
		"look": {
			"skin": "light", "build": "broad", "height": "tall", "hair_style": "short",
			"hair_color": "gray", "beard": "full", "eyes": "narrow", "eye_color": "blue",
			"brows": "thick", "nose": "wide", "mouth": "neutral", "hat": "cap", "hat_color": "brown",
			"shirt_style": "longsleeve", "belt": "brown", "pants": "olive", "shoes": "brown",
		},
		"prop": "sapling",
	},
]

## Liefert { look (gültig!), overrides, scale, prop, extras, cape, ghost, hover }.
## `body_color` = Farbe, die der NPC bisher für seine Körperkapsel nutzte; ungleich der
## Standardfarbe → wird zur Hemdfarbe (Rückwärtskompatibilität mit _get_body_color()).
static func resolve(display_name: String, body_color: Color = DEFAULT_BODY_COLOR, explicit_look: Dictionary = {}) -> Dictionary:
	var preset := find_preset(display_name)
	var look: Dictionary
	var overrides: Dictionary = {}
	var role_style: Dictionary = {}
	if preset.is_empty():
		look = CharacterLook.from_seed(display_name)
		# Berufs-NPCs ("Töpferin Berta"): Kleidung + Requisit des Berufs, Gesicht/Haare bleiben namensabhängig.
		role_style = ProfessionCatalog.style_for_name(display_name)
		for key in (role_style.get("look", {}) as Dictionary).keys():
			look[key] = (role_style["look"] as Dictionary)[key]
	else:
		look = CharacterLook.default_look()
		for key in (preset.get("look", {}) as Dictionary).keys():
			look[key] = (preset["look"] as Dictionary)[key]
		overrides = (preset.get("overrides", {}) as Dictionary).duplicate()

	for key in explicit_look.keys():
		look[key] = explicit_look[key]
	look = CharacterLook.sanitize(look)

	if not body_color.is_equal_approx(DEFAULT_BODY_COLOR):
		overrides["shirt_color"] = body_color

	return {
		"look": look,
		"overrides": overrides,
		"scale": CharacterLook.body_scale(look),
		"prop": String(preset.get("prop", role_style.get("prop", ""))),
		"extras": (preset.get("extras", []) as Array).duplicate(),
		"cape": preset.get("cape", null),
		"ghost": bool(preset.get("ghost", false)),
		"hover": float(preset.get("hover", 0.0)),
	}

## Preset-Eintrag für einen Anzeigenamen ({} wenn keiner passt). Vergleich über GANZE Wörter.
static func find_preset(display_name: String) -> Dictionary:
	var words: PackedStringArray = display_name.to_lower().split(" ", false)
	for entry in PRESETS:
		for w in ((entry as Dictionary)["words"] as Array):
			if words.has(String(w)):
				return entry as Dictionary
	return {}
