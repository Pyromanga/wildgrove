extends VillagerNPC
class_name SettlerNPC

## SettlerNPC — zufällig vor Gebäuden stehender, beklaubarer Dorfbewohner (Wunsch
## "Gebäude, die randomly spawnen, mit NPCs"). Gespawnt von ChunkEntitySpawner, siehe
## ChunkStructureBuilder.NPC_TYPE_BY_STRUCTURE.
##
## Baut auf VillagerNPC auf (Taschendiebstahl, Kollision, Körper via NPCVisualBuilder) und
## ergänzt nur Variation: Name, Rolle, Beutel-Inhalt und eine Flavor-Zeile für "Untersuchen".
## Alles wird aus der SPAWN-POSITION abgeleitet (EntityOrchestrator setzt sie VOR add_child,
## siehe dortigen Kommentar) — auf jedem Peer identisch, ohne dass etwas übertragen werden muss.
##
## Subklassen (FarmerNPC, WaterCarrierNPC) überschreiben nur die _role_*-Funktionen. Eigene
## Skriptpfade pro Rolle, weil der MultiplayerSpawner Skriptpfad → type_id auflöst.
##
## Namen meiden bewusst alle Wörter aus NPCLook.PRESETS, sonst bekäme ein Siedler zufällig
## das Aussehen eines Story-NPCs.

const FIRST_NAMES: Array[String] = [
	"Anselm", "Berta", "Cord", "Dörte", "Emil", "Frida", "Gero", "Hanne", "Ida", "Jonas",
	"Katja", "Lenz", "Marta", "Nils", "Olga", "Piet", "Rike", "Sven", "Tilda", "Udo",
	"Vera", "Wiebke", "Yannick", "Zora",
]

func _role_title() -> String:
	return "Siedler"

func _role_gold() -> Vector2i:
	return Vector2i(5, 40)

## Anzeigename aus Vorname + Rolle. Hook für Rollen mit gegenderten Titeln (ProfessionNPC).
func _compose_name(first_name: String) -> String:
	return "%s %s" % [_role_title(), first_name]

func _role_lines() -> Array[String]:
	return [
		"Ruhiges Fleckchen hier. Solange die Goblins wegbleiben.",
		"Das Dach muss vor dem Winter noch dicht werden.",
		"Früher war der Wald noch nicht so nah am Haus.",
		"Wenn du Holz übrig hast — ich bin immer dankbar.",
		"Nachts hört man manchmal Heulen aus dem Dickicht.",
	]

func _ready() -> void:
	# Name + Zeile deterministisch aus der Position; Orchestrator-Name danach zurücksetzen
	# (VillagerNPC._ready() überschreibt ihn, der positionsbasierte ist aber der eindeutige).
	var orchestrator_name: String = name
	var h: int = absi(hash(Vector2i(roundi(position.x * 10.0), roundi(position.z * 10.0))))
	npc_display_name = _compose_name(FIRST_NAMES[h % FIRST_NAMES.size()])
	var gold: Vector2i = _role_gold()
	_gold_min = gold.x
	_gold_max = gold.y
	super._ready()
	name = orchestrator_name
	var lines: Array[String] = _role_lines()
	var line: String = lines[(h / FIRST_NAMES.size()) % lines.size()]
	for child in get_children():
		if child is InteractableComponent and (child as InteractableComponent).data != null:
			(child as InteractableComponent).data.inspect_text = "%s: \"%s\"" % [npc_display_name, line]
