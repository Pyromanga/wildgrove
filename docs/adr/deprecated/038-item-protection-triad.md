> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-038: Item-Schutz-Dreiklang (PvE, Diebstahl, PvP)

**Status:** Vorgeschlagen — Entwurf, Round 68 Folge-Session
**Datum:** 2026-07
**Kontext:** Wird von ADR-036 (PvP-Tod-Verlust), ADR-037 (PvE-Tod-Loot) und
ADR-039 (Pickpocketing) konsumiert. Entspricht/absorbiert den ursprünglich
separat geplanten Punkt "Todesschutz (Item-Versicherung)" aus der
ursprünglichen 7-Punkte-Skizze — der PvP-Teil dieses Dreiklangs **ist** jene
Versicherung. Neu: `ItemProtectionService`, Item-Metadata-Erweiterung.

## Problem

Drei unterschiedliche Bedrohungen für Spieler-Besitz brauchen drei
unterschiedlich langlebige Schutzmechanismen — sie in einem einzigen Flag
zu vermischen würde die falschen Lebenszyklen aneinanderketten.

## Optionen

### Option A: Ein einziges universelles "geschützt"-Flag pro Item
- ✅ Einfachstes Datenmodell
- ❌ Kann die drei Lebenszyklen (permanent / permanent / einmalig
  verbrauchend) nicht getrennt abbilden — ein Item wäre entweder gegen alles
  oder gegen nichts geschützt

### Option B: Drei getrennte Schutzarten (gewählt)
- ✅ Bildet die tatsächlich unterschiedlichen Lebenszyklen korrekt ab
- ❌ Drei Datenpunkte statt einem, mehr zu pflegende Logik

## Entscheidung

Wichtige Korrektur gegenüber der ursprünglichen Skizze: Schutz ist **kein
statisches Item-Typ-Flag**, sondern ein **Item-Instanz-Zustand**. Für die
Anwendung selbst standen drei Ideen im Raum (NPC-Menü, Kristall-Interaktion,
Scroll-Item) — sie laufen alle auf dieselbe Service-Aktion hinaus
(`request_apply_protection(item_ref, protection_type)`), unterscheiden sich
aber im "Wie kommt der Spieler an die Anwendung":

### Warum Scrolls die sauberste Wahl sind
Ein **Schutz-Scroll** ist selbst ein normales, stapelbares Item — kein neuer
NPC, keine Dialog-Logik, keine Kristall-Sonderklasse nötig:

- Anwendung läuft über eine "Benutze Item X auf Item Y"-Interaktion (gleiches
  Interaktionsmuster wie bestehende Item-Nutzung, ADR-020), keine neue
  UI-Ebene
- **Löst das offene Kostenmodell-Problem organisch:** ein Scroll muss erst
  hergestellt/gekauft/gefunden werden — die Kosten liegen in der
  Scroll-Beschaffung, nicht in einer separaten Gold-Gebühr am NPC
  obendrauf. Kein doppeltes Kostenmodell nötig.
- **Synergie mit ADR-035 (Trading):** Scrolls sind normale Items — handelbar,
  auktionierbar, ohne Sonderfall im Trading-System
- Drei Scroll-Typen (`scroll_pve_protection`, `scroll_theft_protection`,
  `scroll_pvp_protection`), jeder ruft dieselbe Service-Methode mit
  passendem `protection_type` auf

NPC-Menü/Kristall wären funktional gleichwertig, brauchen aber zusätzliche
Infrastruktur (Dialog-System bzw. neue Interactable-Unterklasse) ohne
architektonischen Mehrwert gegenüber "ist einfach ein Item" — deshalb hier
nicht gewählt, aber jederzeit als zusätzlicher *Vertriebsweg* für dieselben
Scrolls ergänzbar (z. B. ein NPC, der Scrolls verkauft), ohne das
Kern-Modell zu ändern.

Die drei Schutzarten selbst bleiben in ihrem Lebenszyklus wie zuvor
konzipiert:

1. **PvE-Todesschutz** (permanent) — Instanz-Flag `is_pve_death_protected:
   bool`. Bestimmt, was **nie** ins Grab (ADR-037) wandert.
2. **Diebstahlschutz** (permanent) — Instanz-Flag `is_theft_protected: bool`.
   Bestimmt, was **nie** durch Pickpocketing (ADR-039) gestohlen werden
   kann. Unabhängig von Flag 1 — je eigenes Scroll pro Schutzart.
3. **PvP-Schutz** (einmalig verbrauchend) — Instanz-Flag
   `is_pvp_protected: bool`, wird nach genau **einem** auslösenden
   PvP-Tod-Ereignis (ADR-036) automatisch auf `false` zurückgesetzt — der
   Spieler braucht ein neues Scroll, um es erneut anzuwenden.

`ItemProtectionService` kapselt sowohl die Anwendung
(`request_apply_protection(item_ref, protection_type)`, serverautoritativ,
konsumiert das Scroll bei Erfolg) als auch die Abfrage
(`is_protected_from(item_ref, threat_type)`), damit ADR-036/037/039 nicht
jeweils eigene Zugriffe bauen.

**Entschieden:** PvE-/Diebstahlschutz kleben permanent am Item, sobald
einmal gesetzt — kein Rückgängigmachen. Ein Scroll auf ein "falsches" Item
anzuwenden ist damit eine endgültige Entscheidung (erhöht den Wert eines
bewusst gewählten Ziel-Items für den Scroll).

## Konsequenzen

### Positiv
- Klare, unabhängige Lebenszyklen statt eines überladenen Flags
- Ein zentraler Abfragepunkt (`ItemProtectionService`) für alle drei
  konsumierenden ADRs

### Negativ / Risiken
- Instanz-State auf Items erhöht die Datenlast pro Item gegenüber einem
  reinen Typ-Flag (jedes Item braucht jetzt eigene Schutz-Metadata statt
  von der `item_id`-Definition zu erben)
- Drei neue Item-Definitionen (Scrolls) nötig, plus deren
  Beschaffungsquelle (Crafting? Loot? Shop?) — nicht Teil dieses ADRs

### Mitigationen
- Scroll-Beschaffung ist bewusst nicht Teil dieses ADRs (Wirtschafts-/
  Balance-Frage, nicht Architektur-Frage) — Scrolls sind aber, weil normale
  Items, automatisch mit jeder zukünftigen Loot-/Crafting-/Shop-Quelle
  kompatibel, ohne dass dieses ADR dafür etwas Neues bauen müsste
- Instanz-Metadata kann sparsam gehalten werden (drei Bools sind klein), kein
  strukturelles Skalierungsproblem zu erwarten

## Ablösung

—

## Update (Round 94) — Scroll-Beschaffung über ShopService

