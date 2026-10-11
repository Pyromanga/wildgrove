extends Node
# justified: Autoload, weil es vor jedem Boot-Signal (services_initialized) verbunden
# sein muss und über die App-Laufzeit hinweg lebt — exakt derselbe Grund wie bei
# IT03Harness/SimpleTerminal. Anders als IT03Harness ist das hier Teil des
# produktiven Codepfads (Tier 3), kein CI-only-Werkzeug — wird NICHT vor dem
# Export entfernt.

## DedicatedServerBootstrap — ADR-010 Round 55: Produktions-Einstiegspunkt für
## Tier 3 (Dedizierter Server).
##
## Aktivierung NUR über User-Cmdline-Argumente (OS.get_cmdline_user_args(),
## alles nach "--" — identisches Muster wie IT03Harness):
##   --dedicated-server        Aktiviert den Tier-3-Boot. Ohne dieses Argument
##                              ist _ready() ein No-Op (Kosten: ein Array-Scan) —
##                              das normale Spiel (Solo/Tier-2-Host/Client) ist
##                              null-verändert, exakt wie beim MainMenu-Flow.
##   --dedicated-port=<int>    Optional, Default SessionManager.DEFAULT_PORT (7777).
##   --admin-port=<int>        Optional, Default AdminConsoleTcpServer.DEFAULT_PORT
##                              (7778). Bindet ausschließlich an 127.0.0.1 —
##                              siehe ADR-040.
##
## ADR-040 (Round 86): sobald der Tier-3-Host erfolgreich läuft, startet
## dieser Node zusätzlich die Admin-Zugänge — AdminConsoleTcpServer
## (127.0.0.1-only, erreichbar via SSH-Port-Forward) UND
## AdminConsoleStdinReader (direkter Terminalzugriff, z.B. via
## `ssh server` + `tmux attach`). Beide teilen sich dieselbe AdminConsole-
## Kernlogik (und damit dasselbe AdminAccountStore/PermissionService/
## SessionManager), aber jede Verbindung bekommt ihre eigene Login-Session
## (siehe AdminConsole-Klassenkommentar). Fehlschlag des TCP-Listeners
## (z.B. Port belegt) ist bewusst KEIN Fail-Fast wie bei create_server() —
## der stdin-Zugang bleibt dann trotzdem verfügbar, ein Admin-Zugang, der
## nicht bootet, darf nicht den ganzen Weltserver mit runterreißen.
##
## Verhalten sobald aktiviert:
##   1. Wartet auf EventBus.system.services_initialized (App-Boot fertig).
##   2. SessionManager.enable_dedicated_server_mode() — MUSS vor create_server()
##      passieren, WorldService liest das Flag beim Welt-Boot.
##   3. SessionManager.create_server(port) direkt (nicht über
##      EventBus.networking.emit_host_game_requested()) — bewusst, weil dieser
##      Pfad für UI-Klicks gedacht ist und Fehlschläge dort stumm bleiben
##      (SessionManager._on_host_game_requested() prüft den bool-Rückgabewert
##      nicht). Ein dedizierter Server ohne UI braucht ein hartes Fail-Fast
##      statt eines für einen Menschen gedachten Retry-Screens.
##   4. Bei Erfolg: EventBus.session.emit_session_requested(
##      SessionManager.DEDICATED_SERVER_WORLD_ID) — bootet die geteilte
##      Welt-Session (kein lokales Player-Entity, siehe WorldSpawner
##      Round 55/ADR-010 "Update (Round 55)").
##   5. Bei Fehlschlag (Port belegt o.ä.): harter Log + get_tree().quit(1) —
##      kein hängender Prozess, kein stiller Fehlzustand (Deployment-
##      Automatisierung/systemd braucht einen eindeutigen Exit-Code).
##
## Kein Rendering-Overhead: dieser Node selbst erzeugt keine Szene, kein UI.
## Ob der Prozess tatsächlich ohne Fenster läuft, entscheidet der Export-Preset
## ("Linux Dedicated Server", dedicated_server=true, siehe export_presets.cfg)
## bzw. der `--headless`-Engine-Start-Flag — nicht dieses Skript.

const LOG_CAT := "DedicatedServerBootstrap"

var _active: bool = false
var _port: int = 0  # 0 = SessionManager.DEFAULT_PORT verwenden
var _admin_port: int = 0  # 0 = AdminConsoleTcpServer.DEFAULT_PORT verwenden

