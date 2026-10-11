# tests/helpers/SceneLifecycleHarness.gd
class_name SceneLifecycleHarness
extends RefCounted

## Schließt genau die Lücke, die tests/IntegrationTest.gd im Kopfkommentar
## offen benennt: "gehört in einen separaten IntegrationTest_SessionLifecycle.gd
## sobald ein Test-Runner-Harness für Scene-Lifecycle verfügbar ist." Dieser
## Harness ist dieses fehlende Stück — er treibt den ECHTEN Boot-Flow
## (App → Character → World) innerhalb eines laufenden GUT-Tests, damit
## Character-Switch und Save/Load-Round-Trip überhaupt testbar werden.
##
## WARUM DAS BISHER FEHLTE: WorldService/SkillSystem/Inventory/… werden erst
## in CharacterScope.configure() gebootet, und das passiert erst, wenn ein
## echter World-Root im SceneTree erscheint (siehe WorldScopeInitializer.gd
## Klassenkommentar: Push-Pattern, ServiceOrchestrator._watch_for_world_initializer()
## lauscht generisch über tree.node_added). In Produktion kommt dieser Root aus
## World.tscn (echtes Terrain, echte Assets, echte Welt-Generierung im
## Hintergrund-Thread). Ein reiner Skript-Test (`gut_cmdln.gd -gdir=...`) lädt
## nie World.tscn — is_playing() bleibt für IMMER false, jeder darauf gegatete
## Test (inkl. tests/IntegrationTest.gd UND der beiden in dieser Session
## hinzugefügten Tests, test_quest_reward_chain.gd/
## test_pvp_death_loss_protections.gd) würde sonst ewig pending() bleiben,
## nie wirklich laufen.
##
## DIE AUSNUTZUNG: WorldScopeInitializer.gd ist rein strukturell — es
## braucht nur einen Node3D-Parent im SceneTree, sonst nichts (kein
## AutoLoad-Zugriff, kein EventBus, kein Pull, siehe dortiger Kommentar
## "Kein AutoLoad-Zugriff. Kein EventBus. Kein Pull."). Ein minimaler
## synthetischer Root (Node3D + WorldScopeInitializer-Kind) durchläuft
## exakt denselben Produktionscodepfad wie die echte World.tscn — ohne
## Terrain-Generierung, ohne Assets.
##
## EHRLICHER HINWEIS — UNVERIFIZIERTE ANNAHME: Dieser Harness wurde ohne
## laufendes Godot geschrieben (kein Binary/Netzwerk in dieser Sandbox). Er
## geht davon aus, dass WorldService.on_world_scene_ready() mit einem NACKTEN
## Node3D-Root (keine vorbereiteten Kind-Nodes wie Spawn-Marker, Chunk-
## Container o.ä.) tatsächlich fertig durchläuft. Falls WorldGenerationService
## oder WorldService konkrete Kind-Nodes im Root voraussetzen, die hier
## fehlen, läuft der Boot in den TIMEOUT dieses Harness (klar erkennbares
## Fehlschlagen mit Log-Ausgabe), NICHT in einen stillen Hänger — das ist
## dann der nächste konkrete Befund für einen echten Lauf, kein Rätselraten.
##
## WICHTIGE EINSCHRÄNKUNG (Round 113 Nachtrag): boot_fresh_session() (und
## reload_current_session()) injizieren den World-Root SYNTHETISCH und
## umgehen damit komplett die Frage, ob GameManager/SceneManager World.tscn
## in der Produktion überhaupt jemals ECHT laden würden. Genau in dieser
## Lücke saß ein realer Bug (SceneManager.STATE_SCENE_MAP mappte PLAYING
## statt LOADING → World.tscn wurde nie geladen, Spieler blieb im Hauptmenü
## hängen — kein einziger bestehender Test hätte das gefangen). Für den
## echten Szenen-Lade-Pfad siehe boot_fresh_session_via_real_scene_load()
## weiter unten in dieser Datei, verwendet von
## tests/integration/test_new_game_boot_flow.gd.
##
## VERWENDUNG:
##   var harness := SceneLifecycleHarness.new(self)  # self = die GutTest-Instanz
##   var ok := await harness.boot_fresh_session("test_player_lifecycle")
##   if not ok:
##       pending("Boot fehlgeschlagen: " + harness.last_error)
##       return
##   # ... Assertions gegen PLAYING-State ...
##   var reloaded := await harness.reload_current_session()  # = "Laden"-Pfad,
##       # Save/Load-Round-Trip: teardown_character+teardown_world, dann
##       # Neuboot mit frischem Spielstand von Disk (SaveSystem.begin_session()).
##   var back_at_menu := await harness.return_to_main_menu()  # Character-Switch:
##       # danach erneut boot_fresh_session(anderer_player_id) für den
##       # zweiten Charakter.
##   harness.cleanup()  # in after_each() — entfernt evtl. verbliebene
##       # synthetische World-Roots, falls ein Testfall mittendrin failte.

