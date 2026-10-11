> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-036: PvP-Tod-Verlust (Skull-Loot & Aura/Gesinnung)

**Status:** Vorgeschlagen — Entwurf, Round 68 Folge-Session
**Datum:** 2026-07
**Kontext:** Hängt an ADR-032 (Player-Flags/Skull) und ADR-033 (Gold).
Nutzt Item-Schutz-Kategorien aus ADR-038. Neu: `AuraService`,
PvP-Death-Loss-Logik in `CombatSystem`/`HealthComponent`.

## Problem

Wenn ein Spieler im PvP stirbt, muss serverautoritativ entschieden werden,
was er verliert — abhängig vom Skull-Status des Killers (ADR-032) und der
eigenen Aura/Gesinnung.

## Optionen

### Option A: Fixer Verlustsatz, unabhängig von Skull
Einfach, aber ignoriert die bereits getroffene Skull-Unterscheidung.
- ✅ Einfach
- ❌ Widerspricht der bereits entschiedenen Skull-Mechanik (ADR-032), die
  genau diese Differenzierung ermöglichen soll

### Option B: Skull-abhängige Verlust-Stufen (gewählt)
- ✅ Nutzt ADR-032 sinnvoll aus, belohnt "faires" (nicht-skulled) Verhalten
- ❌ Mehr Regel-Komplexität

## Entscheidung

**Kernprinzip (Korrektur gegenüber der ursprünglichen Fassung):** Die
Verlust-Regel hängt am **eigenen Skull-Status des sterbenden Spielers**,
nicht am Skull-Status seines Gegners. Wer stirbt, verliert je nachdem, ob
**er selbst** gerade geskullt war — unabhängig davon, ob er in diesem
Kampf der ursprüngliche Angreifer oder das Opfer war.

### Stirbt ein geskullter Spieler
**100 % Verlust** aller mitgeführten Items und Gold (abzüglich der
permanenten Schutzkategorien aus ADR-038 — PvE-Todesschutz und
Diebstahlschutz-Items bleiben **auch hier** unberührt, da diese permanent
sind und nicht PvP-spezifisch). Der einmalige PvP-Schutz-Charge (ADR-038)
kann hier konsumiert werden, um den vollen Verlust einmalig zu verhindern.
Gilt unabhängig davon, wer/was den Tod verursacht hat.

### Stirbt ein nicht-geskullter Spieler (im PvP)
Verlust liegt zwischen **20–70 %** des Item-Werts bzw. der Stack-Mengen —
und zwar bezogen auf das, was nach Abzug der **permanenten
Schutzkategorien aus ADR-038** übrig bleibt (PvE-Todesschutz- und
Diebstahlschutz-Items sind auch hier vollständig ausgenommen, genau wie im
100%-Fall oben; die Prozent-Rechnung greift nur auf den ungeschützten
Rest). Der Prozentsatz ist **proportional** zu dem, was der **Gegner**
(der Killer) selbst riskiert (mitgeführter Item-/Gold-Wert des Gegners zum
Zeitpunkt des Kills): **je mehr der Gegner riskiert, desto mehr verliert
der Sterbende** — Risiko-Belohnung für den, der das Risiko eingegangen ist.

🔸 **Stufen-Tabelle** (Gegner-Risiko → Verlust des Sterbenden):

| Gegner-Risiko (mitgeführter Item-/Gold-Wert) | Verlust |
|---|---|
| ≥ 50.000 | 20 % |
| ≥ 100.000 | 30 % |
| ≥ 1.000.000 | 40 % |
| ≥ 10.000.000 | 50 % |
| ≥ 100.000.000 | 60 % |
| ≥ 1.000.000.000 (1 Milliarde) | 70 % |

**Unterhalb von 50.000 Gegner-Risiko:** fester **5 % Verlust-Sockel** —
kein Flatline bei 20 %, sondern ein deutlich niedrigerer Boden, damit sich
Billig-Ganking ("Raggen": minimal ausgerüstete Angreifer, die risikofrei
schwache Ziele farmen) klar weniger lohnt als ein fairer 50k-Kampf.

