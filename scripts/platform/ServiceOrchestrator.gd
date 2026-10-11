extends Node

## ServiceOrchestrator — Dünne Lifecycle-Shell. Nichts mehr.
##
## Verwaltet nur noch:
##   - App-Boot in _ready()
##   - Character-Boot/Teardown auf Session-Request
##   - World-Boot wenn WorldScopeInitializer signalisiert
##   - Shutdown-Handling
##
## Alle Boot-Logik lebt in BootPipeline.
## Alle Scope-Daten leben in AppScope / CharacterScope / WorldScope.
## Keine _inject_*-Methoden. Keine Cross-Registry-Handshakes. Kein God Object.

const LOG_CAT := "Orchestrator"

var _pipeline: BootPipeline = BootPipeline.new()
var _app_scope: AppScope    = null

## BUG-1-Fix ("UI dupliziert sich manchmal"): hält die aktuell aktive
## HUDManager-Instanz fest. _wire_hud() läuft bei JEDEM Session-Boot (initial
## UND beim Reload-Pfad über _on_scene_reload_requested, z.B. Charakterwechsel
## / "Laden" im Pause-Menü) — siehe dortiger Kommentar. HUDManager ist kein
## DI-Service in einer Registry, also erfasst ihn teardown_character()/
## teardown_world() nie. Diese Referenz erlaubt es, die alte Instanz vor dem
## nächsten boot() explizit abzuräumen.
var _hud_manager: HUDManager = null

## BUG-23 Root-Cause-Fix: true sobald boot_app() erfolgreich durchgelaufen ist.
## Solange false, werden eingehende session_requested-Signale gepuffert statt
## verarbeitet — vorher gingen sie komplett verloren, wenn der Request
## (z.B. "Neues Spiel"-Klick) ankam bevor boot_app() fertig war, weil der
## Connect für session_requested erst NACH boot_app() passierte.
var _boot_complete: bool = false
var _pending_session_request: String = ""

func _ready() -> void:
	# BUG-23 Diagnose: erste Zeile in _ready(), damit ein künftiger Log-Capture
	# sofort zeigt ob/wann dieser Autoload überhaupt zu laufen beginnt, relativ
	# zum MainMenu-Boot.
	AppLogger.log_info("_ready() gestartet.", LOG_CAT)
	_app_scope = AppScope.new(ServiceRegistry.new())
	# Round 109 (TODO Punkt 1): IEventBus in die App-Registry, VOR boot_app() —
	# IAppContext (für MainMenuController, existiert vor jedem Session-Boot)
	# braucht das schon, sobald MenuScopeInitializer signalisiert.
	_app_scope.register_event_bus(EventBusAdapter.new())

	# Beide Listener JETZT verdrahten — VOR boot_app(). Das ist der eigentliche
	# BUG-23-Fix: egal wie lange boot_app() braucht oder wie früh die Main-Szene
	# (MainMenu.tscn) nachzieht, ein 'Neues Spiel'-Klick oder ein
	# MenuScopeInitializer-Node kann jetzt nie mehr verloren gehen, weil der
	# Connect zu spät kam. session_requested wird gepuffert (s.u.), bis
	# boot_app() durch ist.
	EventBus.session.session_requested.connect(_on_session_requested)
	EventBus.ui.scene_reload_requested.connect(_on_scene_reload_requested)
	# ADR-029 Phase 1 (Round 62): der frühere direkte joined_as_client-Connect
	# hier ("_on_client_connected()", Auto-Boot mit synthetischer
	# "client_%d"-ID) ist entfernt. Der Client wählt jetzt in
	# MainMenuController (JOIN_CHARACTER_SELECT) selbst einen Charakter und
	# durchläuft den Join-Handshake, BEVOR überhaupt session_requested
	# emittiert wird — siehe MainMenuController-Klassenkommentar "Flow Join".
	# Ein Auto-Boot direkt auf joined_as_client hätte diesen Flow strukturell
	# unmöglich gemacht: er hätte bereits gebootet, während der Spieler noch
	# gar keinen Charakter gewählt hatte.
	_watch_for_menu_initializer()

	var result := _pipeline.boot_app(_app_scope, self)
	if not result.ok:
		# Vorher verpuffte dieser Fehler unsichtbar: der einzige Listener auf
		# boot_failed saß in Main.tscn, das nie geladen wird (run/main_scene
		# ist MainMenu.tscn). Jetzt zusätzlich laut geloggt, damit ein
		# Boot-Fehler nie wieder wie ein stilles Hängenbleiben aussieht.
		AppLogger.log_error(
			"App-Boot fehlgeschlagen — Phase '%s': %s" % [result.failed_phase, result.reason],
			LOG_CAT
		)
		EventBus.system.boot_failed.emit(result.failed_phase, result.reason)
		return

	_boot_complete = true
	EventBus.system.state_changed.connect(_on_state_changed)

	if not _pending_session_request.is_empty():
		var pending_id := _pending_session_request
		_pending_session_request = ""
		AppLogger.log_info("Gepufferten Session-Request nachgeholt: '%s'." % pending_id, LOG_CAT)
		_on_session_requested(pending_id)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		_pipeline.teardown_all(_app_scope)

