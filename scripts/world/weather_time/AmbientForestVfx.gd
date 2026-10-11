class_name AmbientForestVfx
extends Node3D

## AmbientForestVfx — reine Ambient-Optik, unabhängig von WeatherService/
## WeatherVfx: treibende, langsam fallende Blätter über dem Spieler, nur
## sichtbar in "forest"/"dense_forest" (siehe BiomeRegistry), plus
## Glühwürmchen nachts im "dense_forest". Beantwortet den letzten offenen
## Punkt aus docs/procedural-textures-and-weather-vfx.md ("leaf_card()
## existiert, wird aber nirgends verwendet").
##
## Gleiches Muster wie WeatherVfx: RefCounted-Wahrheit bleibt woanders
## (hier: TerrainField.get_biome_id_at() für Biom, WorldTimeService.day_time
## für Tag/Nacht statt eigener Services), diese Klasse LIEST nur und schaltet
## Partikel um. Kein Netzwerk-Traffic, kein Save-State — fällt bei
## Verbindungs-/Chunk-Wechseln einfach neu an, wie WindField/WeatherVfx.
##
## Drei GPUParticles3D-Kinder für Laub statt einem: jedes bekommt eine eigene
## leaf_card(hue_seed)-Variante (siehe ProceduralTextureFactory-Kommentar
## "mehrere Blatt-Varianten ohne neuen Code") und trägt nur einen Drittel
## der Gesamtmenge — wirkt weniger wie ein einzelnes wiederholtes Sprite.
## Glühwürmchen sind ein viertes, eigenständiges GPUParticles3D (eigene
## Emissions-Fläche/Höhe/Bewegungsart, siehe _build_fireflies()).
##
## Easter Egg "firefly_watcher" (Round 107, siehe AchievementService.gd
## Klassenkommentar "EASTER EGGS"): _fireflies_active ist bereits exakt das
## Signal, das gebraucht wird ("stehen die Glühwürmchen gerade sichtbar an")
## — kein zweiter Beobachtungs-Mechanismus nötig, nur ein Timer obendrauf
## (_firefly_watch_elapsed), der bei _fireflies_active==false zurückgesetzt
## wird. Netzwerk-Meldung optional (network/local_player_id dürfen leer
## bleiben) — ohne sie bleibt das Easter Egg einfach unerreichbar, kein Crash.

const LOG_CAT := "AmbientForestVfx"

const LEAF_HEIGHT := 3.2
const LEAF_AREA := Vector2(9.0, 9.0)
const LEAF_VARIANTS := 3
const LEAF_COUNT_PER_VARIANT := 16

const FIREFLY_HEIGHT := 1.4
const FIREFLY_AREA := Vector2(5.0, 5.0)
const FIREFLY_COUNT := 24

## Wie oft neu geprüft wird, ob der Spieler noch im Wald/bei Nacht steht
## (Sekunden) — nicht jeden Frame, Biom/Tageszeit ändern sich nicht schlagartig.
const AMBIENT_CHECK_INTERVAL := 1.5

const FOREST_BIOMES := ["forest", "dense_forest"]
const FIREFLY_BIOMES := ["dense_forest"]  # nur der dichte Wald, "forest" bleibt tagsüber-Look
## day_time in Stunden (WorldTimeService, 0..24) — Nacht ist alles außerhalb
## dieses Fensters. Bewusst grobzügig geschätzt (kein Playtest möglich hier).
const NIGHT_START_HOUR := 20.5
const NIGHT_END_HOUR := 5.5

## Wunsch "weiter machen mit Ambient": bisher hatten nur "forest"/"dense_forest" überhaupt
## Ambient-Optik — "meadow"/"desert"/"swamp" (siehe BiomeRegistry, insgesamt 6 Biome) standen
## komplett leer da. Drei weitere, aus genau demselben Baukasten wie Laub/Glühwürmchen oben
## (GPUParticles3D + ParticleProcessMaterial, biomabhängig ein-/ausgeblendet über
## _check_ambient_state()) — siehe _AMBIENT_GROUPS unten für den jetzt generischen
## Umschalt-Mechanismus, der auch künftige Biom-Ambiences ohne weiteren Sonderfall-Code
## aufnimmt. "mountain" bewusst ausgelassen (kein überzeugender eigener Ambient-Effekt ohne
## Partikel-Schnee zu duplizieren, der bereits über WeatherVfx bei echtem Schneewetter läuft).
const MEADOW_BIOMES := ["meadow"]
const DESERT_BIOMES := ["desert"]
const SWAMP_BIOMES := ["swamp"]

