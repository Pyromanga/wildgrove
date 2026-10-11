extends GutTest

## ADR-015 / MIGRATION-015 Phase 6 — Regressions-Schutz.
##
## Verhindert, dass get_nodes_in_group("player")[0] ("Index 0 = ich selbst")
## nach der Migration an einer elften Stelle wieder auftaucht — genau das
## Muster, das _find_local_player_visuals() schon einmal vorgemacht hat
## (korrekter Name, falsche Implementierung). Neuer Code soll stattdessen
## IEntityContext/IUIContext.get_local_player() nutzen.
##
## Whitelist: Dateien mit einer bewusst anderen Semantik als "lokaler Spieler"
## ("nächster Spieler" für Gegner-KI/Tier-Flucht, siehe MIGRATION-015 Phase 2)
## oder die bereits per Authority-Match korrekt implementiert sind.

const SCAN_ROOT := "res://scripts"

const ALLOWED_FILES := [
	# Reference-Implementierung des Authority-Match-Patterns (ADR-015) selbst.
	"res://scripts/entities/animals/pets/PetComponent.gd",
	# "Nächster Spieler" (räumliche Distanz) statt "lokaler Spieler" — siehe
	# MIGRATION-015 Phase 2, bewusst nicht Teil dieser Migration.
	"res://scripts/entities/combat/EnemyNPC.gd",
	"res://scripts/entities/animals/AnimalBase.gd",
	# IEntityContext/IUIContext selbst implementieren get_local_player() intern
	# über get_nodes_in_group("player") — das ist die eine erlaubte Quelle.
	"res://scripts/platform/interfaces/IEntityContext.gd",
	"res://scripts/platform/interfaces/IUIContext.gd",
]

func test_no_group_index_zero_player_access_outside_whitelist() -> void:
	var offenders: Array[String] = []
	_scan_dir(SCAN_ROOT, offenders)
	assert_eq(
		offenders.size(), 0,
		"get_nodes_in_group(\"player\")[0]-artiger Zugriff außerhalb der Whitelist gefunden "
		+ "(ADR-015: ctx.get_local_player() nutzen):\n" + "\n".join(offenders)
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
	# Matches "get_nodes_in_group(...)" gefolgt (auf derselben oder folgenden
	# Zeile ist zu teuer für eine Line-Regex) von "[0]" auf derselben Zeile —
	# deckt die zehn aus ADR-015 bekannten Fundstellen ab, die alle in einer
	# Zeile standen. Zusätzlich: die generelle Gruppen-Suche nach "player" wird
	# separat markiert, damit neue mehrzeilige Varianten nicht durchrutschen.
	var regex := RegEx.new()
	regex.compile("get_nodes_in_group\\(\\s*\"player\"\\s*\\)\\s*\\[\\s*0\\s*\\]")
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
