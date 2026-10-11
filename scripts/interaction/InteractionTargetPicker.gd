extends Node
class_name InteractionTargetPicker

## InteractionTargetPicker — Tap/Klick-Zielauswahl (RuneScape-/Minecraft-Stil): antippen
## wählt EXPLIZIT das gemeinte Objekt aus (statt nur "das nächste in Reichweite", was bei
## mehreren Bäumen nebeneinander mehrdeutig ist) und zeigt es umrandet an (InteractionOutline).
##
## ABLAUF
##   Tap auf Objekt        → anwählen + Umrandung (Button/Kontextmenü beziehen sich darauf)
##   Tap auf gewähltes Obj → in Reichweite: Hauptaktion starten (wie der Interaktions-Button,
##                           z.B. "Weide fällen"), sonst Hinweis "zu weit weg" (Auswahl bleibt)
##   Tap ins Leere         → abwählen (nur bei einer echten Tap-Auswahl, siehe _deselect())
##
## BUGFIX (2026-09-26, "Umrandung soll auch automatisch bei Proximity/Autodetect
## funktionieren — im Endeffekt worauf das ! zeigt"): die Umrandung ist NICHT mehr exklusiv
## an einen Tap gebunden — sie folgt proximity_changed (InteractionSensor), also demselben
## "was ist gerade WIRKLICH das aktuelle Ziel"-Signal, dem auch der Interaktions-Button
## (InteractionButtonController) und das Kontextmenü folgen. Läuft der Spieler einfach an
## einem Baum vorbei (Autodetect, kein Tap), wird der jetzt genauso umrandet wie ein
## angetipptes Ziel — beides landet am Ende in derselben _apply_outline().
##
## TREFFERERMITTLUNG (FIX 2026-09-21): Bäume/Erze haben keinen Collider, und die frühere
## Area3D-Raycast-Lösung traf die 3-m-Erkennungskugeln (ProximityDetector) statt der Objekte —
## der Tap landete beim "nächsten Kugelrand" auf dem Strahl, nicht beim sichtbaren Objekt.
## Jetzt: Strahl gegen die sichtbaren Mesh-Boxen (AABB) aller "interactable"-Nodes; ein
## Physik-Strahl nur gegen Körper (Terrain, Bauteile) sorgt für Verdeckung (ein Baum hinter
## einem Hügel ist nicht anwählbar).
##
## Gilt generisch für ALLES in der Gruppe "interactable". Kein neuer Interaktions-Pfad: die
## Auswahl geht an InteractionSensor.set_manual_target(); UI/Executor laufen unverändert.
## Kein Click-to-move (bewusst außerhalb des Scopes).
##
## Kein Service — direktes Child des Player-Nodes. Empfängt world_tap_requested (TouchInput)
## über den injizierten IEventBus.

const LOG_CAT := "TargetPicker"
const MAX_RAY_DISTANCE: float = 60.0
## Treffer-Toleranz um die Mesh-Box (Meter) — Finger sind ungenauer als Pixel.
const PICK_PADDING: float = 0.2
## Ein Objekt gilt als "nicht verdeckt", wenn es höchstens so weit hinter dem ersten festen
## Treffer beginnt (Bauteile/Gegner haben selbst Körper, ihre Box beginnt knapp davor/dahinter).
const OCCLUSION_TOLERANCE: float = 0.75

var _bus: IEventBus = null
var _camera: PlayerCamera = null
var _sensor: InteractionSensor = null
var _owner_node: Node3D = null

var _outline: InteractionOutline = null

## Wird von PlayerSetup.build() unmittelbar nach add_child() aufgerufen.
func setup(camera: PlayerCamera, sensor: InteractionSensor, owner_node: Node3D) -> void:
	_camera = camera
	_sensor = sensor
	_owner_node = owner_node

## Wird von Player.on_spawn() aufgerufen — analog InteractionSensor.inject_bus()/
## TouchInput.inject_bus().
func inject_bus(bus: IEventBus) -> void:
	_bus = bus
	_bus.world().world_tap_requested.connect(_on_world_tap)
	# BUGFIX (2026-09-26): siehe Klassenkommentar oben — Umrandung folgt jetzt proximity_changed.
	_bus.world().proximity_changed.connect(_on_proximity_changed)
	# Versions-Beleg im Log: fehlt diese Zeile, läuft ein älterer Stand dieses Scripts.
	AppLogger.log_info("Picker bereit (AABB-Treffer, Zweit-Tap = Hauptaktion, Auto-Highlight).", LOG_CAT)

