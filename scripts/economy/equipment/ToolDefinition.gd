extends ItemDefinition
class_name ToolDefinition

## ToolDefinition — Resource für Gathering-Werkzeuge (Axt, Spitzhacke, ...).
##
## Erbt id, display_name, icon, max_stack, sell_price von ItemDefinition.
## Analog zu WeaponDefinition (Kampf-Bonus), aber für Gathering-Geschwindigkeit
## statt Schaden — ausgerüstet über EquipmentService.SLOT_TOOL, nicht SLOT_WEAPON.
##
## Wirkung: speed_stat_id ist der Stat-Name, den InteractionExecutor über
## StatModifierService.get_effective_stat() liest, um action.duration zu
## skalieren (siehe InteractionExecutor.execute_action()). Dieselbe
## Skalierungs-Idee wie InteractableData.yield_stat_id (Drop-Menge), hier
## aber für die Dauer der Interaktion.

## Stat-Name, auf den der Bonus wirkt — muss mit der jeweiligen
## HarvestableEntity-Subklasse übereinstimmen, z.B. "gathering_speed_wood"
## für eine Axt, "gathering_speed_ore" für eine Spitzhacke.
@export var speed_stat_id: String = ""

## Bonus als PERCENT_ADD-Faktor (0.5 = 50% schneller → Dauer wird durch 1.5 geteilt).
@export var speed_bonus: float = 0.5

## Kaufpreis im Shop (Gold). Nur relevant für Items im Shop-Kaufkatalog.
@export var buy_price: int = 0

## BUGFIX (2026-09-25, "Equipment wird nicht 3D gerendert (Axt/Spitzhacke/
## Schaufel)"): WeaponVisual3D griff bisher NUR bei WeaponDefinition (siehe
## dortiger Kommentar) — ToolDefinition hatte weder einen Typ-Diskriminator
## für die Mesh-Form noch eigene Offset/Rotation-Werte, war also strukturell
## unsichtbar. Analog zu WeaponDefinition.weapon_type/visual_offset/
## visual_rotation.
## TONGS/HAMMER (Schmiede-Werkzeuge, siehe docs/smithing-and-crafting.md): reines Handwerkszeug
## ohne Gathering-Bonus (speed_stat_id bleibt leer). Sie werden NICHT verbraucht — SmithingService
## verlangt sie nur als Voraussetzung (SmithingRecipe.required_tools), im Inventar ODER im
## Werkzeug-Slot. Neue Werte immer ANS ENDE: .tres-Dateien speichern den Enum als Zahl
## (Pickaxe.tres: tool_type = 1), Einfügen in der Mitte würde alle bestehenden Werkzeuge umdeuten.
enum ToolType {
	AXE,
	PICKAXE,
	SHOVEL,
	TONGS,
	HAMMER,
	SCYTHE,   # Sense: Gras/Blumen mähen (GroundToolController "Mähen", WorldService.request_grass_cut)
}

## Werkzeug-Typ — steuert Mesh-Form/-Farbe in WeaponVisual3D, analog
## WeaponDefinition.weapon_type.
@export var tool_type: ToolType = ToolType.AXE

## Visueller Offset relativ zum hand_r-Bone (world-units). Wird in
## WeaponVisual3D.attach_to() übernommen.
@export var visual_offset:   Vector3 = Vector3(0.0, -0.15, 0.2)
@export var visual_rotation: Vector3 = Vector3(0.0, 0.0, 0.0)
