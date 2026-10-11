class_name PetComponent
extends CharacterBody3D

## PetComponent — Ein Pet das seinem Besitzer folgt.
##
## Wird über EntityOrchestrator.spawn_entity("pet", pos, config, owner_peer_id)
## erzeugt — entweder beim Fangen eines Tieres (AnimalCatcher) oder beim
## Wiederherstellen eines Saves (PetRestorer). KEIN direktes PetComponent.new()
## + add_child() mehr (siehe AnimalCatcher/PetRestorer) — sonst fehlt die
## EntityRegistry-Registrierung, die der MultiplayerSpawner für Replikation an
## andere Peers braucht, und es gibt kein ctx für den EventBus.
##
## NICHT gepoolt (EntityOrchestrator._ready(): set_max_size_for("pet", 0)) —
## jedes Pet hat eine individuelle Identität (Name/Farbe/Besitzer), Pooling
## würde diese beim Wiederverwenden vermischen.

const LOG_CAT := "Pet"
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

var _color:     Color   = Color(0.7, 0.5, 0.3)
var _body_size: Vector3 = Vector3(0.3, 0.4, 0.3)
var _name:      String  = "Pet"

var _follow_distance: float = 2.5
var _speed:           float = 4.0
var _idle_radius:     float = 1.5

## BUGFIX ("Pets bauen/sammeln/kämpfen nur ab, wenn der Besitzer von Anfang an
## in der Nähe steht und sich nicht bewegt"): vorher zog _physics_process() das
## Pet bei JEDEM Leerlauf-Frame (keine Fähigkeit hält gerade request_movement(),
## siehe unten) auf _follow_distance (2.5m) zum Besitzer zurück. Sobald eine
## Fähigkeit ihr Ziel verlor (erledigt/weg) und das Pet mehr als 2.5m vom
## Besitzer entfernt stand, lief es SOFORT zurück — noch bevor
## PetAbilityComponent im nächsten Scan (SCAN_INTERVAL) überhaupt die Chance
## hatte, in der Nähe ein neues Ziel zu finden. Ein Pet fand dadurch praktisch
## nie autonom etwas, außer der Besitzer stand zufällig selbst direkt neben
## einer Ressource — exakt das gemeldete Symptom.
## Jetzt: ein Pet mit mindestens einer Fähigkeit (_abilities nicht leer)
## bekommt eine lose Leine (siehe _apply_idle_movement()) statt der engen
## _follow_distance — erst außerhalb von LEASH_RADIUS läuft es aktiv zum
## Besitzer zurück, innerhalb bleibt es stehen (bzw. steuert gerade selbst ein
## Fähigkeits-Ziel an) und kann eigenständig scannen/handeln. Ein Pet OHNE
## Fähigkeiten (reiner Begleiter) folgt unverändert eng.
const LEASH_RADIUS: float = 16.0

## Kosmetische Silhouette, übernommen vom gefangenen Tier (siehe AnimalCatcher.catch_animal()) —
## BUGFIX ("Nach dem Fangen ist das ursprüngliche Modell weg"): ohne diese Felder baute
## _build_visuals() nur eine schlichte, kopf-/ohrenlose Kapsel. Defaults entsprechen
## AnimalVisualProfile's eigenen Defaults (generisches "Standardtier"), falls ein Pet ohne
## diese Config-Felder gespawnt wird (z.B. sehr alte Saves vor diesem Fix).
var _ear_style:      int   = AnimalVisualProfile.EarStyle.ROUND
var _tail_style:     int   = AnimalVisualProfile.TailStyle.STUB
var _snout_style:    int   = AnimalVisualProfile.SnoutStyle.SHORT
var _headgear_style: int   = AnimalVisualProfile.HeadgearStyle.NONE
var _tail_scale:     float = 1.0
## Wunsch "mehr Körper für Tiere einbauen": analog zu den Feldern oben vom gefangenen Tier
## übernommen (siehe AnimalCatcher.catch_animal()), damit z.B. eine gefangene Spinne auch
## als Pet eine Spinne bleibt statt zum Standard-Vierbeiner zu werden.
var _body_plan:  int = AnimalVisualProfile.BodyPlan.QUADRUPED
var _wing_style: int = AnimalVisualProfile.WingStyle.NONE
var _back_style: int = AnimalVisualProfile.BackStyle.NONE
## Wunsch "neue Shapes/Formen/Gliedmaßen — Variationen": analog vom gefangenen Tier übernommen.
var _body_shape: int = AnimalVisualProfile.BodyShape.NORMAL
var _leg_style:  int = AnimalVisualProfile.LegStyle.NORMAL
## Wunsch "Textur von Tieren": analog vom gefangenen Tier übernommen.
var _pattern_style: int   = AnimalVisualProfile.PatternStyle.NONE
var _accent_style:  int   = AnimalVisualProfile.AccentStyle.NONE
var _pattern_color: Color = Color(0.12, 0.10, 0.09)

