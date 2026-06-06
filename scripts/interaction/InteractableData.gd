# InteractableData.gd
extends Resource
class_name InteractableData

@export var id: String = "object"
@export var label: String = "Interagieren"
## action_id: Eindeutiger Bezeichner der Aktion (z.B. "chop_oak", "mine_iron").
## Wird von InteractableComponent genutzt um den 3D-Fortschrittsbalken
## korrekt einem spezifischen Objekt zuzuordnen — nicht per label (das wäre
## bei mehreren gleichartigen Objekten mehrdeutig).
## Konvention: "<verb>_<objekttyp>", alles lowercase, kein Leerzeichen.
@export var action_id: String = "interact"
@export var duration: float = 1.5
@export var xp_type: String = "none"
@export var xp_amount: int = 10
## loot_table: Neue datengetriebene Drop-Tabelle (LootTable.tres).
## Wenn gesetzt, wird diese für Drops verwendet statt dem alten drops-Dictionary.
@export var loot_table: LootTable
## drops: Legacy-Feld { "item_id": quantity } — wird ersetzt durch loot_table.
## Bleibt für Rückwärtskompatibilität bis alle Objekte migriert sind.
@export var drops: Dictionary = {}
@export var inspect_text: String = ""
