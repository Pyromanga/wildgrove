# res://scripts/economy/inventory/ItemDefinition.gd
class_name ItemDefinition extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D
## Erhöht (Building-Fix): 99 reichte nicht mehr — größere Bauwerke (z.B. das
## Haus-Template "small_castle" mit 177 Stein, "village_church" mit 202 Stein,
## "forest_lodge" mit 195 Holz, siehe HouseTemplateDefinition.total_cost())
## verlangen ihre GESAMTEN Materialkosten auf einmal (WorldBuildHandler zahlt
## erst den kompletten total_cost, bevor auch nur ein Bauteil gesetzt wird —
## kein Bezahlen Stück für Stück). Da InventorySystem pro Spieler nur EINE
## ItemInstance pro item_id hält (kein Mehrfach-Stapel derselben Ressource,
## siehe dortiger Klassenkommentar), war ein Baumaterial mit max_stack=99 ein
## hartes Limit, keine reine Slot-Frage: überschüssig gesammelte Ressourcen
## gingen beim Aufsammeln oberhalb von 99 einfach verloren (on_item_add_confirmed()
## kappt still auf max_stack) — solche Bauwerke waren dadurch strukturell nie
## fertigstellbar. 999 passt zum bereits für denselben Building-Fix erhöhten
## InventorySystem.DEFAULT_MAX_SLOTS.
@export var max_stack: int = 999
## Verkaufspreis beim Shop-NPC (Gold pro Stück). 0 = ShopService fällt auf
## DEFAULT_SELL_PRICE zurück (siehe dort) statt das Item unverkäuflich zu machen.
@export var sell_price: int = 0

## ADR-038: "" = normales Item (Standardfall). Für Schutz-Scrolls einer der
## ItemProtectionService.TYPE_*-Werte ("pve"/"theft"/"pvp") — bestimmt, WELCHEN
## Schutz das Scroll gewährt, wenn es über request_apply_protection() auf ein
## Ziel-Item angewendet wird. Bewusst auf dem Item selbst (nicht am Aufrufer)
## definiert: ItemProtectionService liest DIESES Feld serverseitig vom
## scroll_item_id aus der ItemDefinition, statt dem Client zu vertrauen, WELCHEN
## protection_type ein Scroll gewährt — ein Client könnte sonst ein billiges
## Scroll mit einem selbstgewählten protection_type="pvp" einreichen.
@export var grants_protection_type: String = ""

## ADR-039: "" = normales Item (Standardfall). Für Diebstahl-Kristalle einer
## der PickpocketService.TIER_*-Werte ("weak"/"normal"/"strong") — bestimmt
## Cooldown UND Erfolgschance-Bonus, wenn dieses Item bei einem
## Pickpocket-Versuch verbraucht wird. Serverseitig aus der ItemDefinition
## gelesen (nicht vom Client übermittelt) — exakt dieselbe
## Fälschungs-Vermeidung wie bei ItemDefinition.grants_protection_type
## (ADR-038): ein Client könnte sonst einen billigen Kristall mit
## selbstgewähltem Tier="strong" einreichen.
@export var pickpocket_crystal_tier: String = ""

## Ausrüstungs-Bonus auf Skill-XP: { skill_id | "all": Faktor } — 0.10 = +10 % XP. Gilt, solange das
## Item ausgerüstet ist, für JEDE Aktions-XP des Skills (Ernten, Schmieden, später Kochen ...),
## siehe SkillSystem.add_action_xp() und EquipmentService._apply_stat_bonus(). Leer = kein Bonus.
## "all" wirkt auf alle Skills. Serverseitig aus der ItemDefinition gelesen, nie vom Client.
@export var xp_bonus: Dictionary = {}

## Farming (Wunsch "Samen pflanzen + ernten"): "" = kein Samen (Standardfall).
## Für Samen-Items die ID der FarmCropDefinition, die dieser Samen anbaut —
## serverseitig aus der ItemDefinition des tatsächlich im Inventar
## vorhandenen Items gelesen, NIE vom Client übermittelt. Identisches
## Sicherheitsmuster wie grants_protection_type (ADR-038)/
## pickpocket_crystal_tier (ADR-039) oben: ein Client könnte sonst einen
## billigen Samen mit einer selbstgewählten, wertvolleren crop_id einreichen.
@export var plants_crop_id: String = ""
