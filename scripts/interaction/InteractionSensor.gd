class_name InteractionSensor extends Area3D

## InteractionSensor — findet das nächste interagierbare Objekt in Reichweite.
##
## Verantwortung: Synchronen Lookup via get_closest() liefern UND
## proximity_changed emittieren wenn sich das nächste Ziel ändert.
##
## WICHTIG: Der Sensor ist die einzige Autorität für proximity_changed.
##   InteractableComponent emittiert proximity_changed nur noch für Logging-Zwecke.
##   Der Sensor aggregiert alle Area3D-Überlappungen und gibt nur das nächste Ziel aus.
##   Das verhindert Flickering wenn der Spieler zwischen zwei Entities läuft.
##
## CollisionShape wird von Player._build_sensor() gesetzt (Radius: 2.5m).

const LOG_CAT := "Sensor"

var _last_closest: Node3D = null
var _bus: IEventBus = null

## Tap-gewähltes Ziel (siehe InteractionTargetPicker) — hat Vorrang vor dem
## nächstgelegenen Objekt, SOLANGE es tatsächlich in der aktuellen Overlap-Menge
## steckt (also physisch in Reichweite ist). Verlässt der Spieler die Reichweite,
## fällt get_closest() automatisch auf die normale Distanz-Auswahl zurück statt
## ein unerreichbares Ziel weiter zu bevorzugen — kein zweiter Reichweiten-Check
## nötig, die Autorität prüft die echte Reichweite ohnehin serverseitig erneut
## (WorldService._max_interaction_range_for()).
var _manual_target: Node3D = null

## Wird von InteractionTargetPicker gesetzt, wenn der Spieler ein Objekt antippt.
func set_manual_target(node: Node3D) -> void:
	_manual_target = node

## Wird von InteractionTargetPicker gesetzt, wenn die Auswahl aufgehoben wird
## (erneutes Antippen desselben Ziels, Antippen von "nichts", oder Ziel despawnt).
func clear_manual_target() -> void:
	_manual_target = null

## Für InteractionTargetPicker: ist `node` gerade Teil der Overlap-Menge (d.h.
## würde von get_closest() als Kandidat gefunden werden)? Bestimmt, ob eine
## Tap-Auswahl sofort "in Reichweite" ist oder nur als Fernziel markiert wird.
func is_in_range(node: Node3D) -> bool:
	return _collect_candidates().has(node)

## Für InteractionTargetPicker._deselect(): steckt gerade eine Tap-Auswahl (statt der
## normalen automatischen Distanz-Auswahl) im Sensor? Damit "Tap ins Leere" nur die
## MANUELLE Auswahl aufhebt, statt danach auch das ganz normale proximity-Highlight
## des zufällig nächsten Objekts zu verschlucken (siehe BUGFIX 2026-09-26 dort).
func has_manual_target() -> bool:
	return is_instance_valid(_manual_target)

## Wird von Player._build_sensor() unmittelbar nach add_child() aufgerufen —
## kein AutoLoad-Zugriff, Konstruktor-Injection-Äquivalent für SceneTree-Nodes.
func inject_bus(bus: IEventBus) -> void:
	_bus = bus

func _ready() -> void:
	add_to_group("interaction_sensor")
	AppLogger.log_debug(
		"InteractionSensor bereit. Monitoring: %s, Monitorable: %s."
		% [str(monitoring), str(monitorable)],
		LOG_CAT
	)

	if not monitoring:
		monitoring = true
		AppLogger.log_warn("monitoring war false — automatisch aktiviert.", LOG_CAT)

## Gibt das aktuell nächste Ziel zurück (oder null).
## Wird von InteractableComponent genutzt um zu prüfen ob SIE das Ziel ist.
func get_current_target() -> Node3D:
	return _last_closest

