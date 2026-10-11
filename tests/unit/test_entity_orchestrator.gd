# res://tests/unit/test_entity_orchestrator.gd
extends GutTest

## Unit-Tests für EntityOrchestrator.resolve_for_player() (ADR-023).
##
## Deckt ab:
##   - unbekannte UUID → null
##   - kein Player-Node mit passendem peer_id → null
##   - Player existiert, aber Entity außerhalb max_range → null
##   - Player existiert, Entity innerhalb max_range → Entity wird zurückgegeben
##   - peer_id-Auflösung nutzt "owner_peer_id"-Meta, nicht Node-Reihenfolge
##   - actor_uuid (Bugfix 2026-09-26, "Pets können Ressourcen manchmal nicht
##     abbauen/sammeln"): Reichweite wird ab EINER ANDEREN registrierten
##     Entity gemessen (z.B. einem Pet), nicht zwingend ab dem Besitzer-Spieler

var _orchestrator: EntityOrchestrator
var _world_root: Node3D

func before_each() -> void:
	_world_root = add_child_autofree(Node3D.new())
	_orchestrator = add_child_autofree(EntityOrchestrator.new())
	_orchestrator.set_event_bus(MockEventBus.new())
	_orchestrator.initialize(_world_root)
	_orchestrator.register_definition("oak_tree", "res://tests/mocks/MockHarvestable.gd", "")

func _spawn_player(peer_id: int, position: Vector3) -> Node3D:
	var player := Node3D.new()
	player.position = position
	player.add_to_group("player")
	player.set_meta("owner_peer_id", peer_id)
	add_child_autofree(player)
	return player

func test_resolve_for_player_returns_null_for_unknown_uuid() -> void:
	_spawn_player(1, Vector3.ZERO)
	var result := _orchestrator.resolve_for_player("does-not-exist", 1, 10.0)
	assert_null(result, "Unbekannte UUID muss null liefern.")

func test_resolve_for_player_returns_null_without_matching_player() -> void:
	var entity := _orchestrator.spawn_entity("oak_tree", Vector3.ZERO)
	var uuid: String = entity.get_meta("entity_uuid")
	# Kein Player mit peer_id=1 in der Gruppe "player" gespawnt.
	var result := _orchestrator.resolve_for_player(uuid, 1, 100.0)
	assert_null(result, "Fehlender Player-Node muss null liefern.")

func test_resolve_for_player_returns_null_outside_range() -> void:
	_spawn_player(1, Vector3(500, 0, 0))
	var entity := _orchestrator.spawn_entity("oak_tree", Vector3.ZERO)
	var uuid: String = entity.get_meta("entity_uuid")
	var result := _orchestrator.resolve_for_player(uuid, 1, 5.0)
	assert_null(result, "Entity außerhalb max_range muss null liefern.")

func test_resolve_for_player_returns_entity_within_range() -> void:
	_spawn_player(1, Vector3(1, 0, 0))
	var entity := _orchestrator.spawn_entity("oak_tree", Vector3.ZERO)
	var uuid: String = entity.get_meta("entity_uuid")
	var result := _orchestrator.resolve_for_player(uuid, 1, 5.0)
	assert_eq(result, entity, "Entity innerhalb max_range muss zurückgegeben werden.")

func test_resolve_for_player_matches_by_owner_peer_id_not_node_order() -> void:
	# Spieler 2 zuerst in der Gruppe, Spieler 1 danach — Auflösung darf sich
	# nicht auf Einfüge-/Iterationsreihenfolge verlassen, sondern muss über
	# das "owner_peer_id"-Meta matchen.
	_spawn_player(2, Vector3(500, 0, 0))
	_spawn_player(1, Vector3(1, 0, 0))
	var entity := _orchestrator.spawn_entity("oak_tree", Vector3.ZERO)
	var uuid: String = entity.get_meta("entity_uuid")
	var result := _orchestrator.resolve_for_player(uuid, 1, 5.0)
	assert_eq(result, entity, "Muss über peer_id=1 (nah) auflösen, nicht über peer_id=2 (fern).")

# ── actor_uuid (Bugfix 2026-09-26) ─────────────────────────

