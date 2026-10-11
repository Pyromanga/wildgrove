# InteractableData.gd
extends Resource
class_name InteractableData

## id: Eindeutiger Bezeichner der Aktion (z.B. "chop", "mine_iron", "attack_enemy").
## Wird von InteractableComponent für Signale und Bar-Zuordnung genutzt.
## Konvention: "<verb>_<objekttyp>", alles lowercase, kein Leerzeichen.
@export var id: String = "interact"
@export var label: String = "Interagieren"
@export var duration: float = 1.5
@export var xp_type: String = "none"
@export var xp_amount: int = 10
## loot_table: Datengetriebene Drop-Tabelle (LootTable.tres). Optional — null
## bedeutet keine Drops (z.B. QuestNPC, Tiere, Angriffs-Interactables von Feinden,
## die stattdessen über EnemyNPC._loot_table_id + DataService droppen).
@export var loot_table: LootTable
## yield_stat_id: Stat-Name für StatModifierService.get_effective_stat(), der die
## Drop-Menge dieser Interaktion skaliert (z.B. "gathering_yield_wood" für Bäume).
## Leer = keine Skalierung, LootTable.roll() bekommt multiplier=1.0.
@export var yield_stat_id: String = ""
## speed_stat_id: Stat-Name für StatModifierService.get_effective_stat(), der
## die DAUER dieser Interaktion skaliert (Werkzeug-Boni, z.B. "gathering_speed_wood"
## für eine Axt). Effektiv-Multiplikator > 1.0 verkürzt duration entsprechend —
## siehe InteractionExecutor.execute_action(). Leer = keine Skalierung.
@export var speed_stat_id: String = ""
@export var inspect_text: String = ""
