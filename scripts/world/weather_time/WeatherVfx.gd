class_name WeatherVfx
extends Node3D

## WeatherVfx — visuelle Fortsetzung von WeatherService (ADR-041 "Bewusst
## NICHT Teil dieser Runde: visuelle Wetter-Effekte" — das hier ist genau
## dieser künftige Aufsatz).
##
## Reine Optik: current_weather bleibt einzig bei WeatherService (RefCounted,
## kein Node, kein Rendering) — diese Klasse LIEST nur über das
## weather_changed-Signal und schaltet Partikel um. Kein Netzwerk-Traffic,
## kein Save-State: fällt bei Verbindungs-/Chunk-Wechseln einfach neu an,
## exakt wie WeatherService selbst rein aus world_seed + Zeit rollt
## (WindField, gleiches Prinzip).
##
## Folgt einem Zielknoten (i.d.R. dem lokalen Player, siehe follow()), damit
## Regen/Schnee immer über dem Spieler fallen statt fest an einer Welt-
## koordinate zu hängen. Alle Texturen kommen aus ProceduralTextureFactory —
## keine einzige Bilddatei.
##
## Schreibt NICHT direkt auf Sun.light_energy (das war eine frühere Version
## dieser Klasse) — seit DayNightCycle existiert, wäre das ein zweiter
## Schreiber auf dieselbe Property und beide Systeme würden sich pro Frame
## gegenseitig überschreiben (wer zuletzt in der Node-Reihenfolge dran ist,
## "gewinnt" zufällig -> Flackern). Stattdessen berechnet diese Klasse nur
## einen Dimm-FAKTOR fürs Wetter (get_sun_factor()) und DayNightCycle ist der
## einzige, der ihn mit seiner eigenen Tag/Nacht-Basishelligkeit multipliziert
## und tatsächlich schreibt. Nebel bleibt weiterhin exklusiv hier (DayNightCycle
## fasst env.fog_* nicht an) — eine Property, ein Schreiber, pro System.

const LOG_CAT := "WeatherVfx"

const RAIN_HEIGHT := 6.0
const RAIN_AREA := Vector2(12.0, 12.0)
const SNOW_HEIGHT := 7.0
const SNOW_AREA := Vector2(14.0, 14.0)

## Nebel/Sonnen-Faktor bauen sich über ein paar Sekunden auf/ab statt hart
## umzuschalten (linearer Lerp-Anteil pro _process()-Aufruf, framerate-
## abhängig wie der Rest dieser Klasse — für einen weichen Wetterübergang
## genau genug, kein Tween-Overhead nötig).
const FOG_LERP_SPEED := 0.15
const SUN_LERP_SPEED := 0.2

var _bus: IEventBus = null
var _wind: WindField = null
var _follow_target: Node3D = null
var _current_weather: String = "clear"

var _rain: GPUParticles3D = null
var _snow: GPUParticles3D = null

## Reine Optik-Ziele (siehe Klassenkommentar) — kein Save-State, keine
## Netzwerk-Synchronisation. _environment darf null sein (z.B. wenn
## configure() ohne sie aufgerufen wird); alle Zugriffe sind entsprechend
## abgesichert.
var _environment: Environment = null
var _target_fog_density: float = 0.0
var _target_fog_color: Color = Color(0.75, 0.78, 0.80)
var _target_sun_factor: float = 1.0
var _current_fog_density: float = 0.0
var _current_sun_factor: float = 1.0

## bus: für weather_changed. world_seed: für den deterministischen Wind.
## active: false auf einem kopflosen dedizierten Server (Tier 3, kein lokaler
## Spieler, kein Rendering) — spart dort unnötige Partikel-Nodes.
## environment: optional — WorldFactory._add_environment()s Ergebnis-Resource
## (siehe WorldService.on_world_scene_ready()). Ohne sie bleibt Nebel
## unverändert (nur Regen/Schnee-Partikel wie zuvor).
func configure(
	bus: IEventBus, world_seed: int, active: bool, environment: Environment = null
) -> void:
	_bus = bus
	_wind = WindField.new(world_seed)
	_environment = environment

	if is_instance_valid(_bus):
		var world_events: WorldEvents = _bus.world()
		if world_events != null and not world_events.weather_changed.is_connected(_on_weather_changed):
			world_events.weather_changed.connect(_on_weather_changed)

	visible = active
	set_process(active)
	if active:
		_build_rain()
		_build_snow()

