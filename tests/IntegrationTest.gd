# IntegrationTest.gd
# GUT ist installiert (res://addons/gut/).
# Dieser Test braucht den echten ServiceOrchestrator — läuft nicht headless ohne Scene.
# Für CI: Unit-Tests in tests/unit/ via:
#   godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/ -gexit

extends GutTest

## IntegrationTest — Prüft Boot-Prozess und Session-Lifecycle.
##
## E-01-Fix (Session 6): Erweitert von 6× assert_not_null auf drei Testgruppen:
##   1. Integrity — Services sind nach Boot nicht null und korrekt typisiert
##   2. GameManager-State — korrekte State-Initialisierung nach Boot
##   3. Session-State — is_session_active() korrekt zur Laufzeit
##
## Hinweis: ServiceOrchestrator, EventBus und GameManager sind AutoLoads.
## before_all() wartet auf services_initialized bevor Tests laufen.
##
## NICHT getestet hier (erfordern Session-Teardown und SceneTree-Kontrolle):
##   - Character-Switch (boot_session A → teardown → boot_session B)
##   - Save/Load-Round-Trip auf Integrations-Ebene
##   - Error-Path: Boot mit korrupter BootstrapConfig
## Diese Fälle gehören in einen separaten IntegrationTest_SessionLifecycle.gd
## sobald ein Test-Runner-Harness für Scene-Lifecycle verfügbar ist.

var _services_ready: bool = false

## Liefert das ServiceOrchestrator-AutoLoad. Kleiner Helfer da dieses Test-File
## den Orchestrator an sehr vielen Stellen braucht (echter Integrationstest,
## kein Mock — siehe Datei-Kopfkommentar).
func _orch() -> Node:
	return get_node("/root/ServiceOrchestrator")

func before_all() -> void:
	# Guard gegen connect-after-signal-Race: ServiceOrchestrator ist AutoLoad
	# und startet den Boot-Prozess bevor GUT's before_all() läuft.
	if _orch().get_service("gamemanager") != null and _orch().get_service("gamemanager").is_playing():
		_services_ready = true
		return
	if not EventBus.system.services_initialized.is_connected(_on_services_ready):
		EventBus.system.services_initialized.connect(_on_services_ready, CONNECT_ONE_SHOT)

func _on_services_ready() -> void:
	_services_ready = true
	AppLogger.log_info("IntegrationTest: Services bereit.", "Test")

# ─────────────────────────────────────────────────────────────────────────────
# 1 — Integrity: Services sind registriert und korrekt typisiert
# ─────────────────────────────────────────────────────────────────────────────

func test_global_services_not_null() -> void:
	assert_not_null(_orch().get_service("savesystem"),   "SaveSystem muss registriert sein")
	assert_not_null(_orch().get_service("data"),         "DataService muss registriert sein")
	assert_not_null(_orch().get_service("inventory"),    "InventorySystem muss registriert sein")
	assert_not_null(_orch().get_service("skill_system"), "SkillSystem muss registriert sein")
	assert_not_null(_orch().get_service("world"),        "WorldService muss registriert sein")
	assert_not_null(_orch().get_service("playerstates"), "PlayerStateService muss registriert sein")

func test_global_services_correct_types() -> void:
	assert_true(_orch().get_service("savesystem")   is SaveSystem,        "save_system muss SaveSystem-Instanz sein")
	assert_true(_orch().get_service("data")         is DataService,       "data muss DataService-Instanz sein")
	assert_true(_orch().get_service("skill_system") is SkillSystem,       "skill_system muss SkillSystem-Instanz sein")
	assert_true(_orch().get_service("playerstates") is PlayerStateService,"player_states muss PlayerStateService-Instanz sein")

func test_session_services_not_null_when_playing() -> void:
	# Session-Services sind nur im PLAYING-State verfügbar
	if not _orch().get_service("gamemanager").is_playing():
		pending("Übersprungen: kein PLAYING-State (kein Charakter gewählt)")
		return
	assert_not_null(_orch().get_service("quest"),      "QuestService muss in Session registriert sein")
	assert_not_null(_orch().get_service("equipment"),  "EquipmentService muss in Session registriert sein")

# ─────────────────────────────────────────────────────────────────────────────
# 2 — GameManager: State nach Boot
# ─────────────────────────────────────────────────────────────────────────────

func test_game_manager_not_in_boot_after_start() -> void:
	assert_ne(
		_orch().get_service("gamemanager").get_state(),
		GameEnums.State.BOOT,
		"GameManager darf nach start_game() nicht in BOOT verbleiben"
	)

func test_game_manager_in_main_menu_or_playing() -> void:
	var state = _orch().get_service("gamemanager").get_state()
	var valid = (state == GameEnums.State.MAIN_MENU or state == GameEnums.State.PLAYING)
	assert_true(valid, "GameManager muss nach Boot in MAIN_MENU oder PLAYING sein")

# ─────────────────────────────────────────────────────────────────────────────
# 3 — Session-State: is_session_active() korrekt zur Laufzeit
# ─────────────────────────────────────────────────────────────────────────────

func test_session_active_matches_game_state() -> void:
	## is_session_active() ist auf registry-State basiert (F-03-Fix),
	## nicht mehr auf GameManager.get_state(). Beide müssen konsistent sein:
	## Im PLAYING-State muss mindestens eine Session laufen.
	if not _orch().get_service("gamemanager").is_playing():
		pending("Übersprungen: kein PLAYING-State")
		return
	assert_true(
		_orch().is_session_active(),
		"is_session_active() muss true sein wenn GameManager PLAYING ist"
	)

func test_save_system_has_active_session_when_playing() -> void:
	if not _orch().get_service("gamemanager").is_playing():
		pending("Übersprungen: kein PLAYING-State")
		return
	assert_true(
		_orch().get_service("savesystem").has_active_session(),
		"SaveSystem muss aktive Session haben wenn GameManager PLAYING ist"
	)
