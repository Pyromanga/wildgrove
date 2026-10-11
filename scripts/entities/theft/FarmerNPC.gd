extends SettlerNPC
class_name FarmerNPC

## FarmerNPC — Bauer an der Scheune. Siehe SettlerNPC.

func _role_title() -> String:
	return "Bauer"

## Bauern kämpfen mit Huftieren (Pet-Kampf).
func _battle_bias_type() -> int:
	return PetBattleTypes.Type.HOOFED

func _role_gold() -> Vector2i:
	return Vector2i(10, 60)

func _role_lines() -> Array[String]:
	return [
		"Die Möhren stehen dieses Jahr prächtig.",
		"Das Heu muss rein, bevor es regnet.",
		"Füchse und Wildschweine — die fressen mir noch die Ernte weg.",
		"Wer sät, der erntet. Wer klaut, der wird erwischt.",
	]
