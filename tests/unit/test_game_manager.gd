# res://tests/unit/test_game_manager.gd
extends GutTest

## Unit-Tests für GameManager (E-02).
##
## Strategie: GameManager extends ServiceNode (Node) — braucht add_child_autofree().
## configure() ohne SceneManager (null) → kein Szenenwechsel, nur State-Tracking.
## StateValidator wird mit echter GameConfig instanziiert.
##
## Abgedeckt:
##   - get_state() Grundzustand: BOOT
##   - change_state() erlaubte Übergänge
##   - change_state() blockierte Übergänge (via StateValidator + GameConfig)
##   - change_state() same-state wird ignoriert
##   - start_game() setzt MAIN_MENU
##   - is_playing() korrekt

var _gm:     GameManager
var _config: GameConfig
var _bus:    MockEventBus

func before_each() -> void:
	_bus    = MockEventBus.new()
	_gm     = add_child_autofree(GameManager.new())
	_config = GameConfig.new()
	# Kein SceneManager → change_state() macht nur State-Tracking, kein Szenenwechsel.
	_gm.configure(ServiceDeps.from_dict({
		"scenemanager": null,
		"gameconfig": _config,
		ServiceKeys.EVENT_BUS: _bus,
	}))

# ─────────────────────────────────────────────────────────────────────────────
# Grundzustand
# ─────────────────────────────────────────────────────────────────────────────

func test_initial_state_is_boot() -> void:
	assert_eq(_gm.get_state(), GameEnums.State.BOOT, "Startzustand muss BOOT sein")

func test_is_playing_false_at_boot() -> void:
	assert_false(_gm.is_playing(), "is_playing() muss false bei BOOT sein")

# ─────────────────────────────────────────────────────────────────────────────
# start_game()
# ─────────────────────────────────────────────────────────────────────────────

func test_start_game_sets_main_menu() -> void:
	_gm.start_game()
	assert_eq(_gm.get_state(), GameEnums.State.MAIN_MENU,
		"start_game() muss State auf MAIN_MENU setzen")

# ─────────────────────────────────────────────────────────────────────────────
# change_state — erlaubte Übergänge (laut GameConfig.valid_transitions)
# ─────────────────────────────────────────────────────────────────────────────

func test_boot_to_main_menu_allowed() -> void:
	_gm.change_state(GameEnums.State.MAIN_MENU)
	assert_eq(_gm.get_state(), GameEnums.State.MAIN_MENU)

func test_main_menu_to_playing_allowed() -> void:
	_gm.change_state(GameEnums.State.MAIN_MENU)
	_gm.change_state(GameEnums.State.PLAYING)
	assert_eq(_gm.get_state(), GameEnums.State.PLAYING)

func test_playing_to_paused_allowed() -> void:
	_gm.change_state(GameEnums.State.MAIN_MENU)
	_gm.change_state(GameEnums.State.PLAYING)
	_gm.change_state(GameEnums.State.PAUSED)
	assert_eq(_gm.get_state(), GameEnums.State.PAUSED)

func test_playing_to_main_menu_allowed() -> void:
	_gm.change_state(GameEnums.State.MAIN_MENU)
	_gm.change_state(GameEnums.State.PLAYING)
	_gm.change_state(GameEnums.State.MAIN_MENU)
	assert_eq(_gm.get_state(), GameEnums.State.MAIN_MENU)

# ─────────────────────────────────────────────────────────────────────────────
# change_state — blockierte Übergänge
# ─────────────────────────────────────────────────────────────────────────────

func test_boot_to_playing_blocked() -> void:
	# BOOT → PLAYING ist nicht in valid_transitions
	_gm.change_state(GameEnums.State.PLAYING)
	assert_eq(_gm.get_state(), GameEnums.State.BOOT, "BOOT→PLAYING muss blockiert sein")

func test_main_menu_to_paused_blocked() -> void:
	_gm.change_state(GameEnums.State.MAIN_MENU)
	_gm.change_state(GameEnums.State.PAUSED)
	assert_eq(_gm.get_state(), GameEnums.State.MAIN_MENU, "MAIN_MENU→PAUSED muss blockiert sein")