# ─────────────────────────────────────────────
# Character-Scope
# ─────────────────────────────────────────────

func _on_session_requested(player_id: String) -> void:
	if not _boot_complete:
		# App-Boot noch nicht fertig (z.B. Request kam extrem früh rein) —
		# puffern statt verlieren. Wird in _ready() nachgeholt sobald
		# boot_app() erfolgreich durchgelaufen ist.
		AppLogger.log_warn(
			"Session-Request '%s' vor Boot-Abschluss — wird gepuffert." % player_id, LOG_CAT
		)
		_pending_session_request = player_id
		return
	_ensure_default_role_for_tier(player_id)
	var char_scope := _app_scope.create_character_scope(player_id, self)
	var result     := _pipeline.boot_character(char_scope, self)
	if not result.ok:
		EventBus.system.boot_failed.emit(result.failed_phase, result.reason)
		return
	# WorldScope wird getriggert sobald WorldScopeInitializer in World.tscn bereit ist.
	# CharacterScope.world_scope_ready → _on_world_scope_ready
	char_scope.world_scope_ready.connect(_on_world_scope_ready)
	_watch_for_world_initializer()
	_wire_hud(char_scope)
	EventBus.session.emit_session_ready()

## ADR-031 "Rollenzuweisung nach Tier" — die bisher fehlende Verdrahtung von
## PermissionService.ensure_default_role() an den Session-Boot (siehe dortiger
## Klassenkommentar und ADR-031 "Bewusst NICHT Teil dieser Runde", Round 80).
##
## Läuft VOR create_character_scope(), weil sie kein CharacterScope braucht —
## PermissionService/SessionManager sind beide App-Scope (global, ADR-009) und
## damit spätestens seit boot_app() (Phase 4) verfügbar, sobald _boot_complete
## true ist.
##
## ensure_default_role() ist idempotent (überschreibt nie eine bereits gesetzte
## Rolle) — ein wiederholter Aufruf bei jedem Session-Boot (z.B. auch beim
## Reload-Pfad in _on_scene_reload_requested()) ist damit gefahrlos.
func _ensure_default_role_for_tier(player_id: String) -> void:
	var permission_service := _app_scope.get_service(ServiceKeys.PERMISSION_SERVICE) as PermissionService
	if not is_instance_valid(permission_service):
		AppLogger.log_warn(
			"PermissionService nicht verfügbar — Tier-Default-Rolle für '%s' übersprungen." % player_id,
			LOG_CAT
		)
		return
	var session_manager := _app_scope.get_service(ServiceKeys.SESSION_MANAGER) as SessionManager
	if not is_instance_valid(session_manager):
		AppLogger.log_warn(
			"SessionManager nicht verfügbar — Tier-Default-Rolle für '%s' übersprungen." % player_id,
			LOG_CAT
		)
		return

	var is_dedicated := session_manager.is_dedicated_server()
	if not _should_get_default_admin(session_manager.is_server(), is_dedicated):
		return  # Tier 2 Client / Tier 3: kein Auto-Eintrag, Fallback bleibt PermissionService.DEFAULT_ROLE_ID ("player").

	if permission_service.ensure_default_role(player_id, "admin"):
		var tier_label := "Tier 1 (Solo)" if session_manager.is_solo() else "Tier 2 (Host)"
		AppLogger.log_info(
			"'%s' automatisch als 'admin' eingestuft (%s, ADR-031)." % [player_id, tier_label],
			LOG_CAT
		)

