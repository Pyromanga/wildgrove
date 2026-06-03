class_name QuestDefinition
extends Resource

## QuestDefinition — statische Quest-Daten als .tres-Ressource.
##
## Wird von DataService beim Boot geladen.
## Enthält NUR Daten — keine Logik.
##
## Beispiel-Dateiname: res://data/quests/quest_tutorial.tres
## id sollte dem Dateinamen ohne .tres entsprechen.

@export var id:           String                 = ""
@export var title:        String                 = ""
@export var description:  String                 = ""
@export var category:     String                 = "main"  ## "main", "side", "daily"

## Objectives in Reihenfolge — alle non-optional müssen erfüllt sein.
@export var objectives:   Array[QuestObjective]  = []

## Belohnung bei Abschluss.
@export var reward:       QuestReward

## Quest-IDs die abgeschlossen sein müssen bevor diese Quest startet.
@export var prerequisites: Array[String]         = []

## Ob die Quest automatisch gestartet wird wenn Prerequisites erfüllt sind.
@export var auto_start:   bool                   = false

## Ob die Quest wiederholbar ist (z.B. Daily Quests).
@export var repeatable:   bool                   = false