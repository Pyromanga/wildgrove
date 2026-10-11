class_name FarmCropDefinition
extends Resource

## FarmCropDefinition — Datengetriebene Konfiguration EINER Feldfrucht.
##
## Analog zu CombatProfile (TD-10)/SkillDefinition: statische, in
## DataService geladene Ressource statt Hardcode im Entity-Skript. Neue
## Feldfrüchte (Kartoffel, Weizen, …) brauchen nur eine neue .tres-Datei
## + Eintrag in DataManifest.CROPS + Samen-/Ernte-Items — kein Code-Änderung
## an FarmPlot.gd nötig.
##
## seed_item_id/harvest_item_id verweisen auf ItemDefinition-IDs (DataService.
## get_item()). growth_seconds ist Echtzeit (kein WorldTime/Tag-Nacht-Zyklus
## verdrahtet — siehe FarmPlot.gd Klassenkommentar "Bewusst NICHT").

@export var id: String = ""
@export var display_name: String = ""
@export var seed_item_id: String = ""
@export var harvest_loot_table_id: String = ""
## XP-Skill für die Ernte — FarmPlot._on_interacted() nutzt InteractionResolver.
## resolve() genau wie HarvestableEntity, xp_type kommt aus der
## InteractableData der "harvest_crop"-Aktion, nicht direkt von hier
## (Konsistenz mit dem bestehenden Resolver-Pfad).
@export var xp_amount: int = 15
@export var growth_seconds: float = 45.0

## Försterei (Wunsch "Försterei-Skill: Setzlinge kaufen + pflanzen"): welche
## SkillDefinition-ID beim Ernten XP bekommt. Default "farming" (Ackerbeete
## bleiben unverändert). Ein FarmPlot ist damit nicht länger zwangsläufig ein
## Ackerbeet — dieselbe Zustandsmaschine (EMPTY → GROWING → READY) trägt auch
## Baum-Setzlinge, nur mit skill_id="forestry" statt "farming" und einer
## Baum-LootTable (z.B. loot_oak_tree.tres) statt einer Ernte-LootTable. Kein
## neues Entity-Skript nötig — siehe FarmPlot.gd Klassenkommentar.
@export var skill_id: String = "farming"

## Wunsch "für alle Baumarten ausbauen + natürlich spawnen lassen": wenn
## gesetzt (z.B. "oak_tree"), ist dies KEINE Feldfrucht mit direktem
## Loot-Ertrag mehr, sondern ein Baum-Setzling. FarmPlot._try_harvest()
## spawnt dann bei READY den echten, registrierten Entity-Typ (siehe
## WorldEntityRegistry.KNOWN_PROP_TYPES — muss dort bereits existieren, z.B.
## OakTree.gd) an der Plot-Position über WorldService.spawn_entity(), statt
## eine harvest_loot_table_id auszurollen. Der gespawnte Baum ist danach ein
## GANZ NORMALER, natürlicher Baum — exakt derselbe Typ, den ChunkEntitySpawner
## auch im Wald verteilt (inkl. RespawnService-Respawn nach dem Fällen, siehe
## WorldService.on_ready()). harvest_loot_table_id bleibt in diesem Fall leer:
## das eigentliche Holz kommt aus dem späteren Fällen des Baums (Woodcutting-
## XP + LogXY-Item), NICHT aus dem Pflanzplatz selbst — xp_amount hier ist
## reine Försterei-XP fürs erfolgreiche Aufziehen.
@export var grows_into_entity_type: String = ""