const POLLEN_HEIGHT := 1.0
const POLLEN_AREA := Vector2(6.0, 6.0)
const POLLEN_COUNT := 20

const DUST_HEIGHT := 1.2
const DUST_AREA := Vector2(7.0, 7.0)
const DUST_COUNT := 18

const MIDGE_HEIGHT := 0.7
const MIDGE_AREA := Vector2(4.0, 4.0)
const MIDGE_COUNT := 22

## Easter Egg "firefly_watcher" — so lange muss _fireflies_active am Stück
## true bleiben. Bewusst dieselbe Dauer wie SunGazeWatcher.SUN_GAZE_SECONDS
## (kein tieferer Grund als Konsistenz — "5 Sekunden" ist die gemeinsame
## Easter-Egg-Referenzdauer dieser Runde).
const FIREFLY_WATCH_SECONDS: float = 5.0
const FIREFLY_ACHIEVEMENT_ID := "firefly_watcher"

var _wind: WindField = null
var _terrain: TerrainField = null
var _time: WorldTimeService = null
var _follow_target: Node3D = null
var _leaves: Array[GPUParticles3D] = []
var _fireflies: GPUParticles3D = null
var _in_forest: bool = false
var _fireflies_active: bool = false
var _ambient_check_timer: float = 0.0

## Wunsch "weiter machen mit Ambient": generische Liste statt eines eigenen
## _xyz_active-Bools + Sonderfall-Blocks pro Biom-Effekt (wie bei Laub/Glühwürmchen oben,
## die wegen Sonderverhalten — Windrichtung fürs Laub, Easter Egg für Glühwürmchen —
## bewusst eigene Felder behalten). Jeder Eintrag: {"node": GPUParticles3D, "biomes":
## Array[String], "day_only"/"night_only": bool, "active": bool (letzter bekannter Zustand,
## für den Log-Zeilen-Vergleich), "label": String}. Siehe _check_ambient_state().
var _ambient_groups: Array[Dictionary] = []

## Easter-Egg-Meldegang (siehe Klassenkommentar) — beide dürfen leer/null
## bleiben, dann bleibt _report_firefly_watched() ein No-Op.
var _network: NetworkBridge = null
var _local_player_id: String = ""
var _firefly_watch_elapsed: float = 0.0
var _firefly_watch_reported: bool = false

## world_seed: für denselben deterministischen Wind wie WeatherVfx (keine
## zweite, abweichende Windquelle). terrain: für den Biom-Check. time_service:
## für den Tag/Nacht-Check (Glühwürmchen) — optional, ohne sie bleiben
## Glühwürmchen dauerhaft aus statt zu raten. active: false auf einem
## kopflosen dedizierten Server (kein Rendering, kein Spieler). network/
## local_player_id: optional, siehe Klassenkommentar "Easter Egg".
func configure(
	world_seed: int, terrain: TerrainField, active: bool, time_service: WorldTimeService = null,
	network: NetworkBridge = null, local_player_id: String = ""
) -> void:
	_wind = WindField.new(world_seed)
	_terrain = terrain
	_time = time_service
	_network = network
	_local_player_id = local_player_id

	visible = active
	set_process(active)
	if active:
		_build_leaves()
		_build_fireflies()
		_build_pollen()
		_build_dust()
		_build_midges()

## Partikel folgen diesem Node (typischerweise der lokale Spieler) statt
## fest an der Welt zu hängen — analog WeatherVfx.follow().
func follow(target: Node3D) -> void:
	_follow_target = target
	# Sofortiger Erst-Check statt bis zum ersten Timer-Intervall zu warten,
	# damit beim Weltbetreten mitten im Wald nicht erst 1.5s lang nichts fällt.
	_check_ambient_state()

