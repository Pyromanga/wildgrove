extends CharacterBody3D
class_name EnemyNPC

## EnemyNPC — Koordiniert KI, Gesundheit, Visuals und Interaktion.
##
## Delegiert:
##   KI-State-Machine    → EnemyAI
##   Visuals + Health-Bar → EnemyVisuals
##   Interaktions-Setup + Schaden-Berechnung → EnemyAttack
##
## on_interacted(action_id) wird von InteractableComponent nach Abschluss aufgerufen.

const LOG_CAT := "EnemyNPC"
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

## Konfigurierbar via on_spawn(config)
var _color:        Color  = Color(0.7, 0.15, 0.15)
var _max_health:   int    = 30
var _damage:       int    = 5
var _speed:        float  = 2.5
var _detect_range: float  = 8.0
var _attack_range: float  = 1.5
var _attack_cd:    float  = 1.5
var _xp_reward:    int    = 20
var _xp_skill:     String = "combat"
var _loot_table_id: String = "goblin_loot"   ## ID der LootTable für Goblin-Drops
var _label:        String = "Goblin"

## CombatProfile-ID dieser Entity-Klasse (TD-10). Default "goblin" passt zum
## aktuell einzigen Gegnertyp im Spiel (EnemySpawner.spawn_entity("goblin", …)).
## Konfigurierbar via on_spawn(cfg) für künftige Gegnertypen.
var _combat_profile_id: String = "goblin"
## EntityRegistry-Key dieser Instanz — wird von EntityOrchestrator via on_spawn(cfg["type_id"]) gesetzt.
## Wird in _die() für enemy_killed-Signal genutzt damit QuestService KILL-Objectives tracken kann.
var _type_id: String = "goblin"

## CombatProfile-ID des Angriffsziels bei _do_melee() (TD-11). Aktuell immer
## der Spieler — kein PvP/Multi-Target geplant, daher Konstante statt Config-Feld.
const PLAYER_COMBAT_PROFILE_ID := "player"

var _ai:     EnemyAI
var _health: HealthComponent
var _visuals: EnemyVisuals

var _ctx:        IEntityContext = null
var _bus:        IEventBus      = null  ## Injiziert via on_spawn(ctx). Pflicht-Dep, kein AutoLoad-Fallback.
var _player_ref: Node3D = null
var _despawn_timer: SceneTreeTimer = null  ## Referenz zum Canceln bei vorzeitigem Despawn
var _despawn_callable: Callable = Callable()  ## Referenz zum gezielten disconnect() bei on_despawn()

func _ready() -> void:
	add_to_group("enemies")
	set_multiplayer_authority(1)
	# G-02: Nächsten Spieler statt [0] wählen — korrekt bei mehreren Spielern.
	_player_ref = _find_closest_player()
	if name == get_class() or name.begins_with("@"):
		name = "%s_%d" % [_label, get_instance_id() % 9999]

	# Player-Referenz wird in on_spawn() reaktiv gehalten — dort ist _bus garantiert
	# gesetzt (kein Fallback-Pattern mehr nötig).

	_ai      = EnemyAI.new(_detect_range, _attack_range, _attack_cd, _speed)
	_visuals = EnemyVisuals.new()
	# _type_id ist zu diesem Zeitpunkt bereits korrekt (Default "goblin" bzw. per _init()
	# überschrieben wie bei SkeletonNPC — auf_spawn(cfg) läuft erst später, siehe dortiger
	# Kommentar), damit EnemyVisuals das passende Modell/Accessoires wählen kann.
	_visuals.build(self, _color, _max_health, _label, _type_id)
	_build_collision()
	_setup_health()
	EnemyAttack.setup_interactable(self, _label)
	_setup_multiplayer_sync()
	AppLogger.log_debug("EnemyNPC '%s' bereit." % name, LOG_CAT)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if _ai.state == EnemyAI.State.DEAD:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	var player := _get_player()
	if not is_instance_valid(player):
		_ai.state = EnemyAI.State.IDLE
		move_and_slide()
		return

	var result := _ai.update(self, player, delta, velocity)
	velocity = result["velocity"]
	if result["do_melee"]:
		_do_melee(player)

	_visuals.update_health_bar(_health.current_health, _health.max_health)
	move_and_slide()

