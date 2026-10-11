extends Node
class_name AdminConsoleStdinReader

## AdminConsoleStdinReader — ADR-040: stdin-Frontend für AdminConsole.
##
## Gedacht für direkten Terminalzugriff (z.B. `ssh server` → `tmux attach`),
## als Alternative/Ergänzung zum TCP-Frontend (AdminConsoleTcpServer).
##
## WARUM EIN THREAD: OS.read_string_from_stdin() blockiert, bis eine Zeile
## ankommt — ein Aufruf davon direkt in _process() würde den gesamten
## Server (Physik, Netzwerk, alle anderen Spieler) einfrieren, solange
## niemand tippt. Analog zu Logger.gd (_file_writer_loop) und
## WorldGenerationService.gd (_thread_generate) läuft das Blockieren deshalb
## in einem eigenen Thread.
##
## WARUM call_deferred() STATT DIREKTEM AUFRUF IM THREAD: AdminConsole.
## handle_line() fasst am Ende SessionManager (multiplayer.multiplayer_peer.
## disconnect_peer()) und PermissionService an — beides Godot-Objekte, deren
## Thread-Sicherheit nicht zugesichert ist. call_deferred() ist hier der von
## Godot vorgesehene Marshalling-Mechanismus, um eine Methode garantiert auf
## dem Main-Thread auszuführen (dasselbe Muster wie Logger.gd/
## WorldGenerationService.gd) — kein Workaround, sondern der dokumentierte
## Weg dafür. Der Worker-Thread selbst fasst NUR OS.read_string_from_stdin()
## an und übergibt das Ergebnis (ein reiner String-Value, kein Shared-State)
## per call_deferred() weiter.
##
## BEKANNTE EINSCHRÄNKUNG — bewusst nicht gelöst, siehe TODO-offene-probleme.md:
## OS.read_string_from_stdin() hat KEINEN Interrupt-Mechanismus. stop() setzt
## nur ein Flag (_running), das erst NACH der nächsten empfangenen Zeile
## (oder EOF) geprüft wird — der Thread kann nicht von außen sofort beendet
## werden, solange er gerade blockiert auf Eingabe wartet. Deshalb bewusst
## KEIN wait_to_finish() beim Server-Shutdown hier: das würde den
## Shutdown-Pfad aufhängen, wenn gerade niemand tippt. Der Thread wird beim
## Prozessende vom Betriebssystem eingesammelt — für einen dedizierten
## Server, dessen Lebenszyklus ohnehin am OS-Prozess hängt (systemd/tmux),
## bewusst akzeptiert statt hier einen Interrupt-Mechanismus nachzubauen,
## den Godot nicht anbietet. UNGEPRÜFT: ob Godots Thread-Destruktor beim
## harten Prozess-Exit dabei eine Fehlermeldung ausgibt (kein Zugriff auf
## eine echte Godot-Runtime zur Verifikation in dieser Sandbox) — siehe TODO.

const LOG_CAT := "AdminConsoleStdinReader"

var _console: AdminConsole
var _session: AdminConsole.AdminConsoleSession
var _thread: Thread = null
var _running_mutex := Mutex.new()
var _running: bool = false

func start(console: AdminConsole) -> void:
	_console = console
	_session = console.new_session()
	_running_mutex.lock()
	_running = true
	_running_mutex.unlock()
	_thread = Thread.new()
	_thread.start(_read_loop)
	AppLogger.log_info("Admin-stdin-Konsole aktiv. 'login <username> <passwort>' eingeben.", LOG_CAT)

## Siehe Klassenkommentar "Bekannte Einschränkung" — beendet den Thread NICHT
## sofort, nur beim nächsten Zeilenempfang/EOF.
func stop() -> void:
	_running_mutex.lock()
	_running = false
	_running_mutex.unlock()

func _is_running() -> bool:
	_running_mutex.lock()
	var result := _running
	_running_mutex.unlock()
	return result

## Läuft NICHT auf dem Main-Thread. Fasst außer OS.read_string_from_stdin()
## nichts an, das Thread-Sicherheit bräuchte — siehe Klassenkommentar.
func _read_loop() -> void:
	while _is_running():
		var line := OS.read_string_from_stdin()
		if line.is_empty():
			# EOF — stdin geschlossen (z.B. kein echtes TTY unter systemd
			# ohne PTY-Zuweisung). Thread sauber beenden statt Busy-Loop.
			AppLogger.log_info("stdin geschlossen (EOF) — Admin-stdin-Thread beendet sich.", LOG_CAT)
			break
		call_deferred("_handle_line_on_main_thread", line)

## Läuft auf dem Main-Thread (via call_deferred aus _read_loop()) — hier
## dürfen SessionManager/PermissionService gefahrlos angefasst werden.
func _handle_line_on_main_thread(line: String) -> void:
	if not is_instance_valid(_session):
		return
	var response := _session.handle_line(line)
	if not response.is_empty():
		print(response)