## Reine Entscheidungslogik, bewusst von den Service-Lookups getrennt — analog
## zu SessionManager._handle_join_handshake(), das aus demselben Grund von
## seiner @rpc-Hülle getrennt ist: eine Methode, die zusätzlich AppScope-
## Lookups macht, lässt sich nicht ohne eine vollständig gebootete App testen.
## Die Tier-Regel selbst (ADR-031 "Rollenzuweisung nach Tier") ist reine Logik
## und verdient einen eigenen, isolierten Test ohne diesen Umweg.
##
## Tier 1 (Solo) und Tier 2 (Host) → automatisch Admin. is_server() deckt
## beide Fälle ab (SessionManager.is_server() == "kein Peer ODER Host" — siehe
## dortiger Klassenkommentar), Tier 3 (Dedizierter Server) wird hier bewusst
## ausgenommen: kein automatisches Root-Konto ohne Passwort-Auth-Schicht
## (siehe ADR-031 "Bewusst NICHT Teil dieser Runde" / PermissionService-
## Klassenkommentar). Tier 2 Client (has_active_peer, nicht Autorität) fällt
## automatisch durch, da is_server() dort false ist.
static func _should_get_default_admin(is_server: bool, is_dedicated_server: bool) -> bool:
	return is_server and not is_dedicated_server

## Reagiert auf "Laden" im Pause-Menü (PauseMenuController._on_load() →
## EventBus.ui.scene_reload_requested). Vorher hat dieses Signal NUR
## SceneManager.change_scene() ausgelöst, mit der (falschen) Annahme im
## PauseMenuController-Kommentar "SaveSystem lädt automatisch letzten Stand".
## Zwei konkrete Bugs dadurch:
##   1. Grauer Bildschirm: _watch_for_world_initializer() ist CONNECT_ONE_SHOT
##      und wurde nur einmal beim initialen Session-Start (_on_session_requested)
##      verdrahtet. Beim Neuladen kam nie wieder ein WorldScopeInitializer-Callback
##      an, boot_world() lief also nie erneut → leerer Viewport ohne Terrain/Entities.
##   2. Veralteter Spielstand: WorldService (und SkillSystem/Inventory/Quest/
##      Equipment) lesen den Spielstand nur einmal in configure() während
##      boot_character() — ein reiner Szenen-Reload ändert daran nichts, die
##      bereits im Speicher laufende (ggf. neuere oder ältere) Session bleibt aktiv.
## Fix: Character- und World-Scope für denselben Spieler sauber abbauen
## (identisch zu teardown_all()'s Reihenfolge) und danach _on_session_requested()
## erneut durchlaufen — das liest den Spielstand frisch von Disk (SaveSystem.
## begin_session()), baut alle Character-Services neu auf und verdrahtet
## _watch_for_world_initializer() neu für die kommende World.tscn-Instanz.
func _on_scene_reload_requested() -> void:
	if not _app_scope.has_character_scope():
		AppLogger.log_warn("scene_reload_requested ohne aktive CharacterScope — ignoriert.", LOG_CAT)
		return

	var char_scope := _app_scope.get_character_scope()
	var player_id := char_scope.player_id
	AppLogger.log_info(
		"Lade-Anfrage: Character-Scope für '%s' wird neu gebootet (frischer Spielstand von Disk)." % player_id,
		LOG_CAT
	)

	if char_scope.has_world_scope():
		_pipeline.teardown_world(char_scope.get_world_scope())
	_pipeline.teardown_character(char_scope)
	_app_scope.destroy_character_scope()

	_on_session_requested(player_id)

