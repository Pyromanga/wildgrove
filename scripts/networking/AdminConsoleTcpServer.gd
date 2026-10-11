extends Node
class_name AdminConsoleTcpServer

## AdminConsoleTcpServer — ADR-040: TCP-Frontend für AdminConsole.
##
## Bindet AUSSCHLIESSLICH an 127.0.0.1 — von außerhalb der Maschine technisch
## nicht erreichbar. Der einzige vorgesehene Zugriffsweg ist ein
## SSH-Port-Forward (`ssh -L <port>:localhost:<port> server`), das SSH bereits
## vollständig authentifiziert/verschlüsselt hat, bevor hier überhaupt ein
## Byte ankommt (siehe ADR-040 "Problem").
##
## BEWUSST OHNE THREAD: TCPServer.is_connection_available()/take_connection()
## und StreamPeerTCP.poll()/get_available_bytes() sind nicht-blockierend —
## anders als OS.read_string_from_stdin() (siehe AdminConsoleStdinReader) gibt
## es hier keinen Grund, den Main-Thread zu verlassen. Polling in _process()
## ist einfacher und risikofrei gegenüber den Thread-Cross-Access-Fallstricken,
## die AdminConsole am Ende sowieso anfassen würde (SessionManager/
## PermissionService — siehe AdminConsoleStdinReader-Klassenkommentar).
##
## MEHRERE GLEICHZEITIGE VERBINDUNGEN: jede akzeptierte Verbindung bekommt
## über AdminConsole.new_session() ihre eigene AdminConsoleSession — ein
## zweiter Admin landet nicht im Login-Zustand des ersten (siehe
## AdminConsole-Klassenkommentar).
##
## PROTOKOLL: naives zeilenbasiertes UTF-8-Textprotokoll (kein Framing über
## Längenpräfix o.ä.) — ausreichend für ein Handtipp-Terminal via SSH-Tunnel/
## nc/telnet. Kein Passwort-Masking (kein Verzicht auf Passwort-Echo beim
## Tippen) — bewusst nicht Teil dieser Runde, siehe ADR-040
## "Bewusst NICHT Teil dieser Runde".

const LOG_CAT := "AdminConsoleTcpServer"
const DEFAULT_PORT := 7778
const BIND_ADDRESS := "127.0.0.1"

class _Connection:
	extends RefCounted
	var peer: StreamPeerTCP
	var session: AdminConsole.AdminConsoleSession
	var buffer: String = ""

var _console: AdminConsole
var _server: TCPServer
var _connections: Array[_Connection] = []

## Startet den Listener. Gibt false zurück, wenn der Port nicht gebunden
## werden konnte (z.B. bereits belegt) — Aufrufer entscheidet, ob das ein
## Fail-Fast (Tier-3-Boot) oder nur eine Warnung wert ist.
func start(console: AdminConsole, port: int = DEFAULT_PORT) -> bool:
	_console = console
	_server = TCPServer.new()
	var err := _server.listen(port, BIND_ADDRESS)
	if err != OK:
		AppLogger.log_error(
			"Admin-TCP-Listener konnte %s:%d nicht binden (Error %d)." % [BIND_ADDRESS, port, err],
			LOG_CAT
		)
		_server = null
		return false
	set_process(true)
	AppLogger.log_info(
		"Admin-TCP-Listener aktiv auf %s:%d (nur via SSH-Port-Forward erreichbar)." % [BIND_ADDRESS, port],
		LOG_CAT
	)
	return true

func stop() -> void:
	set_process(false)
	for conn in _connections:
		conn.peer.disconnect_from_host()
	_connections.clear()
	if is_instance_valid(_server):
		_server.stop()
	_server = null

func connection_count() -> int:
	return _connections.size()

func _process(_delta: float) -> void:
	if not is_instance_valid(_server):
		return

	while _server.is_connection_available():
		_accept_new_connection()

	var i := _connections.size() - 1
	while i >= 0:
		if not _pump_connection(_connections[i]):
			_connections.remove_at(i)
		i -= 1

func _accept_new_connection() -> void:
	var peer: StreamPeerTCP = _server.take_connection()
	if not is_instance_valid(peer):
		return
	var conn := _Connection.new()
	conn.peer = peer
	conn.session = _console.new_session()
	_connections.append(conn)
	AppLogger.log_info("Neue Admin-TCP-Verbindung (aktiv: %d)." % _connections.size(), LOG_CAT)
	_send(conn, "WildGrove Admin-Konsole. 'login <username> <passwort>' eingeben.")

## Gibt false zurück, wenn die Verbindung entfernt werden soll (getrennt).
func _pump_connection(conn: _Connection) -> bool:
	conn.peer.poll()
	if conn.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false

	var available := conn.peer.get_available_bytes()
	if available <= 0:
		return true

	conn.buffer += conn.peer.get_utf8_string(available)
	# Zeilenweise verarbeiten — ein TCP-Chunk kann mehrere oder auch nur
	# einen Teil einer Zeile enthalten (kein Zeilen-Framing im Transport).
	while true:
		var newline_pos := conn.buffer.find("\n")
		if newline_pos == -1:
			break
		var line := conn.buffer.substr(0, newline_pos).strip_edges()
		conn.buffer = conn.buffer.substr(newline_pos + 1)
		var response := conn.session.handle_line(line)
		if not response.is_empty():
			_send(conn, response)
	return true

func _send(conn: _Connection, text: String) -> void:
	conn.peer.put_utf8_string(text + "\n")
