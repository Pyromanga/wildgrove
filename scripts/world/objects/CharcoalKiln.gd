extends HarvestableEntity
class_name CharcoalKiln

## CharcoalKiln — Rauchender Kohlenmeiler (Skill "charcoal_burning" / Köhlerei).
## Lifecycle, Despawn und Harvest-State kommen von HarvestableEntity.
## Hier: nur Typ-ID, InteractableData und Visuals.
##
## Echte Welt: Im Meiler verschwelt Holz unter sehr wenig Luft über Tage zu
## Holzkohle (Pyrolyse); sie brennt heißer als Holz und war der Brennstoff der
## Schmiede. Spawnt in Wäldern (BiomeRegistry). Respawn: siehe
## WorldService.configure().
##
## Der Bildungstext lebt in data/skills/charcoal_burning.tres.

func _get_entity_type_id() -> String:
	return "charcoal_kiln"

func _build_interactable_data() -> InteractableData:
	var d := InteractableData.new()
	d.id           = "harvest_charcoal_kiln"
	d.label        = "Holzkohle bergen"
	d.duration     = 3.0
	d.xp_type      = "charcoal_burning"
	d.xp_amount    = 20
	d.loot_table   = preload("res://data/loot_tables/loot_charcoal_kiln.tres")
	d.inspect_text = "Ein rauchender Erdhügel: der Kohlenmeiler. Wusstest du? Darin brennt Holz tagelang mit sehr wenig Luft zu Holzkohle, die heißer brennt als Holz."
	return d

func _build_visuals() -> void:
	_add_placeholder_cylinder(0.8, 0.9, Color(1.0, 0.95, 0.9), "charcoal")
	_add_smoke()
	AppLogger.log_debug("CharcoalKiln Placeholder-Zylinder erstellt.", "charcoal_kiln")

## Kleiner Ambient-Bonus zur neuen charcoal()-Textur: der Inspect-Text nennt den
## Meiler bereits "rauchenden Erdhügel", visuell kam bisher aber kein Rauch —
## reiner Deko-Effekt, kein Zustand, kein Aus-/Einschalten nötig (der Meiler
## "brennt" die ganze Zeit, bis er abgeerntet und despawnt wird). Grauer,
## weicher Punkt (ProceduralTextureFactory.snowflake(), hier zweckentfremdet)
## statt einer neuen Sprite-Textur — Rauch ist im Kern derselbe weiche
## Kreis-Falloff wie eine Schneeflocke, nur größer/grau/langsamer.
func _add_smoke() -> void:
	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = 10
	smoke.lifetime = 4.0
	smoke.position = Vector3(0.0, 0.95, 0.0)
	smoke.visibility_aabb = AABB(Vector3(-1.0, -0.2, -1.0), Vector3(2.0, 4.0, 2.0))

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.55, 0.55, 0.55)
	mat.albedo_texture = ProceduralTextureFactory.snowflake()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = mat
	smoke.draw_pass_1 = mesh

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.gravity = Vector3(0.0, 0.15, 0.0)  # steigt langsam, statt zu fallen wie Regen/Schnee/Laub
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.3
	pm.scale_min = 1.0
	pm.scale_max = 2.2
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	# Weiches Ein-/Ausblenden über die Lebenszeit statt hartem Erscheinen/
	# Verschwinden — gleicher Trick wie bei AmbientForestVfx.Fireflies.
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 0.6))
	fade.add_point(1.0, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	smoke.process_material = pm
	smoke.emitting = true
	add_child(smoke)
