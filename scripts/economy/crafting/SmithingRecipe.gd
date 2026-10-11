extends Resource
class_name SmithingRecipe

## SmithingRecipe — datengetriebene Beschreibung EINES Schmelz- oder Schmiede-Rezepts.
##
## Neues Rezept = neue .tres unter data/smithing_recipes/ + Eintrag in
## DataManifest.SMITHING_RECIPES (am besten über content_forge.py, Typ "smithing_recipe").
## Es ist KEIN Code nötig: SmithingService, das Schmiede-Panel und die Tests lesen alles aus
## dieser Resource.
##
## Zwei Stationen (siehe BuildPieceDefinition.station_kind — das Bauteil, an dem das Rezept
## verfügbar ist):
##   STATION_FURNACE (Hochofen): Erz zu Barren schmelzen, Eisen zu Stahl aufkohlen.
##   STATION_ANVIL   (Amboss):   Barren zu Waffen und Rüstung schmieden.
##
## Die Station gehört zum REZEPT, nicht zur Anfrage des Clients. SmithingService liest sie aus
## der Definition — ein Client kann ein Amboss-Rezept also nicht "am Hochofen" auslösen.

const STATION_FURNACE := "furnace"
const STATION_ANVIL   := "anvil"

## Alle gültigen Stationen. Gleiche Strings wie BuildPieceDefinition.station_kind.
const STATIONS: Array[String] = [STATION_FURNACE, STATION_ANVIL]

## Eindeutige Rezept-Id (snake_case, z.B. "smelt_iron", "forge_iron_sword"). Gleichzeitig Dateiname.
@export var id: String = ""

## Anzeigename im Schmiede-Panel (deutsch).
@export var display_name: String = ""

## An welcher Station das Rezept verfügbar ist (STATION_FURNACE | STATION_ANVIL).
@export var station: String = STATION_ANVIL

## Zutaten: { item_id (String): Menge (int) }. Alles wird beim Herstellen verbraucht.
## Brennstoff (Holzkohle) steht hier als normale Zutat — kein eigener Brennstoff-Mechanismus.
@export var inputs: Dictionary = {}

## Ergebnis-Item (item_id) und Menge.
@export var output_item_id: String = ""
@export var output_quantity: int = 1

## Verarbeitungs-Skill dieses Rezepts: bestimmt, wessen Level geprüft (min_level) und wem die XP
## gutgeschrieben werden. Default "smithing" (alle Schmiede-Rezepte, bestehende .tres ohne das
## Feld). Weitere Verarbeitungs-Skills (Kochen, Handwerk ...) nutzen denselben Service: neues
## Rezept mit anderem skill_id + eigener Station — kein neuer Service nötig.
@export var skill_id: String = "smithing"

## Mindest-Level im Skill `skill_id`.
@export var min_level: int = 1

## XP, die das erfolgreiche Herstellen im Skill `skill_id` bringt (vor Ausrüstungs-Bonus).
@export var xp: int = 10

## Werkzeuge, die der Spieler HABEN muss (Item-Ids; im Inventar ODER im Werkzeug-Slot
## ausgerüstet). Sie werden NICHT verbraucht. Hochofen → Zange, Amboss → Hammer + Zange.
@export var required_tools: Array[String] = []

## Wahr, wenn das Rezept an der angegebenen Station verfügbar ist.
func is_available_at(station_kind: String) -> bool:
	return station == station_kind

## Alle Item-Ids, die dieses Rezept berührt (Zutaten, Werkzeuge, Ergebnis) — für
## Konsistenz-Prüfungen in Tests/Tools.
func referenced_item_ids() -> Array[String]:
	var out: Array[String] = []
	for item_id in inputs:
		out.append(String(item_id))
	for tool_id in required_tools:
		out.append(tool_id)
	out.append(output_item_id)
	return out

## Strukturell gültig? (Leere Liste = ok.) Reine Daten-Prüfung ohne Zugriff auf andere
## Ressourcen — ob die referenzierten Items existieren, prüft der Content-Test.
func validation_errors() -> Array[String]:
	var errs: Array[String] = []
	if id.is_empty():
		errs.append("id fehlt")
	if display_name.is_empty():
		errs.append("display_name fehlt")
	if not STATIONS.has(station):
		errs.append("unbekannte Station '%s'" % station)
	if skill_id.is_empty():
		errs.append("skill_id fehlt")
	if inputs.is_empty():
		errs.append("keine Zutaten")
	for item_id in inputs:
		if int(inputs[item_id]) <= 0:
			errs.append("Zutat '%s' hat Menge <= 0" % item_id)
	if output_item_id.is_empty():
		errs.append("output_item_id fehlt")
	if output_quantity <= 0:
		errs.append("output_quantity <= 0")
	if min_level < 1:
		errs.append("min_level < 1")
	if xp < 0:
		errs.append("xp < 0")
	return errs
