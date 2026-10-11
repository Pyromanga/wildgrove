class_name PetBattleTypes
extends RefCounted

## PetBattleTypes — Typen und Typ-Tabelle der Pet-Kämpfe (Pokémon-Prinzip: stark/schwach gegen).
##
## SECHS Tiertypen auf einem RING: jeder Typ ist gegen die nächsten ZWEI im Ring stark (×2)
## und gegen die zwei davor schwach (×0,5), gegen sich selbst und den gegenüberliegenden normal.
## Damit hat jeder Typ genau zwei Stärken und zwei Schwächen — ohne Tabelle pflegen zu müssen,
## und neue Tierarten brauchen nur einen Typ (siehe SPECIES_TYPES / type_for()).
##
##   RAUBTIER → Huftier, Nager        Huftier → Nager, Insekt        Nager → Insekt, Gift
##   INSEKT   → Gift, Wasser          GIFT    → Wasser, Raubtier     WASSER → Raubtier, Huftier
##
## NORMAL (Rempler u.Ä.) ist gegen alles ×1 und kein Tier-Typ.

enum Type { PREDATOR, HOOFED, RODENT, INSECT, VENOM, AQUA, NORMAL }

const RING: Array[int] = [Type.PREDATOR, Type.HOOFED, Type.RODENT, Type.INSECT, Type.VENOM, Type.AQUA]

const LABELS: Dictionary = {
	Type.PREDATOR: "Raubtier",
	Type.HOOFED:   "Huftier",
	Type.RODENT:   "Nager",
	Type.INSECT:   "Insekt",
	Type.VENOM:    "Gift",
	Type.AQUA:     "Wasser",
	Type.NORMAL:   "Normal",
}

## Farbe je Typ (Typ-Etikett im Kampf-Fenster).
const COLORS: Dictionary = {
	Type.PREDATOR: Color(0.85, 0.40, 0.30),
	Type.HOOFED:   Color(0.75, 0.62, 0.38),
	Type.RODENT:   Color(0.62, 0.55, 0.45),
	Type.INSECT:   Color(0.70, 0.80, 0.30),
	Type.VENOM:    Color(0.65, 0.40, 0.85),
	Type.AQUA:     Color(0.35, 0.65, 0.95),
	Type.NORMAL:   Color(0.70, 0.70, 0.70),
}

const SUPER_EFFECTIVE: float = 2.0
const NOT_EFFECTIVE: float = 0.5

## Typ je Art für Vierbeiner (Insekten/Spinnen/Schlangen/Fische ergeben sich aus dem Bauplan).
## Schlüssel = species_id in Kleinbuchstaben. Unbekannte Vierbeiner → HOOFED (siehe type_for()).
const SPECIES_TYPES: Dictionary = {
	# Raubtiere
	"wolf": Type.PREDATOR, "lynx": Type.PREDATOR, "coyote": Type.PREDATOR, "badger": Type.PREDATOR,
	"raccoon": Type.PREDATOR, "weasel": Type.PREDATOR, "mink": Type.PREDATOR, "tiger": Type.PREDATOR,
	"leopard": Type.PREDATOR, "cheetah": Type.PREDATOR, "panda": Type.PREDATOR, "skunk": Type.PREDATOR,
	"hyena": Type.PREDATOR, "jackal": Type.PREDATOR, "mongoose": Type.PREDATOR, "ferret": Type.PREDATOR,
	"fox": Type.PREDATOR, "bear": Type.PREDATOR,
	# Huftiere / Herdentiere
	"moose": Type.HOOFED, "bison": Type.HOOFED, "goat": Type.HOOFED, "mountain_goat": Type.HOOFED,
	"elk": Type.HOOFED, "horse": Type.HOOFED, "donkey": Type.HOOFED, "wild_boar_sow": Type.HOOFED,
	"zebra": Type.HOOFED, "giraffe": Type.HOOFED, "warthog": Type.HOOFED, "gazelle": Type.HOOFED,
	"antelope": Type.HOOFED, "deer": Type.HOOFED, "boar": Type.HOOFED, "sheep": Type.HOOFED,
	# Nager / Kleinsäuger
	"hedgehog": Type.RODENT, "chipmunk": Type.RODENT, "porcupine": Type.RODENT, "mole": Type.RODENT,
	"vole": Type.RODENT, "mouse": Type.RODENT, "rat": Type.RODENT, "shrew": Type.RODENT,
	"squirrel": Type.RODENT, "rabbit": Type.RODENT,
	# Wassertier unter den Vierbeinern
	"otter": Type.AQUA,
}

## Typ einer Art: Insekt/Spinne/Schlange/Fisch ergeben sich eindeutig aus dem Bauplan, nur bei
## Vierbeinern entscheidet die Tabelle SPECIES_TYPES (Fallback HOOFED für künftige Arten).
static func type_for(species_id: String, body_plan: int) -> int:
	match body_plan:
		AnimalVisualProfile.BodyPlan.INSECT:
			return Type.INSECT
		AnimalVisualProfile.BodyPlan.SPIDER, AnimalVisualProfile.BodyPlan.SNAKE:
			return Type.VENOM
		AnimalVisualProfile.BodyPlan.FISH:
			return Type.AQUA
		_:
			return int(SPECIES_TYPES.get(species_id.to_lower(), Type.HOOFED))

## Schadensfaktor eines Angriffs vom Typ `attack` auf ein Ziel vom Typ `defend`: 2.0 / 1.0 / 0.5.
static func effectiveness(attack: int, defend: int) -> float:
	var a: int = RING.find(attack)
	var d: int = RING.find(defend)
	if a < 0 or d < 0:
		return 1.0  # NORMAL
	var diff: int = posmod(d - a, RING.size())
	if diff == 1 or diff == 2:
		return SUPER_EFFECTIVE
	if diff == RING.size() - 1 or diff == RING.size() - 2:
		return NOT_EFFECTIVE
	return 1.0

static func label_for(type_id: int) -> String:
	return String(LABELS.get(type_id, "?"))

static func color_for(type_id: int) -> Color:
	return COLORS.get(type_id, Color(0.7, 0.7, 0.7)) as Color
