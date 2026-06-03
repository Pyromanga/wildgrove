class_name BaseUIComponent
extends RefCounted

## BaseUIComponent — Basisklasse für alle HUD-Komponenten.
##
## FIX: build() wurde aus der Basisklasse entfernt.
##
## Das Problem: GDScript erzwingt bei virtuellen Methoden-Overrides exakt
## dieselbe Signatur wie die Parent-Klasse. Da jede Komponente unterschiedliche
## Abhängigkeiten in build() braucht (EventBus, Services, Player, ...) ist eine
## einheitliche Signatur unmöglich ohne auf untypisierte Variants auszuweichen.
##
## Neue Architektur:
##   - Jede Komponenten-Klasse deklariert build() mit ihrer eigenen Signatur,
##     OHNE die Parent-Methode zu überschreiben (kein Override-Konflikt möglich
##     wenn die Basis keine build()-Methode hat).
##   - HUDBuilder ruft build() direkt auf den konkreten Typen auf.
##
## Subklassen können _init() für Dependency Injection nutzen wenn nötig.