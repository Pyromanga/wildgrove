> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-033: Spieler-Währung (Gold)

**Status:** Umgesetzt (Round 88) — siehe Umsetzungsstand unten
**Datum:** 2026-07
**Kontext:** Fundament für Bank (ADR-034), Trading (ADR-035), PvP-Tod-Verlust
(ADR-036) und PvE-Tod-Loot (ADR-037). Neu: `CurrencyService`.

## Problem

Es existiert keine Spielwährung. Alle folgenden Wirtschafts-ADRs setzen Gold
als gemeinsame Recheneinheit voraus.

## Optionen

### Option A: Gold als Item im bestehenden `InventorySystem`
Gold wird wie ein stapelbares Item behandelt.
- ✅ Kein neuer Service, nutzt bestehende Infrastruktur
- ❌ Semantisch unsauber (Gold ist keine Beute mit `item_id`, sondern ein
  Konto-Wert; Stack-Limits/Gewichts-Regeln von Items passen nicht auf Gold)

### Option B: Eigenständiger `CurrencyService` (gewählt)
Gold als eigenes, ganzzahliges Feld pro `player_uuid`, eigener Service.
- ✅ Sauberer Schnitt, keine Item-Sonderfälle
- ✅ Folgt demselben `request_/on_*_confirmed`-Muster wie Inventar (ADR-004)
- ❌ Ein weiterer Service mehr in der Service-Landschaft

## Entscheidung

Option B. `CurrencyService` (Session-Scope wie `InventorySystem`/
`SkillSystem`, ADR-009), `player_uuid`-verschachtelt (ADR-029-Konvention,
kein `peer_id`).

- `request_add_gold(amount: int)` / `request_remove_gold(amount: int)` —
  Client meldet nur Absicht, Server berechnet/bestätigt
  (`on_gold_changed_confirmed`), identisches Muster zu
  `InventorySystem.request_add_item()` nach der Round-45-Bereinigung
- Serverseitige Validierung: kein negativer Kontostand, Overflow-Schutz.
  **Wichtig:** GDScript-`int` ist 64-Bit (~9,2 Trillionen Maximum) — das muss
  auch so genutzt werden. Ein versehentlicher 32-Bit-Cap (~2,1 Milliarden)
  würde bereits an der 1-Milliarden-Schwelle aus ADR-036s Verlust-Tabelle
  anecken. Kein künstlich niedrigeres Cap einführen, sofern nicht explizit
  aus Balance-Gründen gewünscht.
- Persistenz über `ISaveProvider` (ADR-005/006), gleicher Save-Bucket wie
  Inventar oder eigener Schlüssel — Detailfrage für Umsetzung, keine
  ADR-relevante Entscheidung
- `EventBus.economy` (bestehender Namespace, siehe ADR-022) bekommt
  `gold_changed(player_id, new_amount, delta)`

## Konsequenzen

### Positiv
- Einheitliche Recheneinheit für alle nachfolgenden Wirtschafts-ADRs
- Wiederverwendung des bereits bewährten Absicht-statt-Wert-Musters
  (Lehre aus Round 45 Cheat-Audit)

### Negativ / Risiken
- Zwei Systeme (Inventar + Gold) statt einem — Konsumenten (Bank, Trading)
  müssen beide ansprechen, kein einheitliches "Wallet"-Interface

### Mitigationen
- Keine — Trennung ist bewusst, siehe Option-Begründung

## Ablösung

—

## Umsetzungsstand (Round 88)

`CurrencyService` (`scripts/economy/currency/CurrencyService.gd`) — exakt
Option B wie entschieden. `request_add_gold(player_id, amount)`/
`request_remove_gold(player_id, amount)` → `on_gold_changed_confirmed()`
(gleiches Absicht-statt-Wert-Muster wie `InventorySystem`), inkl.
Verteidigung-in-der-Tiefe-Validierung direkt in `on_gold_changed_confirmed()`
(nicht nur in den `request_*`-Methoden), C-02-Autoritäts-Guard,
`MAX_GOLD = 2^63-1` als echtes Overflow-Limit (kein künstliches Cap, wie
gefordert). Persistenz über `ISaveProvider`, eigener Save-Key `"currency"`.
Registriert in `config/BootstrapConfig.tres` (Session-Service, Deps
`savesystem`+`event_bus`) und in `BootPipeline.gd`s Phase-C8-Late-Inject-Liste
für `inject_network_bridge()`. Economy-Backsync über denselben
`NetworkBridge.send_economy_update_for_player()`/`economy_state_received`-
Kanal wie `InventorySystem`, mit `kind = "currency"`.

**Korrektur ggü. ADR-Text:** "`EventBus.economy` (bestehender Namespace, siehe
ADR-022)" existiert tatsächlich nicht in `IEventBus.gd` — `InventorySystem`
verwendet für sein analoges `inventory_changed`-Signal ebenfalls keinen
EventBus-Namespace, sondern ein eigenes Signal direkt am Service. Dieselbe
Konvention wurde hier übernommen (`gold_changed`-Signal direkt an
`CurrencyService`) statt einen ungenutzten Namespace zu erfinden.

Tests: `tests/unit/test_currency_service.gd` (Add/Remove-Erfolg und
-Ablehnung, Overflow- und Negativ-Kontostand-Schutz auch bei
Direktaufruf-Umgehung, Multi-Tenanz, Save-Round-Trip, Economy-Backsync
inkl. `kind`-Filterung — analog `test_economy_backsync_r7.gd`).

**Bewusst nicht Teil dieser Runde:** kein UI (`CurrencyUIController`/HUD-
Anzeige) — noch kein Konsument, der Gold anzeigen müsste, bevor
Trading (ADR-035) existiert. Kommt zusammen mit dem Trading-Handshake-UI.
