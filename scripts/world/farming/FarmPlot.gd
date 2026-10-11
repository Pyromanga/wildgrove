extends StaticBody3D
class_name FarmPlot

## FarmPlot — Pflanzbarer Beet-/Pflanzplatz (Wunsch "Farming: Samen pflanzen + ernten").
##
## Försterei-Erweiterung (Wunsch "Försterei-Skill: Setzlinge kaufen +
## pflanzen"): dieselbe Klasse trägt jetzt auch Baum-Setzlinge, nicht nur
## Feldfrüchte — welcher Skill beim Ernten XP gibt (farming vs. forestry)
## steht in FarmCropDefinition.skill_id, nicht hier am Node. Ein Plot mit
## cfg["crop_id"]="oak_sapling" (siehe WorldSpawner.spawn_all()) ist also ein
## Baumschul-Platz, exakt dieselbe EMPTY→GROWING→READY-Maschine wie ein
## Karottenbeet — kein eigenes TreePlot-Skript nötig.
##
## Anders als HarvestableEntity (Baum/Erz): despawnt NICHT nach der Ernte,
## sondern durchläuft wiederholt eine Zustandsmaschine EMPTY → GROWING →
## READY → (Ernte) → EMPTY. Deshalb eigenes, schlankes Skript statt
## HarvestableEntity-Subklasse — dessen on_despawn()/on_spawn()-Lifecycle ist
## auf "einmal ernten, dann weg" zugeschnitten (siehe dortiger
## Klassenkommentar "Despawn via EntityOrchestrator"), das passt hier nicht.
##
## _crop_id ist PRO PLOT fest (via on_spawn(cfg), Default "carrot") — kein
## Samen-Auswahl-UI wie bei ADR-038s Scrolls. Ein Plot baut also immer
## dieselbe Feldfrucht an; mehrere Feldfrucht-Typen bedeuten aktuell mehrere
## Plots mit unterschiedlicher cfg["crop_id"], keine Auswahl pro Interaktion.
## (Follow-up, falls gewünscht: Auswahl-UI analog InventoryUIController._
## on_scroll_selected(), dann crop_id vom Client-Klick statt fix am Node.)
##
## Bewusst NICHT an WorldTime/Tag-Nacht-Zyklus gekoppelt — ein einfacher,
## nur auf der Autorität laufender Timer (Echtzeit-Sekunden aus
## FarmCropDefinition.growth_seconds). Wachstum läuft weiter, während kein
## Spieler in der Nähe ist (kein Pausieren außerhalb der ProximityDetector-
## Reichweite) — bewusst einfach für den ersten Wurf.
##
## PERSISTENZ (2026-09-27 behoben, "bepflanzte Felder nicht persistent"):
## stage + ready_at werden über WorldService.get_farm_plots()
## (FarmPlotRegistry, Sparse-Registry analog TerrainMaterialLayer) unter
## einem Positions-Key gespeichert (WorldData.make_key("farm_plot",
## global_position) — FarmPlots stehen an festen, deterministischen
## Dorf-Layout-Positionen, ein Positions-Key ist also stabil über Save/Load
## hinweg). ready_at ist ein ABSOLUTER Unix-Zeitstempel, kein "verbleibende
## Sekunden"-Wert — konsequent zu Ende gedacht im Sinne des Kommentars oben
## ("Wachstum läuft weiter, während kein Spieler in der Nähe ist"): eine
## Pflanze wächst dadurch auch weiter, während die App komplett zu ist, statt
## bei jedem Neuladen wieder bei voller Wachstumsdauer anzufangen. War die
## App länger zu als die Wachstumsdauer, ist der Plot beim nächsten
## on_spawn() sofort READY statt erst nach einem neuen vollen Timer-Lauf.
## _crop_id wird BEWUSST NICHT mitgespeichert, siehe FarmPlotRegistry-
## Klassenkommentar (Spawn-Zeit-Konstante, keine Spieler-Daten).
##
## BEKANNTE EINSCHRÄNKUNG (Baum-Setzlinge): _spawn_grown_tree() spawnt den
## echten Baum exakt an der Plot-Position — das Bodenbeet-Mesh (1.2×0.2×1.2,
## siehe _build_visuals()) bleibt danach unverändert am selben Fleck stehen,
## Baum-Mesh und Beet überlappen sich also sichtbar. Rein kosmetisch (keine
## Gameplay-Auswirkung, das Beet ist ab da wieder EMPTY/bepflanzbar) — für
## den ersten Wurf akzeptiert statt eines eigenen "Baumschul"-Visuals.
##
## AUTORITÄTS-ROUTING: wie VillagerNPC/EnemyNPC — set_multiplayer_authority(1),
## InteractableComponent._handle_completion() routet Klicks von Clients
## bereits generisch zur Autorität, kein eigener Netzwerk-Zweig nötig.
##
## SYNC: stage (int) wird über MultiplayerSynchronizer repliziert (10 Hz,
## wie EnemyNPC-Position) — Clients sehen dadurch Wachstum/Ernte visuell,
## auch wenn sie selbst nicht Autorität sind. _crop_id wird NICHT repliziert:
## es ist eine Spawn-Zeit-Konstante, auf allen Peers bereits identisch (wie
## world_seed-abgeleitete Werte bei anderen Entities), kein Laufzeit-Sync nötig.

