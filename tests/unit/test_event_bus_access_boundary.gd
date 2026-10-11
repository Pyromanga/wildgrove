extends GutTest

const SCAN_ROOT := "res://scripts"

## Round 109 (TODO Punkt 1): MainMenuController.gd und HUDManager.gd sind raus —
## beide vollständig auf IEventBus/IAppContext bzw. IEventBus/IUIContext
## migriert. ServiceOrchestrator.gd/Main.gd bleiben: App-Scope-Bootstrap
## selbst (registrieren/verdrahten den Bus, sind kein Consumer), analog zur
## BootPipeline-Ausnahme in ADR-017.
const ALLOWED_FILES := [
	"res://scripts/eventbus/EventBus.gd",
	"res://scripts/eventbus/EventBusAdapter.gd",
	"res://scripts/platform/ServiceOrchestrator.gd",
	"res://scripts/platform/Main.gd",
	# Beide tragen einen "justified: Autoload"-Kopfkommentar (Bootstrap-Ebene,
	# derselbe Grund wie ServiceOrchestrator/Main.gd) — standen aber nie auf
	# dieser Whitelist. Gefunden von scripts/agent/build/fix_eventbus_direct_access.py
	# (Round 109), unabhängig von der MainMenu/HUD-Migration.
	"res://scripts/platform/DedicatedServerBootstrap.gd",
	"res://scripts/testing/IT03Harness.gd",
]

func test_no_raw_eventbus_access_outside_whitelist() -> void:
	var offenders: Array[String] = []
	_scan_dir(SCAN_ROOT, offenders)
	assert_eq(
		offenders.size(), 0,
		"Direkter EventBus.*-Zugriff außerhalb der Whitelist gefunden:\n" + "\n".join(offenders)
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
	regex.compile("(?<![A-Za-z0-9_])EventBus\\.")
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
