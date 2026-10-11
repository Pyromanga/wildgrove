> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-039: Pickpocketing

**Status:** Vorgeschlagen — Entwurf, Round 68 Folge-Session
**Datum:** 2026-07
**Kontext:** Hängt an ADR-030 (Zonen — eigene "Diebes-Zonen") und ADR-038
(Diebstahlschutz-Flag). Unabhängig von den PvP-Zonen-Regeln aus ADR-032.
Neu: `PickpocketService`.

## Problem

Spieler sollen anderen Spielern Gold und Items stehlen können, aber nicht
überall — und nicht gegen theft-geschützte Items (ADR-038).

## Optionen

### Option A: An PvP-Zonen/Regeln koppeln
Diebstahl nur dort erlaubt, wo auch PvP aktiv ist.
- ✅ Wiederverwendung der PvP-Zonen-Logik
- ❌ Vermischt zwei konzeptuell unterschiedliche Bedrohungen — Projektinhaber
  hat explizit eigene Zonenregel gewünscht (Städte etc.), nicht Kopplung an
  PvP-Gebiete

### Option B: Eigener Zonentyp "Diebes-Zone" (gewählt)
Nutzt das generische Zonen-System (ADR-030), aber mit eigenem Tag
(`"theft"`), unabhängig vom `"pvp"`-Tag.
- ✅ Saubere Trennung, Diebes-Zonen können z. B. sichere PvP-Städte sein
- ❌ Erfordert eigene Zonen-Belegung (welche Gebiete sind Diebes-Zonen) —
  laut Projektinhaber aber ohnehin schon inhaltlich vorgesehen

## Entscheidung

Option B. `PickpocketService` (Session-Scope), serverautoritativ:

- Aktion nur verfügbar, wenn Zielspieler sich in einer Zone mit Tag
  `"theft"` befindet (ADR-030-Konsument)
- Stehlbar: Gold **und** Items, außer solche mit `is_theft_protected == true`
  (ADR-038)
- Interaktion läuft über das bestehende Interaktionssystem (ADR-020),
  Ergebnis (Erfolg/Fehlschlag, gestohlene Menge) wird ausschließlich
  serverseitig gewürfelt/bestimmt — Absicht-statt-Wert-Muster (ADR-004)

### Entscheidung: Diebstahl-Kristalle + Skill-Formel

**Auslöse-Item statt reiner Aktion:** Ein Diebstahlversuch braucht ein
verbrauchbares Item — einen **Diebstahl-Kristall** — in drei Stärkestufen
(schwach/normal/stark). Kein Kristall im Inventar = keine
Pickpocket-Interaktion möglich. Jeder Kristall wird bei Benutzung verbraucht
(ein Versuch pro Kristall), unabhängig von Erfolg/Fehlschlag.

Die Kristallstufe bestimmt zwei Dinge gleichzeitig:

| Kristall | Cooldown gegen dasselbe Opfer | Erfolgschance-Bonus |
|---|---|---|
| Schwach | 1 Sekunde | ~+5 % |
| Normal | 1 Minute | ~+10 % |
| Stark | 24 Stunden | ~+20 % |

(Prozentwerte sind Platzhalter fürs Balancing, Größenordnung ist aber
festgelegt.) Das ergibt einen echten Trade-off: der starke Kristall gibt den
größten Schub, sperrt den Täter aber 24h gegen genau dieses Opfer.

**Skill-basierte Grundchance:** Sowohl Täter als auch Opfer haben einen
eigenen `Diebstahl`-Skill (neuer Eintrag im bestehenden `SkillSystem`/
`SkillDefinition`-Muster, keine Sonderarchitektur nötig). Opfer-Skill wirkt
als passive Verteidigung gegen den Täter-Skill (genaue Verrechnungsformel
noch offen, siehe unten). Der Skill ist **uncapped** (`max_level = -1` —
im bestehenden `SkillDefinition`-Schema bereits als Fall vorgesehen, siehe
`get_xp_required()`/`max_level`-Doku im Code).

**Meilenstein-Kurve für Mehrfach-Diebstahl** (effektives Level nach
Verrechnung mit Opfer-Verteidigung):
- Ab Level **100**: 100 % Chance, **1** Item zu stehlen
- Ab Level **1.000**: 100 % Chance, **2** Items zu stehlen
- Ab Level **10.000**: 100 % Chance, **3** Items zu stehlen
- Muster: Schwelle für `N` Items = `100 × 10^(N-1)` — bewusst endloses
  Grind-Design, kein hartes Cap