enum Stage { EMPTY, GROWING, READY }

const LOG_CAT := "FarmPlot"
## Fallback, falls (Daten-Fehler) keine FarmCropDefinition geladen werden
## konnte — der Normalfall liest die Skill-ID aus _crop_def.skill_id (Försterei-
## Erweiterung, siehe FarmCropDefinition.gd), NICHT mehr diese Konstante.
const SKILL_ID := "farming"

## Wird von MultiplayerSynchronizer repliziert — der inline-Setter sorgt
## dafür, dass sowohl die Autorität (lokale Zuweisung unten) als auch
## Clients (Sync-Schreibzugriff) automatisch die Visuals/Interactable-Daten
## nachziehen, ohne zwei getrennte Code-Pfade pflegen zu müssen.
var stage: int = Stage.EMPTY:
	set(value):
		stage = value
		_apply_stage(value)

var _crop_id: String = "carrot"
var _crop_def: FarmCropDefinition = null

## Persistenz (2026-09-27, siehe Klassenkommentar "PERSISTENZ"). _save_key
## steht ab on_spawn() fest (global_position ist dann schon final gesetzt).
## _ready_at ist nur während Stage.GROWING aussagekräftig.
var _save_key: String = ""
var _ready_at: float = 0.0

var _interactable_comp: InteractableComponent = null
var _soil_mesh: MeshInstance3D = null
var _growth_timer: Timer = null
var _ctx: IEntityContext = null
var _data: DataService = null

func _ready() -> void:
	set_multiplayer_authority(1)
	if name == get_class() or name.begins_with("@"):
		name = "farm_plot_%d" % (get_instance_id() % 9999)
	_build_visuals()
	_setup_interactable()
	_setup_multiplayer_sync()
	_growth_timer = Timer.new()
	_growth_timer.name = "GrowthTimer"
	_growth_timer.one_shot = true
	_growth_timer.timeout.connect(_on_growth_finished)
	add_child(_growth_timer)
	AppLogger.log_debug("FarmPlot '%s' bereit (crop='%s')." % [name, _crop_id], LOG_CAT)

# ─────────────────────────────────────────────
# Visuals
# ─────────────────────────────────────────────

func _build_visuals() -> void:
	_soil_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 0.2, 1.2)
	_soil_mesh.mesh = box
	_soil_mesh.position.y = 0.1
	add_child(_soil_mesh)

	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.2, 0.2, 1.2)
	col.shape = sh
	col.position.y = 0.1
	add_child(col)

	_apply_stage(stage)

## Rein visuelles Feedback (Placeholder — kein Factory3D.create_*() für Crops
## vorhanden, anders als bei den Nature-Props). Farbe/Höhe ändern sich je
## Zustand: brauner Boden (EMPTY) → grüner Trieb (GROWING) → oranger,
## erhöhter "voller" Zustand (READY).
func _update_soil_color() -> void:
	if not is_instance_valid(_soil_mesh):
		return
	var mat := StandardMaterial3D.new()
	match stage:
		Stage.EMPTY:
			mat.albedo_color = Color(0.35, 0.22, 0.10)
			_soil_mesh.scale.y = 1.0
		Stage.GROWING:
			mat.albedo_color = Color(0.30, 0.55, 0.20)
			_soil_mesh.scale.y = 1.5
		Stage.READY:
			mat.albedo_color = Color(0.85, 0.50, 0.10)
			_soil_mesh.scale.y = 2.0
	_soil_mesh.material_override = mat

