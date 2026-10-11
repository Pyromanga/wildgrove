# ADR-051 — NPC-Dialog: mehrere gleichzeitige Quest-Stränge & Gesprächsoptionen

**AMENDMENT (2026-10):** Das Slot-System (Stufe 1/2: `QuestNPCDialogController`,
`add_independent_slot`, `_add_extra_quest_slot`) wurde ENTFERNT. Es gibt nur noch
EIN Dialogsystem: `DialogueTreeController` (Stufe 3). Stufe-1/2-Beschreibungen
unten sind historisch. Siehe `docs/architecture-hygiene.md`.

**Status:** Proposed — Stufe 1 + Stufe 2 + Stufe 3 UMGESETZT (2026-09-26/27,
Code + Tests, siehe Konsequenzen-Abschnitt unten).
`adr_tool.py` zeigt dieses ADR weiterhin als `unverified`, weil es kein
eigenes Check-/Build-Script gibt, das die Slot-Mechanik strukturell verifiziert
(nur GUT-Unit-Tests, siehe `docs/manager/MANAGER.md` §3: reine Tests zählen
dort nicht als "Script-enforced" im ADR-Tool-Sinn — das ist erwartet, kein
Fehler).

**Datum:** 2026-09-26

**Bezug:** `TODO-offene-probleme.md` § "NPC-Dialog kennt nur EINEN Quest-
Strang gleichzeitig"; betrifft `QuestNPC.gd`,
`scripts/progression/quests/ui/QuestNPCDialogController.gd`,
`QuestService.gd`, `QuestObjectiveHandler.gd`; als Fallbeispiele bereits
beobachtet an `WoodcutterNPC.gd`, `MinerNPC.gd`, `HerbalistNPC.gd`,
`WudangMasterNPC.gd`, `AncestorSpiritNPC.gd`, `GuardNPC.gd`.

---

## Kontext

Jede bisherige Quest-NPC-Subklasse (`MinerNPC`, `HerbalistNPC`,
`WoodcutterNPC`, `WudangMasterNPC`, `AncestorSpiritNPC`, `GuardNPC`) folgt
demselben, in `QuestNPCDialogController.gd` fest kodierten Muster:

- **Ein** `_quest_id` + **ein** optionaler `_next_quest_id` (2-Schritt-Kette,
  siehe dortiger Klassenkommentar "YAGNI statt N-Ketten-Struktur").
- Drei Zustände (`HAS_QUEST` / `QUEST_ACTIVE` / `QUEST_DONE`), linear
  durchlaufen. Sobald `QUEST_DONE` erreicht ist (und `next_quest_id` leer
  oder ebenfalls abgeschlossen ist), bleibt der NPC für immer bei seinem
  `dialog_completed_text` — unabhängig davon, was anderswo im Spiel gerade
  quest-technisch mit diesem NPC zu tun hat.
- **Eine** Label3D-Sprechblase pro NPC, kein Auswahlmenü — der Spieler klickt
  einmal auf "Interagieren", es passiert das, was der aktuelle State
  vorschreibt. Keine Verzweigung, keine Wahl.

**Was schon (zufällig) funktioniert, aber nicht sichtbar ist:** `TALK`-
Objectives (`QuestObjectiveHandler.resolve_talk()`) hängen NICHT am
Dialog-State-Objekt des NPCs, sondern an einem globalen `npc_talked_to`-
Signal, das bei JEDER Interaktion mit dem NPC feuert — unabhängig davon, ob
der NPC "seinen eigenen" Quest gerade anbietet. Deshalb kann
`quest_babatunde_tale` verlangen "sprich mit Erik", ohne dass `WoodcutterNPC`
selbst je davon erfährt: Erik zeigt weiterhin nur seinen eigenen Text, aber
im Hintergrund zählt das Gespräch trotzdem für Babatundes Quest. Das ist der
Mechanismus, der die aktuellen Ketten überhaupt erst querverweisbar macht —
er ist aber unsichtbar für den Spieler (Erik "weiß" im Dialog nichts von
Babatunde) und würde bei einer echten Kollision (zwei AKTIVE Quests, die
BEIDE denselben NPC als Hauptgeber wollen) nicht mehr reichen, weil dann
zwei verschiedene `dialog_offer_text`/`dialog_completed_text` um dieselbe
eine Sprechblase konkurrieren würden.

