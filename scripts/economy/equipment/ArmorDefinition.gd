extends ItemDefinition
class_name ArmorDefinition

## ArmorDefinition — Resource für Rüstungsteile (Helm, Brustpanzer, Beinschutz, Stiefel).
##
## Erbt id, display_name, icon, max_stack, sell_price von ItemDefinition.
## Analog zu WeaponDefinition (Schaden) und ToolDefinition (Gathering-Tempo), aber für
## Schadensminderung — ausgerüstet über die vier Rüstungs-Slots des EquipmentService
## (SLOT_HELMET/SLOT_CHEST/SLOT_LEGS/SLOT_BOOTS). Die Slot-Ids sind dieselben Strings, die das
## Equipment-Panel (EquipmentUIController.SLOT_LABELS) schon vor dieser Klasse anzeigte.
##
## Wirkung: EquipmentService._apply_stat_bonus() legt pro Slot einen FLAT_ADD-StatModifier auf
## den Stat EquipmentService.STAT_ARMOR. Die Summe über alle Slots ist die zusätzliche
## physische Rüstung des Spielers (gleiche Skala wie CombatProfile.armor: 0.10 = 10 %
## weniger physischer Schaden). CombatSystem.calculate_damage() clamped das Gesamtergebnis
## ohnehin auf 0.85 — auch ein voller Satz kann also nie unverwundbar machen.
##
## Der Slot ist PRO ITEM fest (ein Helm passt nur in den Helm-Slot). EquipmentService.
## on_equip_confirmed() prüft das serverseitig, damit ein Client dasselbe Teil nicht in mehrere
## Slots legen und so seine Rüstung vervielfachen kann.

enum ArmorSlot {
	HELMET,
	CHEST,
	LEGS,
	BOOTS,
}

## Slot-Id je ArmorSlot — dieselben Strings wie EquipmentService.SLOT_* und die Schlüssel in
## EquipmentUIController.SLOT_LABELS/SLOT_ICONS.
const SLOT_IDS := {
	ArmorSlot.HELMET: "helmet",
	ArmorSlot.CHEST:  "chest",
	ArmorSlot.LEGS:   "legs",
	ArmorSlot.BOOTS:  "boots",
}

## In welchen Slot dieses Teil gehört.
@export var armor_slot: ArmorSlot = ArmorSlot.CHEST

## Physische Schadensminderung dieses Teils (0.0–1.0, additiv über alle Slots).
## Richtwerte der Schmiede-Rüstungen: siehe docs/smithing-and-crafting.md.
@export_range(0.0, 1.0, 0.005) var armor_value: float = 0.0

## Slot-Id (String) dieses Teils, z.B. "helmet".
func get_slot_id() -> String:
	return String(SLOT_IDS.get(armor_slot, ""))

## Alle vier Rüstungs-Slot-Ids (Reihenfolge wie im Equipment-Panel, von oben nach unten).
static func all_slot_ids() -> Array[String]:
	var out: Array[String] = []
	for slot in [ArmorSlot.HELMET, ArmorSlot.CHEST, ArmorSlot.LEGS, ArmorSlot.BOOTS]:
		out.append(String(SLOT_IDS[slot]))
	return out

## true, wenn slot_id einer der Rüstungs-Slots ist.
static func is_armor_slot(slot_id: String) -> bool:
	return all_slot_ids().has(slot_id)