## Peer-ID des Besitzers — das Pet folgt NUR diesem Spieler, nicht "irgendeinem"
## (relevant sobald mehrere Spieler eigene Pets haben). Default 1 (Solo/Host)
## für Saves ohne owner_peer_id (Alt-Feld, siehe get_save_state()).
var _owner_peer_id: int = 1

## Stabile player_id des Besitzers (SessionManager-UUID, NICHT die peer_id) —
## gebraucht von PetAbilityComponent für Aktionen, die eine player_id statt
## einer peer_id erwarten (aktuell nur Graben, siehe dortiges
## emit_terrain_edit_requested()). AnimalCatcher.catch_animal() liefert sie
## bereits im Spawn-Config mit ("owner_player_id", bisher nur für die
## deterministische Namensvergabe genutzt) — hier zusätzlich gespeichert statt
## bei jedem Grab-Versuch neu über NetworkBridge aufzulösen. Leerer String
## (alte Saves, Solo ohne NetworkBridge) wird in on_spawn() best-effort
## nachaufgelöst, siehe dort.
var _owner_player_id: String = ""

## Fähigkeiten dieses Pets (siehe PetAbilities-Konstanten) — bestimmt, welche
## PetAbilityComponent-Kinder _build_abilities() in on_spawn() erzeugt.
var _abilities: Array[String] = []

## Tierart des gefangenen Tieres (z.B. "horse") — vom AnimalCatcher übernommen, im Save
## mitgeführt. Leer bei Alt-Saves/unbekannter Art. Entscheidet, ob das Pet ein Reittier
## ist (siehe MountDefinitions) — die Fähigkeits-Defaults nutzten sie schon beim Fangen.
var _species_id: String = ""

## Reiter sitzt auf: das Pet hängt dann am Reiter (PlayerMount.sync_pet()), eigene Bewegung,
## Fähigkeiten und Leine ruhen. Nicht gespeichert — nach dem Laden steht das Pet frei da.
var _ridden: bool = false

## FEATURE (Wunsch "Pets sollen XP bekommen wie der Spieler auch, generelles
## Pet-Level statt an einen Skill gebunden, Cap bei 100") — siehe PetLeveling
## für die Kurve. _xp ist die ABSOLUTE Gesamt-XP über die gesamte Lebenszeit
## des Pets (nicht "XP seit letztem Level-Up") — Level wird daraus bei Bedarf
## via PetLeveling.resolve() abgeleitet, nicht separat mitgeführt, damit beide
## Werte nie auseinanderlaufen können.
var _xp: int = 0

## Gehört dieses Pet zum Kampfteam der Pet-Kämpfe (höchstens PetBattleEngine.MAX_TEAM = 10 pro
## Besitzer)? Gewählt im Kampf-Fenster (PetBattleController), Teil des Saves ("battle_team"). Ändert
## sonst nichts am Pet — ein Kampfpet sammelt/kämpft in der Welt weiter wie bisher.
var _battle_team: bool = false

var _bus: IEventBus      = null
## Vollständiger Context (nicht nur der Bus) — PetAbilityComponent braucht
## get_world()/get_network_bridge() für die eigentlichen Fähigkeits-Aktionen.
var _ctx: IEntityContext = null

## Cache — wird über IEventBus.player() (player_died/player_respawned) aktuell
## gehalten, kein Polling im Physik-Frame.
var _player_ref: Node3D = null

# ─────────────────────────────────────────────
# Bewegungs-Arbitrierung für Fähigkeiten (siehe PetAbilityComponent)
# ─────────────────────────────────────────────
## null = normales Besitzer-Folgeverhalten. Sonst: die PetAbilityComponent,
## die gerade "das Steuer hält" — max. eine gleichzeitig, damit nicht zwei
## Fähigkeiten (z.B. Kampf + Graben auf demselben Eber) widersprüchliche
## velocity-Ziele in denselben Physik-Frame schreiben.
var _movement_owner:        Node    = null
var _movement_target:       Vector3 = Vector3.ZERO
var _movement_arrive_radius: float  = 1.0

