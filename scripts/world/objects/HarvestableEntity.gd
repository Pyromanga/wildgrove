extends Node3D
class_name HarvestableEntity

## HarvestableEntity — Basisklasse für alle abbau-/fällbaren Welt-Objekte.
##
## Subklassen implementieren:
##   _get_entity_type_id() -> String   — EntityRegistry-Key ("oak_tree", "iron_ore", ...)
##   _build_interactable_data() -> InteractableData — Typ-spezifische Interaktion
##   _build_visuals()                  — Typ-spezifische 3D-Darstellung
##
## Die Basisklasse übernimmt:
##   - Lifecycle (on_spawn / on_despawn / _ready)
##   - InteractableComponent aufbauen und verdrahten
##   - Context in InteractableComponent propagieren
##   - Despawn via EntityOrchestrator (UUID-Lookup) oder Fallback queue_free()
##   - Harvest-State via WorldService.mark_harvested(type_id, pos)
##
## Neue Ressource-Typen (WillowTree, CopperOre, ...): nur Subklasse anlegen,
## 3 Methoden implementieren, in WorldEntityRegistry.register_all() eintragen.
## Kein Lifecycle-Code mehr kopieren.

var _interactable_comp: InteractableComponent = null
var _ctx:               IEntityContext        = null

## Wunsch "Bäume ... über Spieltage hinweg wachsen": roher `config`-Parameter von on_spawn(),
## VOR _build_visuals() gesetzt (siehe dort) — so können Subklassen (OakTree/WillowTree/
## MapleTree/PineTree) in ihrer eigenen _build_visuals() (die selbst keine Parameter hat, um
## nicht alle ~15 HarvestableEntity-Subklassen anzufassen) trotzdem an z.B. "planted_day"
## herankommen, ohne die _build_visuals()-Signatur zu ändern. Für alle anderen Subklassen
## (IronOre, WildBeehive, ...) einfach ein ungenutztes leeres Dictionary.
var _spawn_config: Dictionary = {}

## Wunsch "Bäume ... über Spieltage hinweg wachsen": _build_visuals() allein reicht nicht, um
## sichtbar ÜBER DIE ZEIT zu wachsen — es läuft nur einmal beim (Re-)Spawn, ein bereits
## stehender Baum würde nie von Sapling auf Jungbaum/ausgewachsen aktualisiert. Deshalb hier
## generisch (für ALLE HarvestableEntity-Subklassen, nicht nur Bäume): Default "" = "kein
## wachsender Baum", macht _on_day_advanced() für alle anderen Typen (Erz, Bienenstock, ...) zu
## einem reinen No-Op nach dem ersten Vergleich. OakTree/WillowTree/MapleTree/PineTree
## überschreiben das mit ihrer TreeGrowthStage.suffix_for_tree()-Berechnung.
func _tree_growth_suffix() -> String:
	return ""

## Letzter über _tree_growth_suffix() berechneter Wert — verhindert unnötiges Neu-Aufbauen bei
## jedem Tageswechsel, wenn sich am Stadium nichts geändert hat (der Normalfall: die meisten
## Tage ändert sich nichts, siehe TreeGrowthStage.SAPLING_DAYS/YOUNG_DAYS).
var _last_growth_suffix: String = ""

# ─────────────────────────────────────────────
# Abstrakt — Subklassen müssen überschreiben
# ─────────────────────────────────────────────

## EntityRegistry-Key dieser Entität. Wird für Harvest-State-Key genutzt.
## Beispiele: "oak_tree", "iron_ore", "copper_ore", "willow_tree"
func _get_entity_type_id() -> String:
	push_error("HarvestableEntity: _get_entity_type_id() nicht implementiert in '%s'." % get_class())
	return "unknown"

## Erstellt und gibt die Typ-spezifischen InteractableData zurück.
## Wird einmalig in _ready() aufgerufen.
func _build_interactable_data() -> InteractableData:
	push_error("HarvestableEntity: _build_interactable_data() nicht implementiert in '%s'." % get_class())
	return InteractableData.new()

