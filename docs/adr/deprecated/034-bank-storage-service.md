> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-034: Bank/Lager-Service

**Status:** Umgesetzt (Round 88) — siehe Umsetzungsstand unten
**Datum:** 2026-07
**Kontext:** Hängt an ADR-033 (Gold). Neu: `BankService`.

## Problem

Spieler brauchen einen sicheren, vom Inventar getrennten Lagerort für Items
und Gold — insbesondere relevant, da PvP-Tod (ADR-036) und Diebstahl
(ADR-039) nur das mitgeführte Inventar/Gold betreffen sollen, nicht
eingelagerte Bestände.

## Optionen

### Option A: Bank als "zweites Inventar" (gleiche Datenstruktur wie `InventorySystem`, separate Instanz)
- ✅ Wiederverwendung bestehender Item-Stack-/Slot-Logik
- ❌ Keine eigene Kapazitätslogik, falls Bank andere Regeln braucht
  (z. B. größere Kapazität, keine Gewichtsgrenze)

### Option B: Eigenständiger `BankService` mit eigenem Schema (gewählt)
- ✅ Kapazität/Regeln unabhängig vom Inventar erweiterbar
- ✅ Klarer Trennungspunkt für "was ist PvP-/Diebstahl-exponiert" (Inventar)
  vs. "was ist sicher" (Bank)
- ❌ Etwas Code-Duplikation gegenüber `InventorySystem`, falls nicht bewusst
  eine gemeinsame Basis-Komponente extrahiert wird

## Entscheidung

Option B, mit geteilter Basis wo sinnvoll. `BankService` (Session-Scope wie
`InventorySystem`, `player_uuid`-verschachtelt):

- Getrennter Item- und Gold-Speicher pro Spieler, kein automatischer Zugriff
  vom Inventar aus — Items/Gold müssen aktiv ein-/ausgezahlt werden
  (`request_deposit_item`/`request_withdraw_item`,
  `request_deposit_gold`/`request_withdraw_gold`)
- Zugriff nur über Interaktion mit einer Bank-Entität/NPC (bestehendes
  Interaktionssystem, ADR-020) — kein Fernzugriff
- Serverautoritativ, gleiches Muster wie ADR-033: Absicht statt Wert
- Persistenz über eigenen `ISaveProvider`-Bucket (ADR-005/006)
- **Konsequenz für ADR-035 (Trading):** gilt differenziert nach Handelsart —
  der **Handshake-Handel** operiert ausschließlich auf dem Inventar, Bank-
  Items müssen dafür erst abgehoben werden. Das **Auktionshaus** darf
  dagegen direkt aus Bank **oder** Inventar listen (kein Abheben nötig),
  siehe ADR-035 für die genaue Quellen-Priorität

## Konsequenzen

### Positiv
- Klare Trennlinie zwischen "exponiert" (Inventar) und "sicher" (Bank) für
  alle Risiko-Systeme (PvP-Tod, Diebstahl)

### Negativ / Risiken
- Zusätzlicher Service mit ähnlicher, aber nicht identischer Logik zu
  `InventorySystem` — Wartungsaufwand für zwei ähnliche Systeme

### Mitigationen
- Falls sich beim Bauen zeigt, dass die Überschneidung zu groß ist: gemeinsame
  Basis-Komponente (`ItemContainerBase` o. ä.) extrahieren — nicht Teil
  dieser Entscheidung, aber als Umsetzungshinweis festgehalten

## Umsetzungsstand (Round 88)

- `BankService` (`scripts/economy/bank/BankService.gd`): eigenständiges
  Schema (Option B) wie entschieden — getrennte `_items`/`_gold`-Dictionaries,
  KEIN gemeinsamer Code mit `InventorySystem` (die in "Mitigationen"
  angedeutete `ItemContainerBase`-Extraktion wurde nicht gebraucht, die
  Überschneidung blieb klein: nur `get_all_items()`-artige Rückgabeform).
- `request_deposit_item`/`request_withdraw_item`/`request_deposit_gold`/
  `request_withdraw_gold` + `on_*_confirmed`-Gegenstücke, netzwerksicher über
  eigene `NetworkBridge`-RPCs (analog `ShopService`, Round 88) — Rollback bei
  fehlgeschlagener Auszahlung, damit kein Gold zwischen Bank und Spieler
  "verschwinden" kann.
- `BankNPC` + Panel-UI (Inventar↔Bank für Items, Betrag-Eingabe für Gold),
  exaktes Gegenstück zu `ShopNPC`/Shop-Panel.
- Persistenz über eigenen `"bank"`-Save-Bucket (Items + Gold zusammen).
- **Zugriff nur über Interaktion** (kein Fernzugriff) — erfüllt wie im ADR
  gefordert, da Ein-/Auszahlung ausschließlich über `BankNPC`s
  `"talk_bank_npc"`-Interaktion das UI überhaupt erst öffnet.
- **Noch offen:** die in der ADR erwähnte Konsequenz für ADR-035 (Handshake-
  Handel nur aus Inventar, Auktionshaus aus Bank oder Inventar) ist erst
  relevant, sobald ADR-035 selbst gebaut wird — aktuell nicht verdrahtet.

## Ablösung

—