func _exit_tree() -> void:
	_clear_outline()

## Highlight nur solange gültig, wie das Ziel noch existiert (z.B. Baum abgeerntet).
func _process(_delta: float) -> void:
	if is_instance_valid(_outline) and not _outline.is_target_valid():
		_clear_outline()
		if is_instance_valid(_sensor):
			_sensor.clear_manual_target()

func _on_world_tap(screen_pos: Vector2) -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(_camera.camera):
		AppLogger.log_warn("Tap ignoriert: keine gültige Kamera.", LOG_CAT)
		return

	var hit := _pick(screen_pos)
	if hit == null:
		AppLogger.log_info("Tap @ %s: kein Ziel getroffen." % str(screen_pos), LOG_CAT)
		_deselect()
		return

	if is_instance_valid(_outline) and _outline.get_target() == hit:
		AppLogger.log_info("Tap @ %s: gewähltes Ziel '%s' erneut angetippt." % [str(screen_pos), hit.name], LOG_CAT)
		_activate_selected(hit)
		return

	_select(hit)

# ─────────────────────────────────────────────
# Treffer
# ─────────────────────────────────────────────

func _pick(screen_pos: Vector2) -> Node3D:
	var cam := _camera.camera
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)

	var solid_dist := _solid_hit_distance(cam, origin, dir)
	return pick_from_ray(get_tree().get_nodes_in_group("interactable"),
		origin, dir, solid_dist, _owner_node)

## Entfernung zum ersten festen Treffer (nur Körper: Terrain, Bauteile, Gegner), sonst
## MAX_RAY_DISTANCE. Areas zählen bewusst nicht (Erkennungskugeln, Trigger).
func _solid_hit_distance(cam: Camera3D, origin: Vector3, dir: Vector3) -> float:
	var params := PhysicsRayQueryParameters3D.create(origin, origin + dir * MAX_RAY_DISTANCE)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	if is_instance_valid(_owner_node) and _owner_node is CollisionObject3D:
		params.exclude = [(_owner_node as CollisionObject3D).get_rid()]
	var result := cam.get_world_3d().direct_space_state.intersect_ray(params)
	if result.is_empty():
		return MAX_RAY_DISTANCE
	return origin.distance_to(result["position"] as Vector3)

## Reine Auswahl-Logik (statisch, ohne Physik → testbar): das nächste Interactable, dessen
## sichtbare Mesh-Box vom Strahl getroffen wird und das nicht hinter `solid_dist` verdeckt ist.
static func pick_from_ray(
	candidates: Array, origin: Vector3, dir: Vector3, solid_dist: float, exclude: Node = null
) -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	for c in candidates:
		if not is_instance_valid(c) or not (c is Node3D):
			continue
		var node: Node3D = c
		if node == exclude or not node.is_visible_in_tree():
			continue
		var box := compute_global_aabb(node)
		if box.size == Vector3.ZERO:
			continue
		var hit: Variant = box.grow(PICK_PADDING).intersects_ray(origin, dir)
		if hit == null:
			continue
		var d: float = origin.distance_to(hit as Vector3)
		if d > MAX_RAY_DISTANCE or d > solid_dist + OCCLUSION_TOLERANCE:
			continue
		if d < best_dist:
			best_dist = d
			best = node
	return best

## Weltraum-Box aller sichtbaren Meshes unter `root` (ohne Umrandungs-Klone). Größe ZERO,
## wenn es kein Mesh gibt.
static func compute_global_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var has_any := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and not n.name.begins_with("__outline__"):
			var mi := n as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree():
				var b: AABB = mi.global_transform * mi.get_aabb()
				box = b if not has_any else box.merge(b)
				has_any = true
		for child in n.get_children():
			stack.append(child)
	return box

# ─────────────────────────────────────────────
# Auswahl
# ─────────────────────────────────────────────

func _select(target: Node3D) -> void:
	_apply_outline(target)
	if is_instance_valid(_sensor):
		_sensor.set_manual_target(target)
	AppLogger.log_info("Ziel angetippt: '%s'." % target.name, LOG_CAT)

