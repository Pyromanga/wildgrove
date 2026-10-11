class_name WorldData
extends RefCounted

## WorldData — Reines Daten-Objekt für den Weltzustand.
##
## KEIN Node-Overhead — extends RefCounted (kein SceneTree nötig).
##
## KEY-SCHEMA:
##   Alle harvest-Keys verwenden das generische Format:
##     "%s_%d_%d_%d" % [type_id, int(x), int(y), int(z)]
##   Beispiele: "oak_tree_5_0_5", "iron_ore_-3_0_2", "copper_ore_8_0_4"
##
##   mark_harvested() schreibt dieses Format (via HarvestableEntity.on_despawn).
##   is_harvested_by_type() und unmark_harvested() lesen dasselbe Format.
##
## Nur ein Schema für Positionen (typed_tree_positions/typed_ore_positions) —
## das frühere parallele untyped tree_positions/ore_positions-Array (jeder Baum
## automatisch "oak_tree", jedes Erz "iron_ore") wurde entfernt (Round-38-Cleanup):
## es war als "Abwärtskompatibilität" markiert, hatte aber nie echte alte Saves zu
## bedienen und wurde nie durch echte Prozedural-Generierung befüllt.

## Typisierte Positionen: { type_id: Array[Vector3] }
## Ermöglicht gemischte Baumtypen an unterschiedlichen Positionen.
var typed_tree_positions: Dictionary = {}
## Typisierte Erzpositionen: { type_id: Array[Vector3] }
var typed_ore_positions: Dictionary = {}
var player_position:   Vector3 = Vector3.ZERO
## Set once at world creation. Passed to ChunkManager so terrain is deterministic
## across sessions, reloads, and between server and client.
var world_seed:        int = 0
## Format: { "oak_tree_5_0_5": true, "iron_ore_-3_0_2": true }
var harvested_objects: Dictionary = {}

## Wunsch "Bäume ... über Spieltage hinweg wachsen": Pflanz-Tag (WorldTimeService.day_count zum
## Zeitpunkt des Respawns) je nachgewachsenem Baum — Geschwister-Feld zu harvested_objects,
## gleiches Schema/Schlüssel (make_key()). NUR für Bäume gesetzt, die tatsächlich schon einmal
## gefällt wurden und nachgewachsen sind (siehe RespawnService → WorldService.spawn_entity()-
## Callback in on_ready()); ein Baum, der noch nie gefällt wurde (originaler Weltbestand beim
## Chunk-Laden), hat hier KEINEN Eintrag und gilt als "schon immer da" (ausgewachsen) — siehe
## TreeGrowthStage.gd für die Unterscheidung "statische Wald-Varietät" vs. "echtes Nachwachsen".
## Format: { "oak_tree_5_0_5": 42 } — 42 = Tag, an dem der Baum zuletzt (wieder) gepflanzt wurde.
var planted_day: Dictionary = {}

## Spieler-Änderungen am Gelände (Graben/Aufschütten/Einebnen) als Delta zum prozeduralen
## Terrain. NIE die Instanz austauschen, nur laden/ändern (load_save()): TerrainField
## hält dieselbe Referenz. Siehe TerrainEditLayer.
var terrain_edits: TerrainEditLayer = TerrainEditLayer.new()

## Von Spielern abgelegtes Bodenmaterial (2026-09-26, "Sand aus der Wüste im
## Wald ablegen und es bleibt Sand") — Geschwister-Feld zu terrain_edits,
## gleiches Muster: NIE die Instanz austauschen, TerrainField hält dieselbe
## Referenz. Siehe TerrainMaterialLayer.
var terrain_materials: TerrainMaterialLayer = TerrainMaterialLayer.new()

## Zustand bepflanzter Felder (2026-09-27, "bepflanzte Felder nicht
## persistent") — siehe FarmPlotRegistry. NIE die Instanz austauschen.
var farm_plots: FarmPlotRegistry = FarmPlotRegistry.new()

## Leitern (Klettern aus tiefen Gruben) und Funde (Erz/Edelsteine, die beim Graben freiliegen) —
## wie build_registry die Wahrheit; die Nodes sind nur Ansichten. NIE die Instanz austauschen.
var ladders: LadderRegistry = LadderRegistry.new()
var dig_finds: DigFindRegistry = DigFindRegistry.new()

