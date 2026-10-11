class_name DayNightCycle
extends Node

## DayNightCycle — dreht die Sonne, dimmt sie und tönt Himmel/Umgebungslicht
## nach WorldTimeService.day_time. Bisher (siehe docs/procedural-textures-and-
## weather-vfx.md, "Bekannte Grenzen") lief die Sonne aus WorldFactory nur mit
## einer fest einprogrammierten Rotation/Helligkeit — WorldTimeService.day_time
## tickte bereits, wurde aber nirgends fürs Licht verwendet. Das hier ist der
## fehlende Verbraucher.
##
## Reine Optik, wie WeatherVfx/AmbientForestVfx: WorldTimeService.day_time
## bleibt die einzige Wahrheit (bereits gespeichert/wiederhergestellt), diese
## Klasse LIEST nur und schreibt auf Sun/Environment. Kein eigener Zustand,
## kein Save-State.
##
## EIN Schreiber pro Property, damit sich nichts pro Frame gegenseitig
## überschreibt (siehe WeatherVfx-Klassenkommentar für die ausführliche
## Begründung): DayNightCycle ist der einzige Schreiber von Sun.light_energy/
## Sun.rotation_degrees/Environment.ambient_light_energy/Sky-Farben — WeatherVfx
## liefert nur einen Dimm-FAKTOR (get_sun_factor()), den diese Klasse mit ihrer
## eigenen Tag/Nacht-Basishelligkeit multipliziert, statt selbst zu schreiben.
## Nebel (env.fog_*) bleibt umgekehrt exklusiv bei WeatherVfx — diese Klasse
## fasst ihn nicht an.
##
## Bonus-Aufgabe (siehe Settings-Panel "Lichtschächte"): schaltet
## Environment.volumetric_fog_enabled nach dem Settings-Key "volumetric_fog"
## um — AUS per Default (siehe SettingsService.DEFAULTS-Kommentar dort für die
## Mobile-Performance-Begründung), reagiert aber sofort auf
## SettingsService.setting_changed, kein Weltneustart nötig zum Ausprobieren.

const LOG_CAT := "DayNightCycle"

## Stunden (WorldTimeService.day_time, 0..24), an denen Morgen-/Abenddämmerung
## beginnen bzw. voller Tag/voller Nacht erreicht ist. Grobzügig geschätzt
## (kein Godot-Runtime hier zum Gegenprüfen verfügbar, wie der Rest dieser
## Optik-Schicht) — bewusst DIESELBEN Eckwerte wie AmbientForestVfx.NIGHT_START_HOUR/
## NIGHT_END_HOUR (20.5/5.5) für ein konsistentes "wann ist eigentlich Nacht"
## über beide Klassen hinweg, hier nur mit einer zusätzlichen weichen
## Übergangsbreite von 2h davor/danach statt eines harten Cutoffs.
const DAY_START := 6.0
const DAY_FULL := 8.0
const DUSK_START := 18.5
const NIGHT_FULL := 20.5

## Sonnenhelligkeit: DAY_SUN_ENERGY matcht WorldFactorys bisherigen (statischen)
## Wert 1.2 — beim ersten Sonnenaufgang/Zenit soll sich nichts sprunghaft
## anders anfühlen als vorher, nur jetzt eben mit einem Tagesverlauf drumherum.
const NIGHT_SUN_ENERGY := 0.08
const DAY_SUN_ENERGY := 1.2
const NIGHT_AMBIENT := 0.12
const DAY_AMBIENT := 0.5

## Fester Azimut (Y-Rotation) — nur die Elevation (X) läuft über den Tag,
## ein wandernder Azimut wäre ein zweiter Freiheitsgrad ohne spürbaren
## Zusatznutzen für ein stilisiertes Mobile-RPG-Tageslicht.
const SUN_YAW_DEG := 30.0

const SKY_TOP_DAY := Color(0.2, 0.5, 0.9)
const SKY_HORIZON_DAY := Color(0.6, 0.8, 1.0)
const SKY_TOP_NIGHT := Color(0.02, 0.03, 0.09)
const SKY_HORIZON_NIGHT := Color(0.05, 0.06, 0.16)

## Experimentell, siehe Klassenkommentar — deutlich teurer als der normale
## Nebel (WeatherVfx), deshalb fest niedrig statt konfigurierbar: wer die
## Performance nicht will, lässt den Regler einfach aus statt ihn hochzudrehen.
const VOLUMETRIC_FOG_DENSITY := 0.03

var _time: WorldTimeService = null
var _sun: DirectionalLight3D = null
var _environment: Environment = null
var _sky_material: ProceduralSkyMaterial = null
var _weather_vfx: WeatherVfx = null
var _settings: SettingsService = null