# ─────────────────────────────────────────────
# Interaktions-Callback
# ─────────────────────────────────────────────

## peer_id: echte peer_id des angreifenden Spielers, seit ADR-015 Phase 4
## bereits korrekt von InteractableComponent durchgereicht. Seit ADR-019 wird
## er jetzt auch tatsächlich verwendet — vorher lief hier "player" als
## hartcodierter String-Platzhalter in player_melee_damage(), der weder
## Skill-Level-Lookup noch Killer-Attribution korrekt bedienen konnte.
func _on_interacted(action_id: String, peer_id: int) -> void:
	if action_id != "attack_enemy" or _ai.state == EnemyAI.State.DEAD:
		return

	# G-05: Client-Prediction — sofortiges Hit-Feedback ohne auf Server-Antwort zu warten.
	# Für Tier 2 (Hosted Coop, lokales Netzwerk <20ms) kaum spürbar;
	# für Internet-Coop (>80ms RTT) verhindert es 160ms+ gefühlte Input-Latenz.
	# Prediction-Feedback: visueller Hit-Flash + Sound. Der echte Schaden-Wert
	# kommt danach vom Server — keine Reconciliation nötig wenn er nahe genug ist.
	if not is_multiplayer_authority():
		# G-05: Sofortiges Hit-Feedback auf dem Client ohne auf Server-Antwort zu warten.
		# Zeigt einen vorläufigen Treffer-Indikator — der echte Schadenswert
		# wird vom Server via MultiplayerSynchronizer (HP-Sync) nachgereicht.
		# Kein Reconciliation-Schritt nötig: HP-Wert wird ohnehin repliziert.
		_ui_bus().emit_floating_loot_text_requested("⚔", global_position)
		# Server übernimmt: _on_interacted() läuft dort erneut als Autorität.
		return

	# Schaden-Berechnung über CombatSystem (ADR-008).
	# IEntityContext liefert CombatSystem/DataService. Beide sind seit on_spawn()
	# Pflicht-Dep (siehe dortige Guards) — kein Fallback-Pfad mehr nötig.
	var combat: CombatSystem = _ctx.get_combat_system()
	var data: DataService    = _ctx.get_data()

	var record: DamageRecord = combat.player_melee_damage(peer_id)
	var profile: CombatProfile = (
		data.get_combat_profile(_combat_profile_id)
		if is_instance_valid(data)
		else CombatProfile.default_profile()
	)
	# calculate_damage_with_profile gibt die modifizierte Instanz zurück —
	# Rückgabewert muss zugewiesen werden, sonst bleibt final_amount=0.
	record = combat.calculate_damage_with_profile(record, profile)

	record.target_id = name
	if is_instance_valid(_health):
		combat.apply_damage(record, _health)
		# On-Hit Effekte (Gift etc.) nach dem Treffer anwenden — attacker_peer_id
		# mitgeben, damit ein Gift-/Brand-Tick denselben Killer bekommt (ADR-019).
		combat.apply_weapon_on_hit(_health, "player", name, peer_id)
		AppLogger.log_debug(
			"Spieler trifft '%s': %s → %d/%d HP"
			% [name, record.to_debug_string(), _health.current_health, _health.max_health],
			LOG_CAT
		)

	# ADR-020 / R-2, Berechnungs-Hälfte (Round 43): Interaktions-XP für den
	# abgeschlossenen Schwung selbst (getrennt von der Kill-XP in _die()) lief
	# bisher client-seitig über InteractableData.xp_amount in
	# InteractionExecutor._on_tween_finished() — ungeprüft, ob überhaupt ein
	# lebender Gegner in Reichweite war. Beides ist jetzt durch den Aufrufer
	# bereits sichergestellt, bevor dieser Code hier läuft: is_multiplayer_authority()
	# oben, "_ai.state == DEAD"-Guard am Funktionsanfang, und (auf Tier 2/3)
	# resolve_for_player()'s Reichweitenprüfung (ADR-023) vor dem Aufruf dieses
	# Hooks überhaupt. CombatSystem kennt keine Miss-Chance (siehe
	# CombatSystem.calculate_damage(): MIN_DAMAGE-Clamp, kein 0-Treffer-Pfad) —
	# jeder Aufruf hier ist ein tatsächlich gelandeter Treffer, keine zusätzliche
	# Bedingung nötig. AttackInteractable.data ist die servereigene Kopie
	# (gebaut in EnemyAttack.setup_interactable(), nie vom Client übertragen).
	var attack_ic := get_node_or_null("AttackInteractable") as InteractableComponent
	if is_instance_valid(attack_ic):
		# Round 69: siehe identischer Kommentar in HarvestableEntity._on_interacted() —
		# player_id wird HIER am Aufrufer aufgelöst, nicht innerhalb von
		# InteractionResolver (geklärte Design-Frage, TODO-offene-probleme.md).
		var network: NetworkBridge = _ctx.get_network_bridge() if is_instance_valid(_ctx) else null
		var attack_player_id := network.get_player_id_for_peer(peer_id) if is_instance_valid(network) else ""
		InteractionResolver.resolve(attack_ic.data, peer_id, attack_player_id, _bus, _ctx.get_stat_modifiers())
	else:
		AppLogger.log_warn(
			"_on_interacted(): kein 'AttackInteractable'-Node — Interaktions-XP nicht vergeben.",
			LOG_CAT
		)