func _process(delta: float) -> void:
	if is_instance_valid(_follow_target):
		global_position = _follow_target.global_position

	_ambient_check_timer -= delta
	if _ambient_check_timer <= 0.0:
		_ambient_check_timer = AMBIENT_CHECK_INTERVAL
		_check_ambient_state()

	_process_firefly_watch(delta)

	if not is_instance_valid(_wind):
		return
	_wind.advance(delta)
	var dir3: Vector3 = Vector3(_wind.direction.x, 0.0, _wind.direction.y)
	for leaf in _leaves:
		if not is_instance_valid(leaf):
			continue
		var pm := leaf.process_material as ParticleProcessMaterial
		if pm != null:
			# Blätter treiben deutlich stärker seitlich als Regen/Schnee —
			# sie sind leicht, kein senkrechter Fall, sondern Trudeln im Wind.
			pm.direction = (Vector3.DOWN * 0.4 + dir3 * (0.5 + _wind.strength)).normalized()
	# Glühwürmchen wandern nur leicht mit dem Wind (kein "Fall" wie Laub) —
	# die eigentliche Bewegung kommt aus Turbulenz/Orbit in _build_fireflies().
	if is_instance_valid(_fireflies):
		var firefly_pm := _fireflies.process_material as ParticleProcessMaterial
		if firefly_pm != null:
			firefly_pm.direction = (Vector3.UP * 0.1 + dir3 * _wind.strength * 0.15).normalized()
	# Wüsten-Sandstaub: anders als Laub/Glühwürmchen überwiegend VOM WIND GETRIEBEN statt nur
	# leicht beeinflusst (siehe _build_dust()-Kommentar "wird in _process() auf die echte
	# Windrichtung gesetzt") — daher über "wind_follow" markiert statt hart im generischen
	# _ambient_groups-Dict verdrahtet (die anderen Gruppen brauchen das nicht).
	for group in _ambient_groups:
		if not bool(group.get("wind_follow", false)):
			continue
		var node: GPUParticles3D = group["node"]
		if not is_instance_valid(node):
			continue
		var dust_pm := node.process_material as ParticleProcessMaterial
		if dust_pm != null:
			dust_pm.direction = (dir3 * (0.3 + _wind.strength)).normalized()

func _check_ambient_state() -> void:
	# Einmal berechnet statt wie vorher implizit zweimal (einmal hier, einmal im neuen
	# generischen _ambient_groups-Durchlauf unten) — bleibt "" ohne gültiges Terrain/
	# Follow-Target (matcht keine Biom-Liste, schaltet alles sauber ab statt zu raten).
	var biome_id: String = ""
	if is_instance_valid(_terrain) and is_instance_valid(_follow_target):
		biome_id = _terrain.get_biome_id_at(global_position.x, global_position.z)

	var forest_active: bool = biome_id in FOREST_BIOMES
	var fireflies_active: bool = biome_id in FIREFLY_BIOMES and _is_night()

	if forest_active != _in_forest:
		_in_forest = forest_active
		for leaf in _leaves:
			if is_instance_valid(leaf):
				leaf.emitting = _in_forest
		AppLogger.log_info(
			"AmbientForestVfx: fallendes Laub %s." % ("aktiviert" if _in_forest else "deaktiviert"),
			LOG_CAT
		)

	if fireflies_active != _fireflies_active:
		_fireflies_active = fireflies_active
		if is_instance_valid(_fireflies):
			_fireflies.emitting = _fireflies_active
		AppLogger.log_info(
			"AmbientForestVfx: Glühwürmchen %s." % ("aktiviert" if _fireflies_active else "deaktiviert"),
			LOG_CAT
		)

	# Wunsch "weiter machen mit Ambient": generischer Durchlauf für Pollen/Staub/Mücken (und
	# jede künftige Biom-Ambience) statt eines weiteren Hand-Sonderfalls pro Effekt — siehe
	# _ambient_groups-Kommentar. Nutzt dasselbe biome_id von oben.
	for group in _ambient_groups:
		var wants_active: bool = biome_id in (group["biomes"] as Array)
		if wants_active and bool(group["day_only"]) and _is_night():
			wants_active = false
		if wants_active and bool(group["night_only"]) and not _is_night():
			wants_active = false
		if wants_active != bool(group["active"]):
			group["active"] = wants_active
			var node: GPUParticles3D = group["node"]
			if is_instance_valid(node):
				node.emitting = wants_active
			AppLogger.log_info(
				"AmbientForestVfx: %s %s." % [group["label"], "aktiviert" if wants_active else "deaktiviert"],
				LOG_CAT
			)

