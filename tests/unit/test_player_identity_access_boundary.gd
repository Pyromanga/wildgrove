extends GutTest

## ADR-029 Plan-Schritt 4 (Round 63): SessionManager ist die einzige Stelle im
## Projekt, die peer_id ↔ player_id (player_uuid) verwaltet (_peer_slots).
## Jede weitere Stelle muss SessionManager.get_player_id_for_peer()/
## get_local_player_id()/get_peer_id_for_player() fragen (direkt oder über
## eine Fassade wie NetworkBridge, die selbst delegiert) statt sich selbst
## Zugriff auf die interne Registry zu verschaffen oder die Zuordnung anders
## nachzubauen.
##
## Analog zu test_identity_access_boundary.gd — dort für die peer_id-Berechnung
## selbst (multiplayer.get_unique_id()), hier für die player_id-Zuordnung
## (_peer_slots). Ohne diesen Test verhindert nichts, dass morgen eine zweite
## Stelle direkt in _peer_slots liest oder schreibt statt den kanonischen
## Getter zu fragen (AUDIT-05, Abschnitt "Warum das immer wieder passiert" —
## dasselbe Muster, nur für eine zweite Registry).

const SCAN_ROOT := "res://scripts"

## Dateien, in denen ._peer_slots legitim direkt vorkommen darf:
##   - SessionManager.gd: die kanonische Registry selbst.
const ALLOWED_FILES := [
	"res://scripts/session/SessionManager.gd",
]

func test_no_raw_peer_slots_access_outside_whitelist() -> void:
	var offenders: Array[String] = []
	_scan_dir(SCAN_ROOT, offenders)
	assert_eq(
		offenders.size(), 0,
		"Direkter Zugriff auf SessionManager._peer_slots außerhalb der Whitelist "
		+ "gefunden — dieselbe Art Mutation wie AUDIT-05, nur für die player_id-"
		+ "Registry statt die peer_id-Berechnung. SessionManager.get_player_id_for_peer()/"
		+ "get_local_player_id()/get_peer_id_for_player() fragen statt selbst zuzugreifen:\n"
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
	regex.compile("\\._peer_slots\\b")
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