## Fordert die Bewegungssteuerung für requester an. Gibt true zurück wenn
## requester ab jetzt (oder weiterhin) steuert, false wenn eine ANDERE
## Fähigkeit gerade hält (der Aufrufer muss dann warten/es später erneut
## versuchen). Ein erneuter Aufruf desselben requesters aktualisiert nur das
## Ziel (z.B. wenn ein Kampfziel sich bewegt).
func request_movement(requester: Node, target_pos: Vector3, arrive_radius: float) -> bool:
	if is_instance_valid(_movement_owner) and _movement_owner != requester:
		# DIAGNOSE (2026-10-01, "Pet baut nur ab, wenn ich es nah hinlotse"): falls
		# ein Pet mehrere Fähigkeiten hat, wäre eine dauerhaft blockierte Steuerung
		# (z.B. eine Fähigkeit, die nie release_movement() aufruft) ein plausibler
		# Grund, warum eine ANDERE Fähigkeit nie ins Arbeiten kommt. Nur einmal pro
		# neuem Requester loggen würde mehr Buchhaltung brauchen als es wert ist —
		# PetAbilityComponent.SEEKING loggt die Ablehnung bereits gedrosselt
		# (STATUS_LOG_INTERVAL), hier bewusst ungedrosselt auf DEBUG, da
		# request_movement() nur 1x pro Physik-Frame pro Fähigkeit läuft.
		AppLogger.log_debug(
			"request_movement('%s'): abgelehnt — '%s' hält die Steuerung bereits." \
			% [requester.name if is_instance_valid(requester) else "?",
			   _movement_owner.name if is_instance_valid(_movement_owner) else "?"],
			LOG_CAT
		)
		return false
	_movement_owner = requester
	_movement_target = target_pos
	_movement_arrive_radius = max(0.1, arrive_radius)
	return true

## Gibt die Steuerung frei, NUR wenn requester sie aktuell hält (kein
## Fremdeingriff möglich).
func release_movement(requester: Node) -> void:
	if _movement_owner == requester:
		_movement_owner = null

func is_movement_claimed_by(requester: Node) -> bool:
	return _movement_owner == requester

## BUGFIX (2026-10-02, "Pet baut nur ab, wenn ich es nah hinlotse" — jetzt per
## Logging konkret nachgewiesen statt vermutet, siehe Log vom 2026-10-02):
## Pets blieben wochenlang scheinbar "fast angekommen" stehen (Log zeigte
## 25+ Sekunden lang exakt dieselbe Position, Distanz ~2.2004m bei
## HARVEST_ARRIVE_RADIUS=2.2) und wechselten NIE von SEEKING zu ACTING.
## Ursache: _steer_toward() bremst proportional zur Restdistanz ab
## (t = (dist-stop_distance)/3.0) — die letzten Zentimeter vor stop_distance
## ergeben eine Zielgeschwindigkeit nahe Null (hier: ~0.0005 m/s), die
## move_and_slide() praktisch nicht mehr sichtbar vorwärtsbewegt (Boden-
## Snapping/Physik-Rundung schluckt Sub-Millimeter-Schritte). Die exakte
## "<=" Prüfung hier verlangte aber ein TATSÄCHLICHES Unterschreiten von
## stop_distance, das dadurch nie eintrat — klassisches "nähert sich
## asymptotisch, erreicht nie" Problem.
## Fix in ZWEI Teilen (siehe auch _steer_toward() unten):
##   1. Hier: eine Toleranz (ARRIVE_TOLERANCE) statt exakter Gleichheit — "nah
##      genug" zählt bereits als angekommen, unabhängig davon ob die
##      Bewegungskurve exakt konvergiert.
##   2. _steer_toward(): Mindestgeschwindigkeit in der Schlussphase, damit das
##      Pet die letzten Zentimeter überhaupt noch sichtbar zurücklegt, statt
##      asymptotisch auf Schneckentempo abzubremsen.
## Mit Fix 2 sollte Fix 1 im Normalfall gar nicht mehr nötig sein — als
## Sicherheitsnetz bleibt er trotzdem drin (z.B. falls ein Ziel sich bewegt,
## siehe Kampf-Fähigkeit, oder bei sehr niedriger Framerate).
const ARRIVE_TOLERANCE: float = 0.3

func has_arrived_at_movement_target() -> bool:
	return global_position.distance_to(_movement_target) <= _movement_arrive_radius + ARRIVE_TOLERANCE

func has_ability(ability_id: String) -> bool:
	return _abilities.has(ability_id)

# ─────────────────────────────────────────────
# Öffentliche Lese-/Schreib-API fürs Pet-Menü (siehe PetPanelController)
# ─────────────────────────────────────────────

func get_owner_peer_id() -> int:
	return _owner_peer_id

func get_pet_name() -> String:
	return _name

func get_species_id() -> String:
	return _species_id

func is_mountable() -> bool:
	return MountDefinitions.is_mountable(_species_id)

func is_ridden() -> bool:
	return _ridden

func set_ridden(value: bool) -> void:
	_ridden = value
	if value:
		# Laufende Fähigkeits-Steuerung abbrechen, sonst läuft sie nach dem Absteigen weiter.
		_movement_owner = null
		velocity = Vector3.ZERO

## Kopie zurückgeben — niemals die interne Array-Referenz nach außen geben,
## sonst könnte ein UI-Panel sie versehentlich mutieren, ohne über
## set_abilities() zu gehen (und damit ohne _build_abilities() neu aufzubauen).
func get_abilities() -> Array[String]:
	return _abilities.duplicate()

