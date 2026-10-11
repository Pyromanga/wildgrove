extends RefCounted
class_name WorldFactory

## WorldFactory — Erzeugt die STATISCHE Spielwelt (Geometrie + Licht + Player).
##
## WICHTIG — Was gehört NICHT hierher:
##   Entities (OakTree, IronOre, NPCs) → EntityOrchestrator (via WorldService)
##   Services, UI → jeweilige Manager
##
## Anti-Pattern VERHINDERT:
##   VERBOTEN: Node3D.new() + node.set_script(script)
##   GRUND: set_script() nach Node-Erstellung triggert _ready() ein zweites Mal
##          (Godot's Engine ruft _ready() beim Tree-Eintritt auf, und nochmal wenn
##          das Script gesetzt wird). Bei CharacterBody3D: undefiniertes Physik-Verhalten.
##   KORREKT: script.new() → direkte Instanz MIT Script von Anfang an.
##            Damit gibt es exakt einen _ready()-Aufruf nach add_child().

const LOG_CAT := "WorldFactory"

## Erzeugt die statische Welt-Geometrie ohne Entities.
## Gibt einen temporären Container-Node zurück — WorldService verschiebt dessen Kinder
## in world_root (die echte World.tscn).
##
## Enthält: Beleuchtung, Himmel. (Gelände: TerrainField + ChunkManager, nicht hier.)
## NICHT enthalten: Player, OakTree, IronOre, NPCs → alle via EntityOrchestrator gespawnt.
func create_world() -> Node3D:
	var t := AppLogger.log_begin("create_world()", LOG_CAT)
	var world := Node3D.new()
	world.name = "WorldContainer"

	_add_environment(world)
	# Player wird via EntityOrchestrator.spawn_entity("player", ...) gespawnt.
	# WorldSpawner.spawn_all() übernimmt das nach on_world_scene_ready().

	AppLogger.log_end("create_world()", t, LOG_CAT)
	AppLogger.log_info(
		"Statische Welt erstellt. Nodes: %d." % world.get_child_count(), LOG_CAT
	)
	return world

# ─────────────────────────────────────────────
# Umgebung
# ─────────────────────────────────────────────

func _add_environment(world: Node3D) -> void:
	# Sonne — Rotation/Helligkeit sind nur der Platzhalter für den allerersten
	# Frame. DayNightCycle übernimmt beides danach laufend nach
	# WorldTimeService.day_time (siehe dortigen Klassenkommentar); dieser
	# Wert hier ist bewusst "irgendein plausibler Taghimmel", kein Zielwert.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)

	# Prozeduraler Himmel — sky_top_color/sky_horizon_color sind ebenfalls nur
	# der Erstwert, DayNightCycle tönt sie laufend zwischen Tag/Nacht um.
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.5, 0.9)
	sky_mat.sky_horizon_color = Color(0.6, 0.8, 1.0)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5

	# Nebel: standardmäßig AUS, WeatherVfx schaltet ihn bei Wetter "fog"
	# (und leichter bei "rain"/"storm") ein/aus, siehe dortigen Kommentar.
	# Werte hier sind nur der Ruhezustand ("clear") — nicht die Zielwerte.
	env.fog_enabled = false
	env.fog_light_color = Color(0.75, 0.78, 0.8)
	env.fog_density = 0.01
	env.fog_sun_scatter = 0.2
	# Volumetrischer Nebel ("Lichtschächte"/God-Rays im Kronendach): deutlich
	# teurer als der einfache exponentielle Nebel oben (voller Froxel-
	# Raymarch pro Frame), das Projekt zielt laut README auf Touch-first
	# MOBILE ab — deshalb standardmäßig AUS und NICHT hier fest verdrahtet,
	# sondern hinter dem Settings-Key "volumetric_fog" (siehe SettingsService.
	# DEFAULTS-Kommentar) versteckt: wer es ausprobieren will, schaltet es im
	# Settings-Panel ein, DayNightCycle setzt volumetric_fog_enabled dann live
	# um (siehe dortiger Kommentar) — kein Weltneustart nötig. Bewusst nur
	# EIN Bool statt eines Reglers, gegen "Stärke auf Anschlag" auf Geräten,
	# die das nicht wegstecken.
	env.volumetric_fog_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env_node.environment = env
	world.add_child(env_node)

	AppLogger.log_debug("Umgebung (Sonne + Himmel) erstellt.", LOG_CAT)
