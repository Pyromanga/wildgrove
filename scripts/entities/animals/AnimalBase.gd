extends CharacterBody3D
class_name AnimalBase

## AnimalBase — Basisklasse für alle Tiere.
##
## State Machine: IDLE → WANDER → FLEE (Spieler zu nah)
## Unterklassen überschreiben _on_ready_extended() für Farbe, Größe, Speed.
##
## Delegiert Geometrie-Bau → AnimalVisualBuilder (statische Helfer-Klasse)
##
## INTERAKTION: InteractableComponent ruft _on_interacted(action_id) am Parent auf.

const LOG_CAT := "Animal"
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

enum State { IDLE, WANDER, FLEE }

var _color:        Color   = Color(0.7, 0.5, 0.3)
var _body_size:    Vector3 = Vector3(0.4, 0.6, 0.4)
var _speed:        float   = 3.0
var _flee_radius:  float   = 5.0
var _idle_time:    float   = 2.0
var _wander_range: float   = 8.0
var _home_radius:  float   = 15.0

## Kosmetische Silhouette (Ohren/Schnauze/Schwanz/Kopfschmuck) — siehe
## AnimalVisualProfile-Klassenkommentar. Bewusst GETRENNT von _color/_body_size: die
## beiden bleiben alleinige Quelle für die Kollisionskapsel (_build_collision()).
## BUGFIX ("Nach dem Fangen ist das ursprüngliche Modell weg"): AnimalCatcher gibt diese
## Felder inzwischen mit an das gespawnte Pet weiter (siehe dort) — PetComponent baut daraus
## dieselbe AnimalVisualBuilder-Silhouette statt einer schlichten Kapsel, siehe
## PetComponent._build_visuals(). Defaults ergeben ein generisches "Standardtier" für
## Unterklassen, die diese Felder nicht setzen.
var _ear_style:      int = AnimalVisualProfile.EarStyle.ROUND
var _tail_style:     int = AnimalVisualProfile.TailStyle.STUB
var _snout_style:    int = AnimalVisualProfile.SnoutStyle.SHORT
var _headgear_style: int = AnimalVisualProfile.HeadgearStyle.NONE
var _tail_scale:     float = 1.0

## Wunsch "mehr Körper für Tiere einbauen — Insekten, Spinnen, Schlangen, Fische, große
## Säugetiere": siehe AnimalVisualProfile.BodyPlan-Kommentar. Default QUADRUPED hält
## bestehende Unterklassen unverändert. _aquatic ist UNABHÄNGIG vom Bauplan (ein Fisch
## braucht FISH-Geometrie UND aquatische Physik, siehe _physics_process() unten) — getrennt
## gehalten, falls künftig mal ein nicht-aquatisches Tier mit FISH-Optik gebraucht wird
## (z.B. ein ausgestelltes totes Fisch-Objekt) oder umgekehrt.
var _body_plan:  int   = AnimalVisualProfile.BodyPlan.QUADRUPED
var _wing_style: int   = AnimalVisualProfile.WingStyle.NONE
var _back_style: int   = AnimalVisualProfile.BackStyle.NONE
## Wunsch "neue Shapes/Formen/Gliedmaßen für Tiere — Variationen" — siehe
## AnimalVisualProfile.BodyShape/LegStyle-Kommentar. NORMAL = bisheriges Verhalten.
var _body_shape: int   = AnimalVisualProfile.BodyShape.NORMAL
var _leg_style:  int   = AnimalVisualProfile.LegStyle.NORMAL
## Wunsch "Textur von Tieren" — siehe AnimalVisualProfile.PatternStyle-Kommentar.
var _pattern_style: int   = AnimalVisualProfile.PatternStyle.NONE
var _pattern_color: Color = Color(0.12, 0.10, 0.09)
## Bauplan-spezifisches Zusatzmerkmal — siehe AnimalVisualProfile.AccentStyle.
var _accent_style: int = AnimalVisualProfile.AccentStyle.NONE
## Gefangenen-/Schaukasten-Modus (Zoo am Spawn, siehe ZooPlacer): das Tier steht still, flieht
## nicht, ist nicht fangbar und läuft ohne Physik. Gesetzt über enter_display_mode() bzw. die
## Spawn-Config {"captive": true}. ACHTUNG Reihenfolge: EntityOrchestrator.spawn_entity() ruft
## add_child() (→ _ready()) VOR on_spawn() — _ready() kennt die Config also noch nicht, deshalb
## baut enter_display_mode() die bis dahin entstandene Fang-Interaktion wieder zurück.
var _captive: bool = false
## Fisch-Sonderfall: keine Schwerkraft/kein is_on_floor()-Gedöns (ein Fisch hat keine Beine
## und steht nie "auf" etwas) — stattdessen ein sanftes vertikales Pendeln um die
## Spawnhöhe, damit er sichtbar im Wasser "schwimmt" statt stocksteif auf der
## Wasseroberfläche zu kleben. Siehe _physics_process().
var _aquatic: bool = false