func _on_state_changed(new_state: int) -> void:
	if new_state == GameEnums.State.MAIN_MENU and _app_scope.has_character_scope():
		var char_scope := _app_scope.get_character_scope()
		# BUGFIX (2026-09-16, "Charakter-Wechsel ohne Trennung"): MUSS vor
		# destroy_character_scope() laufen — WorldService.report_local_player_leaving()
		# braucht das noch lebende WorldService/NetworkBridge, um den anderen
		# Peers mitzuteilen, dass der eigene Spieler die Welt verlässt (siehe
		# dortiger Kommentar für die Symptome ohne diesen Fix: Spieler-Leichen
		# + "Node not found: .../MultiplayerSync"-Absturz beim nächsten
		# Charakter-Wechsel dieses Peers).
		if char_scope.has_world_scope():
			var world_svc := char_scope.get_world_scope().registry.get_service(ServiceKeys.WORLD) as WorldService
			if is_instance_valid(world_svc):
				world_svc.report_local_player_leaving()
		# BUGFIX (2026-09-25, "Tiere werden beim Charakterwechsel in die Luft
		# gelauncht" / BUG-B tatsächliche Root-Cause): dieser Pfad rief bislang
		# destroy_character_scope() DIREKT auf, ohne vorher die Teardown-Pipeline
		# laufen zu lassen — anders als _on_scene_reload_requested() (siehe dort).
		# CharacterScope.destroy()/WorldScope.destroy() räumen selbst NICHTS ab
		# (kein ServiceTeardownManager-Aufruf, siehe deren Klassenkommentare) —
		# jeder Character-Service (u.a. InteractionExecutor) blieb also mit
		# offener EventBus-Verbindung am Leben. IEventBus lebt im App-Scope und
		# ist über Charakterwechsel hinweg IDENTISCH — der nächste Charakter
		# bootet einen ZWEITEN InteractionExecutor, der sich auf denselben Bus
		# registriert. Ergebnis: jede Interaktion (u.a. "Tier fangen") lief
		# doppelt, zwei Pets exakt an derselben Position → CharacterBody3D-
		# Capsules überlappen komplett → Godots Physik-Auflösung schießt eines
		# auf absurde Koordinaten (>1e18 units). Der frühere Debounce-Fix in
		# InteractionExecutor.gd (_last_started) griff nicht, weil es zwei
		# GETRENNTE Instanzen mit je eigenem Dictionary waren — kein Bug in der
		# Dedupe-Logik selbst, sondern schlicht eine zweite lebende Instanz.
		# Fix: exakt dieselbe Teardown-Reihenfolge wie im Reload-Pfad, bevor der
		# Scope zerstört wird — das löst on_cleanup() auf jedem Service aus und
		# trennt alle Bus-Verbindungen des alten Charakters zuverlässig.
		if char_scope.has_world_scope():
			_pipeline.teardown_world(char_scope.get_world_scope())
		_pipeline.teardown_character(char_scope)
		_app_scope.destroy_character_scope()
		EventBus.session.emit_session_unloaded()

# ─────────────────────────────────────────────
# World-Scope — getriggert durch WorldScopeInitializer (Push, kein Pull)
# ─────────────────────────────────────────────

func _on_world_initializer_ready(world_root: Node3D) -> void:
	var char_scope := _app_scope.get_character_scope()
	if char_scope == null:
		AppLogger.log_warn("WorldScopeInitializer signalisierte aber kein CharacterScope aktiv.", LOG_CAT)
		return
	var world_scope := char_scope.create_world_scope(world_root, self)
	# await: boot_world() ist jetzt eine Coroutine (Welt-Generierung läuft im
	# Hintergrund-Thread, siehe WorldGenerationService). GameManager steht während
	# dieser Zeit im LOADING-State (siehe _on_session_ready) und wechselt erst bei
	# EventBus.world().world_scene_ready (emittiert am Ende von on_world_scene_ready())
	# zu PLAYING — dieser Aufruf hier blockiert die Engine also nicht.
	var result := await _pipeline.boot_world(world_scope, self)
	if not result.ok:
		EventBus.system.boot_failed.emit(result.failed_phase, result.reason)