## time_service/sun/environment: siehe WorldService.on_world_scene_ready()
## (Nodes/Resource kommen unverändert aus WorldFactory._add_environment()).
## weather_vfx: für get_sun_factor() (siehe Klassenkommentar). settings:
## optional — ohne sie bleibt "Lichtschächte" fest aus (kein Live-Toggle).
## active: false auf einem kopflosen dedizierten Server (kein Rendering).
func configure(
	time_service: WorldTimeService, sun: DirectionalLight3D, environment: Environment,
	weather_vfx: WeatherVfx, settings: SettingsService, active: bool
) -> void:
	_time = time_service
	_sun = sun
	_environment = environment
	_weather_vfx = weather_vfx
	_settings = settings

	if is_instance_valid(_environment) and _environment.sky != null:
		_sky_material = _environment.sky.sky_material as ProceduralSkyMaterial

	if is_instance_valid(_settings):
		_apply_volumetric_fog(_settings.get_setting("volumetric_fog", false))
		if not _settings.setting_changed.is_connected(_on_setting_changed):
			_settings.setting_changed.connect(_on_setting_changed)

	set_process(active)
	if active:
		# Sofortiger Erst-Anwurf statt bis zum ersten _process()-Tick zu warten
		# — sonst hängt die Sonne für einen Frame lang noch auf WorldFactorys
		# statischem Platzhalterwert.
		_apply(0.0 if not is_instance_valid(_time) else _time.day_time)

func _process(_delta: float) -> void:
	if not is_instance_valid(_time):
		return
	_apply(_time.day_time)

func _apply(day_time: float) -> void:
	if not is_instance_valid(_sun):
		return
	var day_factor := _compute_day_factor(day_time)

	# Elevation über den ganzen Tag; DAY_START=6 -> Horizont (Sonnenaufgang),
	# 12 -> Zenit (Licht zeigt gerade nach unten), 18 -> Horizont
	# (Sonnenuntergang), 0/24 -> "unter" dem Horizont (Nacht).
	var pitch_deg: float = (day_time / 24.0) * 360.0 - 90.0
	_sun.rotation_degrees = Vector3(pitch_deg, SUN_YAW_DEG, 0.0)

	var weather_factor: float = _weather_vfx.get_sun_factor() if is_instance_valid(_weather_vfx) else 1.0
	_sun.light_energy = lerp(NIGHT_SUN_ENERGY, DAY_SUN_ENERGY, day_factor) * weather_factor

	if is_instance_valid(_environment):
		_environment.ambient_light_energy = lerp(NIGHT_AMBIENT, DAY_AMBIENT, day_factor)
	if is_instance_valid(_sky_material):
		_sky_material.sky_top_color = SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, day_factor)
		_sky_material.sky_horizon_color = SKY_HORIZON_NIGHT.lerp(SKY_HORIZON_DAY, day_factor)

## 0.0 (volle Nacht) .. 1.0 (voller Tag), mit weichem smoothstep-Übergang an
## Morgen-/Abenddämmerung statt eines harten Umschaltens. Eigene Funktion statt
## eines einzelnen sin()-Terms, weil "voller Tag" bewusst ein PLATEAU ist
## (8 bis 18:30 Uhr konstant hell) statt eines spitzen Maximums nur exakt um
## 12 Uhr — wirkt für ein Tageslicht-Gefühl natürlicher als ein reiner Sinus.
func _compute_day_factor(t: float) -> float:
	if t >= DAY_FULL and t < DUSK_START:
		return 1.0
	if t >= DAY_START and t < DAY_FULL:
		return smoothstep(DAY_START, DAY_FULL, t)
	if t >= DUSK_START and t < NIGHT_FULL:
		return 1.0 - smoothstep(DUSK_START, NIGHT_FULL, t)
	return 0.0  # NIGHT_FULL..24 und 0..DAY_START (über Mitternacht hinweg)

func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "volumetric_fog":
		_apply_volumetric_fog(value)

## Siehe Klassenkommentar/VOLUMETRIC_FOG_DENSITY — reines Ein/Aus, keine
## einstellbare Stärke (bewusst, gegen "Regler auf Anschlag" auf Geräten,
## die das nicht wegstecken).
func _apply_volumetric_fog(enabled: Variant) -> void:
	if not is_instance_valid(_environment):
		return
	var on: bool = bool(enabled)
	_environment.volumetric_fog_enabled = on
	if on:
		_environment.volumetric_fog_density = VOLUMETRIC_FOG_DENSITY
	AppLogger.log_info(
		"DayNightCycle: Lichtschächte (volumetrischer Nebel) %s." % ("aktiviert" if on else "deaktiviert"),
		LOG_CAT
	)