var _admin_account_store: AdminAccountStore
var _admin_console: AdminConsole
var _admin_tcp_server: AdminConsoleTcpServer
var _admin_stdin_reader: AdminConsoleStdinReader

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--dedicated-server":
			_active = true
		elif a.begins_with("--dedicated-port="):
			_port = int(a.substr(len("--dedicated-port=")))
		elif a.begins_with("--admin-port="):
			_admin_port = int(a.substr(len("--admin-port=")))

	if not _active:
		return  # Normales Spiel — kein Verhalten geändert.

	AppLogger.log_info("Tier-3-Boot angefordert (--dedicated-server).", LOG_CAT)
	if EventBus.system.services_initialized.is_connected(_on_services_ready):
		return
	EventBus.system.services_initialized.connect(_on_services_ready, CONNECT_ONE_SHOT)

func _on_services_ready() -> void:
	var orch := get_node_or_null("/root/ServiceOrchestrator")
	var sm := orch.get_service(ServiceKeys.SESSION_MANAGER) as SessionManager if orch != null else null
	if not is_instance_valid(sm):
		_fail("SessionManager nicht verfügbar nach App-Boot — Tier-3-Start abgebrochen.")
		return

	# Muss vor create_server() gesetzt sein — WorldService liest das Flag
	# einmalig beim Welt-Boot (Phase W2 in BootPipeline.boot_world()).
	sm.enable_dedicated_server_mode()

	var port := _port if _port > 0 else SessionManager.DEFAULT_PORT
	AppLogger.log_info("Starte Tier-3-Host auf Port %d." % port, LOG_CAT)
	if not sm.create_server(port):
		_fail("create_server(%d) fehlgeschlagen — Port belegt oder Netzwerkfehler." % port)
		return

	AppLogger.log_info(
		"Tier 3 aktiv. Welt-Session wird unter reservierter ID '%s' gebootet (kein lokales Player-Entity)." % SessionManager.DEDICATED_SERVER_WORLD_ID,
		LOG_CAT
	)
	EventBus.session.emit_session_requested(SessionManager.DEDICATED_SERVER_WORLD_ID)

	_start_admin_console(orch, sm)

func _fail(reason: String) -> void:
	AppLogger.log_error("Tier-3-Boot fehlgeschlagen: %s" % reason, LOG_CAT)
	get_tree().quit(1)

## ADR-040: startet die beiden Admin-Zugänge, sobald der Tier-3-Host selbst
## erfolgreich läuft. Absichtlich NACH create_server() statt davor — ein
## Admin-Zugang ohne laufenden Weltserver dahinter wäre nutzlos und würde nur
## verwirrende Zwischenzustände erlauben.
func _start_admin_console(orch: Node, sm: SessionManager) -> void:
	var permissions := orch.get_service(ServiceKeys.PERMISSION_SERVICE) as PermissionService

	_admin_account_store = AdminAccountStore.new()
	_admin_account_store.load()
	_admin_account_store.ensure_bootstrap_account()  # No-op falls schon Konten existieren

	_admin_console = AdminConsole.new(_admin_account_store, permissions, sm)

	_admin_tcp_server = AdminConsoleTcpServer.new()
	add_child(_admin_tcp_server)
	var admin_port := _admin_port if _admin_port > 0 else AdminConsoleTcpServer.DEFAULT_PORT
	if not _admin_tcp_server.start(_admin_console, admin_port):
		# Bewusst KEIN _fail()/quit() — ein nicht bootender Admin-TCP-Listener
		# darf den Weltserver nicht mit runterreißen, siehe Klassenkommentar
		# oben. stdin bleibt als Fallback-Zugang verfügbar.
		AppLogger.log_warn(
			"Admin-TCP-Listener nicht gestartet — Admin-Zugriff nur noch über stdin (tmux/screen) möglich.",
			LOG_CAT
		)

	_admin_stdin_reader = AdminConsoleStdinReader.new()
	add_child(_admin_stdin_reader)
	_admin_stdin_reader.start(_admin_console)

## Best-effort-Cleanup beim Prozessende — siehe AdminConsoleStdinReader
## "Bekannte Einschränkung": stop() signalisiert dem stdin-Thread nur, sich
## zu beenden, wartet aber bewusst NICHT auf ihn (wait_to_finish() würde
## hängen, solange OS.read_string_from_stdin() blockiert). Der TCP-Server
## lässt sich dagegen sauber und sofort stoppen (kein Thread).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH or what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_admin_tcp_server):
			_admin_tcp_server.stop()
		if is_instance_valid(_admin_stdin_reader):
			_admin_stdin_reader.stop()