## Rohdaten für die Kampfwerte (PetBattleMon.from_profile()): Art, Bauplan, Größe, Tempo, Level.
## Ein Zugriffspunkt statt die privaten Felder in der Kampf-UI einzeln abzugreifen.
func get_battle_profile() -> Dictionary:
	return {
		"name": _name,
		"species_id": _species_id,
		"body_plan": _body_plan,
		"body_size": _body_size,
		"speed": _speed,
		"level": get_level(),
	}

func is_in_battle_team() -> bool:
	return _battle_team

## Nimmt das Pet ins Kampfteam auf bzw. heraus. NUR auf dem Besitzer-Client wirksam (gleicher
## Autoritäts-Guard wie set_abilities()/add_xp(): Pets sind client-autoritativ). Die Obergrenze
## von 10 prüft der Aufrufer (PetBattleTeam.can_add()), nicht das einzelne Pet.
func set_battle_team(value: bool) -> void:
	if not is_multiplayer_authority():
		return
	_battle_team = value

## Kosmetik fürs Pet-Menü (Kopf-Icon im Grid, siehe PetHeadIcon) — dieselben
## Felder, aus denen _build_visuals() das 3D-Modell baut, damit das Icon dem
## Pet in der Welt entspricht. Reine Kopie, keine interne Referenz.
func get_appearance() -> Dictionary:
	return {
		"color":          _color,
		"ear_style":      _ear_style,
		"snout_style":    _snout_style,
		"headgear_style": _headgear_style,
	}

## Was das Pet GERADE tut (Pet-Menü: Filter + Status-Zeile): { "ability":
## String (PetAbilities-ID, "" = untätig), "acting": bool (true = führt die
## Aktion gerade aus, false = läuft noch hin/sucht) }. Mehrere Fähigkeiten
## können gleichzeitig nicht-IDLE sein — dann gewinnt eine, die schon ACTING
## ist, sonst die erste gefundene. Nur auf der Besitzer-Kopie aussagekräftig
## (nur dort laufen die PetAbilityComponent-Zustandsmaschinen).
func get_current_activity() -> Dictionary:
	var best: Dictionary = {"ability": "", "acting": false}
	for child in get_children():
		if not (child is PetAbilityComponent):
			continue
		var comp := child as PetAbilityComponent
		var st: int = comp.get_activity_state()
		if st == PetAbilityComponent.State.IDLE:
			continue
		var acting: bool = st == PetAbilityComponent.State.ACTING
		if String(best["ability"]).is_empty() or (acting and not bool(best["acting"])):
			best = {"ability": comp.ability_id, "acting": acting}
	return best

## Siehe PetLeveling — Level wird aus der absoluten XP-Summe abgeleitet, nie
## separat gespeichert (kann dadurch nie aus dem Takt geraten).
func get_level() -> int:
	return int(PetLeveling.resolve(_xp)["level"])

func get_xp() -> int:
	return _xp

## Fortschritt im aktuellen Level, als Dictionary {"xp_into_level", "xp_for_next"}
## — fürs Pet-Menü (Fortschrittsbalken in der Detailansicht), siehe PetPanelVisuals.
func get_level_progress() -> Dictionary:
	var resolved := PetLeveling.resolve(_xp)
	return {"xp_into_level": resolved["xp_into_level"], "xp_for_next": resolved["xp_for_next"]}

## Vergibt XP an dieses Pet (aufgerufen von PetAbilityComponent nach einer
## abgeschlossenen Aktion, siehe PetLeveling.xp_reward_for()). NUR auf dem
## Besitzer-Client wirksam — gleicher Autoritäts-Guard wie set_abilities(),
## aus demselben Grund: Pet-XP ist reiner Client-Zustand (siehe _xp-
## Feldkommentar), eine Fremd-Kopie dieses Pets auf einem anderen Peer soll
## nicht mitzählen (der Besitzer-Client ist für sein eigenes Pet maßgeblich).
## Meldet einen Level-Up per emit_interaction_reward_text() (gleicher Toast-
## Mechanismus wie beim Zähmen selbst) — rein kosmetisch, kein Spielmechanik-
## Effekt am Level selbst (siehe PetLeveling-Klassenkommentar: "Formel ist
## halb so wichtig").
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	if not is_multiplayer_authority():
		return
	var level_before := get_level()
	_xp += amount
	var level_after := get_level()
	if level_after > level_before:
		AppLogger.log_info(
			"Pet '%s': Level-Up %d → %d (XP gesamt: %d)." % [_name, level_before, level_after, _xp],
			LOG_CAT
		)
		if is_instance_valid(_bus):
			_bus.world().emit_interaction_reward_text("%s ist jetzt Level %d!" % [_name, level_after])