## Erstellt die 3D-Darstellung dieser Entität.
## Wird in on_spawn() aufgerufen wenn ctx.get_factory3d() verfügbar ist.
## Für Factory3D-Calls: ctx ist zu diesem Zeitpunkt gesetzt.
func _build_visuals() -> void:
	push_error("HarvestableEntity: _build_visuals() nicht implementiert in '%s'." % get_class())

# ─────────────────────────────────────────────
# Lifecycle — geerbt, nicht überschreiben
# ─────────────────────────────────────────────

func _ready() -> void:
	var type_id := _get_entity_type_id()
	if name == get_class() or name.begins_with("@"):
		name = "%s_%d" % [type_id, get_instance_id() % 9999]
	set_multiplayer_authority(1)
	_setup_interactable()
	# Wunsch "Bäume ... über Spieltage hinweg wachsen": _ready() feuert bei gepoolten Entities
	# GENAU EINMAL pro Node-Instanz (im Gegensatz zu on_spawn(), das bei jeder Pool-
	# Wiederverwendung erneut läuft) — hier verbinden ist also verbindungs-sicher, ohne vorher
	# is_connected() prüfen zu müssen (kein Risiko, sich bei jedem Respawn ein zweites Mal zu
	# verbinden). Für alle Nicht-Baum-Subklassen bleibt _tree_growth_suffix() immer "" → der
	# Callback ist dort nach dem ersten Vergleich ein reines No-Op.
	EventBus.world.time_of_day_changed.connect(_on_day_advanced)
	AppLogger.log_info(
		"%s bereit bei %s. Label: '%s'." % [
			type_id,
			str(position),
			_interactable_comp.data.label if _interactable_comp else "?"
		],
		type_id
	)

## Aufgerufen von EntityOrchestrator NACH add_child() und NACH _ready().
func on_spawn(config: Dictionary = {}, ctx: IEntityContext = null) -> void:
	_ctx = ctx
	_spawn_config = config
	AppLogger.log_debug("%s.on_spawn() config: %s" % [_get_entity_type_id(), str(config)], _get_entity_type_id())
	if is_instance_valid(_interactable_comp):
		_interactable_comp.inject_context(_ctx)
	# Pool-Reuse-Guard: Visuals vor dem Aufbau bereinigen damit sich bei jedem
	# Spawn-Zyklus keine MeshInstance3D-Kinder akkumulieren.
	_clear_visuals()
	_build_visuals()
	# Baseline für _on_day_advanced() (siehe dortiger Kommentar) — DIREKT nach dem ersten
	# _build_visuals()-Aufruf dieses (Re-)Spawns, damit ein frisch nachgewachsener Sapling nicht
	# beim allernächsten Tageswechsel sofort unnötig neu gebaut wird (derselbe Wert nochmal).
	_last_growth_suffix = _tree_growth_suffix()
	_on_spawn_extended(config)

## Hook für Subklassen die on_spawn zusätzliche Logik brauchen (optional).
func _on_spawn_extended(_config: Dictionary) -> void:
	pass

## EventBus.world.time_of_day_changed-Handler (siehe _ready()) — prüft bei JEDEM Tageswechsel,
## ob sich _tree_growth_suffix() geändert hat (für alle Nicht-Baum-Typen immer "" → sofortiges
## No-Op) und baut die Visuals nur dann neu auf. is_inside_tree()/visible schließt gepoolte
## (geparkte, siehe EntityOrchestrator._pool_container-Kommentar) Bäume billig aus, bevor
## überhaupt _tree_growth_suffix() gerechnet wird — ein wartender Baum im Pool muss nicht
## mitaltern, er bekommt beim nächsten echten (Re-)Spawn ohnehin einen frischen planted_day.
func _on_day_advanced(_hour: int) -> void:
	# is_visible_in_tree() statt nur `visible`: geparkte (gepoolte) Entities hängen unter dem
	# unsichtbaren EntityOrchestrator._pool_container (dessen `visible = false` gesetzt ist,
	# siehe dortiger Kommentar) — die eigene `visible`-Property des Kindes bleibt dabei
	# unangetastet (weiterhin true), nur die geerbte Sichtbarkeit ist false. Nur DAS
	# unterscheidet zuverlässig "aktiv im Wald stehend" von "geparkt, wartet auf Respawn".
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var suffix := _tree_growth_suffix()
	if suffix == _last_growth_suffix:
		return
	_last_growth_suffix = suffix
	_clear_visuals()
	_build_visuals()