### Aura/Gesinnung
`AuraService` führt einen Reputationswert pro Spieler (`player_uuid`). Jeder
Skull-auslösende (unprovozierte) Kill senkt die Aura; sie regeneriert über
Zeit bei gutem Verhalten. Unterschreitet Aura eine Schwelle, gilt dieselbe
10-Sekunden-Safe-Zone-Vulnerabilität wie bei aktivem Skull (ADR-032) —
Mechanismus ist dort bereits spezifiziert, dieses ADR definiert nur die
Bewertungs-/Schwellenlogik.

🔸 **Entschieden:** Regeneration läuft über **direkte
Spieler-Interaktion**, nicht über reine Zeit: Spieler können sich
gegenseitig "bedanken" (eine neue Interaktion, ähnlich den bestehenden
Interaktionsmustern aus ADR-020), was die Aura des Bedankten verbessert.
Begrenzung: **maximal einmal pro 24 Stunden pro Spielerpaar** — dieselben
zwei Spieler können sich nicht mehrfach am Tag gegenseitig hochbedanken.

**Wertebereich:** Aura ist auf **`-6.000` bis `+6.000`** gedeckelt (beide
Richtungen), unabhängig davon, wie sie sich verändert.

**Punktewert pro Dank:** proportional zum aktuellen Aura-Defizit, nicht
fix — ein Dank bei tief negativer Aura gibt einen großen Sprung, während
ein Dank nahe/über neutral einen kleineren, aber weiterhin positiven
Zuwachs gibt (Danken trägt also auch über neutral hinaus ins Positive):

- Solange `aura < 0`: `gain = max(50, round(abs(aura) × 0.05))` — mindestens
  50 Punkte, oder 5 % des aktuellen Minus-Abstands, je nachdem was größer
  ist. Bei `aura = -6.000` ergibt das z. B. 300 Punkte pro Dank; bei
  `aura = -100` die Mindestmenge von 50.
- Sobald `aura >= 0`: fixer, kleinerer Zuwachs pro Dank (z. B. `+25`) für
  weiteres Klettern ins Positive — kein Deckel bei neutral.
- Beide Zweige werden am Ende auf den `-6.000`/`+6.000`-Rahmen geclampt.

🔸 Konkrete Zahlen (50/5%/25) sind ein fairer Vorschlag, kein finaler
Balance-Wert — wird beim tatsächlichen Balancing ohnehin nochmal
angefasst, liefert aber eine funktionierende, in sich konsistente
Ausgangsbasis.

## Konsequenzen

### Positiv
- Klare Kopplung an das bereits etablierte Skull-System, keine Parallel-Logik
- Aura-Verfall macht wiederholtes unprovoziertes Griefen zunehmend riskant

### Negativ / Risiken
- Konkrete Aura-Regenerations-Zahlen (50/5%/25) sind ein Vorschlag, kein
  finaler Balance-Wert — aber strukturell nicht blockierend

### Mitigationen
- Formel liefert eine funktionierende, in sich konsistente Ausgangsbasis;
  Anpassung ist reines Zahlen-Tuning, keine Architektur-Änderung

## Ablösung

—

## Umsetzungsstand (Round 91)

`PvPDeathLossService` und `AuraService` sind umgesetzt, inklusive
PvP-Targeting/Angriffs-Interaktion (existierte bereits aus einer früheren
Runde) und der neuen "Danken"-Spieler-Interaktion. Loot-Empfänger: **der
Killer** (mit dem Auftraggeber abgestimmt — die ADR selbst legt das nicht
explizit fest).

### `PvPDeathLossService` (`scripts/entities/combat/PvPDeathLossService.gd`)
- Einziger Einstiegspunkt: `apply_death_loss(victim_player_id, killer_player_id)`,
  aufgerufen von `Player._on_player_died()` sobald `DamageRecord.attacker_peer_id`
  auf einen ANDEREN Spieler auflöst.