const DEFAULT_BOOT_TIMEOUT_SEC := 10.0
const POLL_INTERVAL_SEC := 0.1

var last_error: String = ""

var _test: Node  # die GutTest-Instanz — braucht get_tree()
var _orch: Node
var _synthetic_roots: Array[Node3D] = []

func _init(test_instance: Node) -> void:
	_test = test_instance
	_orch = _test.get_node("/root/ServiceOrchestrator")

func _gamemanager() -> Node:
	return _orch.get_service("gamemanager")

## Bootet eine frische Session für player_id — äquivalent zu einem "Neues
## Spiel" / "Charakter beitreten"-Klick im MainMenu, nur ohne UI.
## player_id sollte pro Testfall eindeutig sein (kein Reset-Pfad für eine
## bereits abgeschlossene Session-Historie — siehe test_quest_reward_chain.gd
## Kommentar zum selben Thema).
func boot_fresh_session(player_id: String, timeout_sec: float = DEFAULT_BOOT_TIMEOUT_SEC) -> bool:
	last_error = ""
	var gm := _gamemanager()
	if gm == null:
		last_error = "GameManager nicht registriert."
		return false
	if gm.is_playing():
		last_error = "Bereits eine PLAYING-Session aktiv — vorher return_to_main_menu() aufrufen."
		return false

	EventBus.session.emit_session_requested(player_id)
	# Muss NACH dem Emit passieren: _on_session_requested() (ServiceOrchestrator)
	# ruft _watch_for_world_initializer() synchron auf, BEVOR emit_session_requested()
	# zurückkehrt (kein await auf dem Pfad bis dahin) — der tree.node_added-Listener
	# ist also garantiert schon aktiv, wenn wir jetzt den synthetischen Root einhängen.
	_inject_synthetic_world_root()

	return await _wait_for_playing(timeout_sec)

## Entspricht EXAKT dem Produktions-"Laden"-Pfad
## (ServiceOrchestrator._on_scene_reload_requested(), ausgelöst normalerweise
## vom Pause-Menü): reißt CharacterScope + WorldScope für den AKTUELLEN
## Spieler ab und bootet neu — liest den Spielstand dabei frisch von Disk
## (SaveSystem.begin_session()). Das IST der Save/Load-Round-Trip auf
## Integrationsebene: Zustand vor dem Aufruf sichern (im Test), Aufruf,
## Zustand danach mit dem vorher gespeicherten Stand vergleichen.func reload_current_session(timeout_sec: float = DEFAULT_BOOT_TIMEOUT_SEC) -> bool:
	last_error = ""
	var gm := _gamemanager()
	if gm == null or not gm.is_playing():
		last_error = "Kein aktives PLAYING — reload_current_session() setzt eine laufende Session voraus."
		return false

	EventBus.ui.emit_scene_reload_requested()
	# Wie in boot_fresh_session(): _on_scene_reload_requested() ruft am Ende
	# selbst wieder _on_session_requested() auf (synchron bis dahin), das
	# wiederum _watch_for_world_initializer() neu verdrahtet — der alte
	# synthetische Root wurde durch teardown_world() bereits mit abgebaut,
	# hier kommt ein frischer rein.
	_inject_synthetic_world_root()

	return await _wait_for_playing(timeout_sec)