## Bereinigt alle visuellen Kinder dieser Entity.
## Wird am Anfang von on_spawn() aufgerufen — verhindert Visual-Akkumulation
## bei Pool-Reuse (EntityPool gibt Entity zurück ohne Kinder zu entfernen).
## Subklassen können überschreiben wenn gezielte Bereinigung nötig ist.
## Wichtig: _interactable_comp wird NICHT entfernt (ist kein visueller Child).
func _clear_visuals() -> void:
	for child in get_children():
		if child == _interactable_comp:
			continue  # InteractableComponent erhalten
		# Sofortiges free() statt queue_free(): queue_free() ist deferred (wirkt erst
		# am Frame-Ende) — bei zwei synchronen on_spawn()-Aufrufen im selben Frame
		# (Pool-Reuse!) wäre das alte Mesh beim Neuaufbau noch nicht entfernt und
		# würde sich akkumulieren. Reine Visual-Kinder haben keine hängenden
		# Cross-Frame-Verbindungen, sofortiges free() ist hier sicher.
		remove_child(child)
		child.free()

## Aufgerufen von EntityOrchestrator beim Despawn.
## Chunk wird entladen — das Objekt ist NICHT abgeerntet. Nur aufräumen, kein mark_harvested()
## (siehe EntityOrchestrator.unload_entity()). Beim nächsten Laden des Chunks entsteht es neu.
func on_unload() -> void:
	if is_instance_valid(_interactable_comp):
		_interactable_comp.disconnect_world_events()

func on_despawn() -> void:
	var type_id := _get_entity_type_id()
	AppLogger.log_debug("%s.on_despawn() bei %s." % [type_id, str(global_position)], type_id)
	if is_instance_valid(_interactable_comp):
		_interactable_comp.disconnect_world_events()
	var world: WorldService = _ctx.get_world() if is_instance_valid(_ctx) else null
	if is_instance_valid(world):
		world.mark_harvested(type_id, global_position)
		AppLogger.log_info("Harvest-Marker gesetzt: '%s' @ %s." % [type_id, str(global_position)], type_id)
	else:
		AppLogger.log_warn("WorldService nicht verfügbar — Harvest-State nicht persistiert.", type_id)

# ─────────────────────────────────────────────
# Shared Helpers — Subklassen nutzen diese statt eigener Duplikate
# ─────────────────────────────────────────────

## Gemeinsamer Placeholder-Zylinder für Bäume — ersetzt die dreifache Duplikation
## in OakTree, WillowTree, MapleTree.
## radius: Zylinderradius (oben = unten), height: Zylinderhöhe, color: Stammfarbe.
## texture_category: optional — ProceduralTextureFactory-Kategorie (siehe
## MeshCache.get_textured_material()), z.B. "glass" (Fulgurit) oder "charcoal"
## (Kohlenmeiler). Leer (Default) = unverändertes Verhalten, reine Flächenfarbe
## — bestehende Aufrufer ohne dritten Parameter (OakTree/WillowTree/... als
## echter Factory3D-Fallback) bleiben unangetastet. Ohne Factory3D/MeshCache
## verfügbar (z.B. weil _ctx fehlt) fällt es automatisch auf die Flächenfarbe
## zurück statt einen Fehler zu werfen — "etwas Einfarbiges" ist immer noch
## besser als "gar nichts".
func _add_placeholder_cylinder(radius: float, height: float, color: Color, texture_category: String = "") -> void:
	var mesh_inst := MeshInstance3D.new()
	var cyl       := CylinderMesh.new()
	cyl.top_radius    = radius
	cyl.bottom_radius = radius
	cyl.height        = height
	mesh_inst.mesh    = cyl
	mesh_inst.material_override = _placeholder_material(color, texture_category)
	mesh_inst.position.y      = height * 0.5
	add_child(mesh_inst)

