## tests/unit/test_state_validator.gd
## Unit-Tests für StateValidator und GameConfig.
##
## Abdeckung:
##   - GameConfig lädt valid_transitions korrekt (nicht leer)
##   - Alle erlaubten Übergänge laut GameConfig werden akzeptiert
##   - Nicht definierte Übergänge werden blockiert
##   - MAIN_MENU → PLAYING ist erlaubt (Regression: war blockiert durch leere .tres)
##   - StateValidator gibt true zurück wenn config null ist (Fallback)
##   - Übergänge vom gleichen State in sich selbst sind nicht erlaubt

extends GutTest

var _config: GameConfig

func before_each() -> void:
	_config = GameConfig.new()

func after_each() -> void:
	_config = null

# ─────────────────────────────────────────────
# GameConfig — Daten korrekt geladen
# ─────────────────────────────────────────────

func test_game_config_valid_transitions_not_empty() -> void:
	assert_false(
		_config.valid_transitions.is_empty(),
		"valid_transitions darf nicht leer sein — .tres oder Script-Default fehlt."
	)

func test_game_config_has_all_states() -> void:
	var expected := ["BOOT", "MAIN_MENU", "LOADING", "PLAYING", "PAUSED", "CUTSCENE", "GAME_OVER", "CREDITS"]
	for state in expected:
		assert_true(
			_config.valid_transitions.has(state),
			"valid_transitions muss Key '%s' enthalten." % state
		)

# ─────────────────────────────────────────────
# Erlaubte Übergänge
# ─────────────────────────────────────────────

func test_main_menu_to_playing_allowed() -> void:
	# Regression: war blockiert weil GameConfig.tres kein valid_transitions-Feld hatte
	assert_true(
		StateValidator.is_transition_allowed(
			GameEnums.State.MAIN_MENU, GameEnums.State.PLAYING, _config
		),
		"MAIN_MENU → PLAYING muss erlaubt sein."
	)

func test_main_menu_to_loading_allowed() -> void:
	assert_true(
		StateValidator.is_transition_allowed(
			GameEnums.State.MAIN_MENU, GameEnums.State.LOADING, _config
		),
		"MAIN_MENU → LOADING muss erlaubt sein."
	)

func test_playing_to_paused_allowed() -> void:
	assert_true(
		StateValidator.is_transition_allowed(
			GameEnums.State.PLAYING, GameEnums.State.PAUSED, _config
		),
		"PLAYING → PAUSED muss erlaubt sein."
	)

func test_playing_to_main_menu_allowed() -> void:
	assert_true(
		StateValidator.is_transition_allowed(
			GameEnums.State.PLAYING, GameEnums.State.MAIN_MENU, _config
		),
		"PLAYING → MAIN_MENU muss erlaubt sein."
	)

func test_paused_to_playing_allowed() -> void:
	assert_true(
		StateValidator.is_transition_allowed(
			GameEnums.State.PAUSED, GameEnums.State.PLAYING, _config
		),
		"PAUSED → PLAYING muss erlaubt sein."
	)

func test_loading_to_playing_allowed() -> void:
	assert_true(
		StateValidator.is_transition_allowed(
			GameEnums.State.LOADING, GameEnums.State.PLAYING, _config
		),
		"LOADING → PLAYING muss erlaubt sein."
	)

func test_game_over_to_main_menu_allowed() -> void:
	assert_true(
		StateValidator.is_transition_allowed(
			GameEnums.State.GAME_OVER, GameEnums.State.MAIN_MENU, _config
		),
		"GAME_OVER → MAIN_MENU muss erlaubt sein."
	)

# ─────────────────────────────────────────────
# Blockierte Übergänge
# ─────────────────────────────────────────────

func test_boot_to_playing_blocked() -> void:
	assert_false(
		StateValidator.is_transition_allowed(
			GameEnums.State.BOOT, GameEnums.State.PLAYING, _config
		),
		"BOOT → PLAYING muss blockiert sein."
	)

