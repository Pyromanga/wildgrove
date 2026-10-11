extends GutTest

## ADR-017 / AUDIT-05 (Mutation 1 + 3): SessionManager ist die einzige Stelle im
## Projekt, die "wer bin ich" (peer_id) aus multiplayer.get_unique_id() berechnet.
## Jede weitere Stelle muss SessionManager.get_local_peer_id() fragen (direkt
## oder über eine Fassade wie NetworkBridge, die selbst delegiert) statt die
## Berechnung ein zweites Mal hinzuschreiben.
##
## Analog zu test_event_bus_access_boundary.gd — dort für EventBus, hier für
## Identität. Ohne diesen Test verhindert nichts, dass morgen eine elfte
## get_local_peer_id()-Kopie entsteht (AUDIT-05, Abschnitt "Warum das immer
## wieder passiert").

const SCAN_ROOT := "res://scripts"

## Dateien, in denen multiplayer.get_unique_id() legitim direkt vorkommen darf:
##   - SessionManager.gd: die kanonische Quelle selbst.
##
## ADR-015 Phase 5: AnimalCatcher.gd stand hier bis Runde 6 auf der Liste, weil
## es owner_peer_id über animal.get_multiplayer().get_unique_id() geraten hat —
## eine Näherung, weil die Interaktion selbst keine Spieler-Identität trug.
## Seit Phase 4/5 bekommt catch_animal() player_id als echten Parameter
## (aus dem interacted-Signal). Der Aufruf existiert dort nicht mehr —
## Eintrag entfernt statt als toter Whitelist-Rest stehen zu lassen.
##
## ADR-025-Vorarbeit (2026-07): Player.gd stand hier ebenfalls, weil es die
## lokale unique_id gegen get_multiplayer_authority() verglich, um "ist das
## mein eigener Spieler" zu beantworten (Godot-idiomatischer Authority-Check).
## Dieser Vergleich ist jetzt durch _owner_peer_id != ctx.get_local_peer_id()
## ersetzt (siehe TODO "BLOCKER für ADR-025/026-Umsetzung") — Player.gd ruft
## multiplayer.get_unique_id() nirgends mehr direkt auf, Eintrag entfernt statt
## als toter Whitelist-Rest stehen zu lassen.
const ALLOWED_FILES := [
	"res://scripts/session/SessionManager.gd",
]

func test_no_raw_get_unique_id_outside_whitelist() -> void:
	var offenders: Array[String] = []
	_scan_dir(SCAN_ROOT, offenders)
	assert_eq(
		offenders.size(), 0,
		"Direkte multiplayer.get_unique_id()-Berechnung außerhalb der Whitelist "
		+ "gefunden — das ist die Mutation, die AUDIT-05 dokumentiert. "
		+ "SessionManager.get_local_peer_id() fragen statt neu zu berechnen:\n"
		+ "\n".join(offenders)
	)

func _scan_dir(path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full_path := path + "/" + entry
		if dir.current_is_dir():
			_scan_dir(full_path, offenders)
		elif entry.ends_with(".gd") and not (full_path in ALLOWED_FILES):
			_scan_file(full_path, offenders)
		entry = dir.get_next()
	dir.list_dir_end()

func _scan_file(path: String, offenders: Array[String]) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var regex := RegEx.new()
	regex.compile("multiplayer\\.get_unique_id\\(\\)")
	var line_no := 0
	while not f.eof_reached():
		var line := f.get_line()
		line_no += 1
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var code := line.split("#")[0]
		if regex.search(code) != null:
			offenders.append("%s:%d" % [path, line_no])