## Partikel folgen diesem Node (typischerweise der lokale Spieler) statt
## fest an der Welt zu hängen. Optional — ohne Aufruf bleibt WeatherVfx an
## seiner eigenen Position (z.B. wenn der Aufrufer selbst schon folgt).
func follow(target: Node3D) -> void:
	_follow_target = target

## Für den initialen Zustand direkt nach dem Bauen der Welt (WeatherService
## hat zu dem Zeitpunkt schon ein current_weather, aber noch kein Signal
## gefeuert — hier wird nur der bestehende Zustand übernommen, nicht neu
## gewürfelt).
func set_weather(weather: String) -> void:
	_on_weather_changed(weather, _current_weather)

func _on_weather_changed(new_weather: String, _old_weather: String) -> void:
	_current_weather = new_weather
	_update_fog_and_light_targets(new_weather)
	if not is_instance_valid(_rain) or not is_instance_valid(_snow):
		return  # inaktiv (dedizierter Server) — configure(active=false)

	_rain.emitting = new_weather in ["rain", "storm"]
	_rain.amount_ratio = 1.0 if new_weather == "storm" else 0.5
	_snow.emitting = new_weather == "snow"
	AppLogger.log_info("WeatherVfx: Optik auf '%s' umgeschaltet." % new_weather, LOG_CAT)

## Setzt nur die ZIEL-Werte für Nebel/Sonnenhelligkeit — der eigentliche
## Übergang passiert weich über mehrere _process()-Aufrufe (siehe
## FOG_LERP_SPEED/SUN_LERP_SPEED), damit ein Wetterwechsel nicht wie ein
## harter Szenenschnitt wirkt. Werte sind Erstabschätzungen (kein Godot-
## Runtime hier zum Gegenprüfen verfügbar, siehe Klassenkommentar).
func _update_fog_and_light_targets(weather: String) -> void:
	match weather:
		"clear":
			_target_fog_density = 0.0
			_target_fog_color = Color(0.75, 0.78, 0.80)
			_target_sun_factor = 1.0
		"rain":
			_target_fog_density = 0.012
			_target_fog_color = Color(0.55, 0.58, 0.62)
			_target_sun_factor = 0.75
		"storm":
			_target_fog_density = 0.020
			_target_fog_color = Color(0.40, 0.42, 0.46)
			_target_sun_factor = 0.50
		"fog":
			# Deutlich dichter als Regen/Sturm — "fog" ist die einzige Wetterlage,
			# bei der Nebel selbst der Effekt ist statt nur eine Randnotiz dazu.
			_target_fog_density = 0.045
			_target_fog_color = Color(0.80, 0.80, 0.78)
			_target_sun_factor = 0.70
		"snow":
			_target_fog_density = 0.008
			_target_fog_color = Color(0.85, 0.87, 0.92)
			_target_sun_factor = 0.90
		_:
			_target_fog_density = 0.0
			_target_fog_color = Color(0.75, 0.78, 0.80)
			_target_sun_factor = 1.0

func _process(delta: float) -> void:
	if is_instance_valid(_follow_target):
		global_position = _follow_target.global_position

	_apply_fog_and_light_lerp()

	if not is_instance_valid(_wind):
		return
	_wind.advance(delta)
	if _current_weather == "storm":
		_wind.set_gust_multiplier(1.4)

	var dir3: Vector3 = Vector3(_wind.direction.x, 0.0, _wind.direction.y)
	if is_instance_valid(_rain):
		var rain_mat := _rain.process_material as ParticleProcessMaterial
		if rain_mat != null:
			# Regen fällt schräg in Windrichtung statt rein senkrecht — Sturm kippt stärker.
			rain_mat.direction = (Vector3.DOWN + dir3 * _wind.strength * 0.6).normalized()
			rain_mat.spread = 4.0 + _wind.strength * 8.0
	if is_instance_valid(_snow):
		var snow_mat := _snow.process_material as ParticleProcessMaterial
		if snow_mat != null:
			snow_mat.direction = (Vector3.DOWN + dir3 * _wind.strength * 0.9).normalized()