## Problem

Zwei konkrete, vom Nutzer benannte Lücken:

1. **"Mehrere Quests gleichzeitig von derselben Person."** Ein NPC kann
   aktuell nur EINEN Strang gleichzeitig aktiv führen. Ein NPC, der
   thematisch mehrere unabhängige Aufgaben anzubieten hätte (z.B. Talia
   könnte parallel sowohl die Diebstahlgeschichte als auch — rein
   hypothetisch — eine zweite, unabhängige Wächter-Aufgabe anbieten), müsste
   dafür entweder in zwei NPC-Instanzen aufgespalten werden (unschön,
   bricht die "eine Person, mehrere Anliegen"-Illusion) oder wartet, bis
   Strang 1 fertig ist, bevor Strang 2 überhaupt sichtbar wird (aktuelles
   Verhalten von `next_quest_id`).

2. **"Ein Schritt, wo man mit einem ANDEREN NPC reden muss, sollte dafür
   sorgen, dass der NPC mehrere Sprachmöglichkeiten hat."** Aktuell: nein.
   Der Ziel-NPC eines fremden TALK-Objectives zeigt nach wie vor nur seinen
   eigenen, unveränderten Text — es gibt keine Rückmeldung im Dialog selbst
   ("ah, du kommst wegen Talias Sache"), keine Auswahl zwischen "über meine
   eigene Aufgabe reden" und "worüber ich sonst noch Bescheid weiß".

Beides läuft auf dieselbe strukturelle Lücke hinaus: **die Sprechblase
zeigt einen State, keine Liste von Optionen.**

## Entscheidung

Kein Big-Bang-Rewrite. Drei unabhängig auslieferbare Stufen, jede für sich
spielbar und nutzbar, damit nicht erst die ganz große Lösung fertig sein
muss, bevor irgendein sichtbarer Fortschritt existiert (gleiche Denkweise
wie ADR-050s Phasenplan). Reihenfolge ist bewusst so gewählt, dass jede
Stufe die Datenstruktur der nächsten bereits vorwegnimmt, statt sie später
migrieren zu müssen.

### Stufe 1 (klein) — mehrere Quest-Slots pro NPC, weiterhin einzelne Sprechblase — **UMGESETZT**

**Tatsächliche Umsetzung (2026-09-26):** `QuestNPCDialogController` bekam
zusätzlich zum bestehenden Primär-Strang (`_quest_id`/`_offer_text`/...,
unverändert) eine `Array[ExtraSlot]` (neue innere Klasse `ExtraSlot`: eigener
`quest_id`, `obj_id`, `required`, Dialog-Texte, eigener `state`,
`obj_progress`, optionale eigene 2-Schritt-Kette). Neue Methode
`add_independent_slot(...)` registriert einen Slot; `QuestNPC.gd` bekam das
Gegenstück `_add_extra_quest_slot(...)`, das Subklassen in ihrem `_init()`
aufrufen (analog zu bestehenden `next_quest_id`-Zuweisungen).

`on_interact()` wählt bei Priorität "aktiv vor anbietbar vor erledigt" zuerst
unter Primär-Slot und allen Extra-Slots — bei leerem `_extra_slots` ist der
Codepfad byte-identisch zum alten `match state: ...`-Verhalten (keine der 6
bestehenden NPC-Subklassen oder ihrer Tests mussten geändert werden).
`on_quest_completed()`/`on_extra_objective_updated()`/`has_quest_id()`
routen entsprechend pro Slot. Wichtiger Fund dabei: `on_objective_updated()`
brauchte für Extra-Slots eine EIGENE Methode (`on_extra_objective_updated`,
mit `obj_id`-Parameter) statt die bestehende zu erweitern — sonst hätte ein
Quest mit mehreren Objectives (z.B. `quest_talia_investigation`, 4
Objectives) bei jedem Nebenschauplatz-Objective fälschlich den angezeigten
Fortschritt des getrackten Haupt-Objectives überschrieben.

**Nicht Teil dieser Stufe (bewusst):** kein Auswahlmenü — bei mehreren
gleichzeitig ansprechbaren Slots gewinnt einer nach fester Priorität, der
Spieler sieht nur diesen einen. Das ist exakt die Lücke, die Stufe 2 schließt.