var _state:         State   = State.IDLE
var _state_timer:   float   = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _spawn_origin:  Vector3 = Vector3.ZERO
var _player_ref:    Node3D  = null  # Cached once — no per-frame SceneTree scan

func _ready() -> void:
	_spawn_origin = global_position
	set_multiplayer_authority(1)
	_on_ready_extended()
	# Cache the player reference once instead of scanning the SceneTree every physics frame.
	# If the player node isn't in the tree yet, wait for the group to be populated.
	# ADR-015 / MIGRATION-015 Phase 2 note: this is intentionally still players[0],
	# NOT ctx.get_local_player() — flee behavior wants "the nearest player", not
	# "the local player", and a real nearest-player search (like EnemyNPC's
	# _find_closest_player()) is a separate, not-yet-done fix, named but not solved
	# here to keep this migration's scope from growing.
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player_ref = players[0] as Node3D

	# BUGFIX (2026-09-17, "Tiere sind an anderen Orten"): dieser Block hat den
	# deterministischen, positions-basierten Namen aus
	# EntityOrchestrator.spawn_entity() bisher UNCONDITIONAL mit einem
	# get_instance_id()-Suffix überschrieben — pro Prozess unterschiedlich,
	# also auf jedem Peer ein anderer Name für "dasselbe" Tier. Anders als bei
	# EnemyNPC._ready() (die denselben Hack nur greifen lässt, wenn der Name
	# NOCH der Klassenname/"@..." ist) fehlte hier die Bedingung komplett —
	# das hat den world_seed-Sync-Fix für Tiere von Anfang an unterlaufen.
	# Jetzt: nur noch greifen, wenn der Name wirklich noch unbenannt ist.
	if name == get_class() or name.begins_with("@"):
		name = "Animal_%d" % (get_instance_id() % 999)

	_setup_multiplayer_sync()


	# Geometrie über Builder — kein Mesh-Code in dieser Datei
	add_child(AnimalVisualBuilder.build(build_visual_profile()))
	_build_collision()
	add_to_group("animals")
	_setup_catch_interaction()
	AppLogger.log_debug("Tier '%s' @ %s" % [name, str(global_position)], LOG_CAT)

func _on_ready_extended() -> void:
	pass  ## Unterklassen: hier name, _color, _body_size, _speed setzen

## Das Aussehen dieses Tiers als AnimalVisualProfile. Aus _ready() herausgezogen, damit der
## Zoo (ZooMeasure) die Maße eines Tiers bestimmen kann, ohne es in den Baum zu hängen:
## Instanz mit .new() erzeugen, _on_ready_extended() aufrufen, dann dies hier.
func build_visual_profile() -> AnimalVisualProfile:
	var visual_profile := AnimalVisualProfile.new(_color, _body_size)
	visual_profile.ear_style      = _ear_style
	visual_profile.tail_style     = _tail_style
	visual_profile.snout_style    = _snout_style
	visual_profile.headgear_style = _headgear_style
	visual_profile.tail_scale     = _tail_scale
	visual_profile.body_plan      = _body_plan
	visual_profile.wing_style     = _wing_style
	visual_profile.back_style     = _back_style
	visual_profile.body_shape     = _body_shape
	visual_profile.leg_style      = _leg_style
	visual_profile.pattern_style  = _pattern_style
	visual_profile.pattern_color  = _pattern_color
	visual_profile.accent_style   = _accent_style
	return visual_profile

func is_captive() -> bool:
	return _captive

## Schaltet das Tier zum reinen Ausstellungsstück (Zoo): keine KI/Physik, nicht fangbar.
## Idempotent. Läuft nach _ready() (siehe _captive-Kommentar), darf also die schon erzeugte
## Fang-Interaktion entfernen.
func enter_display_mode() -> void:
	_captive = true
	velocity = Vector3.ZERO
	set_physics_process(true)  # _physics_process() übernimmt den Fisch-Auftrieb, siehe dort
	if is_instance_valid(_catch_interactable):
		_catch_interactable.queue_free()
		_catch_interactable = null

func is_aquatic() -> bool:
	return _aquatic