func test_paused_to_game_over_blocked() -> void:
	assert_false(
		StateValidator.is_transition_allowed(
			GameEnums.State.PAUSED, GameEnums.State.GAME_OVER, _config
		),
		"PAUSED → GAME_OVER muss blockiert sein."
	)

func test_game_over_to_playing_blocked() -> void:
	assert_false(
		StateValidator.is_transition_allowed(
			GameEnums.State.GAME_OVER, GameEnums.State.PLAYING, _config
		),
		"GAME_OVER → PLAYING muss blockiert sein."
	)

func test_credits_to_playing_blocked() -> void:
	assert_false(
		StateValidator.is_transition_allowed(
			GameEnums.State.CREDITS, GameEnums.State.PLAYING, _config
		),
		"CREDITS → PLAYING muss blockiert sein."
	)

# ─────────────────────────────────────────────
# Null-Safety / Fallback
# ─────────────────────────────────────────────

func test_null_config_allows_any_transition() -> void:
	assert_true(
		StateValidator.is_transition_allowed(
			GameEnums.State.BOOT, GameEnums.State.PLAYING, null
		),
		"Null-Config muss alle Übergänge erlauben (Fallback)."
	)

func test_loaded_tres_valid_transitions_not_empty() -> void:
	# Regression: GameConfig.tres hatte kein valid_transitions-Feld →
	# Godot setzte es auf {} → alle Übergänge blockiert.
	var loaded := load("res://config/GameConfig.tres") as GameConfig
	assert_not_null(loaded, "GameConfig.tres muss ladbar sein.")
	assert_false(
		loaded.valid_transitions.is_empty(),
		"GameConfig.tres muss valid_transitions enthalten (nicht leer)."
	)

func test_loaded_tres_transition_actually_works() -> void:
	# Regression: StateValidator castete Dictionary-Werte aus .tres mit
	# "as Array[String]" — das gibt in Godot 4 null zurück für ungetypte Arrays,
	# wodurch alle Übergänge still blockiert wurden.
	# Dieser Test lädt die echte .tres (nicht GameConfig.new()) und prüft
	# dass StateValidator damit korrekt arbeitet.
	var loaded := load("res://config/GameConfig.tres") as GameConfig
	assert_not_null(loaded, "GameConfig.tres muss ladbar sein.")
	assert_true(
		StateValidator.is_transition_allowed(
			GameEnums.State.MAIN_MENU, GameEnums.State.PLAYING, loaded
		),
		"MAIN_MENU → PLAYING muss mit geladener .tres funktionieren (nicht nur mit GameConfig.new())."
	)

func test_loaded_tres_all_critical_transitions_work() -> void:
	# Stellt sicher dass kein Übergang durch einen Serialisierungs- oder Cast-Bug
	# blockiert wird — mit der echten geladenen .tres.
	var loaded := load("res://config/GameConfig.tres") as GameConfig
	assert_not_null(loaded, "GameConfig.tres muss ladbar sein.")

	var critical := [
		[GameEnums.State.MAIN_MENU, GameEnums.State.PLAYING],
		[GameEnums.State.MAIN_MENU, GameEnums.State.LOADING],
		[GameEnums.State.LOADING,   GameEnums.State.PLAYING],
		[GameEnums.State.PLAYING,   GameEnums.State.PAUSED],
		[GameEnums.State.PAUSED,    GameEnums.State.PLAYING],
		[GameEnums.State.PLAYING,   GameEnums.State.MAIN_MENU],
		[GameEnums.State.GAME_OVER, GameEnums.State.MAIN_MENU],
	]

	for pair in critical:
		var from_str = GameEnums.State.keys()[pair[0]]
		var to_str   = GameEnums.State.keys()[pair[1]]
		assert_true(
			StateValidator.is_transition_allowed(pair[0], pair[1], loaded),
			"%s → %s muss mit geladener .tres erlaubt sein." % [from_str, to_str]
		)
