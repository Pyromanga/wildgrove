extends Node
## DataService.gd — Die Single-Source-of-Truth

const TREES = {
	"oak": {"label": "Eiche fällen", "xp": 50, "time": 3.5, "drop": "oak_log"},
	"birch": {"label": "Birke fällen", "xp": 20, "time": 2.0, "drop": "birch_log"}
}

const PLAYER_STATS = {
	"speed": 6.0,
	"gravity": 12.0,
	"jump_force": 4.5,
	"interact_range": 4.0
}

## Sicheres Abrufen von Baum-Daten
func get_tree_data(type: String) -> Dictionary:
	return TREES.get(type, {"label": "Baum", "xp": 10, "time": 1.0, "drop": "wood"})

## Sicheres Abrufen von Player-Stats
func get_stat(stat_name: String) -> float:
	return PLAYER_STATS.get(stat_name, 0.0)