## BUGFIX (2026-09-17, "Tiere sind an anderen Orten"): fehlte komplett — der
## is_multiplayer_authority()-Guard in _physics_process() (siehe unten) sorgt
## zwar dafür, dass nur der Server die KI/Bewegung simuliert, aber ohne
## MultiplayerSynchronizer bekamen andere Peers dessen Ergebnis nie mitgeteilt:
## ihre eigene, lokal gespawnte Kopie blieb einfach regungslos am Spawnpunkt
## stehen, während die Server-Kopie herumwanderte — von jedem Peer aus sah es
## so aus, als stünde das Tier "woanders". Exaktes Gegenstück zu
## EnemyNPC._setup_multiplayer_sync() (siehe dort für Details).
func _setup_multiplayer_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSync"
	sync.replication_interval = 0.1   # 10 Hz — wie EnemyNPC, unkritisch für Tier-Wandern
	add_child(sync)
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	sync.replication_config = config
	AppLogger.log_debug("MultiplayerSynchronizer erstellt (position, rotation, 10Hz).", LOG_CAT)

# ─────────────────────────────────────────────
# Interaktion
# ─────────────────────────────────────────────

func _setup_catch_interaction() -> void:
	if _captive:
		return
	var d := InteractableData.new()
	d.id           = "catch_animal"
	d.label        = "Tier fangen"
	d.duration     = 2.0
	d.xp_type      = "none"
	d.xp_amount    = 0
	d.inspect_text = get_inspect_text()
	_catch_interactable = InteractableComponent.new()
	_catch_interactable.data = d
	add_child(_catch_interactable)
	# Connect signal upward — component never calls get_parent() directly.
	_catch_interactable.interacted.connect(_on_interacted)

## peer_id (ADR-015 Phase 4/5): kommt jetzt echt aus der Interaktion selbst
## (InteractableAction.peer_id → InteractionExecutor → interacted-Signal),
## statt wie zuvor in AnimalCatcher über animal.get_multiplayer().get_unique_id()
## angenähert zu werden. Siehe AnimalCatcher.catch_animal() für die Auflösung
## der Näherung.
##
## ADR-020 / R-3: Guard analog zu EnemyNPC._on_interacted() — catch_animal()
## spawnt eine neue Entity (Pet) und gibt 'self' frei; beides darf nur einmal
## und nur auf der Autorität passieren. Auf einem Nicht-Autorität-Peer läuft
## dieser Hook trotzdem lokal (via InteractableComponent._handle_completion()'s
## direktem Emit), aber ohne sichtbares Feedback — anders als bei EnemyNPC gibt
## es hier keinen sinnvollen "vorläufigen" Zustand zu zeigen (kein Hit-Flash-
## Äquivalent für "Tier wird möglicherweise gefangen"). Die echte Wirkung kommt
## über den RPC-Pfad (WorldService.request_entity_interaction()) zur Autorität.
func _on_interacted(action_id: String, peer_id: int) -> void:
	if action_id != "catch_animal":
		return
	if not is_multiplayer_authority():
		return
	AnimalCatcher.catch_animal(self, peer_id)

## Unterklassen überschreiben für individuelle Beschreibung.
func get_inspect_text() -> String:
	return "Ein Tier."

# ─────────────────────────────────────────────
# Physics / AI
# ─────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _captive:
		# Schaukasten: keine KI, kein Fliehen, keine Schwerkraft — das Tier steht genau dort,
		# wo ZooPlacer es hingesetzt hat. Nur Fische treiben sanft auf/ab (wie in freier Wildbahn).
		# Nur die Autorität bewegt (MultiplayerSynchronizer repliziert position — ein lokaler
		# Zusatz-Versatz auf Clients würde sonst gegen die replizierte Position ankämpfen).
		if _aquatic and is_multiplayer_authority():
			position.y += cos(Time.get_ticks_msec() * 0.001 + float(get_instance_id() % 97)) * 0.15 * delta
		return
	if not is_multiplayer_authority():
		return
	if _aquatic:
		# Kein Boden, keine Schwerkraft — sanftes Auf/Ab um die Spawnhöhe statt Fallen/
		# Stehenbleiben (siehe _aquatic-Feldkommentar oben).
		velocity.y = sin(Time.get_ticks_msec() * 0.001 + get_instance_id()) * 0.15
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	_state_timer -= delta

	match _state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
			if _state_timer <= 0.0:
				_enter_wander()
		State.WANDER:
			_move_toward(_wander_target, _speed, delta)
			if global_position.distance_to(_wander_target) < 0.6 or _state_timer <= 0.0:
				_enter_idle()
		State.FLEE:
			_move_toward(_wander_target, _speed * 2.2, delta)
			if _state_timer <= 0.0:
				_enter_idle()

	var home_flat := Vector2(
		global_position.x - _spawn_origin.x,
		global_position.z - _spawn_origin.z
	)
	if home_flat.length() > _home_radius and _state != State.FLEE:
		_wander_target = _spawn_origin
		_state         = State.WANDER
		_state_timer   = 4.0

	move_and_slide()
	_check_player_proximity()

