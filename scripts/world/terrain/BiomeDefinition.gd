# res://scripts/world/terrain/BiomeDefinition.gd
class_name BiomeDefinition extends Resource

## BiomeDefinition — Daten-Resource für ein Welt-Biom.
##
## Jedes Biom definiert Farben, Vegetation und Strukturen.
## Wird von WorldGenerationService via Noise-Sampling ausgewählt.

@export var biome_id: String = ""
@export var display_name: String = ""

## Terrain-Farben
@export var terrain_color_grass: Color = Color(0.2, 0.55, 0.15)
@export var terrain_color_dirt:  Color = Color(0.45, 0.30, 0.15)
@export var terrain_color_rock:  Color = Color(0.45, 0.45, 0.45)

## Natürliches Bodenmaterial dieses Bioms beim Graben (2026-09-26, "natürlich
## Erde/Sand je nach Biom spawnen") — Item-ID aus data/items/. Siehe
## TerrainField.get_material_at() für die volle Auflösungsreihenfolge
## (abgelegtes Material > Kies-Unterboden ab einer gewissen Tiefe >
## dieses Feld) und BiomeRegistry für die Werte pro Biom.
@export var surface_material: String = "dirt"

## Spawn-Wahrscheinlichkeiten: prop_id → chance (0.0–1.0 pro Tile)
@export var prop_chances: Dictionary = {}

## Spawn-Wahrscheinlichkeiten für Gegner: enemy_type_id → chance (0.0–1.0 pro
## Chunk). Bewusst getrennt von prop_chances (Round 75) — Gegner sind
## `EntityOrchestrator`-Gruppe "enemies" (Kampf/AI), keine Deko/Harvestables
## wie Bäume/Erze. Siehe ChunkEntitySpawner._spawn_enemy() und
## WorldEntityRegistry.KNOWN_ENEMY_TYPES (nur dort registrierte Typen werden
## tatsächlich gespawnt, alles andere wird gefiltert — siehe dortiger Kommentar).
@export var enemy_chances: Dictionary = {}

## Strukturen die in diesem Biom spawnen können
@export var structure_types: Array[String] = []

## Optionale Atmosphäre
@export var fog_density: float = 0.0
@export var snow_coverage: float = 0.0   # 0.0 = kein Schnee, 1.0 = voll

## Deko-Vegetation (2026-10-05, Wunsch "Landschaft wirkt leer — Büsche und Gras fehlen"):
## wird NICHT als Entity gespawnt, sondern pro Chunk als MultiMesh gezeichnet (siehe
## ChunkVegetationBuilder) — keine Interaktion, keine Kollision, praktisch keine Node-Kosten.
## Anzahl Versuche pro Chunk (64 m × 64 m); Wasser, Steilhänge und umgegrabener/abgelegter
## Boden werden beim Platzieren aussortiert, die tatsächliche Zahl liegt darunter.
@export var grass_per_chunk: int = 0
@export var bush_per_chunk: int = 0
## Grasfarben: Basis (unten am Halm) und Spitze. Standard = dunkleres/helleres Grün.
@export var grass_color_base: Color = Color(0.16, 0.36, 0.10)
@export var grass_color_tip:  Color = Color(0.40, 0.62, 0.20)
## Busch-Grundfarbe (pro Busch leicht variiert).
@export var bush_color: Color = Color(0.18, 0.40, 0.14)

## Versuche pro Chunk für Props (Bäume, Pilze, Steine ...). 0 = globaler Standard aus
## ChunkEntitySpawner (siehe dort). Dichte Biome (Wald) brauchen mehr Versuche als Wüste.
@export var prop_attempts_min: int = 0
@export var prop_attempts_max: int = 0

## Blumen (2026-10-06, "es fehlen Blumen"): ebenfalls MultiMesh-Deko (siehe ChunkVegetationBuilder),
## aber in FARBFLECKEN statt gleichverteilt — ein Beet gehört zu EINER Farbe aus flower_colors.
## flower_per_chunk = Blumen pro Chunk insgesamt (verteilt auf ~4 Flecken). Leer/0 = keine.
## Mit der Sense (tool_scythe) lassen sie sich zusammen mit dem Gras mähen.
@export var flower_per_chunk: int = 0
@export var flower_colors: Array[Color] = []