**Lineare statt exponentieller XP-Kurve:** Das bestehende
`SkillDefinition.xp_scaling_factor` (Standard `1.5`, exponentiell wie
RuneScape) muss für den `Diebstahl`-Skill auf **`1.0`** gesetzt werden —
das ergibt konstante XP pro Level. Das ist bereits heute rein
**datengetrieben lösbar** (eine neue `.tres`-Ressource,
`xp_scaling_factor = 1.0`, `xp_to_level_up = [<konstanter Wert>]`,
`max_level = -1`) — **kein Code-Umbau am `SkillSystem` nötig**, da die
Extrapolationsformel (`base × scaling_factor^overflow`) mit Faktor 1.0
automatisch linear wird.

**Verrechnungsformel (Vorschlag, zur Bestätigung):** `effektives_level =
max(0, täter_level - opfer_level)` — Opfer-Skill wirkt als direkter Abzug
vom Täter-Level, kein komplexeres Verhältnis. Jede Item-Stufe bekommt ihre
eigene lineare Rampe zwischen den Meilensteinen (0 % am unteren Ende, 100 %
am oberen):

- **1. Item:** `chance_1 = clamp(effektives_level / 100, 0%, 100%)` —
  linear von Level 0 (0 %) bis Level 100 (100 %)
- **2. Item:** `chance_2 = clamp((effektives_level − 100) / 900, 0%, 100%)`
  — linear von Level 100 (0 %) bis Level 1.000 (100 %), erst relevant
  nachdem Item 1 schon (nahezu) sicher ist
- **3. Item:** `chance_3 = clamp((effektives_level − 1.000) / 9.000, 0%,
  100%)` — linear von Level 1.000 bis Level 10.000, gleiches Muster

Kristall-Bonus (+5/10/20 %) wird additiv auf `chance_1` angewendet
(gedeckelt bei 100 %) — gibt niedrigstufigen Dieben mit gutem Kristall
einen spürbaren, aber nicht garantierten Schub.

🔸 Reiner Vorschlag, keine endgültige Balance-Entscheidung — wird beim
tatsächlichen Balancing ohnehin nochmal angefasst, aber liefert eine faire,
konsistente Ausgangsbasis statt einer Wissenslücke.

### Diebstahl-Kristall-Herkunft
Über einen **Shop-NPC** erhältlich. Dafür wird vermutlich ein eigenes
"NPC-Shop-System"-ADR nötig — nicht Teil dieses ADRs, aber als klarer
Folge-Bedarf festgehalten (betrifft dann vermutlich auch die
Scroll-Beschaffung aus ADR-038).

### XP-Vergabe
XP wird bei **jedem** Versuch vergeben — Erfolg und Fehlschlag. Bei Erfolg
gibt es den **Löwenanteil** der XP, bei Fehlschlag nur einen kleinen
Trostbetrag. 🔸 Genaues Verhältnis (z. B. Fehlschlag = 10–20 % der
Erfolgs-XP) ist Balancing-Feintuning, nicht Teil dieser Entscheidung.

### Notification
Sofortige Systemnachricht ans Opfer bei **jedem** Versuch — Erfolg wie
Fehlschlag, keine Unterscheidung.

## Konsequenzen

### Positiv
- Saubere Trennung von PvP- und Diebstahl-Zonen erlaubt unabhängiges
  Weltdesign (z. B. eine PvP-freie Stadt, die trotzdem Diebes-Zone ist)
- Wiederverwendung von Zonen-System, Interaktionssystem und
  Diebstahlschutz-Flag statt Neubau

### Negativ / Risiken
- Verrechnungsformel ist ein Vorschlag, kein final gesetzter Wert — echtes
  Balancing steht noch aus (aber strukturell nicht blockierend)
- Kristall-Herkunft hängt an einem noch zu schreibenden NPC-Shop-ADR

### Mitigationen
- Kristallstufen-Cooldown (1s/1min/24h je nach Stärke) begrenzt
  Missbrauch bereits strukturell, unabhängig vom Formel-Feintuning
- Verrechnungsformel liefert eine faire, in sich konsistente
  Ausgangsbasis statt einer Wissenslücke — Anpassung ist ein reiner
  Zahlen-Tuning-Vorgang, keine Architektur-Änderung