# ─────────────────────────────────────────────
# Kampf
# ─────────────────────────────────────────────

func _do_melee(player: Node3D) -> void:
	var hc := player.get_node_or_null("HealthComponent") as HealthComponent
	if not is_instance_valid(hc):
		return

	# Resistenz, kein EventBus.world.damage_dealt. Jetzt über CombatSystem,
	# spiegelbildlich zu _on_interacted() (Spieler → Gegner). CombatSystem/DataService
	# sind seit on_spawn() Pflicht-Dep (siehe dortige Guards) — kein Fallback-Pfad mehr.
	var combat: CombatSystem = _ctx.get_combat_system()
	var data: DataService    = _ctx.get_data()

	var record: DamageRecord = combat.enemy_melee_damage(name, "player", float(_damage))
	var profile: CombatProfile = (
		data.get_combat_profile(PLAYER_COMBAT_PROFILE_ID)
		if is_instance_valid(data)
		else CombatProfile.default_profile()
	)
	# Ausrüstungs-Rüstung des getroffenen Spielers (Schmiede-Rüstung) kommt zur Profil-Rüstung dazu.
	var victim_player_id := ""
	var net: NetworkBridge = _ctx.get_network_bridge() if is_instance_valid(_ctx) else null
	if is_instance_valid(net) and player.has_meta("owner_peer_id"):
		victim_player_id = net.get_player_id_for_peer(int(player.get_meta("owner_peer_id")))
	combat.calculate_damage_with_profile(record, profile, victim_player_id)
	combat.apply_damage(record, hc)

	AppLogger.log_debug(
		"%s trifft Spieler: %s → %d/%d HP"
		% [_label, record.to_debug_string(), hc.current_health, hc.max_health],
		LOG_CAT
	)