func _check_player_proximity() -> void:
	# Use the cached reference — zero SceneTree traversal per frame.
	if not is_instance_valid(_player_ref):
		# Retry cache once (handles the case where player spawned after this animal).
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		_player_ref = players[0] as Node3D
	if global_position.distance_to(_player_ref.global_position) < _flee_radius \
	   and _state != State.FLEE:
		var flee_dir: Vector3 = (global_position - _player_ref.global_position).normalized()
		_wander_target = global_position + flee_dir * _wander_range
		_state         = State.FLEE
		_state_timer   = 3.5

func _move_toward(target: Vector3, spd: float, delta: float) -> void:
	var dir: Vector3 = target - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		dir = dir.normalized()
		velocity.x = move_toward(velocity.x, dir.x * spd, 12.0 * delta)
		velocity.z = move_toward(velocity.z, dir.z * spd, 12.0 * delta)
		# BUGFIX ("Tiere laufen mit dem Schwanz voraus"): look_at() dreht die lokale
		# -Z-Achse zum Ziel — das Tiermodell ist aber mit +Z = vorne gebaut (siehe
		# AnimalVisualBuilder-Klassenkommentar, Kopf sitzt auf +Z, Schwanz auf -Z).
		# Mit "global_position + dir" zeigte deshalb der Schwanz in Laufrichtung.
		# Zielpunkt umgekehrt ("- dir") dreht stattdessen +Z (den Kopf) korrekt in dir.
		look_at(global_position - dir, Vector3.UP)

func _enter_idle() -> void:
	_state       = State.IDLE
	_state_timer = _idle_time + randf_range(-0.5, 1.5)

func _enter_wander() -> void:
	_state       = State.WANDER
	_state_timer = 3.0 + randf_range(0.0, 2.0)
	_wander_target = _spawn_origin + Vector3(
		randf_range(-_wander_range, _wander_range),
		0.0,
		randf_range(-_wander_range, _wander_range)
	)

# ─────────────────────────────────────────────
# Collision
# ─────────────────────────────────────────────

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var sh  := CapsuleShape3D.new()
	sh.radius  = _body_size.x * 0.45
	sh.height  = _body_size.y
	col.shape  = sh
	col.position.y = _body_size.y * 0.5
	add_child(col)

# ─────────────────────────────────────────────
# EntityOrchestrator-Interface
# ─────────────────────────────────────────────

## via on_spawn() — Pflicht-Dep für alles was Services/EventBus braucht
## (aktuell: AnimalCatcher beim Fangen — Pet-Spawn + Reward-Text).
var _ctx: IEntityContext = null

## BUGFIX (2026-09-17, "Tiere fangen erreicht Autorität nicht"): Referenz auf
## die in _setup_catch_interaction() (läuft in _ready(), VOR on_spawn()) erzeugte
## Komponente — sonst kein Weg, ihr den erst später verfügbaren Kontext
## nachzureichen. Exakt dasselbe Bug-Muster wie bei PlayerAttack/PlayerTrade/
## PlayerThank/PlayerPickpocket (die inject_context() komplett vergessen hatten) —
## hier fehlte nicht der Aufruf, sondern der Zeitpunkt war zu früh (Kontext
## existiert erst ab on_spawn(), _setup_catch_interaction() lief aber in _ready()).
var _catch_interactable: InteractableComponent = null

## BUG-FIX: fehlte der zweite Parameter 'ctx' — EntityOrchestrator.spawn_entity()
## ruft immer entity.on_spawn(config, ctx) auf (siehe HarvestableEntity/EnemyNPC).
## Ohne ctx crashte jedes Tier-Spawn mit "Expected 1 argument(s)".
func on_spawn(_cfg: Dictionary = {}, ctx: IEntityContext = null) -> void:
	_ctx = ctx
	if bool(_cfg.get("captive", false)):
		enter_display_mode()
	if is_instance_valid(_catch_interactable):
		_catch_interactable.inject_context(ctx)
	_spawn_origin = global_position
	_enter_idle()

## Öffentlicher Zugriff für AnimalCatcher (separate Utility-Klasse, kein interner Code).
func get_context() -> IEntityContext:
	return _ctx

func on_despawn() -> void:
	pass
