extends ProfessionNPC
class_name BrewerNPC

## BrewerNPC — Beruf "brewer", alle Daten in ProfessionCatalog. Eigenes Skript, weil der
## MultiplayerSpawner Skriptpfad → type_id auflöst (siehe ProfessionNPC).

func _profession_id() -> String:
	return "brewer"