func test_credits_to_playing_blocked() -> void:
	_gm.change_state(GameEnums.State.MAIN_MENU)
	_gm.change_state(GameEnums.State.CREDITS)
	_gm.change_state(GameEnums.State.PLAYING)
	assert_eq(_gm.get_state(), GameEnums.State.CREDITS, "CREDITS→PLAYING muss blockiert sein")

# ─────────────────────────────────────────────────────────────────────────────
# Same-state ignorieren
# ─────────────────────────────────────────────────────────────────────────────

func test_same_state_transition_ignored() -> void:
	_gm.change_state(GameEnums.State.MAIN_MENU)
	# Zweiter Aufruf mit gleichem State: darf keinen Fehler werfen
	_gm.change_state(GameEnums.State.MAIN_MENU)
	assert_eq(_gm.get_state(), GameEnums.State.MAIN_MENU, "State muss gleich bleiben")

# ─────────────────────────────────────────────────────────────────────────────
# is_playing()
# ─────────────────────────────────────────────────────────────────────────────

func test_is_playing_true_when_playing() -> void:
	_gm.change_state(GameEnums.State.MAIN_MENU)
	_gm.change_state(GameEnums.State.PLAYING)
	assert_true(_gm.is_playing(), "is_playing() muss true sein in PLAYING")

# ─────────────────────────────────────────────────────────────────────────────
# REGRESSION-VERTRAG: LOADING muss auf die Welt-Szene gemappt sein
# ─────────────────────────────────────────────────────────────────────────────
## Konkreter Bug (Round 113 Nachtrag): SceneManager.STATE_SCENE_MAP mappte
## PLAYING → World.tscn statt LOADING → World.tscn. Das ist ein Henne-Ei-
## Deadlock: PLAYING wird erst über _on_world_scene_ready() erreicht (siehe
## unten), und world_scene_ready kann nur feuern, wenn World.tscn (mit
## WorldScopeInitializer als Child) bereits geladen ist. Mit PLAYING als
## Trigger wurde die Szene also NIE geladen — das Spiel blieb für immer im
## MainMenu hängen, LOADING intern erreicht, aber sichtbar nichts passiert.
##
## KEIN bestehender Test hätte das gefangen:
##   - test_main_menu_to_playing_allowed() (oben) überspringt LOADING
##     komplett und testet die State-Machine isoliert von SceneManager.
##   - SceneLifecycleHarness (Integration) injiziert einen synthetischen
##     World-Root direkt — umgeht die STATE_SCENE_MAP komplett.
##   - IT03Harness (IT-03) emittiert session_requested direkt und testet
##     Netzwerk-Replikation, nicht den UI→Boot→Szenenwechsel-Pfad.
##
## Dieser Test verdrahtet GameManager mit einem ECHTEN SceneManager (nicht
## null wie in den Tests oben) und prüft die tatsächliche Kopplung: der
## State, den _on_session_ready() setzt (LOADING), MUSS in
## SceneManager.STATE_SCENE_MAP auf die Welt-Szene zeigen — sonst wird sie
## nie geladen, komplett unabhängig davon, ob die State-Machine selbst
## korrekt ist. Siehe auch tests/integration/test_new_game_boot_flow.gd für
## den echten End-to-End-Beleg (reales Szenen-Laden, kein synthetischer Root).
func test_loading_state_triggers_world_scene_load() -> void:
	var sm := add_child_autofree(SceneManager.new())
	sm.configure(ServiceDeps.from_dict({ServiceKeys.EVENT_BUS: _bus}))

	_gm.configure(ServiceDeps.from_dict({
		ServiceKeys.SCENE: sm,
		"gameconfig": _config,
		ServiceKeys.EVENT_BUS: _bus,
	}))
	_gm.on_ready()

	_gm.change_state(GameEnums.State.MAIN_MENU)
	# Exakt der Produktionspfad: session_ready → LOADING (siehe _on_session_ready()).
	_bus.session().emit_session_ready()

	assert_eq(_gm.get_state(), GameEnums.State.LOADING,
		"session_ready muss zu LOADING führen (_on_session_ready()).")
	assert_true(
		SceneManager.STATE_SCENE_MAP.has(GameEnums.State.LOADING),
		"LOADING muss in STATE_SCENE_MAP stehen — sonst lädt World.tscn nie " +
		"(PLAYING wird erst NACH world_scene_ready erreicht, das World.tscn " +
		"bereits geladen voraussetzt — Henne-Ei-Deadlock, siehe Kommentar oben)."
	)
	assert_eq(
		SceneManager.STATE_SCENE_MAP.get(GameEnums.State.LOADING),
		"res://scenes/World.tscn",
		"LOADING muss auf die echte Welt-Szene zeigen."
	)

