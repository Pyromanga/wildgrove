# res://tests/unit/test_adr003_lint.gd
extends GutTest

## ADR-003 Enforcement — GUT-seitige Verifikation.
##
## Prüft dieselbe Invariante wie lint_servicenode.sh, aber aus GUT heraus:
## Jede .gd-Datei die "extends ServiceNode" in Zeile 1 deklariert muss
## "# justified:" in den ersten 15 Zeilen haben.
##
## Zweck: Fängt Verstöße auch in headless-GUT-Läufen ab (ohne Bash-Skript).
## Ergänzt, ersetzt aber NICHT lint_servicenode.sh (das prüft auch JUSTIFIED_FILES).
##
## Hinweis: FileAccess.get_open_error() ist Godot-4-Standard (keine DirAccess nötig).

## Bekannte ServiceNode-Dateien (ADR-003 Tabelle — muss mit lint_servicenode.sh synchron sein)
const JUSTIFIED_FILES := [
	"res://scripts/platform/GameManager.gd",
	"res://scripts/interaction/InteractionExecutor.gd",
	"res://scripts/entities/combat/CombatSystem.gd",
	"res://scripts/networking/NetworkBridge.gd",
	"res://scripts/session/SceneManager.gd",
	"res://scripts/session/SessionManager.gd",
	"res://scripts/platform/ServiceTicker.gd",
	"res://scripts/world/respawn/RespawnService.gd",
	"res://scripts/world/core/WorldGenerationService.gd",
	"res://scripts/world/core/WorldService.gd",
]

func _read_lines(path: String, count: int) -> Array:
	var lines: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return lines
	var i := 0
	while not f.eof_reached() and i < count:
		lines.append(f.get_line())
		i += 1
	f.close()
	return lines

func _is_real_servicenode(lines: Array) -> bool:
	## Echte Deklaration: "extends ServiceNode" in Zeile 0-2 (Index 0, 1, 2)
	for i in range(min(3, lines.size())):
		if (lines[i] as String).strip_edges() == "extends ServiceNode":
			return true
	return false

func _has_justified(lines: Array) -> bool:
	for line in lines:
		if (line as String).contains("# justified:"):
			return true
	return false

# ─────────────────────────────────────────────────────────────────────────────
# Test 1: Alle ServiceNode-Dateien haben # justified:
# ─────────────────────────────────────────────────────────────────────────────

func test_all_servicenode_files_have_justified_comment() -> void:
	var violations: Array[String] = []
	for path in JUSTIFIED_FILES:
		var lines := _read_lines(path, 15)
		if lines.is_empty():
			# Datei nicht gefunden — kein Fehler (Pfad kann in Test-Env fehlen)
			continue
		if not _has_justified(lines):
			violations.append(path)

	if not violations.is_empty():
		fail_test("Folgende ServiceNode-Dateien fehlen '# justified:' Kommentar:\n" +
			"\n".join(violations) +
			"\nLoes: Zeile 2 ergaenzen: '# justified: <SceneTree-Nutzung>'")
	else:
		assert_true(true, "Alle known ServiceNode-Dateien haben justified-Kommentar")

# ─────────────────────────────────────────────────────────────────────────────
# Test 2: Keine unbekannte ServiceNode-Deklaration in scripts/
#         (prüft ob neue Dateien vergessen wurden in JUSTIFIED_FILES einzutragen)
# ─────────────────────────────────────────────────────────────────────────────

func test_no_unknown_servicenode_declarations() -> void:
	var unknown: Array[String] = []
	_scan_dir("res://scripts", unknown)
	if not unknown.is_empty():
		fail_test("Unbekannte extends ServiceNode-Deklarationen gefunden (ADR-003-Verletzung):\n" +
			"\n".join(unknown) +
			"\nLoes: Datei in JUSTIFIED_FILES in lint_servicenode.sh + test_adr003_lint.gd eintragen" +
			"\nOder: 'extends Service' verwenden wenn kein SceneTree noetig (ADR-003)")
	else:
		assert_true(true, "Keine unbekannten ServiceNode-Deklarationen")

func _scan_dir(dir_path: String, violations: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with(".") or name == "addons":
			name = dir.get_next()
			continue
		var full_path := dir_path + "/" + name
		if dir.current_is_dir():
			_scan_dir(full_path, violations)
		elif name.ends_with(".gd"):
			var lines := _read_lines(full_path, 3)
			if _is_real_servicenode(lines):
				if not JUSTIFIED_FILES.has(full_path):
					violations.append(full_path)
		name = dir.get_next()
	dir.list_dir_end()