## record: der todesursächliche DamageRecord (ADR-019, HealthComponent.died).
## null nur wenn der Tod über einen direkten take_damage()-Aufruf ausgelöst
## wurde statt über den CombatSystem-Pfad (take_damage_record) — z.B. Tests
## (test_enemy_npc_pool_reuse.gd) oder ein künftiger Schadenskanal, der (noch)
## keinen Record baut. In dem Fall gibt es ehrlich keine Killer-Identität, also
## Default 1 (Solo/Host) mit Log-Warnung statt eines geratenen Werts — das ist
## der dokumentierte Edge-Case aus ADR-019, kein stiller Fallback.
func _die(record: DamageRecord = null) -> void:
	_ai.set_dead()
	remove_from_group("interactable")

	var killer_peer_id := 1
	if is_instance_valid(record) and record.attacker_peer_id != -1:
		killer_peer_id = record.attacker_peer_id
	else:
		var reason := "record=null" if record == null else "record.attacker_peer_id=-1"
		AppLogger.log_warn(
			(
				"_die(): kein Spieler-Angreifer im todesursächlichen DamageRecord (%s) — "
				+ "XP/Loot gehen an Default-Spieler 1. Erwartet bei direktem take_damage()-Aufruf "
				+ "ohne CombatSystem-Pfad (z.B. Test) oder echtem Umweltschaden ohne Spieler-Beteiligung."
			) % reason,
			LOG_CAT
		)

	_player_bus().emit_xp_gained(_xp_skill, _xp_reward, killer_peer_id)
	# KILL-Objective-Tracking: QuestService lauscht auf dieses Signal via on_ready().
	# _type_id wird via on_spawn(cfg["type_id"]) vom EntityOrchestrator gesetzt.
	_world_bus().emit_enemy_killed(_type_id, global_position, killer_peer_id)

	# LootTable-basierte Drops. _loot_table_id ist Pflicht-Feld (Default "goblin_loot",
	# konfigurierbar via on_spawn(cfg)); DataService ist seit on_spawn() Pflicht-Dep.
	var data: DataService = _ctx.get_data()
	if _loot_table_id.is_empty():
		AppLogger.log_warn("_die(): _loot_table_id ist leer — keine Drops für '%s'." % name, LOG_CAT)
	else:
		var loot_table: LootTable = data.get_loot_table(_loot_table_id)
		if is_instance_valid(loot_table):
			var rolled := loot_table.roll()
			for item_id in rolled:
				var qty: int = rolled[item_id]
				_world_bus().emit_loot_collected(item_id, qty, killer_peer_id)
				# Floating-Text für jeden Drop
				var item_def: ItemDefinition = data.get_item(item_id)
				var item_name: String = item_def.display_name if is_instance_valid(item_def) else item_id
				_ui_bus().emit_floating_loot_text_requested(
					"+ %s ×%d" % [item_name, qty], global_position
				)
			# Gold-Drop (ADR-033/Gold-Drops): separat von den Item-Rolls oben,
			# da Gold kein Item ist (kein InventorySystem-Eintrag) — geht
			# stattdessen über CurrencyService. peer_id → player_id-Übersetzung
			# identisch zum attack_player_id-Muster oben (_on_interacted()).
			var gold_amount := loot_table.roll_gold()
			if gold_amount > 0:
				var currency: CurrencyService = _ctx.get_currency() if is_instance_valid(_ctx) else null
				var network: NetworkBridge = _ctx.get_network_bridge() if is_instance_valid(_ctx) else null
				var killer_player_id := network.get_player_id_for_peer(killer_peer_id) if is_instance_valid(network) else ""
				if is_instance_valid(currency) and not killer_player_id.is_empty():
					currency.request_add_gold(killer_player_id, gold_amount)
					_ui_bus().emit_floating_loot_text_requested("+ %d 💰 Gold" % gold_amount, global_position)
				else:
					AppLogger.log_warn(
						"_die(): Gold-Drop (%d) konnte nicht ausgezahlt werden — CurrencyService oder player_id fehlt (Spieler %d)." % [gold_amount, killer_peer_id],
						LOG_CAT
					)
		else:
			AppLogger.log_warn(
				"_die(): LootTable '%s' nicht gefunden — keine Drops für '%s'." % [_loot_table_id, name],
				LOG_CAT
			)

	# BUG-D-FIX: Component NICHT queue_free()en. _ready() (wo
	# EnemyAttack.setup_interactable() die Komponente aufbaut) feuert in Godot
	# nur EINMAL pro Node-Lebenszeit — bei Pool-Reuse (respawn_entity() →
	# spawn_entity() → _pool.acquire()) wird derselbe Node-Instanz wieder
	# add_child()'d, _ready() läuft aber NICHT erneut. Ein hier gefreetes
	# AttackInteractable kam also nie zurück → Gegner nach Respawn dauerhaft
	# nicht angreifbar. remove_from_group("interactable") oben reicht bereits
	# aus, um den toten Gegner unangreifbar zu machen; on_spawn() (beim
	# nächsten Spawn/Reuse) fügt die Gruppe über add_to_group("interactable")
	# wieder hinzu — das Component selbst bleibt analog zum
	# HarvestableEntity-Muster (siehe _clear_visuals()-Kommentar dort)
	# unangetastet erhalten.
	_despawn_timer = get_tree().create_timer(1.5)
	_despawn_callable = _on_despawn_timer_finished
	_despawn_timer.timeout.connect(_despawn_callable)
	AppLogger.log_info("%s besiegt. +%d %s XP." % [_label, _xp_reward, _xp_skill], LOG_CAT)

	# BUGFIX (2026-09-15, "Sterben soll auch synced werden"): _die() lief bis
	# hierhin komplett lokal — queue_free() oben entfernt das Node nur auf DEM
	# Peer, der gerade _die() ausführt (das ist immer die Autorität, siehe
	# is_multiplayer_authority()-Guard in _on_interacted() oben: nur die
	# Autorität wendet Schaden überhaupt an, andere Peers zeigen nur ein
	# Hit-Feedback und kehren vorher zurück). Ohne diesen Broadcast blieb der
	# hier besiegte Gegner auf jedem anderen Peer als "Zombie" stehen — HP
	# selbst wird NICHT über den MultiplayerSynchronizer repliziert (siehe
	# _setup_multiplayer_sync() unten: nur position/rotation), also erfährt
	# kein anderer Peer je von diesem Tod, außer wir sagen es ihm explizit.
	# Nutzt den bereits vorhandenen generischen Broadcast-Kanal (ADR-042,
	# NetworkBridge.broadcast_to_all_peers()) statt einen eigenen RPC zu bauen —
	# `name` ist seit dem world_seed-Sync-Fix (EntityOrchestrator.spawn_entity())
	# auf allen Peers deterministisch identisch, adressiert also zuverlässig
	# dasselbe logische Entity auf der Empfängerseite (siehe
	# WorldService._on_broadcast_event_received()).
	if is_multiplayer_authority():
		var net: NetworkBridge = _ctx.get_network_bridge() if is_instance_valid(_ctx) else null
		if is_instance_valid(net):
			net.broadcast_to_all_peers("entity_despawned", {"name": name})
		else:
			AppLogger.log_warn(
				"_die(): kein NetworkBridge verfügbar — Tod von '%s' wird anderen Peers nicht gemeldet." % name,
				LOG_CAT
			)