## Weist diesem Pet eine neue Fähigkeiten-Menge zu (Pet-Menü, Wunsch "Pets auf
## Ressourcen sammeln usw. verteilen"). NUR auf dem Besitzer-Client wirksam —
## Pets sind client-autoritativ (siehe on_spawn()); ein Aufruf auf der
## replizierten Kopie eines fremden Peers wird ignoriert, exakt dieselbe
## Guard-Logik wie _physics_process()/PetAbilityComponent. Das Pet-Menü fragt
## ohnehin nur WorldService.get_pets_for_peer(lokale peer_id) ab, ruft diese
## Methode also im Normalfall nie auf einer Fremd-Kopie auf — der Guard ist
## trotzdem hier, nicht nur beim Aufrufer, damit set_abilities() für sich
## genommen sicher ist.
##
## Baut die PetAbilityComponent-Kinder komplett neu auf (_build_abilities())
## statt die alte/neue Liste zu diffen — Fähigkeiten haben keinen Zustand, der
## einen sauberen Übergang bräuchte: ein dadurch abgebrochenes ACTING verliert
## höchstens die paar Sekunden Wartezeit einer einzelnen Aktion, nie
## Loot/Fortschritt (siehe PetAbilityComponent._complete_harvest()/_do_attack()
## — Loot/Schaden werden erst NACH Ablauf der Wartezeit ausgelöst).
func set_abilities(new_abilities: Array[String]) -> void:
	if not is_multiplayer_authority():
		AppLogger.log_warn(
			"set_abilities() auf Pet '%s' ignoriert — keine lokale Autorität (gehört Peer %d)." \
			% [_name, _owner_peer_id],
			LOG_CAT
		)
		return
	_abilities = PetAbilities.sanitize(new_abilities)
	_build_abilities()

func _ready() -> void:
	add_to_group("pets")
	# FEATURE (2026-09-17, "Pets cross-peer sichtbar"): fehlte komplett — ohne
	# das hätten andere Peers zwar jetzt eine Kopie des Pets (siehe
	# NetworkBridge._rpc_spawn_remote_pet()), aber die würde nie ihre Position
	# aktualisieren, exakt dasselbe Muster wie bei AnimalBase (siehe dortiger
	# Kommentar für die volle Begründung). Pets sind CLIENT-autoritativ
	# (set_multiplayer_authority(_owner_peer_id) unten in on_spawn(), nicht
	# immer 1) — funktioniert mit MultiplayerSynchronizer genauso, die
	# Autorität ist einfach nicht immer der Server.
	_setup_multiplayer_sync()

func _setup_multiplayer_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSync"
	sync.replication_interval = 0.1   # 10 Hz — wie AnimalBase/EnemyNPC
	add_child(sync)
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	sync.replication_config = config
	AppLogger.log_debug("MultiplayerSynchronizer erstellt (position, rotation, 10Hz).", LOG_CAT)

## Aufgerufen von EntityOrchestrator NACH add_child() und NACH _ready().
## config: { "name": String, "color": Color, "body_size": Vector3,
##           "speed": float, "owner_peer_id": int }
func on_spawn(config: Dictionary = {}, ctx: IEntityContext = null) -> void:
	_name          = config.get("name", _name)
	_color         = config.get("color", _color)
	_body_size     = config.get("body_size", _body_size)
	_speed         = config.get("speed", _speed)
	_species_id    = String(config.get("species_id", ""))
	# Reittiere folgen frei flotter als ein normales Pet (sonst hinkt das Pferd dem Besitzer nach).
	if MountDefinitions.is_mountable(_species_id):
		_speed = maxf(_speed, MountDefinitions.follow_speed_for(_species_id))
	_ear_style      = config.get("ear_style", _ear_style)
	_tail_style     = config.get("tail_style", _tail_style)
	_snout_style    = config.get("snout_style", _snout_style)
	_headgear_style = config.get("headgear_style", _headgear_style)
	_tail_scale     = config.get("tail_scale", _tail_scale)
	_body_plan      = config.get("body_plan", _body_plan)
	_wing_style     = config.get("wing_style", _wing_style)
	_back_style     = config.get("back_style", _back_style)
	_body_shape     = config.get("body_shape", _body_shape)
	_leg_style      = config.get("leg_style", _leg_style)
	_pattern_style  = config.get("pattern_style", _pattern_style)
	_pattern_color  = config.get("pattern_color", _pattern_color)
	_accent_style   = config.get("accent_style", _accent_style)
	_owner_peer_id = config.get("owner_peer_id", 1)
	_owner_player_id = String(config.get("owner_player_id", _owner_player_id))
	# PetAbilities.sanitize() statt der rohen config-Liste: verwirft unbekannte
	# IDs (Tippfehler/altes Save nach Feature-Rollback) statt sie als Fähigkeit
	# zu akzeptieren, für die keine PetAbilityComponent je etwas tut.
	_abilities = PetAbilities.sanitize(config.get("abilities", []))
	# FEATURE (Pet-XP/Level): maxi(0, ...) statt rohem int() — ein manuell
	# editiertes/beschädigtes Save mit negativer XP-Zahl soll nicht zu einem
	# kaputten/negativen Level führen (PetLeveling.resolve() ist für negative
	# Werte nicht ausgelegt), sondern einfach bei 0 landen.
	_xp = maxi(0, int(config.get("xp", 0)))
	# Alte Saves (vor den Pet-Kämpfen) kennen das Feld nicht → false (kein Kampfteam, unverändert).
	_battle_team = bool(config.get("battle_team", false))

	set_multiplayer_authority(_owner_peer_id)

	_build_visuals()
	_build_collision()

	_ctx = ctx
	if is_instance_valid(ctx):
		_bus = ctx.get_event_bus()
	if is_instance_valid(_bus):
		_bus.player().player_died.connect(_on_player_died)
		_bus.player().player_respawned.connect(_on_player_respawned)
	else:
		AppLogger.log_warn(
			"Pet '%s': kein IEventBus im Context — reagiert nicht auf Tod/Respawn des Besitzers." % _name,
			LOG_CAT
		)

	# Best-effort Nachauflösung falls owner_player_id (noch) nicht mitgegeben
	# wurde (z.B. alte Saves von vor diesem Feld) — nötig für die
	# "digging"-Fähigkeit, siehe PetAbilityComponent._do_dig().
	if _owner_player_id.is_empty() and is_instance_valid(ctx):
		var network: NetworkBridge = ctx.get_network_bridge()
		if is_instance_valid(network):
			_owner_player_id = network.get_player_id_for_peer(_owner_peer_id)

	_build_abilities()

	_player_ref = _find_owner()
	AppLogger.log_debug(
		"Pet '%s' bereit (Besitzer: peer %d, Fähigkeiten: %s)." % [_name, _owner_peer_id, str(_abilities)],
		LOG_CAT
	)