## Entspricht einem "Zum Hauptmenü"-Klick — treibt GameManager zurück auf
## MAIN_MENU, was ServiceOrchestrator._on_state_changed() dazu bringt, die
## CharacterScope sauber abzureißen (destroy_character_scope() +
## emit_session_unloaded()). Danach ist boot_fresh_session() mit einer
## ANDEREN player_id der Character-Switch-Testfall.
func return_to_main_menu(timeout_sec: float = 5.0) -> bool:
	last_error = ""
	EventBus.ui.emit_main_menu_requested()
	var elapsed := 0.0
	while elapsed < timeout_sec:
		var gm := _gamemanager()
		if gm != null and gm.get_state() == GameEnums.State.MAIN_MENU and not gm.is_playing():
			return true
		await _test.get_tree().create_timer(POLL_INTERVAL_SEC).timeout
		elapsed += POLL_INTERVAL_SEC
	last_error = "MAIN_MENU nicht innerhalb von %.1fs erreicht (letzter State: %s)." % [
		timeout_sec, GameEnums.State.keys()[_gamemanager().get_state()] if _gamemanager() else "?"
	]
	return false

## In after_each() aufrufen — entfernt jeden synthetischen World-Root, der
## bei einem fehlgeschlagenen/abgebrochenen Testfall noch im SceneTree hängt.
## Ohne das könnte ein späterer Testfall in DERSELBEN Datei einen zweiten
## WorldScopeInitializer sehen, der gar nicht zu seinem eigenen
## boot_fresh_session()-Aufruf gehört (der generische tree.node_added-Scan in
## ServiceOrchestrator unterscheidet nicht, WELCHER Testfall den Root erzeugt hat).
func cleanup() -> void:
	for root in _synthetic_roots:
		if is_instance_valid(root):
			root.queue_free()
	_synthetic_roots.clear()

func _inject_synthetic_world_root() -> void:
	var root := Node3D.new()
	root.name = "SceneLifecycleHarness_SyntheticWorldRoot"
	var initializer := WorldScopeInitializer.new()
	root.add_child(initializer)
	_test.get_tree().root.add_child(root)
	_synthetic_roots.append(root)