## Gemeinsamer Placeholder-Quader für Erze — ersetzt direktes add_child()
## in IronOre/CopperOre. texture_category: siehe _add_placeholder_cylinder().
func _add_placeholder_box(size: Vector3, color: Color, texture_category: String = "") -> void:
	var m   := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh   = box
	m.material_override = _placeholder_material(color, texture_category)
	add_child(m)

## Gemeinsamer Placeholder-Kegel(stumpf) für Hügel/Nester (AntHill, TermiteMound,
## MoleHill). bottom_radius > top_radius = Hügel; top_radius 0 = Spitze. y_offset hebt den
## Kegel an (z.B. für einen aufgesetzten Schlot). texture_category: siehe
## _add_placeholder_cylinder().
func _add_placeholder_cone(bottom_radius: float, top_radius: float, height: float, color: Color, texture_category: String = "", y_offset: float = 0.0) -> void:
	var mesh_inst := MeshInstance3D.new()
	var cone      := CylinderMesh.new()
	cone.bottom_radius = bottom_radius
	cone.top_radius    = top_radius
	cone.height        = height
	mesh_inst.mesh     = cone
	mesh_inst.material_override = _placeholder_material(color, texture_category)
	mesh_inst.position.y = y_offset + height * 0.5
	add_child(mesh_inst)

## Gemeinsamer Placeholder-Ellipsoid für hängende Nester (WaspNest, HornetNest).
## radius = Querradius, height = volle Höhe; unten abgeflacht auf dem Boden gedacht
## (Mittelpunkt auf height/2 + y_offset). texture_category: siehe _add_placeholder_cylinder().
func _add_placeholder_ellipsoid(radius: float, height: float, color: Color, texture_category: String = "", y_offset: float = 0.0) -> void:
	var mesh_inst := MeshInstance3D.new()
	var sphere    := SphereMesh.new()
	sphere.radius = radius
	sphere.height = height
	mesh_inst.mesh = sphere
	mesh_inst.material_override = _placeholder_material(color, texture_category)
	mesh_inst.position.y = y_offset + height * 0.5
	add_child(mesh_inst)

## Liefert ein texturiertes Material aus MeshCache (über Factory3D.cache),
## wenn texture_category gesetzt UND Factory3D/MeshCache gerade verfügbar
## sind — sonst ein reines StandardMaterial3D mit Flächenfarbe (altes
## Verhalten). Ein Erzblock mit Adern-Textur sieht deutlich weniger nach
## Platzhalter aus als eine einfarbige Box; kostet hier nur diese eine
## gemeinsame Stelle statt jede Subklasse einzeln umzubauen.
func _placeholder_material(color: Color, texture_category: String) -> StandardMaterial3D:
	if texture_category != "" and is_instance_valid(_ctx):
		var factory: Factory3D = _ctx.get_factory3d()
		if is_instance_valid(factory) and is_instance_valid(factory.cache):
			return factory.cache.get_textured_material(color, texture_category)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _setup_interactable() -> void:
	var d := _build_interactable_data()
	_interactable_comp = InteractableComponent.new()
	_interactable_comp.data = d
	add_child(_interactable_comp)
	_interactable_comp.interacted.connect(_on_interacted)
	AppLogger.log_debug(
		"InteractableComponent '%s' erstellt (XP: %d %s)." % [d.label, d.xp_amount, d.xp_type],
		_get_entity_type_id()
	)