## Erzeugt für jede Fähigkeit in _abilities eine eigene PetAbilityComponent
## (siehe dortiger Klassenkommentar zur Begründung: eine Komponente pro
## Fähigkeit statt einer einzigen Multi-Fähigkeit-Klasse, damit z.B. ein Eber
## Bergbau + Graben unabhängig voneinander verfolgen kann — Bewegungssteuerung
## wird trotzdem über request_movement()/release_movement() oben serialisiert).
## Pool-Reuse-Guard: alte Fähigkeits-Kinder zuerst entfernen (Pets sind zwar
## laut Klassenkommentar NICHT gepoolt, aber on_spawn() kann bei einem
## Hot-Reload-Pfad theoretisch erneut laufen — kein Risiko, doppelte Kinder
## zu akkumulieren einzugehen).
func _build_abilities() -> void:
	for child in get_children():
		if child is PetAbilityComponent:
			remove_child(child)
			child.queue_free()
	for ability_id in _abilities:
		var comp := PetAbilityComponent.new()
		comp.name = "Ability_%s" % ability_id
		comp.ability_id = ability_id
		add_child(comp)
		comp.setup(self, _ctx, _bus, _owner_peer_id, _owner_player_id)

func on_despawn() -> void:
	if is_instance_valid(_bus):
		if _bus.player().player_died.is_connected(_on_player_died):
			_bus.player().player_died.disconnect(_on_player_died)
		if _bus.player().player_respawned.is_connected(_on_player_respawned):
			_bus.player().player_respawned.disconnect(_on_player_respawned)

func _on_player_died() -> void:
	_player_ref = null

func _on_player_respawned() -> void:
	_player_ref = _find_owner()

## Sucht den Spieler-Node mit owner_peer_id-Meta == _owner_peer_id — NICHT
## einfach "den ersten Spieler in der Gruppe". Damit läuft in Multiplayer mit
## mehreren Pets jedes seinem eigenen Besitzer hinterher statt alle demselben
## (meist zufällig zuerst gefundenen) Spieler.
##
## Meta statt get_multiplayer_authority(): "wem gehört das Player-Node" und
## "wer ist Netzwerk-Autorität darüber" sind zwei verschiedene Fragen, die
## bisher nur zufällig übereinstimmten. Seit ADR-025 (Autorität = Server für
## Player-Nodes) gilt das nicht mehr, siehe TODO "BLOCKER für
## ADR-025/026-Umsetzung". Pets selbst sind von ADR-025 nicht betroffen —
## nur die Suche nach ihrem Besitzer-Player war über denselben Umweg gebaut.
func _find_owner() -> Node3D:
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node3D and p.get_meta("owner_peer_id", 1) == _owner_peer_id:
			return p as Node3D
	# Fallback für Solo/Host: bei genau einem Spieler in der Gruppe ist die
	# Authority-Prüfung ohnehin eindeutig — greift nur falls sie aus irgendeinem
	# Grund nicht matcht (z.B. Timing beim Session-Start).
	return get_tree().get_first_node_in_group("player") as Node3D

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	# Wird geritten: Position/Ausrichtung kommt vom Reiter (PlayerMount.sync_pet()).
	if _ridden:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	# Solange eine PetAbilityComponent die Steuerung hält (Sammeln/Kämpfen/
	# Graben — siehe request_movement()), läuft das Pet dorthin statt dem
	# Besitzer hinterher. Gibt die Komponente frei (release_movement()),
	# übernimmt ab dem nächsten Frame automatisch wieder das Leerlaufverhalten.
	if is_instance_valid(_movement_owner):
		_steer_toward(_movement_target, delta, _movement_arrive_radius)
	elif is_instance_valid(_player_ref):
		_apply_idle_movement(delta)

	move_and_slide()

