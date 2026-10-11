# res://tests/integration/test_new_game_boot_flow.gd
extends GutTest

## Echter End-to-End-Test für den "Neues Spiel"-Flow: kein synthetischer
## World-Root, kein Mock — genau der Produktionspfad von
## EventBus.session.emit_session_requested() bis zu einer echten,
## geladenen World.tscn mit GameManager.is_playing() == true.
##
## WARUM DIESER TEST EXISTIERT (Round 113 Nachtrag):
## Ein konkreter Bug — SceneManager.STATE_SCENE_MAP mappte PLAYING statt
## LOADING auf World.tscn — führte dazu, dass "Neues Spiel" im echten Build
## STILLE hängen blieb: kein Crash, kein Fehler-Log, einfach kein
## Szenenwechsel. Der Spieler blieb für immer auf dem Hauptmenü.
##
## Kein bestehender Test hätte das gefangen:
##   - test_game_manager.gd testete State-Übergänge isoliert von
##     SceneManager (kein echter SceneManager injiziert).
##   - tests/helpers/SceneLifecycleHarness.gd (boot_fresh_session()) injiziert
##     einen synthetischen World-Root direkt in den SceneTree — umgeht damit
##     genau die Stelle, die kaputt war.
##   - IT-03 (test_movement_two_peer.gd / IT03Harness.gd) emittiert
##     session_requested direkt und prüft Netzwerk-Replikation, nie den
##     UI→Boot→Szenenwechsel-Pfad.
##
## Dieser Test schließt genau diese Lücke: SceneLifecycleHarness.
## boot_fresh_session_via_real_scene_load() lässt den synthetischen Root weg
## und wartet auf die ECHTE World.tscn als current_scene.
##
## KOSTEN: World.tscn wird wirklich geladen (echte Welt-Generierung im
## Hintergrund-Thread). Spürbar langsamer als die übrigen Unit-Tests — daher
## bewusst als einzelner, gezielter Integrationstest statt Ersatz für die
## schnellen State-Machine-Tests.
##
## EHRLICHER HINWEIS: siehe SceneLifecycleHarness.gd Kopfkommentar zu
## boot_fresh_session_via_real_scene_load() — "UNVERIFIZIERTE ANNAHME", ohne
## laufendes Godot in dieser Sandbox geschrieben. Schlägt der Test aus einem
## unerwarteten Grund fehl, ist last_error/harness-Log der erste Anlaufpunkt,
## kein Rätselraten.

var _harness: SceneLifecycleHarness

func before_each() -> void:
	_harness = SceneLifecycleHarness.new(self)

func after_each() -> void:
	if _harness:
		await _harness.return_to_main_menu()
		_harness.cleanup()

func test_new_game_loads_real_world_scene_and_reaches_playing() -> void:
	var ok := await _harness.boot_fresh_session_via_real_scene_load(
		"test_new_game_boot_flow_player"
	)
	assert_true(ok, "Echter New-Game-Flow fehlgeschlagen: %s" % _harness.last_error)

	var gm := get_node("/root/ServiceOrchestrator").get_service("gamemanager")
	assert_true(is_instance_valid(gm) and gm.is_playing(),
		"GameManager muss nach echtem World-Scene-Load in PLAYING sein.")

	var scene := get_tree().current_scene
	assert_true(
		is_instance_valid(scene) and scene.scene_file_path == "res://scenes/World.tscn",
		"current_scene muss die echte World.tscn sein, nicht MainMenu.tscn " +
		"(genau das Symptom des Round-113-Bugs: Spieler bleibt im Hauptmenü hängen)."
	)

## Regression-Test für den KONKRETEN Bug, nicht nur das Endergebnis: selbst
## wenn jemand den State-Scene-Map-Fix wieder rückgängig macht (PLAYING statt
## LOADING), aber zufällig einen anderen Mechanismus einbaut, der zufällig
## noch funktioniert — dieser Test prüft zusätzlich die Kausalkette explizit.
func test_world_scene_is_loaded_before_playing_state_is_reached() -> void:
	var gm := get_node("/root/ServiceOrchestrator").get_service("gamemanager")
	assert_false(gm.is_playing(), "Vorbedingung: darf vor dem Test nicht schon PLAYING sein.")

	EventBus.session.emit_session_requested("test_causality_player")

	var got_world_scene := await _harness._wait_for_real_world_scene(10.0)
	assert_true(got_world_scene,
		"World.tscn muss VOR is_playing()==true als current_scene erscheinen: %s" % _harness.last_error)
	# Zum Zeitpunkt, an dem die Szene lädt, MUSS is_playing() noch false sein —
	# das ist die Henne-Ei-Kausalität, die der Bug verletzt hat (Szene wurde
	# nie geladen WEIL PLAYING als Trigger benutzt wurde, aber PLAYING selbst
	# erst NACH dem Szenen-Laden erreichbar ist).
	assert_false(gm.is_playing(),
		"Zum Zeitpunkt des Szenenwechsels darf PLAYING noch nicht erreicht sein " +
		"(LOADING muss der Trigger sein, nicht PLAYING).")

	var reached_playing := await _harness._wait_for_playing(10.0)
	assert_true(reached_playing, "PLAYING muss nach dem Szenen-Laden erreicht werden: %s" % _harness.last_error)
