extends ProfessionNPC
class_name CheesemakerNPC

## CheesemakerNPC — Beruf "cheesemaker", alle Daten in ProfessionCatalog. Eigenes Skript, weil der
## MultiplayerSpawner Skriptpfad → type_id auflöst (siehe ProfessionNPC).

func _profession_id() -> String:
	return "cheesemaker"