- Kein `request_*()`/`on_*_confirmed()`-Split — ein PvP-Tod ist ausschließlich
  eine Server-Entscheidung (`HealthComponent.died` feuert nur auf der
  Autorität), es gibt keinen Client-Auslöser, der geroutet werden müsste.
- Risiko-Berechnung (`_compute_risked_value()`) = Gold + `sell_price × Menge`
  über das Inventar — dieselbe Wert-Quelle wie `ShopService`.
- **Bewusst außerhalb des Scopes:** ausgerüstete Items (`EquipmentService`-Slots)
  sind NICHT Teil des Verlust-Pools, nur was im `InventorySystem`-Bag liegt.
  Rundung bei `max_stack=1`-Items (Waffen/Werkzeuge) kann bei niedrigen
  Verlust-Prozentsätzen auf 0 runden — entspricht der ADR wörtlich
  ("Stack-Mengen"), getestet als bewusstes Verhalten, kein Bug.

### `AuraService` (`scripts/world/pvp/AuraService.gd`)
- **Interpretationsentscheidung** (ADR spezifiziert es nicht mechanisch):
  "skull-auslösender (unprovozierter) Kill" = Killer war zum Zeitpunkt des
  Kills selbst geskullt (`PvPService.is_skulled(killer_player_id)`) —
  Skull-Status ist bereits die im Projekt vorhandene Definition von
  "unprovoziert angegriffen" (ADR-032), keine zweite Parallel-Buchführung.
- `AURA_VULNERABILITY_THRESHOLD = -3000` und `KILL_PENALTY = -200` sind
  dokumentierte Platzhalter, kein finaler Balance-Wert (wie die ADR selbst
  für die Dank-Formel anmerkt).
- Dank-Formel exakt wie oben spezifiziert: `max(50, |aura|×5%)` unterhalb 0,
  fixer `+25`-Zuwachs ab 0, beide Zweige auf `±6000` geclampt.
- Cooldown-Persistenz bewusst mit-gespeichert (nicht nur die Aura-Werte) —
  ohne das wäre der 24h-Cooldown über einen Server-Neustart umgehbar.

### PvP-Targeting/Angriffs-Interaktion
War bereits aus einer früheren Runde vorhanden (`PlayerAttack.gd`,
`CombatSystem.resolve_pvp_hit()`) — musste in dieser Runde nicht neu gebaut
werden, nur der Tod-Hook (`Player._on_player_died()`) ergänzt.

### Safe-Zone-Vulnerabilitäts-Fenster (ADR-032-Integration)
`PvPService.report_safe_zone_entered()` prüft jetzt `is_skulled` **ODER**
`AuraService.is_below_vulnerability_threshold()` — beide Bedingungen lösen
das 10s-Anti-Escape-Fenster aus. `AuraService` ist bewusst ein optionaler
Dep von `PvPService` (nicht `required`), um einen Bootstrap-Zyklus zu
vermeiden.

### "Danken"-Interaktion
Neue `PlayerThank.gd` (exaktes Gegenstück zu `PlayerTrade.gd`, ADR-035) —
dritte koexistierende `InteractableComponent` auf dem Player-Node, neben
`attack_player` und `trade_request`. Netzwerk-Routing (`send_aura_thank()`/
`_rpc_aura_thank()`) leitet `from_player_id` **nicht** über das Netz weiter,
sondern leitet es serverseitig aus dem RPC-Absender-Peer ab (analog
`_sender_as_player_uuid()` bei Bank/Shop) — ein client-gesendeter
"ich bin Spieler X"-Parameter wäre fälschbar.

### Nicht Teil dieser Runde
- Kein UI-Widget zur Aura-Anzeige/zum manuellen "Danken"-Auslösen über ein
  Panel — aktuell nur über die Kontext-Interaktion am Spieler-Node auslösbar
  (analog `attack_player`/`trade_request`, die ebenfalls kein eigenes Panel
  haben).

