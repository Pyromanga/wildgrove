class_name StateValidator

## GameConfig ist seit GameManager.configure() ein deps.require()-Pflicht-Dep —
## null kann hier strukturell nicht mehr ankommen, außer die DI ist kaputt.
## In dem Fall fail-loud statt fail-open: eine State-Machine, die bei fehlender
## Config JEDEN Übergang stillschweigend erlaubt, maskiert genau den Bug, den sie
## verhindern soll. Siehe GameManager.change_state() für den einzigen Call-Site.
static func is_transition_allowed(
	from: GameEnums.State, to: GameEnums.State, config: GameConfig
) -> bool:
	if not config:
		AppLogger.log_error(
			"is_transition_allowed(): config ist null — DI kaputt? Übergang wird verweigert (fail-closed).",
			"StateValidator"
		)
		return false

	var from_str: String = str(GameEnums.State.keys()[from])
	var to_str: String = str(GameEnums.State.keys()[to])

	# Kein Cast zu Array[String] — Godot 4 speichert Dictionary-Werte aus .tres
	# als ungetyptes Array. Der Cast "as Array[String]" würde silent nil zurückgeben.
	var allowed: Array = config.valid_transitions.get(from_str, [])

	if not to_str in allowed:
		AppLogger.log_warn("Ungültiger Übergang: %s -> %s" % [from_str, to_str], "StateValidator")
		return false

	return true
