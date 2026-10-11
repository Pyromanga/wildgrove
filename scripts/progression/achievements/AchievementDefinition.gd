class_name AchievementDefinition
extends Resource

## AchievementDefinition — statische Achievement-Daten als .tres-Ressource.
##
## Round 103 (ADR-046 "Umsetzungsstand (Round 103)"): ersetzt/ergänzt die
## in Round 102 fest im Code hinterlegte `AchievementService.
## DEFAULT_DEFINITIONS`-Liste um einen echten, datengetriebenen Workflow —
## exakt dasselbe Muster wie QuestDefinition/ItemDefinition/CombatProfile
## (DataManifest + DataService, siehe dort für die Android-/Export-
## Begründung). `DEFAULT_DEFINITIONS` bleibt zusätzlich als eingebauter
## Fallback bestehen (siehe AchievementService.gd-Klassenkommentar) — .tres-
## Definitionen ERGÄNZEN/ÜBERSCHREIBEN sie, ersetzen sie nicht komplett.
##
## Beispiel-Dateiname: res://data/achievements/first_blood.tres
## id sollte dem Dateinamen ohne .tres entsprechen.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

## Zähler-Ziel — float statt int, damit stat-basierte Achievements
## (Meter gelaufen/gesprungen/gefallen) direkt abbildbar sind, ohne einen
## zweiten Definitionstyp zu brauchen.
@export var target: float = 1.0

@export var category: String = "general"  ## "combat", "economy", "social", "stats", ...

## Easter-Egg-Achievements (siehe AchievementService.gd "EASTER EGGS"): Name/
## Beschreibung bleiben in der UI verborgen ("???"), solange nicht
## freigeschaltet — AchievementPanelVisuals.update_achievement() liest dieses
## Feld. Ändert nichts an Fortschritt/Freischaltung selbst, rein kosmetisch.
@export var hidden: bool = false

## Optionale Gold-Belohnung beim Freischalten (Round 103). 0 = keine
## Belohnung. Kein Item-/XP-Reward-Feld in dieser Runde, siehe
## AchievementService.gd "Bewusst nicht Teil dieser Runde".
@export var reward_gold: int = 0