**Tests:** `test_quest_npc_dialog_controller.gd` (11 neue Fälle: Slot-Zählung,
unabhängiger Fortschritt, obj_id-Filterung, eigene Kette pro Extra-Slot,
`has_quest_id()`, "alle Slots durch"-Fallback) + `test_quest_npc.gd` (2 neue
Fälle über eine Test-Subklasse `TwoSlotNPC`, die die volle Verdrahtung bis
in den Dialog-Controller prüfen). Kein Godot-Runtime-Lauf verfügbar (siehe
übliche Einschränkung dieser Sandbox) — nur strukturell/Syntax geprüft
(`check_gdscript_syntax.py`, alle 531 `.gd`-Dateien grün), nicht gegen GUT
selbst ausgeführt.

### Stufe 2 (mittel) — Auswahlliste, wenn mehr als ein Slot ansprechbar ist — **UMGESETZT**

**Tatsächliche Umsetzung (2026-09-26):** Neue Klasse `NPCDialogueChoiceUI`
(CanvasLayer, eigenständig, kein HUD-/IUIContext-Coupling wie
`ContextMenuController` — bewusst so simpel wie möglich, gleiches
Grundprinzip wie `AdminPanelUI.gd`) zeigt eine Liste von Buttons, wenn
`QuestNPCDialogController.on_interact()` mehr als einen aktuell ansprechbaren
(ACTIVE oder HAS_QUEST) Slot findet. Neue Methode `set_choice_ui_factory()`
(Callable statt fixer Klassenreferenz — hält den Controller testbar mit
leichtgewichtigen Fakes, kein echter Node nötig, siehe
`test_quest_npc_dialog_controller.gd` `FakeChoiceUI`). `QuestNPC.on_spawn()`
verdrahtet die Factory für JEDEN NPC automatisch — sie greift ohnehin nur,
wenn tatsächlich mehr als ein Slot ansprechbar ist, alle 6 bestehenden
NPC-Subklassen bleiben dadurch unverändert (weiterhin nur ein Slot → nie ein
Menü, exakt Stufe-1-Verhalten als Fallback in `_auto_pick_and_show()`).

**Kurzbeschriftung ohne neuen Pflichtparameter:** statt Autor:innen zu
zwingen, für jeden Slot eine eigene Menü-Beschriftung zu schreiben, leitet
`_derive_topic_label()` sie automatisch aus der ersten Zeile des ohnehin
vorhandenen Angebots-/Encourage-Texts ab (gekürzt auf 32 Zeichen). Jede
künftige `add_independent_slot()`-Registrierung bekommt die Auswahlliste
dadurch "gratis", ohne API-Änderung an Stufe 1.