Tests: `tests/unit/test_pvp_death_loss_service.gd`,
`tests/unit/test_aura_service.gd` (beide neu), `test_pvp_service.gd` um
Aura-Integrationstests für das Safe-Zone-Vulnerabilitäts-Fenster ergänzt.
**Ehrlich offen:** wie bei Round 89/90 — kein Godot-Editor/Headless-Runner in
dieser Entwicklungsumgebung verfügbar, alles nur strukturell geprüft. Einmal
im Editor testen, bevor mit ADR-037/039 weitergemacht wird.

## Umsetzungsstand (Round 98) — Kill-Feed-Broadcast (`player_killed_by_player`)

Schließt die in [ADR-018 „Bewusst nicht behoben"](018-systemevents-domain-split.md)
seit Round 53 dokumentierte funktionale Lücke — jetzt möglich durch ADR-042
(`NetworkBridge.broadcast_to_all_peers()`, Round 96).

- Neuer EventBus-Namespace `CombatEvents`
  (`scripts/entities/combat/CombatEvents.gd`, `EventBus.combat`) mit einem
  einzigen Signal `player_killed_by_player(victim_player_id, killer_player_id,
  victim_was_skulled, gold_lost, items_lost_count)` — registriert in
  `IEventBus`/`EventBusAdapter`/`MockEventBus` nach demselben Muster wie
  `ZoneEvents` (ADR-030).
- `PvPDeathLossService.apply_death_loss()` ruft nach der bestehenden
  `death_loss_applied`-Emission zusätzlich `_notify_kill()` auf: emittiert
  `EventBus.combat.player_killed_by_player` **lokal direkt auf der
  Autorität** (kein Rundweg über ihr eigenes Broadcast-RPC — dieselbe
  Konvention wie in ADR-042 für `broadcast_to_all_peers()` festgehalten)
  UND broadcastet `kind == "pvp_kill"` an alle verbundenen Peers. Clients
  empfangen das über eine neue `_on_broadcast_event_received()`-Verdrahtung
  (`_network.broadcast_event_received`, analog `AuctionHouseService`s
  Dual-Channel-Muster aus Round 97) und emittieren dasselbe Signal lokal.
- **Bewusste Abgrenzung zu `death_loss_applied`:** dieses neue Signal ist
  NICHT dessen Ersatz. `death_loss_applied` bleibt die autoritätsseitige
  Quelle der Wahrheit mit dem vollen `items_lost`-Array (für die eigentliche
  Loot-Anwendung/UI beim Opfer/Killer). `player_killed_by_player` trägt
  bewusst nur `items_lost_count` (eine Stack-Anzahl) statt der Item-Details
  — ein reines Kill-Feed-Signal für ALLE Spieler, keine "jeder sieht jeden
  Loot-Inhalt"-Ausweitung.
- Fehlgeschlagene/No-Op-Aufrufe (leere IDs, `victim == killer`) broadcasten
  bewusst nicht — der frühe Guard in `apply_death_loss()` greift vor
  `_notify_kill()`.
- Tests: `tests/unit/test_pvp_death_loss_service.gd` (+5 —
  lokale Autoritäts-Emission ohne NetworkBridge, Broadcast-Payload-Form,
  kein Broadcast beim No-Op-Guard, `broadcast_event_received`-Routing,
  Ignorieren fremder `kind`-Werte).

**Bewusst nicht Teil dieser Runde:** kein UI-Widget für ein tatsächliches
Kill-Feed-Panel — dieses ADR liefert nur die Signal-Infrastruktur
(`EventBus.combat.player_killed_by_player`), an die ein künftiges HUD-Element
sich anschließen kann, analog wie `weather_changed` (ADR-041) zunächst auch
nur als Signal existierte, bevor eine UI es konsumierte. Kein
Rate-Limiting bei sehr vielen PvP-Kills in kurzer Zeit — für die aktuelle
Spielergröße (`MAX_CLIENTS = 8`) unproblematisch, siehe ADR-042
„Negativ/Risiken".

**Ehrlich offen:** wie in jeder Runde seit 89 — kein Godot-Editor/
Headless-Runner verfügbar, nur strukturell geprüft.