# ─────────────────────────────────────────────
# Interaktion
# ─────────────────────────────────────────────

func _setup_interactable() -> void:
	var d := InteractableData.new()
	_interactable_comp = InteractableComponent.new()
	_interactable_comp.data = d
	add_child(_interactable_comp)
	_interactable_comp.interacted.connect(_on_interacted)
	_refresh_interactable_data()

## Aktualisiert die (einzige) InteractableData passend zum aktuellen stage —
## get_actions() in InteractableComponent liest data live bei jedem Aufruf,
## eine In-Place-Mutation reicht also, kein Neuaufbau der Komponente nötig.
func _refresh_interactable_data() -> void:
	if not is_instance_valid(_interactable_comp):
		return
	var d := _interactable_comp.data
	var crop_name := _crop_def.display_name if is_instance_valid(_crop_def) else "etwas"
	match stage:
		Stage.EMPTY:
			d.id           = "plant_seed"
			d.label        = "Pflanzen"
			d.duration     = 1.0
			d.xp_type      = "none"
			d.xp_amount    = 0
			d.loot_table   = null
			d.inspect_text = "Ein leerer Pflanzplatz. Braucht Samen oder einen Setzling."
		Stage.GROWING:
			d.id           = "inspect_growing_plot"
			d.label        = "Beobachten"
			d.duration     = 0.0
			d.xp_type      = "none"
			d.xp_amount    = 0
			d.loot_table   = null
			d.inspect_text = "Hier wächst %s. Noch nicht so weit." % crop_name
		Stage.READY:
			var is_tree := is_instance_valid(_crop_def) and not _crop_def.grows_into_entity_type.is_empty()
			d.id           = "harvest_crop"
			d.label        = "Baum wachsen lassen" if is_tree else "Ernten"
			d.duration     = 1.5
			# Försterei-Erweiterung: xp_type kommt aus der Crop-Definition
			# (skill_id, Default "farming"), nicht mehr aus der SKILL_ID-Konstante
			# — so tragen dieselben Plots auch Baum-Setzlinge mit "forestry"-XP.
			d.xp_type      = _crop_def.skill_id if is_instance_valid(_crop_def) else SKILL_ID
			d.xp_amount    = _crop_def.xp_amount if is_instance_valid(_crop_def) else 0
			# Baum-Setzlinge haben keine eigene Loot-Tabelle mehr (leere
			# harvest_loot_table_id → _resolve_loot_table() liefert bereits null) —
			# das Holz kommt erst später vom gespawnten Baum selbst, siehe
			# _try_harvest()/FarmCropDefinition.grows_into_entity_type.
			d.loot_table   = _resolve_loot_table()
			d.inspect_text = (
				"%s ist ausgewachsen und schlägt gerade Wurzeln als richtiger Baum." % crop_name
				if is_tree else "%s ist bereit!" % crop_name
			)

func _resolve_loot_table() -> LootTable:
	if not is_instance_valid(_crop_def) or not is_instance_valid(_data):
		return null
	return _data.get_loot_table(_crop_def.harvest_loot_table_id)

## Zentraler Stage-Change-Hook — läuft sowohl lokal (Autorität setzt `stage =`)
## als auch auf Clients (MultiplayerSynchronizer schreibt über den Setter).
## Deshalb rein darstellend/daten-aktualisierend, KEINE Gameplay-Wirkung
## (Inventar/XP) hier — die läuft ausschließlich autoritätsseitig in
## _on_interacted().
func _apply_stage(_new_stage: int) -> void:
	if not is_inside_tree():
		return  # Setter kann vor _ready() laufen (initiale Property-Zuweisung).
	_update_soil_color()
	_refresh_interactable_data()

