class_name WorldEvents extends BaseEvents

## WorldEvents.gd
## Alle weltbezogenen Signals.
##
## Namenskonvention: emit_*() Methoden für jeden Event.
## Controller/Services connecten auf die raw signals.

### nicht per label (doppelte "Eiche fällen"-Labels würden alle Bars gleichzeitig zeigen).
signal interaction_started(action_id: String, label: String, duration: float)
signal interaction_finished(action_id: String, label: String)
signal interaction_cancelled(action_id: String, label: String)
signal chunk_loaded(chunk_id: Vector2i)
signal chunk_unloaded(chunk_id: Vector2i)
signal time_of_day_changed(hour: int)

## ADR-041: Wetter geändert. Wird von WeatherService.roll_for_day() emittiert,
## einmal pro Ingame-Tag, deterministisch pro Peer (kein RPC, siehe dortiger
## Klassenkommentar). new_weather/old_weather sind Keys aus WeatherService.WEATHER_TYPES.
signal weather_changed(new_weather: String, old_weather: String)

## Wird von WorldService emittiert sobald die Spielwelt-Szene vollständig im Tree ist.
signal world_scene_ready(world_root: Node)

## Wird von World.gd (_ready) emittiert um WorldService zu benachrichtigen dass der
## SceneTree-Wechsel abgeschlossen ist. WorldService lauscht darauf in on_ready() —
## kein Services-Locator in World.gd nötig.

## Wird von WorldService emittiert wenn die Welt entladen wird (Szenenwechsel).
signal world_scene_unloaded

## Wird von InteractableComponent nach jeder abgeschlossenen Aktion emittiert.
## peer_id: wer den Loot erhält. Default 1 (Solo/Host) für Aufrufer, die die
## wahre Identität (noch) nicht kennen — siehe emit_loot_collected()-Kommentar.
signal loot_collected(item_id: String, quantity: int, peer_id: int)

## Wird von CombatSystem.apply_damage() emittiert sobald Schaden angewendet wurde.
## Empfänger: UI (Floating-Text), AppLogger, zukünftiges Analytics-System.
signal damage_dealt(record: DamageRecord)

## Wird von EnemyNPC._die() emittiert wenn ein Feind besiegt wurde.
## enemy_type_id: der EntityRegistry-Key ("goblin", künftig "skeleton", ...).
## Empfänger: QuestService (KILL-Objectives), zukünftiges Analytics-System.
signal enemy_killed(enemy_type_id: String, position: Vector3, peer_id: int)

## Wird von InteractableComponent emittiert wenn ein inspect_text vorliegt.
signal interaction_reward_text(text: String)

## Wird von InteractableComponent emittiert wenn sich das nächste Interagierbare ändert.
## InteractionButtonController lauscht hier statt in _process() zu pollen.
signal proximity_changed(target: Node3D, in_range: bool)

## Wird von TouchInput emittiert wenn der Spieler auf die Welt tippt (kurzer Tap,
## keine Kamera-Drehung/kein Pinch — siehe TouchInput._maybe_emit_world_tap()).
## screen_pos: Viewport-Koordinaten des Taps. InteractionTargetPicker lauscht
## hier, castet einen Ray von der Player-Kamera und wählt ggf. ein Ziel aus
## (Outline-Umrandung zur Bestätigung, RuneScape/Minecraft-Stil).
signal world_tap_requested(screen_pos: Vector2)

## Entity-Lifecycle-Events (von EntityOrchestrator emittiert).
signal entity_spawned(type_id: String, entity: Node3D, position: Vector3)
signal entity_despawned(type_id: String, uuid: String, position: Vector3)

## Emittiert von Entities (OakTree, IronOre …) wenn sie despawnt werden wollen.
## WorldService lauscht hier und delegiert an EntityOrchestrator — Entities rufen
## Architekturprinzip: Signale aufwärts, kein direkter despawn-Aufruf.
signal entity_despawn_requested(uuid: String)

