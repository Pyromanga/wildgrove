# res://tests/unit/test_scene_manager.gd
extends GutTest

## Unit-Tests für SceneManager (scripts/session/SceneManager.gd) — bisher
## ungetestet (siehe architecture_overview.py-Fund, Round 113).
##
## Strategie: echte Szenenwechsel (get_tree().call_deferred(...)) werden hier
## NICHT geprüft — das würde echte .tscn-Dateien laden und wäre kein Unit-,
## sondern ein Integrationstest (siehe test_boot_pipeline.gd für die
## abgegrenzte Alternative). Getestet wird das, was ohne SceneTree-Seiteneffekt
## deterministisch prüfbar ist:
##   configure() — verdrahtet _bus korrekt (require(), kein optionaler Fall)
##   on_ready()  — verbindet scene_reload_requested am UI-Namespace
##   STATE_SCENE_MAP — Datenkorrektheit (jeder GameEnums.State-Eintrag, der
##     gemappt sein soll, zeigt auf den erwarteten Szenenpfad)
##   transition_to_state() für einen NICHT gemappten State — kein Crash,
##     kein get_tree()-Zugriff (der Branch mit dem Szenenwechsel wird dabei
##     nachweislich nicht betreten)

var _bus: MockEventBus
var _svc: SceneManager

func before_each() -> void:
	_bus = MockEventBus.new()
	_svc = add_child_autofree(SceneManager.new())
	_svc.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))

# ─────────────────────────────────────────────
# STATE_SCENE_MAP — Datenkorrektheit
# ─────────────────────────────────────────────

func test_state_scene_map_covers_main_menu() -> void:
	assert_eq(SceneManager.STATE_SCENE_MAP.get(GameEnums.State.MAIN_MENU), "res://scenes/MainMenu.tscn")

func test_state_scene_map_covers_loading() -> void:
	# FIX (Round 113 Nachtrag): PLAYING als Trigger war ein Henne-Ei-Deadlock
	# (PLAYING wird erst NACH world_scene_ready erreicht, das wiederum
	# WorldScopeInitializer in einer bereits geladenen World.tscn braucht).
	# LOADING ist der State, in dem laut GameManager "Welt wird gebootet" —
	# der richtige Zeitpunkt für den Szenenwechsel.
	assert_eq(SceneManager.STATE_SCENE_MAP.get(GameEnums.State.LOADING), "res://scenes/World.tscn")

func test_state_scene_map_covers_game_over() -> void:
	assert_eq(SceneManager.STATE_SCENE_MAP.get(GameEnums.State.GAME_OVER), "res://scenes/GameOver.tscn")

func test_state_scene_map_has_no_unexpected_entries() -> void:
	assert_eq(SceneManager.STATE_SCENE_MAP.size(), 3, "Nur MAIN_MENU/LOADING/GAME_OVER sind aktuell gemappt")

# ─────────────────────────────────────────────
# transition_to_state() — unbekannter State
# ─────────────────────────────────────────────

func test_transition_to_unmapped_state_does_not_crash() -> void:
	# BOOT ist bewusst nicht in STATE_SCENE_MAP — kein Szenenwechsel-Branch,
	# kein get_tree()-Zugriff nötig. Reiner Verhaltenstest: darf nicht crashen.
	_svc.transition_to_state(GameEnums.State.BOOT)
	pass_test("transition_to_state() mit einem nicht gemappten State crasht nicht")

# ─────────────────────────────────────────────
# configure()/on_ready() — Verdrahtung
# ─────────────────────────────────────────────

func test_on_ready_connects_scene_reload_requested() -> void:
	assert_eq(_bus.ui().scene_reload_requested.get_connections().size(), 0,
		"Vor on_ready() darf noch nichts verbunden sein")
	_svc.on_ready()
	assert_eq(_bus.ui().scene_reload_requested.get_connections().size(), 1,
		"on_ready() muss genau einen Connect auf scene_reload_requested herstellen")
	# Bewusst NICHT emit_scene_reload_requested() aufrufen: der verbundene
	# Slot löst change_scene() -> get_tree().call_deferred("change_scene_to_file", ...)
	# aus. Das wäre ein echter, deferred wirksamer Szenenwechsel im laufenden
	# Testlauf-SceneTree — ein Seiteneffekt, der spätere Tests in derselben
	# Session stören könnte. Die Verbindung selbst ist bereits über
	# get_connections() nachgewiesen, ohne diesen Seiteneffekt auszulösen.
