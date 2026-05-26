extends Node
## DataService.gd — Die Datenbank des Spiels

const TREES = {
	"oak": {
		"label": "Eiche fällen",
		"xp": 50, 
		"time": 3.5, 
		"drop": "oak_log"
	},
	"birch": {
		"label": "Birke fällen",
		"xp": 20, 
		"time": 2.0, 
		"drop": "birch_log"
	}
}

const PLAYER_BASE_STATS = {
	"speed": 6.0,
	"gravity": 12.0,      # Wichtig für den Player-Manager
	"jump_force": 4.5,
	"interact_range": 4.0
}

# Hilfsfunktion: Gibt einen Baum-Datensatz zurück oder einen Standardwert
func get_tree_data(type: String) -> Dictionary:
	if TREES.has(type):
		return TREES[type]
	return {"label": "Baum", "xp": 10, "time": 1.0, "drop": "wood"}