## DIAGNOSE (2026-10-01, "Pet baut nur ab, wenn ich es nah hinlotse"): gedrosselt
## (1x/Sekunde statt jeden Physik-Frame) sichtbar machen, OB ein Pet gerade an
## der Leine hängt und wartet (erwartet, solange PetAbilityComponent noch
## scannt) oder aktiv zum Besitzer zurückläuft (sollte bei einem Pet MIT
## Fähigkeiten nur passieren, wenn es wirklich > LEASH_RADIUS entfernt ist).
var _idle_log_cooldown: float = 0.0
const IDLE_LOG_INTERVAL := 1.0

## Bewegung im Leerlauf (keine Fähigkeit hält gerade request_movement()) — siehe
## LEASH_RADIUS-Kommentar oben zur Begründung. Ein Pet ohne Fähigkeiten folgt
## eng; ein Pet mit mindestens einer Fähigkeit bekommt Ruhe zum eigenständigen
## Scannen, solange es innerhalb der Leine bleibt.
func _apply_idle_movement(delta: float) -> void:
	_idle_log_cooldown -= delta
	var should_log := _idle_log_cooldown <= 0.0
	if should_log:
		_idle_log_cooldown = IDLE_LOG_INTERVAL

	if _abilities.is_empty():
		_steer_toward(_player_ref.global_position, delta, _follow_distance)
		return
	var dist_to_owner := global_position.distance_to(_player_ref.global_position)
	if dist_to_owner > LEASH_RADIUS:
		if should_log:
			AppLogger.log_debug(
				"'%s': IDLE, außerhalb der Leine (dist=%.1fm > LEASH_RADIUS=%.1fm) — laufe zum Besitzer zurück." \
				% [_name, dist_to_owner, LEASH_RADIUS],
				LOG_CAT
			)
		_steer_toward(_player_ref.global_position, delta, _follow_distance)
	else:
		if should_log:
			AppLogger.log_debug(
				"'%s': IDLE, innerhalb der Leine (dist=%.1fm) — stehe/warte auf Fähigkeits-Scan (Abilities=%s)." \
				% [_name, dist_to_owner, _abilities],
				LOG_CAT
			)
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)

## Gemeinsame Bewegungs-/Ausrichtungslogik für Besitzer-Folgeverhalten UND
## Fähigkeits-Steuerung (siehe _physics_process() oben) — vorher direkt im
## Besitzer-Folge-Zweig dupliziert, jetzt einmalig mit variablem stop_distance
## (== _follow_distance beim Folgen, == PetAbilityComponent.arrive_radius bei
## einer aktiven Fähigkeit).
func _steer_toward(target_pos: Vector3, delta: float, stop_distance: float) -> void:
	var dist := global_position.distance_to(target_pos)
	if dist > stop_distance:
		var dir: Vector3 = target_pos - global_position
		dir.y = 0.0
		if dir.length_squared() > 0.01:
			dir = dir.normalized()
			# BUGFIX (siehe has_arrived_at_movement_target()-Kommentar): t ohne
			# Untergrenze lief in der Schlussphase (Restdistanz nur noch wenige
			# Zentimeter) gegen 0 — das Pet bremste asymptotisch ab, statt die
			# letzte kurze Strecke tatsächlich zurückzulegen, und blieb
			# effektiv für immer knapp außerhalb von stop_distance stehen.
			# clampf() mit 0.2 als Untergrenze: sobald das Pet noch draußen ist
			# (dist > stop_distance), bewegt es sich mit MINDESTENS 20% Tempo
			# weiter, bis es stop_distance tatsächlich unterschreitet — danach
			# übernimmt der else-Zweig unten das sanfte Abbremsen auf 0.
			var t: float = clampf((dist - stop_distance) / 3.0, 0.2, 1.0)
			var spd: float = _speed * t
			velocity.x = move_toward(velocity.x, dir.x * spd, 12.0 * delta)
			velocity.z = move_toward(velocity.z, dir.z * spd, 12.0 * delta)
			# BUGFIX ("Tiere/Pets laufen mit dem Schwanz voraus"): siehe identischer
			# Fix + Begründung in AnimalBase._move_toward(). Pet-Körper ist zwar nur
			# eine einfache Kapsel ohne sichtbaren Kopf, übernimmt aber dieselbe
			# +Z-vorne-Konvention — betrifft z.B. das Label3D mit dem Pet-Namen.
			look_at(global_position - dir, Vector3.UP)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)