Analog zum "Mitigationen"-Absatz oben ("automatisch mit jeder zukünftigen
Loot-/Crafting-/Shop-Quelle kompatibel"): alle drei Schutz-Scrolls
(`scroll_pve_protection`/`scroll_theft_protection`/`scroll_pvp_protection`)
sind jetzt in `ShopService.BUY_CATALOG` gelistet (40/40/80 Gold — PvP-Schutz
teurer, da er den einzigen Skull-Loss-Schutz aus ADR-036 darstellt). Kein
neuer Service, kein neues ADR — reine Katalog-Erweiterung im bereits
bestehenden `ShopService` (Round 88), der genau den benötigten Mechanismus
(Gold-Kauf gegen Katalog-Item, netzwerksicher) bereits unverändert
bereitstellt. Preise sind dokumentierte Platzhalter, keine finalen
Balance-Werte. Siehe ADR-039 "Update (Round 94)" für die parallele
Kristall-Beschaffung (derselbe Commit). Tests:
`tests/unit/test_shop_service.gd`.

## Umsetzungsstand (Round 90)

`ItemProtectionService` ist umgesetzt, inklusive UI (integriert ins bestehende
🎒-Inventar-Panel — bewusst **kein** neues Panel, siehe unten) und registriert
in `BootstrapConfig.tres`/`HUDBuilder.gd`.

### `ItemProtectionService` (`scripts/economy/protection/ItemProtectionService.gd`)
- **Abweichung von der Pseudo-Signatur oben:** `request_apply_protection()`
  nimmt `(scroll_item_id, target_item_id, player_id)` entgegen — **kein**
  `protection_type`-Parameter. Der `protection_type` wird ausschließlich
  serverseitig aus `ItemDefinition.grants_protection_type` des Scrolls
  gelesen. Grund: ein client-gesendeter `protection_type` wäre fälschbar
  (billiges Scroll + selbstgewählter `protection_type="pvp"`). "Absicht statt
  Wert" gilt hier für das Scroll selbst — der Client meldet nur, welches
  Scroll er auf welches Ziel anwenden will.
- Zustandslos, kein eigener Save-Key: die drei `is_*_protected`-Felder leben
  direkt auf `ItemInstance` (siehe unten) und werden von `InventorySystem`
  bereits mit-persistiert/mit-synchronisiert.
- Netzwerk-Routing analog Bank/Shop/Trade: eigenes `send_item_protection_apply()`/
  `_rpc_item_protection_apply()` in `NetworkBridge`, weil die Inventar-UI auf
  dem Peer des anwendenden Spielers läuft, nicht zwingend der Autorität.
- Scroll wird **vor** dem Setzen des Flags konsumiert (`remove_item()` zuerst)
  — kein Fenster, in dem ein Schutz gesetzt ist ohne dass das Scroll auch
  wirklich verbraucht wurde.
- `consume_pvp_protection(player_id, item_id)` ist bereits fertig für ADR-036,
  wird aber von diesem Round noch nicht aufgerufen (kein Trigger-Event
  existiert vor ADR-036).

### `ItemInstance`/`ItemDefinition`
- Drei neue Bool-Felder auf `ItemInstance`: `is_pve_death_protected`,
  `is_theft_protected` (beide permanent), `is_pvp_protected` (einmalig
  verbrauchend). In `to_dict()`/`from_dict()` mit-serialisiert; fehlende
  Keys in älteren Saves defaulten über `dict.get()` auf `false` — keine
  `SaveMigrationService`-Versionsbump nötig (rein additiv).
- Neues Feld `ItemDefinition.grants_protection_type: String` (Default `""`).
  Drei neue Item-Ressourcen: `data/items/ScrollPveProtection.tres`,
  `ScrollTheftProtection.tres`, `ScrollPvpProtection.tres` — normale,
  stapelbare Items (`max_stack = 20`), keine Sonderklasse. `sell_price = 0`
  (Beschaffung/Balance bewusst nicht Teil dieses ADRs, siehe Konsequenzen).

### UI — integriert ins Inventar-Panel (kein neues Panel)
- `InventoryVisuals.add_row()` erweitert um einen optionalen zweiten Button
  pro Zeile (generisch gehalten, keine Scroll-spezifische Benennung in dieser
  Klasse) plus eine Status-Zeile für Rückmeldungen.
- `InventoryUIController`: Zwei-Klick-Fluss ohne neue Netzwerk-Route für die
  Auswahl selbst — "📜 Anwenden" auf einem Scroll setzt nur lokalen UI-Zustand
  (`_pending_scroll_item_id`), "🎯 Ziel" auf einem anderen Item löst danach
  `request_apply_protection()` aus. Zustand wird erst nach
  `protection_applied`/`application_failed` zurückgesetzt, nicht optimistisch
  vorher, damit ein Fehlschlag nicht wie ein Erfolg aussieht.

### Nicht Teil dieser Runde
- Kein Trigger-seitiger Aufruf von `consume_pvp_protection()`/`is_protected_from()`
  — kommt mit ADR-036/037/039 selbst.
- Scroll-Beschaffungsquelle (Loot/Crafting/Shop) — wie in den Konsequenzen
  oben festgehalten bewusst nicht Architektur-Scope dieses ADRs.