func _on_world_scope_ready(_world_scope: WorldScope) -> void:
	pass  # Erweiterungspunkt für post-world-boot Wiring

# ─────────────────────────────────────────────
# HUD-Wiring (war: _inject_save_system_into_main_menu + HUDManager.boot)
# HUDScopeInitializer würde das analog übernehmen (offen). MainMenu-Seite ist seit
# BUG-21 (Round 24) über MenuScopeInitializer gelöst, siehe unten.
# Für HUD: bleibt hier als expliziter Aufruf bis der Initializer-Node gebaut ist.
# ─────────────────────────────────────────────

func _wire_hud(char_scope: CharacterScope) -> void:
	var reg     := char_scope.registry
	var factory := func() -> IUIContext: return UIContext.from_registry(reg)
	if get_tree():
		# BUGFIX (UI-Duplikat, siehe _hud_manager-Deklaration oben): vor jedem
		# boot() eine evtl. noch lebende alte Instanz abräumen. queue_free()
		# löst HUDManager._exit_tree() aus, das bereits korrekt aufräumt
		# (Bus-Disconnects, teardown() auf allen Controllern, HUD-Node
		# freigeben) — vorher wurde diese Instanz schlicht nie erreicht, weil
		# HUDManager außerhalb jeder Registry/Boot-Order lebt und so von
		# teardown_character()/teardown_world() nicht erfasst wird. Bislang
		# blieb die alte HUDManager+HUD-Node-Kombination beim Reload also
		# unter /root hängen, während boot() eine zweite daneben aufbaute —
		# zwei parallele HUD-Bäume mit je eigenen (u.a. Quest-)Controllern,
		# beide an dieselben Signale gebunden. Das erklärt neben der
		# sichtbaren UI-Verdopplung mutmaßlich auch Bug #3/#4 (doppelt
		# feuernde Quest-Trigger/-UI-Updates durch den zweiten Controller-Satz).
		if is_instance_valid(_hud_manager):
			AppLogger.log_warn(
				"_wire_hud: alte HUDManager-Instanz noch vorhanden — wird vor Neuaufbau abgeräumt.",
				LOG_CAT
			)
			_hud_manager.queue_free()
		_hud_manager = HUDManager.boot(get_tree(), factory)

# ─────────────────────────────────────────────
# MainMenu-Wiring — Push-Pattern via MenuScopeInitializer (BUG-21)
# App-Scope-DI: existiert vor jedem Session-Boot, kein IUIContext-Injektionspunkt
# (ADR-012) — seit Round 109 aber IAppContext (siehe register_event_bus() oben
# und inject_app_context() unten), schmaler als IUIContext (ISP: App-Scope hat
# kein Quest/Inventory/Skill/etc.). MainMenu.tscn wird bei jedem
# 'main_menu_requested' neu geladen, daher bleibt der node_added-Listener
# dauerhaft verbunden statt one-shot.
# ─────────────────────────────────────────────

func _watch_for_menu_initializer() -> void:
	get_tree().node_added.connect(_on_node_added_check_menu)
	# DEFENSIV (Round 113 Nachtrag): 100% reproduzierbarer Boot-Fehler
	# ("Kein IAppContext injiziert" bei jedem Button-Klick, nicht nur
	# transient) zeigte: node_added für die main_scene (MainMenu.tscn) kann
	# bereits VOR diesem Connect gefeuert haben, je nachdem wann genau die
	# Engine autoloads vs. main scene in die node_added-Reihenfolge einreiht.
	# call_deferred() auf der Emit-Seite (MenuScopeInitializer) allein löst
	# das nicht, wenn der Connect hier schon zu spät kommt. Fallback: aktuell
	# existierenden MenuScopeInitializer direkt suchen und anschließen, falls
	# er node_added bereits verpasst hat.
	_find_and_connect_existing_menu_initializer()