func get_save_state() -> Dictionary:
	return {
		"pos":           var_to_str(global_position),
		"color":         var_to_str(_color),
		# BUGFIX ("Pets verlieren nach Save/Load ihr Modell", schrumpfen zu kleinen
		# Kugeln): body_size/speed fehlten hier komplett — on_spawn() bekam beim
		# Wiederherstellen dadurch nie die tatsächliche Größe des gefangenen Tieres
		# (siehe AnimalCatcher.catch_animal()'s config), sondern immer nur den
		# winzigen PetComponent-Klassen-Default Vector3(0.3, 0.4, 0.3).
		"body_size":     var_to_str(_body_size),
		"speed":         _speed,
		# BUGFIX ("Nach dem Fangen ist das ursprüngliche Modell weg" / Save-Reload):
		# ohne diese Felder verlor ein Pet seine Silhouette auch bei jedem Neuladen wieder,
		# selbst nachdem sie beim Fangen selbst schon korrekt übernommen wurde.
		"ear_style":      _ear_style,
		"tail_style":     _tail_style,
		"snout_style":    _snout_style,
		"headgear_style": _headgear_style,
		"tail_scale":     _tail_scale,
		"body_plan":      _body_plan,
		"wing_style":     _wing_style,
		"back_style":     _back_style,
		"body_shape":     _body_shape,
		"leg_style":      _leg_style,
		"pattern_style":  _pattern_style,
		"pattern_color":  _pattern_color,
		"accent_style":   _accent_style,
		"species_id":    _species_id,
		"name":          _name,
		"owner_peer_id": _owner_peer_id,
		"owner_player_id": _owner_player_id,
		# FEATURE (Pet-Fähigkeiten): ohne dieses Feld würde ein Pet beim
		# nächsten Laden auf PetRestorer.gd's Default zurückfallen (siehe
		# dort) statt die tatsächlich zugewiesenen Fähigkeiten zu behalten —
		# relevant sobald Fähigkeiten künftig mal umverteilbar werden.
		"abilities":     _abilities,
		# FEATURE (Pet-XP/Level): ohne dieses Feld würde ein Pet bei jedem
		# Neuladen wieder bei Level 1 anfangen.
		"xp":            _xp,
		# FEATURE (Pet-Kämpfe): Kampfteam-Zugehörigkeit überlebt Save/Load.
		"battle_team":   _battle_team,
	}

## BUGFIX ("Nach dem Fangen ist das ursprüngliche Modell weg"): baute bisher nur eine
## schlichte, kopf-/ohren-/schwanzlose Kapsel aus _color/_body_size — das gefangene Tier sah
## als Pet komplett anders aus. Jetzt: dieselbe AnimalVisualBuilder-Geometrie wie AnimalBase,
## mit dem vom Tier übernommenen Silhouette-Profil (siehe _ear_style/_tail_style/etc. und
## AnimalCatcher.catch_animal()). _build_collision() bleibt unverändert auf _body_size
## basiert — Kollisionsform ist bewusst von der Kosmetik getrennt, siehe AnimalBase-Vorbild.
func _build_visuals() -> void:
	var profile := AnimalVisualProfile.new(_color, _body_size)
	profile.ear_style      = _ear_style
	profile.tail_style     = _tail_style
	profile.snout_style    = _snout_style
	profile.headgear_style = _headgear_style
	profile.tail_scale     = _tail_scale
	profile.body_plan      = _body_plan
	profile.wing_style     = _wing_style
	profile.back_style     = _back_style
	profile.body_shape     = _body_shape
	profile.leg_style      = _leg_style
	profile.pattern_style  = _pattern_style
	profile.pattern_color  = _pattern_color
	profile.accent_style   = _accent_style
	add_child(AnimalVisualBuilder.build(profile))

	var lbl := Label3D.new()
	lbl.text = _name
	lbl.font_size = 36
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.6, 1.0, 0.6)
	# Etwas höher als vorher (war auf die alte, kopflose Kapsel abgestimmt) — muss jetzt
	# über dem Kopf schweben, nicht nur über dem Rumpf.
	lbl.position.y = _body_size.y * 1.6
	add_child(lbl)

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = _body_size.x * 0.4
	sh.height = _body_size.y
	col.shape = sh
	col.position.y = _body_size.y * 0.5
	add_child(col)