func _wait_for_playing(timeout_sec: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		var gm := _gamemanager()
		if gm != null and gm.is_playing():
			return true
		await _test.get_tree().create_timer(POLL_INTERVAL_SEC).timeout
		elapsed += POLL_INTERVAL_SEC
	var gm := _gamemanager()
	last_error = "PLAYING nicht innerhalb von %.1fs erreicht (letzter State: %s) — " % [
		timeout_sec, GameEnums.State.keys()[gm.get_state()] if gm else "?"
	] + "mögliche Ursache: WorldService/WorldGenerationService erwartet mehr als einen nackten " + \
	"Node3D-Root (siehe Kopfkommentar 'UNVERIFIZIERTE ANNAHME')."
	return false

# ─────────────────────────────────────────────────────────────────────────────
# ECHTES Szenen-Laden — KEIN synthetischer Root (Round 113 Nachtrag)
# ─────────────────────────────────────────────────────────────────────────────
## boot_fresh_session() oben (und reload_current_session()) injizieren einen
## synthetischen World-Root direkt in den SceneTree — das macht WorldScope
## testbar, umgeht aber komplett die Frage "lädt der echte Produktionscode
## (GameManager.change_state() → SceneManager.transition_to_state() →
## get_tree().call_deferred('change_scene_to_file', ...)) World.tscn
## überhaupt?". Genau DAS war der Round-113-Bug: SceneManager.STATE_SCENE_MAP
## hatte PLAYING statt LOADING gemappt — ein Henne-Ei-Deadlock, der von
## boot_fresh_session() oben NICHT sichtbar gewesen wäre, weil es die echte
## Szenen-Lade-Kette gar nicht anfasst.
##
## boot_fresh_session_via_real_scene_load() lässt den synthetischen Root WEG
## und wartet stattdessen auf die ECHTE World.tscn im SceneTree — über genau
## den Produktionspfad, den auch ein Spieler beim Klick auf "Neues Spiel"
## durchläuft. Kosten: World.tscn wird wirklich geladen (echte Welt-
## Generierung im Hintergrund-Thread, siehe WorldGenerationService) — spürbar
## langsamer als boot_fresh_session(), deshalb ein eigener, bewusst
## selektiver Test (tests/integration/test_new_game_boot_flow.gd) statt
## Ersatz für die schnellen Tests, die den synthetischen Root nutzen.
##
## EHRLICHER HINWEIS — UNVERIFIZIERTE ANNAHME (wie beim Rest dieser Datei):
## ohne laufendes Godot geschrieben. Geht davon aus, dass
## get_tree().current_scene nach dem deferred change_scene_to_file()-Aufruf
## zuverlässig auf die neue Root-Node zeigt, sobald diese vollständig geladen
## ist (Standard-Godot-Verhalten, aber hier nie live verifiziert). Falls
## World.tscn aus irgendeinem Grund langsamer lädt als erwartet, läuft dieser
## Harness in seinen eigenen Timeout (klar erkennbares Fehlschlagen mit
## last_error), nicht in einen stillen Hänger.
func boot_fresh_session_via_real_scene_load(player_id: String, timeout_sec: float = DEFAULT_BOOT_TIMEOUT_SEC) -> bool:
	last_error = ""
	var gm := _gamemanager()
	if gm == null:
		last_error = "GameManager nicht registriert."
		return false
	if gm.is_playing():
		last_error = "Bereits eine PLAYING-Session aktiv — vorher return_to_main_menu() aufrufen."
		return false

	EventBus.session.emit_session_requested(player_id)
	# BEWUSST kein _inject_synthetic_world_root() hier — siehe Klassenkommentar
	# oben. Der echte Szenenwechsel läuft über GameManager._on_session_ready()
	# → change_state(LOADING) → SceneManager.transition_to_state(LOADING) →
	# get_tree().call_deferred("change_scene_to_file", "res://scenes/World.tscn").

	if not await _wait_for_real_world_scene(timeout_sec):
		return false
	return await _wait_for_playing(timeout_sec)

## Wartet auf die ECHTE World.tscn als current_scene (nicht auf is_playing() —
## das kann erst danach kommen, siehe Henne-Ei-Kommentar oben). Getrennt von
## _wait_for_playing(), damit ein Fehlschlag hier eindeutig auf "Szene wurde
## nie gewechselt" zeigt statt auf "Szene lief, aber World-Boot intern hängt".
func _wait_for_real_world_scene(timeout_sec: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		var scene := _test.get_tree().current_scene
		if is_instance_valid(scene) and scene.scene_file_path == "res://scenes/World.tscn":
			return true
		await _test.get_tree().create_timer(POLL_INTERVAL_SEC).timeout
		elapsed += POLL_INTERVAL_SEC
	var scene := _test.get_tree().current_scene
	last_error = (
		"World.tscn nicht innerhalb von %.1fs als current_scene erreicht (aktuell: %s) — " % [
			timeout_sec,
			scene.scene_file_path if is_instance_valid(scene) else "null"
		]
		+ "SceneManager.STATE_SCENE_MAP fehlt vermutlich der Eintrag für den State, "
		+ "den _on_session_ready() setzt (Regressionsklasse Round 113 — siehe "
		+ "test_game_manager.gd:test_loading_state_triggers_world_scene_load())."
	)
	return false
