extends SettlerNPC
class_name WaterCarrierNPC

## WaterCarrierNPC — Wasserträger am Brunnen. Siehe SettlerNPC.

## Wasserträger kämpfen mit Wassertieren (Pet-Kampf).
func _battle_bias_type() -> int:
	return PetBattleTypes.Type.AQUA

func _role_title() -> String:
	return "Wasserträger"

func _role_gold() -> Vector2i:
	return Vector2i(3, 25)

func _role_lines() -> Array[String]:
	return [
		"Frisches Wasser, kühl und klar. Aus der tiefsten Quelle weit und breit.",
		"Der Brunnen ist älter als das Dorf, sagt man.",
		"Zwei Eimer, ein Weg — mehr braucht es nicht.",
		"Trink nie aus dem Sumpf. Glaub mir.",
	]