## Spieler-Wünsche an die Welt (Graben/Bauen). UI und Entities emittieren nur — die
## Ausführung samt Prüfungen (Reichweite, Material, Regeln, Solo-Guard) macht WorldService.
## mode: WorldTerrainEditor.MODE_DIG | MODE_FILL. target: Weltposition des Zielpunkts.
signal terrain_edit_requested(player_id: String, mode: String, target: Vector3)
## Sense: Gras/Blumen um target mähen (Ausführung: WorldService.request_grass_cut).
signal grass_cut_requested(player_id: String, target: Vector3)
## Ebnen: Gelände um target schrittweise auf die waagerechte Ebene plane_y ziehen.
## direction: TerrainPlanePlanner.DIR_BOTH | DIR_DOWN (nur abtragen) | DIR_UP (nur auffüllen).
signal terrain_plane_requested(player_id: String, target: Vector3, plane_y: float, direction: String)
## storey: Ebene (0 = Gelände, siehe BuildGrid).
signal build_place_requested(player_id: String, piece_id: String, target: Vector3, rot_steps: int, storey: int)
signal build_remove_requested(player_id: String, key: String)
## Wie build_place_requested, aber für eine komplette HouseTemplateDefinition (mehrere
## Bauteile als eine atomare Operation, siehe WorldBuildHandler "Häuser/Vorlagen").
signal build_house_place_requested(player_id: String, template_id: String, target: Vector3, rot_steps: int, storey: int)

## Leitern (Graben in die Tiefe): Wunsch, an der Wand vor dem Spieler eine Leiter aufzustellen
## (origin = Spielerposition, facing = waagerechte Blickrichtung) bzw. eine abzubauen.
signal ladder_place_requested(player_id: String, origin: Vector3, facing: Vector3)
signal ladder_remove_requested(player_id: String, key: String)

func _init() -> void:
	super._init("Events/World")

func emit_interaction_started(action_id: String, label: String, duration: float) -> void:
	_log("Interaktion gestartet: '%s' / id='%s' (%.1fs)" % [label, action_id, duration])
	interaction_started.emit(action_id, label, duration)

func emit_interaction_finished(action_id: String, label: String) -> void:
	_log("Interaktion beendet: '%s' / id='%s'" % [label, action_id])
	interaction_finished.emit(action_id, label)

func emit_interaction_cancelled(action_id: String, label: String) -> void:
	_log_warn("Interaktion abgebrochen: '%s' / id='%s'" % [label, action_id])
	interaction_cancelled.emit(action_id, label)

func emit_chunk_loaded(chunk_id: Vector2i) -> void:
	_log("Chunk geladen: %s" % str(chunk_id))
	chunk_loaded.emit(chunk_id)

func emit_chunk_unloaded(chunk_id: Vector2i) -> void:
	_log("Chunk entladen: %s" % str(chunk_id))
	chunk_unloaded.emit(chunk_id)

func emit_time_of_day_changed(hour: int) -> void:
	_log("Tageszeit: %02d:00" % hour)
	time_of_day_changed.emit(hour)

func emit_weather_changed(new_weather: String, old_weather: String) -> void:
	_log_info("Wetter: '%s' -> '%s'" % [old_weather, new_weather])
	weather_changed.emit(new_weather, old_weather)

func emit_world_scene_ready(world_root: Node) -> void:
	_log_info("World-Szene bereit: %s" % world_root.name)
	world_scene_ready.emit(world_root)

func emit_world_scene_unloaded() -> void:
	_log_info("World-Szene entladen.")
	world_scene_unloaded.emit()

## peer_id: wer den Loot erhält. Default 1 — nur für Aufrufer gedacht, die die
## wahre Empfänger-Identität (noch) nicht kennen (z.B. EnemyNPC._die(), siehe
## dortiger Kommentar zu fehlender Killer-Attribution). InteractionExecutor
## kennt peer_id bereits korrekt und MUSS ihn explizit übergeben, nicht auf
## den Default verlassen.
func emit_loot_collected(item_id: String, quantity: int, peer_id: int = 1) -> void:
	_log("Loot: %dx '%s' (Spieler %d)" % [quantity, item_id, peer_id])
	loot_collected.emit(item_id, quantity, peer_id)

func emit_interaction_reward_text(text: String) -> void:
	_log("Belohnungstext: '%s'" % text)
	interaction_reward_text.emit(text)

