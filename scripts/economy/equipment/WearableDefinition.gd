extends ItemDefinition
class_name WearableDefinition

## WearableDefinition — Resource für ANZIEHBARE KLEIDUNG (Oberteil, Hose, Schuhe, Hut, Brille,
## Gürtel, Schal, Rucksack/Umhang, Beutel, Schulterplatten).
##
## Gegenstück zu ArmorDefinition (Rüstung mit Schutzwert) — Kleidung ist rein kosmetisch und
## hat keinen Stat. Die Items werden NICHT als .tres gepflegt, sondern von WearableCatalog aus
## dem Look-Katalog (CharacterLook.CATALOG) erzeugt und beim DataService-Start registriert.
## Dadurch kann ein Kleidungsstück und seine Optik nie auseinanderlaufen: `look_values` sind
## exakt die CharacterLook-Felder, die CharacterPartBuilder zum Zeichnen liest.
##
## Wirkung beim Anziehen: EquipmentService → CharacterCreationService.set_worn() schreibt
## `look_values` in den (replizierten) Look des Spielers; Ablegen setzt das Hauptfeld auf "none".

## Slot-Id (WearableCatalog.SLOT_ORDER), z.B. "shirt".
@export var wear_slot: String = ""

## { look_feld: option_id } — was dieses Item im Look setzt, z.B. {"shirt": "wald", "shirt_style": "tshirt"}.
@export var look_values: Dictionary = {}

## Slot-Id (String) dieses Teils — gleiche Schnittstelle wie ArmorDefinition.get_slot_id().
func get_slot_id() -> String:
	return wear_slot