## Alle gebauten Bauteile (Wände, Böden, ...) als Records — die Wahrheit; die 3D-Nodes
## sind nur eine Ansicht, siehe BuildRegistry/WorldBuildHandler.
var build_registry: BuildRegistry = BuildRegistry.new()

## BUG-C-FIX (HP wird nicht gespeichert): pro-Spieler HP-Zustand, analog zu
## "saved_pets" (siehe WorldService.collect_and_store_pet_data()). Format:
## { player_id: { "current": int, "max": int } }. player_id ist die stabile
## Charakter-UUID (siehe Player._resolve_player_uuid()), NICHT die peer_id —
## identisch zum Muster bei Pets (owner_player_id) und aus demselben Grund
## (peer_id ist bei Charakter-Wechsel ohne Verbindungstrennung nicht stabil).
var player_health: Dictionary = {}

## Fügt eine typisierte Baum-Position ein.
## type_id: z.B. "oak_tree", "willow_tree", "maple_tree"
func add_typed_tree(type_id: String, pos: Vector3) -> void:
	if not typed_tree_positions.has(type_id):
		typed_tree_positions[type_id] = []
	if not pos in typed_tree_positions[type_id]:
		typed_tree_positions[type_id].append(pos)

## Fügt eine typisierte Erz-Position ein.
## type_id: z.B. "iron_ore", "copper_ore"
func add_typed_ore(type_id: String, pos: Vector3) -> void:
	if not typed_ore_positions.has(type_id):
		typed_ore_positions[type_id] = []
	if not pos in typed_ore_positions[type_id]:
		typed_ore_positions[type_id].append(pos)

## Einheitlicher Harvest-Marker. Format: "type_id_x_y_z"
## Wird von HarvestableEntity.on_despawn() und WorldService.mark_harvested() aufgerufen.
func mark_harvested(key: String) -> void:
	harvested_objects[key] = true
	AppLogger.log_debug("Als geerntet markiert: '%s'." % key, "WorldData")

## Prüft ob eine Position für einen bestimmten Typ geerntet wurde.
## Verwendet das einheitliche Schema: "type_id_x_y_z"
func is_harvested_by_type(type_id: String, pos: Vector3) -> bool:
	return harvested_objects.has(make_key(type_id, pos))

## Entfernt den Harvested-Marker — aufgerufen durch RespawnService._remove_cb.
## Verwendet einheitlich das generische Schema für alle type_ids.
func unmark_harvested(type_id: String, pos: Vector3) -> void:
	var key := make_key(type_id, pos)
	if harvested_objects.erase(key):
		AppLogger.log_debug("Harvested-Marker '%s' entfernt." % key, "WorldData")
	else:
		AppLogger.log_warn("unmark_harvested: Key '%s' nicht gefunden." % key, "WorldData")

## Setzt/überschreibt den Pflanz-Tag für einen nachgewachsenen Baum. Aufgerufen vom
## spawn_callback in WorldService.on_ready() bei jedem Respawn (nicht beim initialen
## Welt-Aufbau — dort ist type_id/pos-Schema identisch, ein Aufruf würde aber jedem
## ursprünglichen Baum fälschlich einen "Pflanz-Tag 0" verpassen, siehe Feldkommentar).
func mark_planted(type_id: String, pos: Vector3, day: int) -> void:
	planted_day[make_key(type_id, pos)] = day

## -1 wenn kein Eintrag existiert (= originaler Weltbestand, siehe Feldkommentar).
func get_planted_day(type_id: String, pos: Vector3) -> int:
	return planted_day.get(make_key(type_id, pos), -1)

func get_tree_count() -> int:
	var total := 0
	for type_id in typed_tree_positions:
		total += (typed_tree_positions[type_id] as Array).size()
	return total

func get_ore_count() -> int:
	var total := 0
	for type_id in typed_ore_positions:
		total += (typed_ore_positions[type_id] as Array).size()
	return total

# ─────────────────────────────────────────────
# Intern — deterministische Key-Generierung
# ─────────────────────────────────────────────

## Einheitlicher Key für alle Entity-Typen.
## Format: "type_id_x_y_z" — locale-unabhängig, int-gecasted.
## Beispiel: make_key("oak_tree", Vector3(5,0,5)) → "oak_tree_5_0_5"
static func make_key(type_id: String, pos: Vector3) -> String:
	return "%s_%d_%d_%d" % [type_id, int(pos.x), int(pos.y), int(pos.z)]