## true zwischen NIGHT_START_HOUR und NIGHT_END_HOUR (über Mitternacht hinweg).
## Ohne time_service (nicht übergeben) bewusst IMMER false statt zu raten —
## keine Glühwürmchen ist die sicherere Fehlannahme als welche am helllichten Tag.
func _is_night() -> bool:
	if not is_instance_valid(_time):
		return false
	var h: float = _time.day_time
	return h >= NIGHT_START_HOUR or h < NIGHT_END_HOUR

## Easter Egg "firefly_watcher" (siehe Klassenkommentar) — _fireflies_active
## wird bereits alle AMBIENT_CHECK_INTERVAL Sekunden von _check_ambient_state()
## aktualisiert, hier nur der Timer obendrauf. _fireflies_active bleibt
## zwischen zwei Checks stabil (kein Flackern), delta-Akkumulation ist also
## trotz des selteneren Checks korrekt.
func _process_firefly_watch(delta: float) -> void:
	if _firefly_watch_reported:
		return
	if not _fireflies_active:
		_firefly_watch_elapsed = 0.0
		return
	_firefly_watch_elapsed += delta
	if _firefly_watch_elapsed >= FIREFLY_WATCH_SECONDS:
		_report_firefly_watched()

func _report_firefly_watched() -> void:
	_firefly_watch_reported = true
	if not is_instance_valid(_network) or _local_player_id.is_empty():
		AppLogger.log_warn(
			"AmbientForestVfx: NetworkBridge/local_player_id fehlt — kann '%s' nicht melden." % FIREFLY_ACHIEVEMENT_ID,
			LOG_CAT
		)
		return
	_network.send_client_observed_achievement(_local_player_id, FIREFLY_ACHIEVEMENT_ID)
	AppLogger.log_info("AmbientForestVfx: '%s' gemeldet." % FIREFLY_ACHIEVEMENT_ID, LOG_CAT)

func _build_leaves() -> void:
	for i in range(LEAF_VARIANTS):
		var p := GPUParticles3D.new()
		p.name = "FallingLeaves_%d" % i
		p.amount = LEAF_COUNT_PER_VARIANT
		p.lifetime = 7.0 + i * 0.8  # leicht versetzte Lebenszeit -> weniger synchrones Fallen
		p.emitting = false
		p.position = Vector3(0.0, LEAF_HEIGHT, 0.0)
		p.visibility_aabb = AABB(
			Vector3(-LEAF_AREA.x, -LEAF_HEIGHT - 1.0, -LEAF_AREA.y),
			Vector3(LEAF_AREA.x * 2.0, LEAF_HEIGHT + 2.0, LEAF_AREA.y * 2.0)
		)
		p.draw_pass_1 = _build_leaf_mesh(i)

		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.DOWN
		pm.spread = 30.0
		pm.gravity = Vector3(0.0, -0.35, 0.0)
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.2
		# Trudeln: Rotation + Orbit geben den typischen "Blatt fällt nicht
		# gerade, sondern schaukelt" Effekt, den Regen/Schnee nicht brauchen.
		pm.orbit_velocity_min = 0.08
		pm.orbit_velocity_max = 0.22
		pm.angular_velocity_min = -60.0
		pm.angular_velocity_max = 60.0
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(LEAF_AREA.x, 0.05, LEAF_AREA.y)
		pm.scale_min = 0.7
		pm.scale_max = 1.3
		p.process_material = pm

		add_child(p)
		_leaves.append(p)