func test_actor_uuid_measures_range_from_actor_not_owner() -> void:
	# Exakte Log-Szenarien reproduziert: Besitzer 9.3m/7.4m entfernt (würde mit
	# max_range=4.5 ohne den Fix ablehnen), das "Pet" (hier: eine zweite
	# registrierte Entity als Stellvertreter, da PetComponent-Setup in einem
	# reinen Unit-Test zu viel Infrastruktur bräuchte) steht direkt am Ziel.
	_spawn_player(1, Vector3(9.3, 0, 0))
	var target := _orchestrator.spawn_entity("oak_tree", Vector3.ZERO)
	var target_uuid: String = target.get_meta("entity_uuid")
	var pet := _orchestrator.spawn_entity("oak_tree", Vector3(1.2, 0, 0))
	var pet_uuid: String = pet.get_meta("entity_uuid")

	var without_actor := _orchestrator.resolve_for_player(target_uuid, 1, 4.5)
	assert_null(without_actor, "Ohne actor_uuid muss weiterhin ab dem Besitzer gemessen werden (Bug reproduziert).")

	var with_actor := _orchestrator.resolve_for_player(target_uuid, 1, 4.5, pet_uuid)
	assert_eq(with_actor, target, "Mit actor_uuid=Pet muss die Reichweite ab dem Pet gemessen werden (Fix).")

func test_actor_uuid_still_rejects_if_actor_itself_out_of_range() -> void:
	_spawn_player(1, Vector3(1, 0, 0))
	var target := _orchestrator.spawn_entity("oak_tree", Vector3.ZERO)
	var target_uuid: String = target.get_meta("entity_uuid")
	var far_pet := _orchestrator.spawn_entity("oak_tree", Vector3(6, 0, 0))
	var far_pet_uuid: String = far_pet.get_meta("entity_uuid")

	var result := _orchestrator.resolve_for_player(target_uuid, 1, 4.5, far_pet_uuid)
	assert_null(result, "Der Fix hebt die Prüfung nicht auf — ein zu weit entferntes actor_uuid muss weiterhin ablehnen.")

func test_actor_uuid_falls_back_to_owner_when_unresolvable() -> void:
	# Unbekannte/bereits despawnte actor_uuid darf nicht crashen — fällt auf
	# die normale Besitzer-Prüfung zurück (mit Log-Warnung, siehe Kommentar).
	_spawn_player(1, Vector3(1, 0, 0))
	var target := _orchestrator.spawn_entity("oak_tree", Vector3.ZERO)
	var target_uuid: String = target.get_meta("entity_uuid")

	var result := _orchestrator.resolve_for_player(target_uuid, 1, 4.5, "does-not-exist")
	assert_eq(result, target, "Unauflösbare actor_uuid muss auf die Besitzer-Prüfung zurückfallen, nicht crashen.")

# ─────────────────────────────────────────────────────────────────────────────
# Pool-Park-Container — BUGFIX (2026-09-26, "Telemetrie meldet ständig verwaiste Nodes")
# ─────────────────────────────────────────────────────────────────────────────
## EntityPool.release() entparent gepoolte (inaktive) Entities bisher komplett — Godots
## Performance-Monitor zählt das als "verwaiste Node" (siehe TelemetryService). Fix: ein
## unsichtbarer Container als Kind von EntityOrchestrator selbst, gepoolte Entities werden
## dorthin reparented statt entparent. Diese Tests decken den vollen unload→spawn-Kreislauf
## über die echte EntityOrchestrator-API ab, nicht nur EntityPool isoliert (siehe test_entity_pool.gd).

func test_ready_creates_pool_container_as_own_child() -> void:
	var container := _orchestrator.get_node_or_null("EntityPoolContainer")
	assert_not_null(container, "_ready() muss einen 'EntityPoolContainer'-Kindnode anlegen")
	assert_true(container.get_parent() == _orchestrator,
		"Der Pool-Container muss Kind des EntityOrchestrator selbst sein")