func _find_and_connect_existing_menu_initializer() -> void:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return
	for child in scene.get_children():
		if child is MenuScopeInitializer:
			_on_node_added_check_menu(child)
			return

func _on_node_added_check_menu(node: Node) -> void:
	if node is MenuScopeInitializer:
		if node.menu_ready.is_connected(_on_menu_initializer_ready):
			return
		node.menu_ready.connect(_on_menu_initializer_ready, CONNECT_ONE_SHOT)

func _on_menu_initializer_ready(menu_root: Control) -> void:
	if not menu_root is MainMenuController:
		return
	var menu := menu_root as MainMenuController
	# Round 109 (TODO Punkt 1): IAppContext statt direktem EventBus-AutoLoad-
	# Zugriff — löst denselben "kein Injektionspunkt vor Session-Boot"-Befund,
	# der MainMenuController zuvor auf der EventBus-Zugriffs-Whitelist hielt.
	menu.inject_app_context(AppContext.from_registry(_app_scope.registry))
	var save_system := _app_scope.get_service(ServiceKeys.SAVE_SYSTEM) as SaveSystem
	if is_instance_valid(save_system):
		menu.inject_save_system(save_system)
	else:
		AppLogger.log_error("SaveSystem nicht in App-Scope verfügbar — MainMenu-Injektion übersprungen.", LOG_CAT)
	# ADR-029 Phase 1 (Round 62): für send_join_handshake() im Join-Flow.
	var session_manager := _app_scope.get_service(ServiceKeys.SESSION_MANAGER) as SessionManager
	if is_instance_valid(session_manager):
		menu.inject_session_manager(session_manager)
	else:
		AppLogger.log_error("SessionManager nicht in App-Scope verfügbar — MainMenu-Injektion übersprungen.", LOG_CAT)

# ─────────────────────────────────────────────
# Debug API
# ─────────────────────────────────────────────

func get_service(service_name: String) -> Object:
	var svc := _app_scope.get_service(service_name)
	if svc == null and _app_scope.has_character_scope():
		svc = _app_scope.get_character_scope().get_service(service_name)
	return svc

## Alle aktuell registrierten Service-Namen (global + aktive Character-Session).
## Wird von SimpleTerminal ('services', 'status') genutzt.
func get_registered_names() -> Array[String]:
	var names := _app_scope.registry.get_all_names()
	if _app_scope.has_character_scope():
		names.append_array(_app_scope.get_character_scope().registry.get_all_names())
	return names

## Kurzinfo zu einem einzelnen Service. Wird von SimpleTerminal ('service', 'status') genutzt.
func get_service_info(service_name: String) -> Dictionary:
	var svc := get_service(service_name)
	if svc == null:
		return {"valid": false}
	return {"valid": is_instance_valid(svc), "class": svc.get_class()}

func is_session_active() -> bool:
	return _app_scope.has_character_scope()

## Lauscht einmalig auf WorldScopeInitializer im SceneTree.
## Wird direkt nach boot_character() aufgerufen — bevor World.tscn geladen ist.
## Sobald WorldScopeInitializer bereit ist, wird world_ready connected und
## node_added sofort disconnected. Kein dauerhaftes Polling.
func _watch_for_world_initializer() -> void:
	get_tree().node_added.connect(_on_node_added_check_world, CONNECT_ONE_SHOT)

func _on_node_added_check_world(node: Node) -> void:
	if node is WorldScopeInitializer:
		node.world_ready.connect(_on_world_initializer_ready, CONNECT_ONE_SHOT)
	else:
		# Noch nicht der richtige Node — weiterwarten
		get_tree().node_added.connect(_on_node_added_check_world, CONNECT_ONE_SHOT)
