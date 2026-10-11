class_name QuestDefinition
extends Resource

## QuestDefinition — statische Quest-Daten als .tres-Ressource.
##
## Wird von DataService beim Boot geladen.
## Enthält NUR Daten — keine Logik.
##
## Beispiel-Dateiname: res://data/quests/quest_tutorial.tres
## id sollte dem Dateinamen ohne .tres entsprechen.

@export var id: String = ""
@export var title: String = ""
@export var description: String = ""
@export var category: String = "main"  ## "main", "side", "daily"

## Objectives in Reihenfolge — alle non-optional müssen erfüllt sein.
@export var objectives: Array[QuestObjective] = []

## BUGFIX ("Questschritte werden alle sofort angezeigt" / "spätere Schritte
## lassen sich vor früheren abschließen"): es gab bisher GAR KEIN Konzept von
## Reihenfolge — QuestPanelController._build_obj_data() zeigte unconditional
## ALLE def.objectives an (auch Schritt 3, bevor Schritt 1 überhaupt erreicht
## war), und JEDER QuestObjectiveHandler.resolve_*() ließ JEDES passende
## Objective Fortschritt machen, egal ob vorherige Objectives schon fertig
## waren. Stichprobe über alle data/quests/*.tres: JEDE existierende
## Mehr-Objective-Quest ist narrativ sequentiell gemeint (z.B.
## quest_talia_investigation: TALK Mira → SKILL forestry 3 → CUSTOM
## caught_fox → TALK Talia) und es gibt aktuell null `optional = true`
## Objectives — ein sequentieller Default bricht also nichts Bestehendes.
## Wenn eine Quest wirklich "in beliebiger Reihenfolge" sein soll (z.B. ein
## reines Sammel-Quest ohne Story-Abhängigkeit), kann sequential hier pro
## Quest auf false gesetzt werden.
@export var sequential: bool = true

## Belohnung bei Abschluss.
@export var reward: QuestReward

## Quest-IDs die abgeschlossen sein müssen bevor diese Quest startet.
@export var prerequisites: Array[String] = []

## Ob die Quest automatisch gestartet wird wenn Prerequisites erfüllt sind.
@export var auto_start: bool = false

## Ob die Quest wiederholbar ist (z.B. Daily Quests).
@export var repeatable: bool = false