## Ablösung

Kein Ablösungsbedarf für dieses ADR selbst. Erwarteter **Folge-ADR**:
NPC-Shop-System (Kristall-Beschaffung hier, vermutlich auch
Scroll-Beschaffung aus ADR-038) — noch nicht geschrieben, aber als
bekannter nächster Schritt festgehalten.

## Umsetzungsstand (Round 93)

`PickpocketService` ist umgesetzt und vollständig verdrahtet, inklusive
Skill, Kristall-Items und der drei Kontextmenü-Aktionen am Ziel-Spieler.

### `PickpocketService` (`scripts/entities/theft/PickpocketService.gd`)
- Formel 1:1 aus dem ADR-Vorschlag übernommen: `effektives_level = max(0,
  täter_level - opfer_level)`, drei lineare Rampen zwischen den
  Meilenstein-Leveln 100/1.000/10.000, Kristall-Bonus additiv auf chance_1.
  Alle konkreten Zahlen (Bonus-%, XP-Beträge, Gold-Diebstahl-Anteil) sind wie
  in der ADR selbst als Platzhalter markiert.
- **Sicherheits-Muster identisch zu ADR-038:** der Kristall-Tier wird
  ausschließlich serverseitig aus `ItemDefinition.pickpocket_crystal_tier`
  gelesen, nicht vom Client übergeben.
- **Zonen-Kopplung:** geprüft wird die Zone DES OPFERS (nicht des Täters) —
  `PickpocketService._victim_in_theft_zone()` löst die peer_id des Opfers
  auf und fragt `ZoneService.has_tag(peer_id, &"theft")`.
- **"Ein Item stehlen"** — Interpretationsentscheidung (ADR spezifiziert
  nicht, was eine gestohlene "Einheit" ist): jeder erfolgreiche Steal-Slot
  entfernt entweder eine kleine Gold-Quote (`STEAL_GOLD_FRACTION`) oder genau
  1 Stück eines zufällig gewählten, nicht-diebstahlgeschützten Item-Stacks —
  nie einen ganzen Stack. Bewusst konservativ, dokumentierter Platzhalter.
- **Kristall-Verbrauch + Cooldown vor der Erfolgsberechnung:** wie in der
  ADR gefordert ("unabhängig von Erfolg/Fehlschlag") — beide werden gesetzt,
  BEVOR überhaupt gewürfelt wird.
- **Cooldown-Persistenz** (paar-basiert, analog `AuraService`) — ohne das
  wäre der 24h-Cooldown der starken Kristallstufe über einen Server-Neustart
  umgehbar.
- Nur `is_theft_protected` (ADR-038) schließt Items vom stehlbaren Pool aus
  — die anderen beiden Schutzkategorien sind für Diebstahl irrelevant.

### Skill + Items
- `data/skills/pickpocketing.tres`: `max_level = -1`, `xp_scaling_factor = 1.0`
  — rein datengetrieben, kein `SkillSystem`-Code-Umbau nötig, exakt wie im
  ADR unter "Lineare statt exponentieller XP-Kurve" gefordert.
- Drei Kristall-Items (`TheftCrystal{Weak,Normal,Strong}.tres`) über das
  neue `ItemDefinition.pickpocket_crystal_tier`-Feld — normale, stapelbare
  Items, keine Sonderklasse (analog ADR-038-Scrolls). Beschaffung bewusst
  nicht Teil dieser Runde (siehe ADR "Ablösung" — eigener Folge-ADR für
  NPC-Shops).

### `PlayerPickpocket` (`scripts/entities/theft/PlayerPickpocket.gd`)
- **Drei feste Kontextmenü-Aktionen statt Auswahl-UI** — anders als
  ADR-038s Scrolls (dort ist das Ziel ein Item im EIGENEN Inventar, in
  derselben Liste wie das Scroll) sind hier Kristall-Wahl UND Ziel
  (ein anderer Spieler) zwei unabhängige Dinge. `pickpocket_weak/normal/
  strong` erscheinen zusammen mit `attack_player`/`trade_request`/
  `thank_player` im bestehenden Kontextmenü (`ContextMenuController`) — alle
  drei bleiben sichtbar, auch ohne den passenden Kristall im Inventar
  (Server entscheidet, analog `attack_player` unabhängig von ausgerüsteter
  Waffe).