## Nähert Nebeldichte/-farbe und den Wetter-Sonnenfaktor schrittweise den in
## _update_fog_and_light_targets() gesetzten Zielwerten an. _environment darf
## fehlen (siehe configure()) — dann bleibt der Nebel unverändert, nur Regen/
## Schnee-Partikel laufen wie zuvor weiter. Der Sonnenfaktor wird IMMER
## weitergerechnet (kein Environment nötig dafür) — DayNightCycle liest ihn
## über get_sun_factor(), unabhängig davon ob hier ein Environment hängt.
func _apply_fog_and_light_lerp() -> void:
	_current_sun_factor = lerp(_current_sun_factor, _target_sun_factor, SUN_LERP_SPEED)
	if is_instance_valid(_environment):
		_current_fog_density = lerp(_current_fog_density, _target_fog_density, FOG_LERP_SPEED)
		_environment.fog_density = _current_fog_density
		_environment.fog_light_color = _environment.fog_light_color.lerp(_target_fog_color, FOG_LERP_SPEED)
		# Erst ab einer minimalen Dichte einschalten (spart den Fog-Pass bei
		# "clear" komplett, statt ihn mit fog_density≈0 trotzdem laufen zu lassen).
		_environment.fog_enabled = _current_fog_density > 0.002

## Wetter-Dimmfaktor für die Sonne (1.0 = ungedimmt/"clear" … 0.5 bei "storm").
## Siehe Klassenkommentar: DayNightCycle ist der einzige Schreiber von
## Sun.light_energy und multipliziert seine eigene Tag/Nacht-Basishelligkeit
## mit diesem Wert. Ohne aktiven DayNightCycle (oder bevor der erste Frame
## gelaufen ist) bleibt die Sonne einfach bei ihrer WorldFactory-Basishelligkeit.
func get_sun_factor() -> float:
	return _current_sun_factor

func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "RainParticles"
	_rain.amount = 500
	_rain.lifetime = 1.1
	_rain.emitting = false
	_rain.position = Vector3(0.0, RAIN_HEIGHT, 0.0)
	_rain.visibility_aabb = AABB(
		Vector3(-RAIN_AREA.x, -RAIN_HEIGHT - 1.0, -RAIN_AREA.y),
		Vector3(RAIN_AREA.x * 2.0, RAIN_HEIGHT + 2.0, RAIN_AREA.y * 2.0)
	)
	_rain.draw_pass_1 = _build_streak_mesh()

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.DOWN
	pm.spread = 4.0
	pm.gravity = Vector3(0.0, -20.0, 0.0)
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(RAIN_AREA.x, 0.05, RAIN_AREA.y)
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	_rain.process_material = pm

	add_child(_rain)

func _build_snow() -> void:
	_snow = GPUParticles3D.new()
	_snow.name = "SnowParticles"
	_snow.amount = 220
	_snow.lifetime = 6.0
	_snow.emitting = false
	_snow.position = Vector3(0.0, SNOW_HEIGHT, 0.0)
	_snow.visibility_aabb = AABB(
		Vector3(-SNOW_AREA.x, -SNOW_HEIGHT - 1.0, -SNOW_AREA.y),
		Vector3(SNOW_AREA.x * 2.0, SNOW_HEIGHT + 2.0, SNOW_AREA.y * 2.0)
	)
	_snow.draw_pass_1 = _build_dot_mesh()

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.DOWN
	pm.spread = 25.0
	pm.gravity = Vector3(0.0, -0.9, 0.0)
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	# Leichtes Taumeln statt schnurgeradem Fall — orbit_velocity gibt Schnee
	# eine seitliche Drift-Komponente, die sich über die Lebenszeit dreht.
	pm.orbit_velocity_min = 0.05
	pm.orbit_velocity_max = 0.15
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(SNOW_AREA.x, 0.05, SNOW_AREA.y)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	_snow.process_material = pm

	add_child(_snow)

func _build_streak_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.45)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = ProceduralTextureFactory.raindrop_streak()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = false
	q.material = mat
	return q

func _build_dot_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = ProceduralTextureFactory.snowflake()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = mat
	return q
