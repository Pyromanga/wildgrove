extends ProfessionNPC
class_name SmithNPC

## SmithNPC — Beruf "smith", alle Daten in ProfessionCatalog. Eigenes Skript, weil der
## MultiplayerSpawner Skriptpfad → type_id auflöst (siehe ProfessionNPC).

func _profession_id() -> String:
	return "smith"