### Einheitlicher Einstiegspunkt (Korrektur während der Umsetzung)
Beim Nachverfolgen des tatsächlichen Trigger-Pfads (Kontextmenü →
`InteractableComponent._handle_completion()` → `WorldService.
request_entity_interaction()` → derselbe `_on_interacted()`-Hook läuft auf
der Autorität erneut) fiel auf, dass dieser Pfad das Client→Autorität-
Routing bereits GENERISCH selbst übernimmt — `request_pickpocket()` wäre
dadurch fast ungenutzt geblieben, weil `Player._on_pickpocket_requested()`
zunächst direkt `on_pickpocket_confirmed()` aufrief. Korrigiert: `Player.
_on_pickpocket_requested()` ruft jetzt `request_pickpocket()` auf (den
öffentlichen Einstiegspunkt), nicht `on_pickpocket_confirmed()` direkt —
konsistent mit `ItemProtectionService.request_apply_protection()`. Der
Netzwerk-Zweig in `request_pickpocket()` greift von diesem einen Aufrufer
aus zwar praktisch nie (`_on_pickpocket_requested()` läuft erst nach einem
`is_multiplayer_authority()`-Guard, ist an der Stelle also immer schon
Autorität), aber `request_pickpocket()` bleibt dadurch die EINE öffentliche
API-Methode für einen künftigen zweiten Aufrufer (z.B. ein UI-Panel-Trigger
ohne `InteractableComponent`), statt zwei verschiedene Einstiegspunkte mit
unterschiedlichen Garantien nebeneinander zu haben. Dieselbe Korrektur wurde
bei der Gelegenheit an `AuraService.request_thank()` aus Round 91
nachgezogen (`Player._on_thank_requested()` rief dort ebenfalls
`on_thank_confirmed()` direkt auf).

### Nicht Teil dieser Runde
- ~~Kristall-Beschaffung (Shop/Loot/Crafting) — siehe ADR "Ablösung", eigener
  Folge-ADR.~~ **Erledigt Round 94, siehe unten — kein eigenes Folge-ADR
  nötig, siehe dortige Begründung.**

## Update (Round 94) — Kristall-Beschaffung über ShopService

Die im "Ablösung"-Abschnitt angekündigte Beschaffung ist umgesetzt, aber
**ohne** neues ADR/Service: der bestehende `ShopService` (Round 88) bietet
bereits exakt den benötigten Mechanismus (Gold gegen Katalog-Item,
netzwerksicher, serverseitig neu validiert) — die drei Kristall-Items sind
normale, stapelbare Items ohne Sonderlogik im Kauf selbst, ebenso wie die
ADR-038-Scrolls. Alle drei `TheftCrystal{Weak,Normal,Strong}`-Items sind
jetzt in `ShopService.BUY_CATALOG` gelistet (15/60/400 Gold, gestaffelt nach
`PickpocketService.TIER_BONUS`/`TIER_COOLDOWN_SEC` — der teure "strong"-Preis
spiegelt den 24h-Cooldown, nicht nur den Bonus). Preise sind, wie alle
anderen Balance-Werte in diesem ADR, dokumentierte Platzhalter. Siehe
ADR-038 "Update (Round 94)" für die parallele Scroll-Beschaffung (derselbe
Commit, dieselbe Katalog-Erweiterung). Kein Produktivcode außerhalb der
Katalog-Konstante geändert. Tests: `tests/unit/test_shop_service.gd` (neue
Preis-/Kauf-Fälle für alle sechs neuen Katalog-Einträge).
- Kein UI-Feedback-Overlay für den Täter selbst (nur das Opfer bekommt eine
  Systemnachricht, wie in der ADR gefordert) — der Täter sieht das Ergebnis
  aktuell nur indirekt über sein verändertes Inventar/Gold.

Tests: `tests/unit/test_pickpocket_service.gd` (neu — Erfolg/Fehlschlag über
Level-Extremfälle deterministisch erzwungen statt echtem RNG zu vertrauen,
um Flakiness zu vermeiden). **Ehrlich offen:** wie bei Round 89–92 — kein
Godot-Editor/Headless-Runner in dieser Entwicklungsumgebung verfügbar, alles
nur strukturell geprüft. Einmal im Editor testen. Damit ist der ursprünglich
geplante Item-Schutz/Tod-Verlust/Diebstahl-Dreiklang (ADR-036/037/038/039)
vollständig umgesetzt.