## Warme, selbstleuchtende Punkte, die frei um den Spieler herum schweben
## statt zu fallen (kaum Schwerkraft, Turbulenz statt gerichteter Bewegung).
## emission_enabled statt nur heller albedo_color, damit WorldFactorys
## env.glow_enabled (siehe dortiger Kommentar) sie tatsächlich zum Leuchten
## bringt statt nur eine helle Fläche zu zeichnen.
func _build_fireflies() -> void:
	var p := GPUParticles3D.new()
	p.name = "Fireflies"
	p.amount = FIREFLY_COUNT
	p.lifetime = 14.0
	p.emitting = false
	p.position = Vector3(0.0, FIREFLY_HEIGHT, 0.0)
	p.visibility_aabb = AABB(
		Vector3(-FIREFLY_AREA.x, -FIREFLY_HEIGHT - 1.0, -FIREFLY_AREA.y),
		Vector3(FIREFLY_AREA.x * 2.0, FIREFLY_HEIGHT + 3.0, FIREFLY_AREA.y * 2.0)
	)
	p.draw_pass_1 = _build_firefly_mesh()

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0  # in alle Richtungen, kein bevorzugtes "Fallen"
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.15
	pm.orbit_velocity_min = 0.03
	pm.orbit_velocity_max = 0.10
	# Turbulenz statt reiner Ballistik -> unregelmäßiges Umherschweben statt
	# einer erkennbaren Wurfbahn (ungetestet, Godot-4.3-Feature, siehe
	# Klassenkommentar zum fehlenden Runtime hier).
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 1.5
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(FIREFLY_AREA.x, 1.0, FIREFLY_AREA.y)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	# Sanftes Auf-/Abblenden über die Lebenszeit statt hartem Erscheinen/
	# Verschwinden — ein Alpha-Kurvenverlauf über CanvasItemMaterial wäre hier
	# Overkill, ein simpler Farbverlauf über color_ramp reicht.
	var fade_gradient := Gradient.new()
	fade_gradient.set_color(0, Color(1, 1, 1, 0))
	fade_gradient.add_point(0.15, Color(1, 1, 1, 1))
	fade_gradient.add_point(0.85, Color(1, 1, 1, 1))
	fade_gradient.set_color(1, Color(1, 1, 1, 0))
	var fade_ramp := GradientTexture1D.new()
	fade_ramp.gradient = fade_gradient
	pm.color_ramp = fade_ramp
	p.process_material = pm

	add_child(p)
	_fireflies = p

## Meadow, tagsüber (day_only) — sanft nach oben treibende, warm-golden angehauchte Pollen-/
## Samenflocken, die im Licht zu glänzen scheinen (leichtes emission). Mechanisch sehr nah an
## _build_fireflies() (Turbulenz statt Ballistik, kaum Schwerkraft), aber ohne deren
## Easter-Egg-Sonderbehandlung — deshalb hier und nicht als vierte Variante dort.
func _build_pollen() -> void:
	var p := GPUParticles3D.new()
	p.name = "MeadowPollen"
	p.amount = POLLEN_COUNT
	p.lifetime = 10.0
	p.emitting = false
	p.position = Vector3(0.0, POLLEN_HEIGHT, 0.0)
	p.visibility_aabb = AABB(
		Vector3(-POLLEN_AREA.x, -POLLEN_HEIGHT - 1.0, -POLLEN_AREA.y),
		Vector3(POLLEN_AREA.x * 2.0, POLLEN_HEIGHT + 2.5, POLLEN_AREA.y * 2.0)
	)
	p.draw_pass_1 = _build_dot_mesh(Color(0.95, 0.88, 0.55), 0.045, true)

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 150.0
	pm.gravity = Vector3(0.0, 0.03, 0.0)  # minimal positiv statt 0 -> treibt sichtbar nach oben
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.1
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 2.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(POLLEN_AREA.x, 0.3, POLLEN_AREA.y)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	p.process_material = pm

	add_child(p)
	_ambient_groups.append({
		"node": p, "biomes": MEADOW_BIOMES, "day_only": true, "night_only": false,
		"active": false, "label": "Wiesen-Pollen",
	})