## BUGFIX (2026-09-27, "Bäume/NPCs despawnen visuell nicht mehr, Interaktion hängt"):
## der Container war bis dahin ein einfaches `Node` (kein `visible`) — geparkte Entities
## blieben dadurch sichtbar UND weiter über Area3D/Gruppen interagierbar an ihrer alten
## Position stehen, obwohl sie laut EntityOrchestrator._entities schon längst despawnt
## waren. Diese zwei Assertions sind der eigentliche Regressionstest dafür.
func test_pool_container_is_invisible() -> void:
	var container := _orchestrator.get_node_or_null("EntityPoolContainer")
	assert_true(container is Node3D, "Pool-Container muss Node3D sein, sonst gibt es kein 'visible' zum Verstecken")
	assert_false(container.visible, "Pool-Container muss unsichtbar sein — sonst bleiben geparkte Bäume/NPCs sichtbar stehen")

func test_pool_container_disables_processing() -> void:
	var container := _orchestrator.get_node_or_null("EntityPoolContainer")
	assert_eq(container.process_mode, Node.PROCESS_MODE_DISABLED,
		"Pool-Container muss Processing (inkl. AI/Physics der geparkten Entities) deaktivieren")

func test_unloaded_entity_becomes_invisible_in_tree() -> void:
	var entity := _orchestrator.spawn_entity("oak_tree", Vector3.ZERO)
	var uuid: String = entity.get_meta("entity_uuid")

	_orchestrator.unload_entity(uuid)

	assert_false(entity.is_visible_in_tree(),
		"Geparkte Entity muss visuell verschwinden (is_visible_in_tree()), auch wenn ihr " +
		"eigenes .visible-Flag unverändert true bleibt — die Unsichtbarkeit kommt vom Container")

func test_respawned_entity_is_visible_again() -> void:
	var entity := _orchestrator.spawn_entity("oak_tree", Vector3.ZERO)
	var uuid: String = entity.get_meta("entity_uuid")
	_orchestrator.unload_entity(uuid)

	var respawned := _orchestrator.spawn_entity("oak_tree", Vector3(5, 0, 0))

	assert_true(respawned.is_visible_in_tree(),
		"Wiederverwendete Entity muss nach dem Zurück-Reparenten unter world_root wieder sichtbar sein")

func test_unload_entity_parks_entity_in_pool_container_not_orphaned() -> void:
	var entity := _orchestrator.spawn_entity("oak_tree", Vector3.ZERO)
	var uuid: String = entity.get_meta("entity_uuid")

	_orchestrator.unload_entity(uuid)

	assert_true(is_instance_valid(entity), "Entity muss nach unload_entity() (Pool-Release) noch leben")
	assert_not_null(entity.get_parent(),
		"BUGFIX: eine gepoolte Entity darf NIE ohne Parent sein — sonst zählt Godots " +
		"Performance-Monitor sie als verwaiste Node")
	assert_eq(entity.get_parent(), _orchestrator.get_node_or_null("EntityPoolContainer"),
		"Gepoolte Entity muss im EntityPoolContainer geparkt sein")

func test_respawn_after_unload_reuses_entity_removed_from_pool_container() -> void:
	var entity := _orchestrator.spawn_entity("oak_tree", Vector3.ZERO)
	var uuid: String = entity.get_meta("entity_uuid")
	_orchestrator.unload_entity(uuid)

	var respawned := _orchestrator.spawn_entity("oak_tree", Vector3(5, 0, 0))

	assert_eq(respawned, entity, "Pool-Hit muss dieselbe (wiederverwendete) Instanz liefern")
	assert_eq(respawned.get_parent(), _world_root,
		"Wiederverwendete Entity muss aus dem Pool-Container entfernt und im World-Root " +
		"neu geparkt sein — sonst schlägt add_child() mit 'already has a parent' fehl")

func test_on_world_unloaded_frees_parked_pool_entities() -> void:
	var entity := _orchestrator.spawn_entity("oak_tree", Vector3.ZERO)
	var uuid: String = entity.get_meta("entity_uuid")
	_orchestrator.unload_entity(uuid)
	assert_true(is_instance_valid(entity))

	_orchestrator.on_world_unloaded()
	await get_tree().process_frame  # queue_free() braucht einen Frame

	assert_false(is_instance_valid(entity),
		"World-Unload muss auch im Pool geparkte Entities tatsächlich freigeben")