func test_playing_is_not_a_scene_load_trigger() -> void:
	# Gegenprobe zum Test oben: PLAYING braucht KEINEN eigenen Map-Eintrag —
	# die Szene ist zu dem Zeitpunkt (world_scene_ready ist bereits gefeuert)
	# längst geladen. Ein Eintrag hier wäre ein unnötiger zweiter Szenenwechsel
	# mitten im laufenden Spiel (Terrain/Entities würden neu geladen).
	assert_false(
		SceneManager.STATE_SCENE_MAP.has(GameEnums.State.PLAYING),
		"PLAYING darf keinen eigenen Szenenwechsel auslösen (Szene ist schon geladen)."
	)

func test_is_playing_false_when_paused() -> void:
	_gm.change_state(GameEnums.State.MAIN_MENU)
	_gm.change_state(GameEnums.State.PLAYING)
	_gm.change_state(GameEnums.State.PAUSED)
	assert_false(_gm.is_playing(), "is_playing() muss false sein in PAUSED")

# ─────────────────────────────────────────────────────────────────────────────
# ADR-028: network_peer_disconnected → geordnete Rückkehr zu MAIN_MENU
# ─────────────────────────────────────────────────────────────────────────────

func test_network_peer_disconnected_returns_to_main_menu_from_playing() -> void:
	_gm.on_ready()
	_gm.change_state(GameEnums.State.MAIN_MENU)
	_gm.change_state(GameEnums.State.PLAYING)
	_bus.networking().emit_network_peer_disconnected()
	assert_eq(_gm.get_state(), GameEnums.State.MAIN_MENU,
		"Autoritätsverlust in PLAYING muss zu MAIN_MENU führen (ADR-028).")

func test_network_peer_disconnected_returns_to_main_menu_from_loading() -> void:
	_gm.on_ready()
	_gm.change_state(GameEnums.State.MAIN_MENU)
	_gm.change_state(GameEnums.State.LOADING)
	_bus.networking().emit_network_peer_disconnected()
	assert_eq(_gm.get_state(), GameEnums.State.MAIN_MENU,
		"Autoritätsverlust in LOADING muss zu MAIN_MENU führen (ADR-028).")

func test_network_peer_disconnected_returns_to_main_menu_from_paused() -> void:
	_gm.on_ready()
	_gm.change_state(GameEnums.State.MAIN_MENU)
	_gm.change_state(GameEnums.State.PLAYING)
	_gm.change_state(GameEnums.State.PAUSED)
	_bus.networking().emit_network_peer_disconnected()
	assert_eq(_gm.get_state(), GameEnums.State.MAIN_MENU,
		"Autoritätsverlust in PAUSED muss zu MAIN_MENU führen (ADR-028).")

func test_network_peer_disconnected_while_already_in_main_menu_is_noop() -> void:
	_gm.on_ready()
	_gm.change_state(GameEnums.State.MAIN_MENU)
	_bus.networking().emit_network_peer_disconnected()
	assert_eq(_gm.get_state(), GameEnums.State.MAIN_MENU,
		"Bereits im Hauptmenü — darf keinen Fehler werfen, State bleibt MAIN_MENU.")

func test_without_on_ready_network_peer_disconnected_has_no_effect() -> void:
	## Kontrollfall: ohne on_ready() ist die Signal-Verdrahtung nie hergestellt worden —
	## belegt, dass der Effekt oben tatsächlich von on_ready()s connect() kommt.
	_gm.change_state(GameEnums.State.MAIN_MENU)
	_gm.change_state(GameEnums.State.PLAYING)
	_bus.networking().emit_network_peer_disconnected()
	assert_eq(_gm.get_state(), GameEnums.State.PLAYING,
		"Ohne on_ready() darf sich am State nichts ändern — Kontrollfall für die Tests oben.")
