class_name InteractionSensor extends Area3D

## InteractionSensor — findet das nächste interagierbare Objekt in Reichweite.
##
## Verantwortung: Synchronen Lookup via get_closest() liefern.
## Kein Event-Emitting — das erledigt InteractableComponent aus seiner eigenen Area3D.
##
## WARUM kein EventBus hier?
##   InteractableComponent hat eine eigene Area3D pro Objekt und emittiert
##   proximity_changed wenn DER Player in DIESES Objekt eintritt/verlässt.
##   InteractionSensor ist die Player-Seite: "Was ist gerade in meiner Nähe?"
##   → synchrone Abfrage für ContextMenuController.
##
## CollisionShape wird von Player._build_sensor() gesetzt (Radius: 2.5m).
## Physics-Layer muss im Editor konfiguriert werden:
##   Layer 2 (Interactables), Mask entsprechend — NICHT hier im Code!

const LOG_CAT := "Sensor"

var _last_closest: Node3D = null


func _ready() -> void:
	Logger.log_debug(
		"InteractionSensor bereit. Monitoring: %s, Monitorable: %s."
		% [str(monitoring), str(monitorable)],
		LOG_CAT
	)

	# Überwachung aktivieren wenn noch nicht gesetzt (Fallback)
	if not monitoring:
		monitoring = true
		Logger.log_warn("monitoring war false — automatisch aktiviert.", LOG_CAT)


func _physics_process(_delta: float) -> void:
	## Erkennt Änderungen im nächsten Ziel und loggt sie.
	## KEIN EventBus-Emit hier — InteractableComponent übernimmt proximity_changed.
	var current := get_closest()
	if current != _last_closest:
		if is_instance_valid(current):
			Logger.log_info(
				"Nächstes Ziel: '%s' (Dist: %.2fm)."
				% [current.name, global_position.distance_to(current.global_position)],
				LOG_CAT
			)
		elif is_instance_valid(_last_closest):
			Logger.log_info("Kein Ziel mehr in Reichweite.", LOG_CAT)
		_last_closest = current


## Gibt das nächste Objekt in der "interactable"-Gruppe zurück, oder null.
## Nutzt get_overlapping_bodies() — gibt Physics-Bodies zurück (StaticBody3D, CharacterBody3D).
## OakTree/IronOre sind Node3D, aber InteractableComponent.get_parent() ist der Physics-Body?
## NEIN: OakTree extends Node3D (kein Physics-Body). Area3D erkennt ihn via
## CollisionShape3D des Sensors — Area3D overlaps werden über area_entered geliefert.
## Für korrekte Erkennung: InteractableComponent._setup_detection() erstellt
## eine eigene Area3D pro Entity. InteractionSensor nutzt get_overlapping_areas()!
func get_closest() -> Node3D:
	var closest: Node3D = null
	var min_dist := 999.0

	# Overlapping Bodies (für CharacterBody3D, StaticBody3D Entities)
	for body in get_overlapping_bodies():
		if body is Node3D and body.is_in_group("interactable"):
			var dist := global_position.distance_to((body as Node3D).global_position)
			if dist < min_dist:
				min_dist = dist
				closest = body

	# Overlapping Areas (für Area3D-basierte Entities — deckt InteractableComponent ab)
	for area in get_overlapping_areas():
		# Die InteractableComponent erstellt eine Area3D als Kind.
		# Ihr Parent (z.B. OakTree) ist das eigentliche Interagierbare.
		var area_parent := area.get_parent()
		if is_instance_valid(area_parent) and area_parent.is_in_group("interactable"):
			var dist := global_position.distance_to(area_parent.global_position)
			if dist < min_dist:
				min_dist = dist
				closest = area_parent

	return closest


## Gibt true zurück wenn gerade ein Ziel in Reichweite ist.
func has_target() -> bool:
	return is_instance_valid(get_closest())
