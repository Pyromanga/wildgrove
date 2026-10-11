extends GutTest

## ADR-018 — Regressions-Schutz für den SystemEvents-Split.
##
## Verhindert zwei Arten von Rückfall:
##   1. Ein Save/Session/Networking-Signal wandert versehentlich zurück in
##      SystemEvents (die Datei bleibt sonst wieder ein Sammelbecken).
##   2. Ein neuer Call-Site nutzt `.system().save_requested` (oder Session-/
##      Networking-Äquivalente) statt der jeweils richtigen Namespace-Methode.

const SCAN_ROOT := "res://scripts"

## Signale, die NICHT mehr in SystemEvents liegen dürfen — sie gehören zu
## PersistenceEvents/SessionEvents/NetworkingEvents (siehe ADR-018).
const MOVED_SIGNAL_NAMES := [
	"save_started", "save_requested", "save_pre_flush", "save_completed",
	"save_slot_deleted", "load_started", "load_completed",
	"session_requested", "session_ready", "session_unloaded",
	"host_game_requested", "join_game_requested", "hosting_started",
	"joined_as_client", "connection_to_server_failed", "network_peer_disconnected",
]

func test_systemevents_only_contains_app_lifecycle_signals() -> void:
	var text := FileAccess.get_file_as_string("res://scripts/eventbus/SystemEvents.gd")
	assert_false(text.is_empty(), "SystemEvents.gd muss lesbar sein")
	for signal_name in MOVED_SIGNAL_NAMES:
		assert_false(
			text.contains("signal %s" % signal_name),
			"SystemEvents darf '%s' nicht mehr enthalten — gehört zu Persistence-/Session-/NetworkingEvents (ADR-018)"
				% signal_name
		)

func test_eventbus_exposes_all_four_domain_namespaces() -> void:
	var bus := EventBus
	assert_true(bus.persistence != null, "EventBus.persistence muss existieren")
	assert_true(bus.session != null,     "EventBus.session muss existieren")
	assert_true(bus.networking != null,  "EventBus.networking muss existieren")
	assert_true(bus.system != null,      "EventBus.system muss weiterhin existieren (App-Lifecycle)")

func test_no_moved_signal_accessed_via_system_namespace() -> void:
	var offenders: Array[String] = []
	_scan_dir(SCAN_ROOT, offenders)
	assert_eq(
		offenders.size(), 0,
		"Zugriff auf ein verschobenes Signal über .system()/EventBus.system gefunden "
		+ "(ADR-018: persistence()/session()/networking() nutzen):\n" + "\n".join(offenders)
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
		elif entry.ends_with(".gd") and full_path != "res://scripts/eventbus/EventBus.gd":
			_scan_file(full_path, offenders)
		entry = dir.get_next()
	dir.list_dir_end()

func _scan_file(path: String, offenders: Array[String]) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var line_no := 0
	while not f.eof_reached():
		var line := f.get_line()
		line_no += 1
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var code := line.split("#")[0]
		if not (".system()." in code or "EventBus.system." in code):
			continue
		for signal_name in MOVED_SIGNAL_NAMES:
			if code.contains(".system().%s" % signal_name) or code.contains("EventBus.system.%s" % signal_name):
				offenders.append("%s:%d" % [path, line_no])
				break