**Nicht Teil dieser Stufe (bewusst):** kein Reagieren auf FREMDE Quests
(Talia bietet weiterhin nur ihre eigenen Slots an, nicht "worüber der
Spieler bei Babatunde gerade redet") und keine mehrstufigen Verzweigungen
innerhalb EINER Auswahl — das bleibt Stufe 3.

**Tests:** `test_quest_npc_dialog_controller.gd` (6 neue Fälle: kein Menü bei
genau einem Slot trotz gesetzter Factory, Stufe-1-Fallback ohne Factory,
Menü-Erzeugung bei 2 Slots, State bleibt bis zur Auswahl unverändert, Wahl
von Index 0/1 löst den richtigen Slot aus, Label-Ableitung aus erster Zeile)
+ `test_quest_npc.gd` (1 neuer Fall: `on_spawn()` setzt immer eine gültige
Factory). Wie bei Stufe 1 nur strukturell/Syntax geprüft (531 `.gd`-Dateien
grün über `check_gdscript_syntax.py`), kein echter Godot/GUT-Lauf verfügbar.

### Stufe 3 (groß) — echtes verzweigendes Dialogsystem — **UMGESETZT**

**Tatsächliche Umsetzung (2026-09-27):** Neue Klasse `DialogueTreeController`
(eigenständig neben `QuestNPCDialogController` — ein NPC bekommt GENAU EINEN
der beiden, nie beide, siehe `QuestNPC._build_dialogue_tree()`-Hook, Default
null = weiterhin Slot-System für alle 6 Alt-NPCs). Generische Struktur wie
geplant: `DialogueNode` (id, text, choices) + `DialogueChoice` (label,
next_node_id, optionaler action-Seiteneffekt, optionale condition). Ein
Gesprächsende ist bewusst KEIN Sonderfall, sondern einfach ein Knoten mit
leeren choices — kein separates "end"-Konzept nötig.

**Mehrstufige Verzweigung innerhalb einer Interaktion:** `_show_node()` ruft
nach einer Auswahl direkt wieder sich selbst für den nächsten Knoten auf —
mehrere Frage/Antwort-Runden laufen dadurch in einem einzigen
Interaktions-Aufruf ab, nicht mehr "eine Sprechblase pro Klick".

**Reaktion auf FREMDE Quests — der eigentliche Kernpunkt:** condition-Strings
(`"quest_completed:<id>"`, `"quest_active:<id>"`, `"quest_not_completed:<id>"`,
`"quest_not_active:<id>"`) werden gegen eine echte `QuestService`-Instanz
ausgewertet, nicht gegen die eigenen Slots des NPCs. Dafür war ein neuer
Lesezugriff nötig, der vorher fehlte: `IEntityContext.get_quest_service()`
(+ `EntityContext`/`EntityOrchestrator`/`WorldService`-Durchreichung über
`ServiceKeys.QUEST`, exakt demselben Muster wie die zehn anderen
`get_optional(ServiceKeys....)`-Zeilen in `WorldService.configure()`). Ohne
gesetzten QuestService gilt jede nicht-leere Bedingung als "nicht erfüllt"
(sicherer Default) statt zu crashen.

**Demo statt Umbau einer lebenden Quest:** `VillageElderNPC.gd` ("Dorfältester
Rasmus") ist ein NEUER, eigenständiger NPC statt einer Umstellung von Talia/
Wei/Babatunde auf Bäume — eine bereits funktionierende, getestete Slot-Kette
in eine Baum-Struktur umzubauen wäre reines Regressions-Risiko ohne
zusätzlichen Erkenntniswert gewesen. Rasmus reagiert stattdessen auf
`quest_babatunde_tale` (Abschluss-Status), ohne diese Quest selbst zu
vergeben oder zu tracken — genau das im Kontext-Abschnitt oben beschriebene
Zielbild.

**Wiederverwendet statt neu gebaut:** die Auswahl-UI ist exakt
`NPCDialogueChoiceUI` aus Stufe 2 (dieselbe Factory/Callable-Injection);
deren `present()` bekam dafür einen optionalen dritten `title`-Parameter
(Default = Stufe 2s generische Frage, damit der bestehende 2-Argumente-
Aufruf aus Stufe 2 unverändert weiterläuft) für den tatsächlichen
NPC-Sprechtext als Überschrift.

**Bewusst NICHT Teil dieser Stufe:** kein Content-Forge-Schema für
Dialogbäume — Bäume werden wie die Slot-Texte aus Stufe 1/2 in GDScript
über `_init()`/`_build_dialogue_tree()`-Aufrufe autorisiert, nicht als
`.tres`-Ressourcen. Das folgt demselben bereits etablierten Muster dieses
Projekts (Quest-MECHANIK ist `.tres`/content-forge-verwaltet, NPC-
DIALOGTEXT ist immer schon Code) und ist eine bewusste Vereinfachung
gegenüber der ursprünglich in ADR-051 skizzierten Idee, keine Lücke.

**Tests:** neue `test_dialogue_tree_controller.gd` (13 Fälle: Navigation,
Mehrstufigkeit, Auswahl-UI-Titel, Fallback ohne Factory, `start_quest`-
Action, vier condition-Fälle GEGEN EINE ECHTE `QuestService`-Instanz nach
demselben Muster wie `test_quest_custom_trigger.gd`, sicherer Default ohne
QuestService) + 5 neue Fälle in `test_quest_npc.gd` (Hook-Default null,
Slot-System bleibt bei Tree-NPCs komplett unbenutzt, kein Crash bei
unabhängigen Quest-Signalen, Routing in `_on_interacted()`). Wie bei Stufe
1/2 nur strukturell/Syntax geprüft, kein echter Godot/GUT-Lauf verfügbar.

## Nachtrag (2026-09-27/28): alle 6 Alt-NPCs konvertiert + Scaffold-Tool

Nach Abschluss von Stufe 3 wurden auch die 6 ursprünglichen Slot-System-NPCs
(`MinerNPC`, `HerbalistNPC`, `WoodcutterNPC`, `WudangMasterNPC`,
`AncestorSpiritNPC`, `GuardNPC`) auf `DialogueTreeController` umgestellt —
für Konsistenz (ein Projekt, ein Dialog-Mechanismus) und weil es einen
echten Mehrwert gibt: `GuardNPC` (Talia) bekam dabei ihr erstes dauerhaft
sichtbares 2-Themen-Menü ("Der Dieb im Pelz" / "Friedhofswache", siehe
`quest_talia_graveyard_watch` — zwischenzeitlich über die Stufe-1-Extra-Slot-
Mechanik an sie gehängt, jetzt sauber als zweiter Unterbaum im selben Tree).

**Neuer Baustein `DialogueTreeController.build_quest_giver()`:** eine
statische Factory, die aus denselben kompakten Parametern wie vorher
`QuestNPCDialogController.set_next_quest()` einen vollständigen
Standard-Questgeber-Baum baut (offen → annehmen → Live-Fortschritt →
erledigt, optional 2. Stufe) — reproduziert das alte Slot-Verhalten exakt,
inklusive "nie ein Menü für den Normalfall" (dafür war ein neuer
Single-Choice-Autoskip in `_show_node()` nötig: vorher zeigte die Baum-
Engine auch bei genau einem sichtbaren Zweig ein 1-Button-Menü, ein Regression
gegenüber Stufe 1/2). Zwei weitere kleine Engine-Erweiterungen kamen dafür
dazu: UND-verknüpfte Bedingungen (`"cond1,cond2"`, für "weder aktiv noch
abgeschlossen") und Live-Fortschritts-Templating (`DialogueNode.with_progress()`,
Pendant zu `dialog_encourage_format`).

**Neues Tool `scripts/agent/build/quest_npc_scaffold.py`:** automatisiert den
Standardfall (eine Quest-Datei oder feste 2-Stufen-Kette + die passende
`_build_dialogue_tree()`-NPC-Datei) aus einer Spec, die `content_forge.py`
für den Quest-Teil intern wiederverwendet statt Logik zu duplizieren.
Bewusst NICHT automatisiert: die Registrierung in
`WorldEntityRegistry.gd`/`WorldSpawner.gd` — beide Dateien haben keinen
projektweit stabilen Texanker (wiederholt an unterschiedlichen Stellen durch
parallele Terrain-/Pet-/Smithing-Arbeit verändert), ein blind suchendes Tool
würde dort irgendwann an der falschen Stelle einfügen. Das Tool druckt die
zwei nötigen Zeilen stattdessen aus.

Siehe `docs/quest-writing-guide.md` Abschnitt 5 für die aktualisierte
Anleitung.

## Konsequenzen

- **Keine der drei Stufen ist in diesem Schritt umgesetzt.** Dieses ADR ist
  ausschließlich die Konzeptstufe (siehe Status oben) — nächster Schritt ist
  eine bewusste Entscheidung, MIT welcher Stufe tatsächlich begonnen wird
  (das war explizit die Nutzerentscheidung für diese Runde: nur Plan, keine
  Umsetzung).
- Stufe 1 ist rückwärtskompatibel zu allen 6 bestehenden NPC-Subklassen,
  wenn deren Migration mitgeliefert wird (kein Verhalten ändert sich für
  Spieler, die nur einen Slot je NPC sehen — was aktuell 100% der Fälle
  sind).
- Stufe 2 führt neue UI ein, die bisher nirgends im Projekt existiert
  (In-World-Auswahl statt Meta-Werkzeug-Buttons) — eigener Design-/Test-
  Aufwand, unabhängig vom Quest-System selbst.
- Stufe 3 ist eine Grundsatzentscheidung mit erheblichem Umfang (neues
  Content-Format, neue Autoren-Tools) und sollte NICHT nebenbei in einer
  Quest-Content-Runde entschieden werden, sondern verdient eine eigene
  Planungsrunde, wenn es soweit ist.
- **Offen, absichtlich nicht hier entschieden:** ob Stufe 3 die
  Wortwahl/das Datenmodell von RuneScript (RuneScape) 1:1 übernehmen soll
  oder ein eigenes, schlankeres Format — das hängt davon ab, wie viel
  Verzweigungstiefe die tatsächlichen Quests am Ende brauchen, und lässt
  sich erst nach ein paar mit Stufe 1/2 gebauten Quests seriös einschätzen.