func _physics_process(_delta: float) -> void:
	if _bus == null:
		return  # inject_bus() noch nicht aufgerufen — Player baut Sensor noch auf

	var current := get_closest()

	if current == _last_closest:
		return  # Kein Wechsel — nichts zu tun

	# Ziel hat sich geändert — proximity_changed für altes und neues Ziel emittieren
	if is_instance_valid(_last_closest):
		AppLogger.log_debug("Ziel verloren: '%s'." % _last_closest.name, LOG_CAT)
		_bus.world().emit_proximity_changed(_last_closest, false)

	if is_instance_valid(current):
		var dist := global_position.distance_to(current.global_position)
		AppLogger.log_info(
			"Nächstes Ziel: '%s' (Dist: %.2fm)." % [current.name, dist],
			LOG_CAT
		)
		_bus.world().emit_proximity_changed(current, true)
	else:
		AppLogger.log_info("Kein Ziel mehr in Reichweite.", LOG_CAT)

	_last_closest = current

## Gibt das nächste Objekt in der "interactable"-Gruppe zurück, oder null.
## Bevorzugt _manual_target (Tap-Auswahl, siehe InteractionTargetPicker), SOLANGE
## es tatsächlich in der aktuellen Overlap-Menge steckt — sonst normale Distanz-Auswahl.
func get_closest() -> Node3D:
	var candidates := _collect_candidates()
	if is_instance_valid(_manual_target) and candidates.has(_manual_target):
		return _manual_target

	var closest: Node3D = null
	var min_dist := 999.0
	for node in candidates:
		var dist := global_position.distance_to(node.global_position)
		if dist < min_dist:
			min_dist = dist
			closest = node
	return closest

## Sammelt alle aktuell überlappenden "interactable"-Entities (Bodies + Areas),
## dedupliziert. Ausgelagert aus get_closest() damit is_in_range() (für
## InteractionTargetPicker) dieselbe Kandidatenmenge nutzen kann, ohne die
## Auswahl-Logik zu duplizieren.
func _collect_candidates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	# Der Sensor hängt als Kind direkt am eigenen Spieler-Node (siehe
	# Player._build_sensor()). Dieser Spieler ist über PlayerAttack/
	# PlayerTrade/PlayerThank/PlayerPickpocket ebenfalls in der Gruppe
	# "interactable" (für ANDERE Spieler gedacht, ADR-032/035/036/039).
	# Ohne diesen Ausschluss würde sich der Sensor mit Distanz ~0m immer
	# selbst als nächstes Ziel finden und jedes echte Interactable
	# (Baum, Erz, Quest-NPC, Gegner) verdecken — Bug: im Solo-Spiel wird
	# dann für jede Interaktion "Ein anderer Spieler." angezeigt.
	var owner_node := get_parent()

	# Overlapping Bodies (für CharacterBody3D, StaticBody3D Entities)
	for body in get_overlapping_bodies():
		if body == owner_node:
			continue
		if body is Node3D and body.is_in_group("interactable"):
			result.append(body)

	# Overlapping Areas (für Area3D-basierte Entities — deckt InteractableComponent ab).
	# Node-Hierarchie bei OakTree/IronOre (extends Node3D):
	#   OakTree  ← Entity-Root, in Gruppe "interactable"
	#     └─ InteractableComponent (Node3D)
	#          └─ ProximityDetector (Node3D)
	#               └─ DetectionArea (Area3D)  ← get_overlapping_areas() liefert diesen
	# InteractionGroupUtil läuft die Vorfahren-Kette hoch (siehe dort).
	for area in get_overlapping_areas():
		var found := InteractionGroupUtil.resolve_interactable(area.get_parent(), owner_node)
		if is_instance_valid(found) and not result.has(found):
			result.append(found)

	return result

## Gibt true zurück wenn gerade ein Ziel in Reichweite ist.
func has_target() -> bool:
	return is_instance_valid(get_closest())

## ALLE aktuell in Reichweite befindlichen Interactables, nicht nur das eine "closest"-Ziel —
## für Player.get_all_nearby_context_actions() (BUGFIX 2026-09-26, "Kontextmenü soll alles
## anzeigen was in der Nähe ist"): ein Objekt mit großer Collision-Box (z.B. Leiter) kann
## andere nahe Objekte (Erz) für den Tap-Raycast verdecken — über das Kontextmenü sollen sie
## trotzdem erreichbar sein, ganz ohne Tap. Öffentlicher Alias für _collect_candidates()
## (die bleibt intern für get_closest()/is_in_range()) — eigener Name macht den Zweck an der
## Aufrufstelle klar, statt eine "privat" benannte Methode von außen zu importieren.
func get_all_candidates() -> Array[Node3D]:
	return _collect_candidates()