## BUGFIX (2026-09-20, "Gegner respawnen nicht"): vorher hier ein rohes
## queue_free() — das entfernt die Node nur lokal aus dem SceneTree, OHNE
## EntityOrchestrator._entities zu bereinigen und OHNE das
## bus.world().entity_despawned-Signal zu emittieren, auf das
## RespawnService._on_entity_despawned() lauscht. Damit kam ein besiegter
## Gegner nie in die Respawn-Queue, selbst mit registrierter
## RespawnService-Config (siehe WorldService.on_ready()). Analog zu
## HarvestableEntity._on_interacted(): auf der Autorität läuft der Despawn
## jetzt über bus.world().emit_entity_despawn_requested(uuid) →
## WorldService._on_entity_despawn_requested() → despawn_entity() →
## EntityOrchestrator.despawn_entity() (räumt _entities auf UND emittiert
## entity_despawned). Nicht-Autoritäts-Peers haben ihre Kopie bereits über
## den Broadcast oben + WorldService._on_broadcast_event_received() /
## despawn_entity_by_name() entfernt bekommen — hier bewusst nur ein
## Fallback-queue_free() falls uuid/bus fehlen (Tests, Edge-Cases).
func _on_despawn_timer_finished() -> void:
	if is_multiplayer_authority():
		var bus: IEventBus = _ctx.get_event_bus() if is_instance_valid(_ctx) else null
		var uuid: String = get_meta("entity_uuid", "")
		if is_instance_valid(bus) and not uuid.is_empty():
			bus.world().emit_entity_despawn_requested(uuid)
			return
		AppLogger.log_warn(
			"_on_despawn_timer_finished(): kein EventBus/keine UUID — direkte queue_free() statt Despawn-Request (kein Respawn möglich).",
			LOG_CAT
		)
	if is_instance_valid(self):
		queue_free()

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _setup_health() -> void:
	_health            = HealthComponent.new()
	_health.name       = "HealthComponent"
	_health.max_health = _max_health
	add_child(_health)
	_health.died.connect(_die)

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var sh  := CapsuleShape3D.new()
	sh.radius = 0.32
	sh.height = 1.0
	col.shape  = sh
	col.position.y = 0.7
	add_child(col)