func _on_interacted(action_id: String, peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	if not is_instance_valid(_ctx):
		AppLogger.log_error("_on_interacted(): kein EntityContext gespeichert.", LOG_CAT)
		return

	match action_id:
		"plant_seed":
			_try_plant(peer_id)
		"harvest_crop":
			_try_harvest(peer_id)
		# "inspect_growing_plot": kein Effekt — reine Inspect-Aktion.

func _try_plant(peer_id: int) -> void:
	if stage != Stage.EMPTY:
		return
	if not is_instance_valid(_crop_def):
		AppLogger.log_error("_try_plant(): keine FarmCropDefinition für '%s'." % _crop_id, LOG_CAT)
		return

	var inventory: InventorySystem = _ctx.get_inventory()
	var network: NetworkBridge = _ctx.get_network_bridge()
	var player_id := network.get_player_id_for_peer(peer_id) if is_instance_valid(network) else ""
	if player_id.is_empty() or not is_instance_valid(inventory):
		AppLogger.log_warn("_try_plant(): player_id/Inventory nicht verfügbar — Pflanzen verweigert.", LOG_CAT)
		return

	# Konsistenz-Guard: das ItemDefinition.plants_crop_id des konfigurierten
	# Samen-Items muss tatsächlich zu dieser Plot-Crop passen — fängt
	# Daten-Autoren-Fehler (falsche seed_item_id in der .tres verdrahtet) ab,
	# analog zum VALID_TIERS-Check bei den Diebstahl-Kristallen.
	var seed_def: ItemDefinition = inventory.get_item_info(_crop_def.seed_item_id)
	if not is_instance_valid(seed_def) or seed_def.plants_crop_id != _crop_id:
		AppLogger.log_error(
			"_try_plant(): seed_item_id '%s' von Crop '%s' hat kein passendes plants_crop_id — Daten-Fehler."
			% [_crop_def.seed_item_id, _crop_id],
			LOG_CAT
		)
		return
	if not inventory.has_item(_crop_def.seed_item_id, player_id, 1):
		# Absicht-statt-Wert (ADR-004): Aktion bleibt sichtbar, auch ohne
		# Samen — analog Pickpocket/Angriff ohne passendes Item/Waffe. Kein
		# eigener Notification-Kanal für diesen ersten Wurf, siehe
		# Klassenkommentar "PERSISTENZ" für weitere bekannte Lücken.
		AppLogger.log_info(
			"_try_plant(): Spieler '%s' hat keinen '%s' — Pflanzen abgebrochen." % [player_id, _crop_def.seed_item_id],
			LOG_CAT
		)
		return
	if not inventory.remove_item(_crop_def.seed_item_id, player_id, 1):
		return

	stage = Stage.GROWING
	_ready_at = Time.get_unix_time_from_system() + _crop_def.growth_seconds
	_growth_timer.start(_crop_def.growth_seconds)
	_save_state()
	AppLogger.log_info(
		"'%s' gepflanzt von '%s' — reif in %.0fs." % [_crop_id, player_id, _crop_def.growth_seconds],
		LOG_CAT
	)

func _on_growth_finished() -> void:
	if not is_multiplayer_authority():
		return
	if stage != Stage.GROWING:
		return
	stage = Stage.READY
	_save_state()

## Ernte läuft über denselben InteractionResolver-Pfad wie HarvestableEntity/
## EnemyNPC (Loot-Roll + XP aus der InteractableData, siehe _refresh_
## interactable_data()) — kein eigener Inventar-/XP-Code nötig, bleibt
## dadurch konsistent mit yield_stat_id-Skalierung etc.
func _try_harvest(peer_id: int) -> void:
	if stage != Stage.READY:
		return
	var network: NetworkBridge = _ctx.get_network_bridge()
	var bus: IEventBus = _ctx.get_event_bus()
	var player_id := network.get_player_id_for_peer(peer_id) if is_instance_valid(network) else ""
	InteractionResolver.resolve(_interactable_comp.data, peer_id, player_id, bus, _ctx.get_stat_modifiers())
	# Wunsch "natürlich spawnen lassen": bei einem Baum-Setzling ersetzt das
	# nicht die Loot-Ausschüttung (die gibt's hier nicht, siehe
	# grows_into_entity_type-Klassenkommentar), sondern spawnt zusätzlich den
	# echten Baum an der Plot-Position — danach ist es ein ganz normaler
	# natürlicher Baum (Fällen/Respawn laufen komplett über OakTree/MapleTree/
	# PineTree/WillowTree + RespawnService, kein Sonderfall mehr hier).
	if is_instance_valid(_crop_def) and not _crop_def.grows_into_entity_type.is_empty():
		_spawn_grown_tree(_crop_def.grows_into_entity_type)
	stage = Stage.EMPTY
	_ready_at = 0.0
	_save_state()
	AppLogger.log_info("'%s' geerntet von Peer %d — Beet wieder leer." % [_crop_id, peer_id], LOG_CAT)

## Schreibt den aktuellen Zustand in die FarmPlotRegistry (siehe
## Klassenkommentar "PERSISTENZ"). stage == EMPTY löscht den Eintrag dort
## (Sparse-Prinzip) statt ihn explizit zu speichern.
func _save_state() -> void:
	if _save_key.is_empty() or not is_instance_valid(_ctx):
		return
	var world: WorldService = _ctx.get_world()
	if not is_instance_valid(world) or not is_instance_valid(world.get_farm_plots()):
		return
	world.get_farm_plots().set_state(_save_key, stage, _ready_at)

func _spawn_grown_tree(entity_type: String) -> void:
	var world: WorldService = _ctx.get_world() if is_instance_valid(_ctx) else null
	if not is_instance_valid(world):
		AppLogger.log_error(
			"_spawn_grown_tree(): kein WorldService im EntityContext — '%s' konnte nicht spawnen." % entity_type,
			LOG_CAT
		)
		return
	var tree := world.spawn_entity(entity_type, global_position)
	if is_instance_valid(tree):
		AppLogger.log_info("Setzling ausgewachsen: '%s' @ %s." % [entity_type, str(global_position)], LOG_CAT)
	else:
		AppLogger.log_error("_spawn_grown_tree(): spawn_entity('%s') fehlgeschlagen." % entity_type, LOG_CAT)

# ─────────────────────────────────────────────
# Multiplayer-Sync
# ─────────────────────────────────────────────

func _setup_multiplayer_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSync"
	sync.replication_interval = 0.1  # 10 Hz, analog EnemyNPC-Positions-Sync.
	add_child(sync)
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:stage"))
	sync.replication_config = config

# ─────────────────────────────────────────────
# EntityOrchestrator-Interface
# ─────────────────────────────────────────────

func on_spawn(cfg: Dictionary = {}, ctx: IEntityContext = null) -> void:
	_ctx = ctx
	if cfg.has("crop_id"):
		_crop_id = cfg["crop_id"]
	_data = ctx.get_data() if is_instance_valid(ctx) else null
	if is_instance_valid(_data):
		_crop_def = _data.get_crop_definition(_crop_id)
	else:
		AppLogger.log_error("on_spawn(): kein DataService im EntityContext — Farming-Daten fehlen.", LOG_CAT)
	# Pool-Reuse-Guard (wie HarvestableEntity._clear_visuals()): _ready() läuft
	# bei einer aus dem EntityPool wiederverwendeten Instanz kein zweites Mal,
	# ein zurückgegebener Plot könnte also mit altem GROWING/READY-Zustand
	# wieder auftauchen. Timer explizit stoppen, sonst könnte ein alter
	# Timeout aus der vorherigen Nutzung noch nachfeuern.
	if is_instance_valid(_growth_timer):
		_growth_timer.stop()

	# Bugfix 2026-09-27 ("bepflanzte Felder nicht persistent"): vorher IMMER
	# EMPTY, unabhängig davon, was vorher gepflanzt war (siehe Klassenkommentar
	# "PERSISTENZ"). global_position steht hier bereits fest (WorldSpawner
	# setzt die Position vor on_spawn()), der Speicher-Key lässt sich also
	# schon bilden.
	_save_key = WorldData.make_key("farm_plot", global_position)
	var world: WorldService = _ctx.get_world() if is_instance_valid(_ctx) else null
	var saved: Dictionary = (
		world.get_farm_plots().get_state(_save_key)
		if (is_instance_valid(world) and is_instance_valid(world.get_farm_plots()))
		else {}
	)

	if saved.is_empty():
		stage = Stage.EMPTY
		return

	var saved_stage: int = int(saved.get("stage", Stage.EMPTY))
	_ready_at = float(saved.get("ready_at", 0.0))

	match saved_stage:
		Stage.READY:
			stage = Stage.READY
		Stage.GROWING:
			var remaining: float = _ready_at - Time.get_unix_time_from_system()
			if remaining <= 0.0:
				# War die App länger zu als die Wachstumsdauer — sofort reif,
				# kein künstliches Warten auf einen längst abgelaufenen Timer.
				stage = Stage.READY
				_save_state()  # ready_at war für GROWING gedacht, jetzt READY persistieren.
			else:
				stage = Stage.GROWING
				_growth_timer.start(remaining)
		_:
			stage = Stage.EMPTY

func on_despawn() -> void:
	if is_instance_valid(_growth_timer):
		_growth_timer.stop()