func emit_proximity_changed(target: Node3D, in_range: bool) -> void:
	if is_instance_valid(target):
		if in_range:
			_log("Nähe erkannt: '%s'" % target.name)
		else:
			_log("Nähe verlassen: '%s'" % target.name)
	proximity_changed.emit(target, in_range)

## Kein _log() hier bewusst: TouchInput kann das potenziell auf jeden kurzen
## Tap feuern — das würde bei jedem Antippen der Welt eine Logzeile erzeugen.
## InteractionTargetPicker loggt bereits selbst, WENN daraus eine Zielauswahl wird.
func emit_world_tap_requested(screen_pos: Vector2) -> void:
	world_tap_requested.emit(screen_pos)

func emit_entity_spawned(type_id: String, entity: Node3D, position: Vector3) -> void:
	_log("Entity gespawnt: type='%s' pos=%s" % [type_id, str(position)])
	entity_spawned.emit(type_id, entity, position)

func emit_entity_despawned(type_id: String, uuid: String, position: Vector3 = Vector3.ZERO) -> void:
	_log("Entity despawnt: type='%s' uuid='%s' pos=%s" % [type_id, uuid, str(position)])
	entity_despawned.emit(type_id, uuid, position)

func emit_entity_despawn_requested(uuid: String) -> void:
	_log("Entity-Despawn angefordert: uuid='%s'" % uuid)
	entity_despawn_requested.emit(uuid)

func emit_terrain_edit_requested(player_id: String, mode: String, target: Vector3) -> void:
	_log("Gelände-Änderung angefordert: %s @ %s (Spieler '%s')" % [mode, str(target), player_id])
	terrain_edit_requested.emit(player_id, mode, target)

func emit_grass_cut_requested(player_id: String, target: Vector3) -> void:
	_log("Mähen angefordert @ %s (Spieler '%s')" % [str(target), player_id])
	grass_cut_requested.emit(player_id, target)

func emit_terrain_plane_requested(player_id: String, target: Vector3, plane_y: float, direction: String = "both") -> void:
	_log("Ebnen angefordert: %s @ %s auf %.2f m (Spieler '%s')" % [direction, str(target), plane_y, player_id])
	terrain_plane_requested.emit(player_id, target, plane_y, direction)

func emit_ladder_place_requested(player_id: String, origin: Vector3, facing: Vector3) -> void:
	_log("Leiter angefordert @ %s Richtung %s (Spieler '%s')" % [str(origin), str(facing), player_id])
	ladder_place_requested.emit(player_id, origin, facing)

func emit_ladder_remove_requested(player_id: String, key: String) -> void:
	_log("Leiter abbauen angefordert: '%s' (Spieler '%s')" % [key, player_id])
	ladder_remove_requested.emit(player_id, key)

func emit_build_place_requested(
	player_id: String, piece_id: String, target: Vector3, rot_steps: int, storey: int = 0
) -> void:
	_log("Bauen angefordert: '%s' @ %s rot=%d Ebene=%d (Spieler '%s')" % [piece_id, str(target), rot_steps, storey, player_id])
	build_place_requested.emit(player_id, piece_id, target, rot_steps, storey)

func emit_build_remove_requested(player_id: String, key: String) -> void:
	_log("Abreißen angefordert: '%s' (Spieler '%s')" % [key, player_id])
	build_remove_requested.emit(player_id, key)

func emit_build_house_place_requested(
	player_id: String, template_id: String, target: Vector3, rot_steps: int, storey: int = 0
) -> void:
	_log("Hausbau angefordert: '%s' @ %s rot=%d Ebene=%d (Spieler '%s')" % [template_id, str(target), rot_steps, storey, player_id])
	build_house_place_requested.emit(player_id, template_id, target, rot_steps, storey)

func emit_damage_dealt(record: DamageRecord) -> void:
	_log("Schaden: %s" % record.to_debug_string())
	damage_dealt.emit(record)

func emit_enemy_killed(enemy_type_id: String, position: Vector3, peer_id: int = 1) -> void:
	_log("Feind besiegt: type='%s' pos=%s (Spieler %d)" % [enemy_type_id, str(position), peer_id])
	enemy_killed.emit(enemy_type_id, position, peer_id)