## peer_id: kommt aus resolve_and_dispatch_interaction()/dem lokalen
## interacted-Emit — echte Identität des erntenden Spielers (ADR-015/ADR-020).
##
## ADR-020 / R-1 (Round 43): Loot-Roll + XP-Bemessung laufen jetzt HIER, nicht
## mehr in InteractionExecutor._on_tween_finished(). Dieser Hook läuft dank des
## Autoritäts-Guards unten UND des Round-42-Transports garantiert nur auf der
## echten Autorität — exakt die Voraussetzung, die InteractionResolver.resolve()
## selbst nicht mehr prüft (das ist bewusst nicht seine Verantwortung, siehe
## dortige Doku). _interactable_comp.data ist die servereigene Kopie der
## InteractableData (aus der Szene/Resource geladen, nie vom Client übertragen) —
## es gibt keinen Pfad, über den ein Client hier eine andere loot_table oder
## einen anderen xp_amount einschleusen könnte.
##
## ADR-020 / R-3 + R-6: Guard analog zu EnemyNPC._on_interacted(). Vorher lief
## dieser Hook auf JEDEM Peer, der seinen lokalen Tween zuerst beendet hat —
## auf einem Nicht-Host-Client despawnte das Objekt dadurch nur lokal (der
## despawn-Request lief über den lokalen, pro-Peer-EventBus, siehe R-6), der
## Server hatte nie davon erfahren und hielt das Objekt weiterhin für
## interagierbar. Jetzt läuft die eigentliche Wirkung ausschließlich auf der
## Autorität — erreicht über InteractableComponent._handle_completion()'s
## RPC-Weiterleitung (WorldService.request_entity_interaction()), nicht mehr
## über den rein lokalen Tween-Abschluss eines beliebigen Peers.
func _on_interacted(action_id: String, peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var type_id := _get_entity_type_id()
	var bus: IEventBus = _ctx.get_event_bus() if is_instance_valid(_ctx) else null
	if is_instance_valid(_interactable_comp):
		var stat_mods: StatModifierService = _ctx.get_stat_modifiers() if is_instance_valid(_ctx) else null
		# Round 69: InteractionResolver.resolve() braucht jetzt zusätzlich zur
		# peer_id auch die stabile player_id (für den StatModifierService-Aufruf
		# darin) — Auflösung passiert HIER, am Aufrufer, nicht in
		# InteractionResolver selbst (siehe dessen Klassenkommentar + geklärte
		# Design-Frage in TODO-offene-probleme.md). Leerer NetworkBridge/
		# unauflösbare peer_id → leerer String, resolve() behandelt das als
		# "kein Stat-Bonus", kein Crash.
		var network: NetworkBridge = _ctx.get_network_bridge() if is_instance_valid(_ctx) else null
		var player_id := network.get_player_id_for_peer(peer_id) if is_instance_valid(network) else ""
		InteractionResolver.resolve(_interactable_comp.data, peer_id, player_id, bus, stat_mods)
	AppLogger.log_info("Interaktion '%s' abgeschlossen — %s despawnt." % [action_id, type_id], type_id)
	# BUGFIX (2026-09-17, "Bäume/Erze despawnen nicht bei anderen Peers"):
	# genau dieselbe Lücke wie bei EnemyNPC._die() (siehe dortiger Kommentar) —
	# despawnt bisher nur lokal auf der Autorität über den EventBus, kein
	# anderer Peer erfuhr je davon. Nutzt denselben Broadcast-Kanal
	# (NetworkBridge.broadcast_to_all_peers(), ADR-042) mit dem deterministischen
	# Node-Namen als Adressierung (siehe EntityOrchestrator.spawn_entity() und
	# WorldService._on_broadcast_event_received()/despawn_entity_by_name()).
	var despawn_network: NetworkBridge = _ctx.get_network_bridge() if is_instance_valid(_ctx) else null
	if is_instance_valid(despawn_network):
		despawn_network.broadcast_to_all_peers("entity_despawned", {"name": name})
	else:
		AppLogger.log_warn(
			"_on_interacted(): kein NetworkBridge verfügbar — Despawn von '%s' wird anderen Peers nicht gemeldet." % name,
			type_id
		)
	var uuid: String = get_meta("entity_uuid", "")
	if not uuid.is_empty():
		if bus != null:
			bus.world().emit_entity_despawn_requested(uuid)
		else:
			AppLogger.log_warn("Kein IEventBus im Context — direkte queue_free() statt Despawn-Request.", type_id)
			on_despawn()
			queue_free()
	else:
		AppLogger.log_warn("Keine UUID — direkte queue_free().", type_id)
		on_despawn()
		queue_free()