func _get_player() -> Node3D:
	# Kein Polling mehr hier — _player_ref wird event-getrieben gesetzt:
	# einmalig in _ready() (falls der Player schon existiert), danach über
	# world().entity_spawned / player_respawned (siehe _on_entity_spawned()).
	# Vorher rief dies bei jedem _physics_process-Frame ohne validen Player
	# get_tree().get_nodes_in_group("player") auf — und da Gegner vor dem
	# Player gespawnt werden (siehe Log-Reihenfolge), war das ein Full-Tree-
	# Scan pro Gegner pro Frame bis der Player existierte.
	return _player_ref

## EventBus-Accessors — liefern den injizierten IEventBus-Namespace. Kein AutoLoad-Fallback.
## Hilfsmethoden für typisierten Bus-Zugriff. _bus ist ab on_spawn() Pflicht-Dep —
## kein AutoLoad-Fallback mehr (siehe ADR-014, EnemyNPC ist kein Pre-Boot-Node).
func _player_bus() -> PlayerEvents: return _bus.player()
func _world_bus()  -> WorldEvents:  return _bus.world()
func _ui_bus()     -> UIEvents:     return _bus.ui()

## G-02: Gibt den nächsten validen Spieler-Node zurück.
## Bei einem Spieler identisch zu players[0];
## bei mehreren Spielern wird der räumlich nächste gewählt —
## damit verfolgen Gegner den richtigen Spieler.
func _find_closest_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	var closest: Node3D = null
	var closest_dist := INF
	for p in players:
		if not is_instance_valid(p):
			continue
		var dist := global_position.distance_squared_to((p as Node3D).global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = p as Node3D
	return closest

func _on_player_ref_died() -> void:
	_player_ref = null

func _on_player_ref_respawned() -> void:
	# G-02: Nächsten Spieler wählen statt [0].
	_player_ref = _find_closest_player()

## Ersetzt das alte Polling in _get_player(): world().entity_spawned feuert für
## JEDE Entity (Bäume, Erz, Gegner, Spieler …), daher hier auf type_id == "player"
## filtern. Nur relevant solange noch kein _player_ref bekannt ist — sobald einer
## gesetzt ist, ignorieren wir weitere Spawns (andere Spieler, die später in Coop
## beitreten, werden weiterhin nur über player_respawned neu evaluiert, um
## bestehendes Chase-Verhalten nicht zu unterbrechen).
func _on_entity_spawned(type_id: String, _entity: Node3D, _position: Vector3) -> void:
	if type_id != "player":
		return
	if not is_instance_valid(_player_ref):
		_player_ref = _find_closest_player()

# ─────────────────────────────────────────────
# Multiplayer-Sync (Sprint D)
# ─────────────────────────────────────────────

## Position-Sync für Clients: Server ist Autorität (set_multiplayer_authority(1) in _ready()).
## Clients empfangen Position und Rotation; Velocity wird nicht repliziert da
## Clients keinen _physics_process ausführen (Guard in Sprint C).
##
## replication_interval = 0.1s → 10 Hz. Gegner-Bewegung ist weniger latenz-kritisch
## als Spieler — 10 Hz reicht für sichtbar flüssige KI-Bewegung.
func _setup_multiplayer_sync() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSync"
	sync.replication_interval = 0.1   # 10 Hz — Gegner weniger latenz-kritisch als Player
	add_child(sync)
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	sync.replication_config = config
	AppLogger.log_debug("MultiplayerSynchronizer erstellt (position, rotation, 10Hz).", LOG_CAT)

# ─────────────────────────────────────────────
# EntityOrchestrator-Interface
# ─────────────────────────────────────────────

func on_spawn(cfg: Dictionary = {}, ctx: IEntityContext = null) -> void:
	_ctx = ctx
	# IEventBus aus EntityContext injizieren — Pflicht-Dep, kein AutoLoad-Fallback.
	# Signal-Connects erfolgen hier weil _bus erst ab on_spawn() garantiert gesetzt ist.
	if is_instance_valid(ctx) and ctx.has_method("get_event_bus"):
		_bus = ctx.get_event_bus() as IEventBus
	if _bus == null:
		AppLogger.log_error(
			"EnemyNPC.on_spawn(): kein IEventBus im EntityContext — Spawn ohne DI nicht unterstützt.",
			LOG_CAT
		)
		return
	# CombatSystem ist ab hier Pflicht-Dep, exakt wie IEventBus oben — kein
	# stiller Schaden-Fallback mehr in _on_interacted()/_do_melee() (siehe dort).
	if not is_instance_valid(ctx) or not is_instance_valid(ctx.get_combat_system()):
		AppLogger.log_error(
			"EnemyNPC.on_spawn(): kein CombatSystem im EntityContext — Spawn ohne DI nicht unterstützt.",
			LOG_CAT
		)
		return
	_player_bus().player_died.connect(_on_player_ref_died)
	_player_bus().player_respawned.connect(_on_player_ref_respawned)
	# Ersetzt Polling in _get_player(): Gegner werden vor dem Player gespawnt,
	# daher ist _player_ref hier normalerweise noch null — dieses Signal liefert
	# ihn nach, sobald der Player tatsächlich existiert, statt jeden Frame den
	# SceneTree abzufragen.
	if not _world_bus().entity_spawned.is_connected(_on_entity_spawned):
		_world_bus().entity_spawned.connect(_on_entity_spawned)
	if cfg.has("label"):       _label       = cfg["label"]
	if cfg.has("color"):       _color       = cfg["color"]
	if cfg.has("max_health"):  _max_health  = cfg["max_health"]
	if cfg.has("damage"):      _damage      = cfg["damage"]
	if cfg.has("xp_reward"):   _xp_reward   = cfg["xp_reward"]
	if cfg.has("loot_table"): _loot_table_id = cfg["loot_table"]
	if cfg.has("combat_profile"): _combat_profile_id = cfg["combat_profile"]
	if cfg.has("type_id"):        _type_id           = cfg["type_id"]
	if is_instance_valid(_health):
		_health.max_health = _max_health
		_health.reset()
		# on_despawn() disconnectet das died-Signal — bei Pool-Reuse muss es
		# hier wieder verbunden werden, sonst stirbt der Goblin nie.
		if not _health.died.is_connected(_die):
			_health.died.connect(_die)
	_ai.state = EnemyAI.State.IDLE
	add_to_group("interactable")
	# BUG-D-FIX: inject_context() wurde hier bisher NIE aufgerufen — anders als
	# bei jedem anderen Interactable-Setup im Code (HarvestableEntity, Ladder,
	# BuildPiece, Gravestone, AnimalBase, PlayerAttack, PlayerTrade,
	# PlayerThank, PlayerPickpocket). _ctx blieb dauerhaft null, wodurch
	# InteractableComponent._setup_bar()/_connect_world_events() nie liefen —
	# die 3D-Fortschrittsbar beim Angreifen fehlte (Angriff selbst funktioniert
	# unabhängig davon über das direkt verbundene 'interacted'-Signal →
	# _on_interacted()). Muss NACH add_child() in _ready() UND bei jedem
	# on_spawn()-Aufruf (auch Pool-Reuse) erneut laufen, da _ctx pro Spawn-
	# Zyklus eine neue EntityContext-Instanz sein kann.
	var attack_ic := get_node_or_null("AttackInteractable") as InteractableComponent
	if is_instance_valid(attack_ic):
		attack_ic.inject_context(ctx)
	else:
		AppLogger.log_warn(
			"on_spawn(): kein 'AttackInteractable'-Node gefunden — inject_context() übersprungen.",
			LOG_CAT
		)

func on_despawn() -> void:
	_ai.set_dead()
	if is_instance_valid(_health) and _health.died.is_connected(_die):
		_health.died.disconnect(_die)
	if _player_bus().player_died.is_connected(_on_player_ref_died):
		_player_bus().player_died.disconnect(_on_player_ref_died)
	if _player_bus().player_respawned.is_connected(_on_player_ref_respawned):
		_player_bus().player_respawned.disconnect(_on_player_ref_respawned)
	if _world_bus().entity_spawned.is_connected(_on_entity_spawned):
		_world_bus().entity_spawned.disconnect(_on_entity_spawned)
	# Timer canceln — feuert sonst nach Ablauf auch wenn Node bereits freigegeben.
	if is_instance_valid(_despawn_timer):
		if _despawn_timer.timeout.is_connected(_despawn_callable):
			_despawn_timer.timeout.disconnect(_despawn_callable)
		_despawn_timer = null