## Desert, Tag wie Nacht (kein day_only/night_only) — flach treibender Sandstaub, überwiegend
## seitlich vom Wind getragen statt zu fallen oder zu steigen (anders als Laub/Pollen).
func _build_dust() -> void:
	var p := GPUParticles3D.new()
	p.name = "DesertDust"
	p.amount = DUST_COUNT
	p.lifetime = 9.0
	p.emitting = false
	p.position = Vector3(0.0, DUST_HEIGHT, 0.0)
	p.visibility_aabb = AABB(
		Vector3(-DUST_AREA.x, -DUST_HEIGHT - 1.0, -DUST_AREA.y),
		Vector3(DUST_AREA.x * 2.0, DUST_HEIGHT + 2.0, DUST_AREA.y * 2.0)
	)
	p.draw_pass_1 = _build_dot_mesh(Color(0.82, 0.70, 0.45, 0.55), 0.05, false)

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.RIGHT   # wird in _process() ohnehin auf die echte Windrichtung gesetzt
	pm.spread = 25.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.3
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.3
	pm.turbulence_noise_scale = 1.2
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(DUST_AREA.x, 0.4, DUST_AREA.y)
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	p.process_material = pm

	add_child(p)
	_ambient_groups.append({
		"node": p, "biomes": DESERT_BIOMES, "day_only": false, "night_only": false,
		"active": false, "label": "Wüsten-Sandstaub", "wind_follow": true,
	})

## Swamp, Tag wie Nacht — enges, dunkles Mückenschwarm-Gewusel nah am Boden (starke Turbulenz,
## kaum gerichtete Bewegung, wie Glühwürmchen aber unbeleuchtet/dunkel statt leuchtend).
func _build_midges() -> void:
	var p := GPUParticles3D.new()
	p.name = "SwampMidges"
	p.amount = MIDGE_COUNT
	p.lifetime = 6.0
	p.emitting = false
	p.position = Vector3(0.0, MIDGE_HEIGHT, 0.0)
	p.visibility_aabb = AABB(
		Vector3(-MIDGE_AREA.x, -MIDGE_HEIGHT - 0.5, -MIDGE_AREA.y),
		Vector3(MIDGE_AREA.x * 2.0, MIDGE_HEIGHT + 1.5, MIDGE_AREA.y * 2.0)
	)
	p.draw_pass_1 = _build_dot_mesh(Color(0.12, 0.11, 0.10), 0.025, false)

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.ZERO
	pm.spread = 180.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 3.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(MIDGE_AREA.x, 0.3, MIDGE_AREA.y)
	pm.scale_min = 0.7
	pm.scale_max = 1.1
	p.process_material = pm

	add_child(p)
	_ambient_groups.append({
		"node": p, "biomes": SWAMP_BIOMES, "day_only": false, "night_only": false,
		"active": false, "label": "Sumpf-Mücken",
	})

## Gemeinsame Punkt-Mesh-Basis für Pollen/Staub/Mücken — reuse von
## ProceduralTextureFactory.snowflake() (weicher runder Fleck) statt dreier neuer Texturen,
## nur eingefärbt/skaliert. `glow`: Pollen bekommt ein ganz leichtes emission (soll im Licht
## glänzen), Staub/Mücken bleiben unbeleuchtet.
func _build_dot_mesh(color: Color, size: float, glow: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.albedo_texture = ProceduralTextureFactory.snowflake()
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.8
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = mat
	return q

func _build_leaf_mesh(hue_seed: int) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Blatt dreht sich frei, beide Seiten sichtbar
	mat.albedo_texture = ProceduralTextureFactory.leaf_card(48, hue_seed)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = mat
	return q

func _build_firefly_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true  # nimmt den color_ramp-Fade oben auf
	mat.albedo_color = Color(0.85, 0.95, 0.35)
	mat.albedo_texture = ProceduralTextureFactory.snowflake()  # weicher runder Punkt, hier zweckentfremdet
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.95, 0.35)
	mat.emission_energy_multiplier = 2.5
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = mat
	return q