## proximity_changed(target, true): der Sensor hat SEIN aktuelles Ziel gewechselt — egal ob
## weil sich der Spieler einem neuen Objekt genähert hat (reine Proximity/Autodetect, kein
## Tap nötig) oder weil ein per Tap gewähltes Ziel gerade in Reichweite gekommen ist. In
## beiden Fällen ist genau das jetzt "das tatsächlich ausgewählte" Ziel (= worauf auch der
## Interaktions-Button "!" zeigt) — die Umrandung soll dem folgen, nicht nur dem expliziten
## Tap-Pfad vorbehalten sein.
##
## proximity_changed(target, false): der Sensor hat DIESES Ziel als "nicht mehr aktuell"
## gemeldet (Spieler weggelaufen, Objekt despawnt). Nur die Umrandung entfernen, wenn sie
## GENAU dieses Ziel zeigt — ein per Tap gewähltes, aber außer Reichweite befindliches Ziel
## taucht in _collect_candidates() ohnehin nie als "closest" auf und wird von diesem Signal
## daher nie fälschlich betroffen.
func _on_proximity_changed(target: Node3D, in_range: bool) -> void:
	if in_range:
		_apply_outline(target)
	elif is_instance_valid(_outline) and _outline.get_target() == target:
		_clear_outline()

## Zeigt die Umrandung für `target` — überspringt den Neuaufbau, wenn genau dieses Ziel
## schon umrandet ist (z.B. Tap auf das ohnehin schon proximity-markierte Objekt).
func _apply_outline(target: Node3D) -> void:
	if is_instance_valid(_outline) and _outline.get_target() == target:
		return
	_clear_outline()
	_outline = InteractionOutline.new(target)

## Zweiter Tap auf das gewählte Ziel: in Reichweite → Hauptaktion starten (identisch zum
## Interaktions-Button: erste Aktion, die kein "Untersuchen" ist), sonst Hinweis. Die Auswahl
## bleibt in beiden Fällen bestehen. Überlappende Starts fängt der InteractionExecutor ab.
func _activate_selected(target: Node3D) -> void:
	if _bus == null:
		return
	if not (is_instance_valid(_sensor) and _sensor.is_in_range(target)):
		AppLogger.log_info("'%s' außer Reichweite — nur markiert." % target.name, LOG_CAT)
		_bus.ui().emit_notification_requested("Zu weit weg — geh näher heran.")
		return
	if not (is_instance_valid(_owner_node) and _owner_node.has_method("get_context_actions")):
		AppLogger.log_warn("Owner hat keine get_context_actions() — Tap-Aktion nicht möglich.", LOG_CAT)
		return
	var actions: Array[InteractableAction] = _owner_node.call("get_context_actions")
	for action in actions:
		if not action.id.ends_with("_inspect"):
			AppLogger.log_info("Tap-Aktion → '%s'." % action.label, LOG_CAT)
			_bus.ui().emit_interaction_execute_requested(action)
			return
	AppLogger.log_info("'%s': keine Hauptaktion — Kontextmenü." % target.name, LOG_CAT)
	_bus.ui().emit_request_context_menu()

## "Tap ins Leere" hebt NUR eine echte Tap-Auswahl auf — steht gerade kein manuelles
## Ziel im Sensor (die Umrandung zeigt dann ohnehin schon das ganz normale, automatische
## Proximity/Autodetect-Ziel), gibt es nichts abzuwählen; sonst würde ein Leer-Tap neben
## einem längst automatisch markierten Baum dessen Umrandung fälschlich verschlucken, bis
## der Spieler sich wegbewegt (proximity_changed feuert ja nur bei einer ECHTEN Änderung).
func _deselect() -> void:
	if not (is_instance_valid(_sensor) and _sensor.has_manual_target()):
		return
	_sensor.clear_manual_target()
	# Nach dem Zurücksetzen fällt der Sensor sofort auf sein natürliches Ziel zurück
	# (falls gerade eins in Reichweite ist) — die Umrandung soll dem folgen statt einfach
	# zu verschwinden, auch wenn proximity_changed erst nächsten Physik-Tick feuert.
	var natural: Node3D = _sensor.get_closest()
	if is_instance_valid(natural):
		_apply_outline(natural)
	else:
		_clear_outline()

func _clear_outline() -> void:
	if is_instance_valid(_outline):
		_outline.destroy()
	_outline = null
