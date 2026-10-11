# ADR-050 — Native-Signal → Domain-Event-Migration (Konzept + Migrationsplan)

**Status:** Proposed — Konzept akzeptiert, Umsetzung noch NICHT begonnen (siehe
`TODO-offene-probleme.md` Punkt 5: "Vor Code: eigenes Konzept/ADR mit
Migrationsplan"). Dieses ADR ist bewusst der Konzept-Schritt, nicht der
Code-Schritt — `adr_tool.py` wird es daher korrekt als `unverified` zeigen,
bis Phase 3 unten tatsächlich läuft. Das ist kein Fehler, sondern Absicht
(Decision 0010: kein ADR ohne zugehöriges Script wird als "aktiv/enforced"
behauptet).
**Datum:** 2026-06 (Round 110)
**Bezug:** TODO-offene-probleme.md Punkt 5, Decision 0015,
`docs/manager/reports/native-signal-categorization.md`

---

## Kontext

99 native `signal`-Deklarationen (91 eindeutige Namen) existieren im Projekt
außerhalb der `*Events.gd`-Klassen, die der `EventBus`-Autoload kapselt.
`EventBus` selbst ist bereits eine funktionierende, typisierte, austauschbare
Indirektion (`IEventBus`/`EventBusAdapter`, ADR-012, ADR-017) — aber sie ist
nicht der einzige Kanal. Ein konkretes, bereits gefundenes Symptom:
`EventBus.player.inventory_changed` existiert, wird aber nirgends emittiert
(toter Kanal), während `InventorySystem.inventory_changed` als natives Signal
parallel dieselbe Tatsache trägt und breit genutzt wird. Zwei Kanäle für
eine Tatsache, Namensgleichheit rein zufällig — kein geplantes Design.

Decision 0015 hat das jetzt gemessen statt geschätzt (`analyze_native_signals.py`,
`make signal-categorize`):

| Kategorie | Anzahl | Bedeutung |
|---|---|---|
| LOCAL | 21 | Kein externer Nicht-Test-Connect. Bleibt natives Signal. |
| CROSS_LAYER | 52 | Mind. 1 externer, nicht-lokaler Connect. Migrationskandidat. |
| NEEDS_HUMAN | 18 | 4 Namenskollisionen + 14 mutmaßliche Parent-Child-UI-Fälle. Vor Migration einzeln entscheiden. |

Volle Liste mit Dateipfaden: `docs/manager/reports/native-signal-categorization.md`
(wird bei jedem `make signal-categorize`-Lauf neu berechnet, kein eingefrorener
Snapshot).

---

## Entscheidung

**Kein neuer Mechanismus.** `EventBus`/`IEventBus`/`*Events.gd` + die
Path-B-Indirektion (`ctx.bus().<ns>().<signal>`, ADR-012) ist bereits ein
typisierter, austauschbarer, projektweit etablierter Domain-Event-Kanal —
das exakte Ziel, das TODO Punkt 5 mit "kanonischer, typisierter
Domain-Event-Mechanismus, keine rohen String-Signal-Namen" beschreibt. Ihn
zu duplizieren (z.B. eine neue `DomainEvent`-Resource-Hierarchie) würde die
"zwei Kanäle für eine Tatsache"-Situation nur eine Ebene höher wiederholen.

**Zielzustand pro Signal:**

- **CROSS_LAYER-Signale wandern in die `*Events.gd` ihrer fachlichen Domain**
  (Deklaration + `emit_<signal>()`-Wrapper, Konvention aus Decision 0014).
  Emitter wechseln auf `EventBus.<ns>.emit_<signal>(...)`, externe Konsumenten
  auf `ctx.bus().<ns>().<signal>.connect(...)` (Path B, ADR-012-konform —
  Path A bleibt Ausnahme für die bereits dokumentierten Bootstrap-Fälle).
- **Das native `signal` auf der ursprünglichen Klasse bleibt nur erhalten**,
  wenn nach der Migration noch ein echter lokaler Node-Subtree-Connect übrig
  ist (selten — die meisten CROSS_LAYER-Fälle hatten genau einen externen
  Konsumenten und keinen lokalen). Sonst wird es entfernt, nicht doppelt
  gepflegt.
- **LOCAL-Signale bleiben unverändert.** Kein Migrationsdruck ohne externen
  Konsumenten — Migration ohne Symptom wäre Arbeit ohne Nutzen.
- **NEEDS_HUMAN-Signale werden NICHT automatisch migriert.** Sie brauchen
  Phase 1 unten zuerst.

---

## Migrationsplan (phasiert — TODO Punkt 5 nennt dies explizit "größte und
riskanteste Migration der ganzen Liste", entsprechend klein geschnitten)

### Phase 1 — NEEDS_HUMAN einzeln auflösen (18 Fälle, kein Automatismus)

**4 Namenskollisionen** (`close_requested`, `health_changed`,
`purchase_completed`, `transaction_failed`) — pro Kollisionsgruppe: jede
Deklaration einzeln ansehen, entscheiden ob sie überhaupt dieselbe
fachliche Bedeutung hat (bisher nicht verifiziert — reiner Namenszufall ist
möglich, siehe `inventory_changed`-Präzedenzfall oben) oder ob sie getrennt
migriert werden müssen (z.B. `close_requested` in `BankVisuals.gd` ist
wahrscheinlich nicht dieselbe fachliche Sache wie in `TradeVisuals.gd`,
auch wenn der Name identisch ist).

**14 mutmaßliche Parent-Child-UI-Fälle** — pro Fall die zugehörige `.tscn`
prüfen (dieses Tool hat keinen Scene-Tree-Zugriff, das ADR-050-Konzept
schließt das nicht ein): ist der Connector tatsächlich der `.tscn`-Parent
des Deklarierers? Dann bleibt es LOCAL trotz Dateigrenze (ADR-Zielarchitektur
erlaubt das explizit). Ist es das nicht, wandert es nach CROSS_LAYER und
folgt Phase 2.

Ergebnis von Phase 1 fließt als Ergänzung in dieses ADR (Nachtrag, keine
neue ADR-Nummer, siehe MEMORY_PROTOCOL.md-Prinzip "nicht löschen, ergänzen").

### Phase 2 — CROSS_LAYER-Migration in Domain-Batches, nicht auf einmal

52 Signale in einem Schritt zu migrieren ist die Art riskanter
Große-Schritte, vor der `docs/manager/MANAGER.md` warnt. Reihenfolge: pro
fachlicher Domain (`economy/`, `progression/`, `entities/`, `onboarding/`,
`social/`, `networking/`, `world/` — je eigener Batch), jeweils:

1. Prüfen ob die Domain bereits einen `EventBus`-Namespace/`*Events.gd` hat
   (die meisten haben das — `PlayerEvents`, `QuestEvents`, etc.). Falls
   nicht: erst anlegen (folgt demselben Muster wie bestehende `*Events.gd`).
2. Prüfen ob am Zielnamen schon ein **totes** EventBus-Signal wartet (der
   `inventory_changed`-Fall) — falls ja, das native Signal ersetzt den toten
   Kanal, kein neuer Name nötig.
3. Migrieren, Tests anpassen, ZIP-Output — ein Batch pro Round, nicht alle
   auf einmal (Working Rule 1 aus `ImplementAgent.md`: "One bug/change at a
   time").

### Phase 3 — Codemod (noch nicht gebaut, separater Round)

Sobald Phase 1+2 an mind. einem Batch das Muster bestätigt haben: Codemod
`scripts/agent/build/fix_native_signal_migration.py` nach demselben Muster
wie `fix_emit_wrapper_names.py`/`fix_eventbus_direct_access.py` (BuildSession,
Dry-Run zuerst, siehe Decision 0014). Erst dann wird dieses ADR über
`service_graph.py`/`scripts/agent/build/`-Referenz tatsächlich
`ENFORCED` im Sinne von `adr_tool.py` — vorher wäre das eine unbelegte
Behauptung genau der Art, die Decision 0010 abgeschafft hat.

### Phase 4 — Regressionsschutz

Neuer `service_graph.py`-Finding (Vorschlag, noch nicht gebaut):
`NATIVE_SIGNAL_EXTERNAL_CONNECT` (WARN) — meldet jedes native Signal mit
externem Nicht-Test-Connect außerhalb seines `ui/`-Subtrees, damit künftig
neu entstehende Fälle nicht erneut unbemerkt durchrutschen, bevor sie sich
zu einem zweiten `inventory_changed`-Fall auswachsen.

---

## Alternativen erwogen

**Neue eigene `DomainEvent`-Klassenhierarchie statt `EventBus` wiederzuverwenden**
— verworfen. `IEventBus`/`EventBusAdapter` ist bereits typisiert (GDScript-
Signale mit typisierten Parametern, kein `Dictionary`/`String`-basiertes
Event-System) und bereits austauschbar (ADR-012/017 haben genau diese
Abstraktionsgrenze geschaffen). Ein zweiter Mechanismus würde das ursprüngliche
Problem (zwei Kanäle für eine Tatsache) auf einer höheren Ebene reproduzieren.

**Alle 52 CROSS_LAYER-Signale in einem Round migrieren** — verworfen. TODO
Punkt 5 nennt dies selbst "größte und riskanteste Migration der ganzen
Liste"; ein Fehler in einem 52-Signale-Patch wäre schwer zu isolieren.
Domain-Batches (Phase 2) halten jeden Schritt einzeln überprüfbar und
rückrollbar.

**NEEDS_HUMAN-Fälle nach bestem Wissen automatisch auflösen (z.B. "erster
Treffer gewinnt")** — verworfen, exakt das stille Raten, vor dem TODO Punkt 5
selbst warnt ("Namenskollisionen ... kann ich statisch nicht sicher auflösen,
kein Raten") und das der bereits behobene `EMIT_WRAPPER_UNRESOLVED`-Bug
(TODO Punkt 5 Changelog) als Präzedenzfall zeigt, wie stilles Raten unbemerkt
falsch sein kann.

**Dieses ADR erst schreiben, wenn Phase 1 komplett ist** — verworfen. Das
Konzept (Zielmechanismus + Migrationsplan) ist unabhängig vom Ausgang der 18
Einzelfälle entscheidbar; auf sie zu warten hätte nur die andere Arbeit
blockiert, ohne dass Phase 1 vom Konzept abhinge.

---

## Konsequenzen

**Positiv:** ein einziger kanonischer Kopplungskanal für schichtübergreifende
Fakten (statt zwei parallelen, teils toten); Wiederverwendung bereits
getesteter Infrastruktur statt neuer Abstraktion; jeder Migrationsschritt
einzeln messbar via `make signal-categorize` (Zahl der CROSS_LAYER-Fälle
sollte nach jedem Batch sinken — Regressionsindikator kostenlos vorhanden).

**Negativ / Trade-off:** dieses ADR ist bewusst noch `unverified` in
`adr_tool.py` — es beschreibt einen Plan, keinen abgeschlossenen Zustand.
Wer nur `adr_tool.py list` liest, sieht das nicht sofort als "in Arbeit"
markiert; das TODO-Item bleibt daher explizit offen und verweist hierher,
statt sich auf den ADR-Status allein zu verlassen.

**Offen:** Phase 1 (18 Fälle) ist noch nicht begonnen. Kein CROSS_LAYER-Signal
wurde in diesem Round tatsächlich migriert — dieser Round liefert das Konzept,
nicht die Umsetzung, wie von TODO Punkt 5 gefordert.

---

## Nachtrag (Round 111) — Phase 1 abgeschlossen

Die 14 mutmaßlichen Parent-Child-UI-Fälle brauchten am Ende keine `.tscn`-
Prüfung von Hand — `analyze_native_signals.py` wurde stattdessen um die
DI-Lookup-Provenienz-Regel erweitert (siehe Decision-Log Round 110/111):
ein Connector ist genau dann lokal, wenn er sein Objekt direkt konstruiert/
als Parameter bekommt (auch über Scene-Tree-Traversal), nie über
`get_service()`/`ctx.get_X()`/`deps.require()`/AutoLoad-Namen. Damit lösten
sich 14 der 18 Fälle mechanisch auf, keine manuelle `.tscn`-Prüfung nötig.
Übrig blieben nur die 4 echten Namenskollisionen — die wurden jetzt einzeln
per Signatur-/Connect-Ziel-Vergleich aufgelöst (kein Raten, siehe
`TODO-offene-probleme.md` Round 111 für die Herleitung):

| Signal | Kollisions-Gruppen | Befund |
|---|---|---|
| `close_requested` | Bank/Auction/Trade/Shop-Visuals | Zufall — je `_visuals`-Parameter, kein DI. Alle 4 bleiben **LOCAL**. |
| `health_changed` | HealthComponent (int) vs. PlayerStats (float) | Keine echte Kollision — der einzige externe Connect (`Player.gd`) nutzt eine `(int, int)`-Lambda, passt nur zu HealthComponent. HealthComponent-Signal → **CROSS_LAYER**, PlayerStats-Signal → **LOCAL** (nur Tests). |
| `purchase_completed` | AuctionHouseService (6 Params) vs. ShopService (4 Params) | Zwei unabhängige Fakten. Beide **CROSS_LAYER**, aber getrennte Zielnamen bei der Migration (`auction_purchase_completed`/`shop_purchase_completed`). |
| `transaction_failed` | Bank/Auction/Trade/Shop-Service | Gemeinsame Namenskonvention, vier unabhängige Fakten (`bank.`/`trade.`/`auction.`/`shop.`-Receiver, alle DI). Alle vier **CROSS_LAYER**, getrennte Zielnamen (`bank_transaction_failed`/`trade_transaction_failed`/`auction_transaction_failed`/`shop_transaction_failed`). |

Damit ist Phase 1 vollständig — kein Signal mehr NEEDS_HUMAN im Sinne von
"unklar", nur noch die oben genannten Zielnamen für Phase 2 festgelegt.

## Nachtrag (Round 112) — Phase 2, erster Batch: Bank

Erster tatsächlicher Migrations-Schritt, bewusst klein geschnitten (3
Signale von den 15 CROSS_LAYER-Signalen der economy-Domain) statt die ganze
Domain auf einmal — exakt das "ein Batch pro Round"-Prinzip aus diesem ADR.

- Neuer Namespace `scripts/economy/bank/BankEvents.gd` (`EventBus.bank`),
  registriert in `IEventBus`/`EventBusAdapter`/`MockEventBus` nach dem
  bestehenden `CombatEvents`-Muster (Round 98).
- `BankService.gd`: die drei nativen Signale entfernt (keiner hatte einen
  lokalen Node-Subtree-Connect übrig, siehe Analyse oben), `_bus: IEventBus`
  ergänzt (`deps.get_optional()`, nicht `require()` — Konvention aus Round
  98/PvPDeathLossService), alle 17 `.emit()`-Call-Sites auf drei neue
  private Helper (`_fail()`/`_emit_deposit()`/`_emit_withdraw()`) umgestellt,
  die den `_bus`-Null-Guard zentral an einer Stelle halten statt an 17.
  `transaction_failed` → `bank_transaction_failed` (Phase-1-Namensauflösung
  oben).
- `config/BootstrapConfig.tres`: `"event_bus"` zu `bank`s `optional_deps`
  ergänzt — sonst exakt der Round-98-Bug (still `null` in Produktion), hier
  von vornherein vermieden statt erst gefunden.
- Konsumenten `BankUIController.gd`/`AuctionHouseUIController.gd` auf Path B
  umgestellt (`_ctx.bus().bank().<signal>.connect(...)`, ADR-012-konform).
  `AuctionHouseService`s EIGENES `transaction_failed`/`purchase_completed`
  bewusst NICHT angefasst — anderer Kollisions-Partner, eigener künftiger
  Batch.
- `tests/unit/test_bank_service.gd`: `EVENT_BUS: _bus` (bereits vorhandene
  `MockEventBus`-Instanz, vorher nur für Inventory/Currency verdrahtet) zu
  `BankService.configure()` ergänzt, beide `transaction_failed`-Test-
  Connects auf `_bus.bank().bank_transaction_failed` umgestellt.

Ergebnis: `make signal-migration-status` zeigt CROSS_LAYER 35 → 33 (zwei
eindeutige Namen — `deposit_completed`/`withdraw_completed` — komplett
verschwunden; `transaction_failed` bleibt als Name bestehen, aber mit einer
Kollisions-Deklaration weniger, 4→3). **Ehrlich offen wie immer:** kein
Godot-Editor/Headless-Runner verfügbar, alles nur strukturell geprüft
(Klammern-Balance, Signaturen gegen echte API abgeglichen), nicht gegen die
echte Godot/GUT-Runtime gelaufen. Als Nächstes: nächster economy-Sub-Batch
(z.B. Currency/Inventory/Equipment — je ein eigenes Signal, kein Kollisions-
Ballast) oder die AuctionHouse/Shop/Trade-Hälfte der `transaction_failed`/
`purchase_completed`-Kollision.

## Nachtrag (Round 113) — Phase 2, zweiter Batch: Auction/Trade/Shop
(`transaction_failed`/`purchase_completed`-Kollision vollständig aufgelöst)

Schließt die in Round 111 festgelegte Zielarchitektur für die restlichen
drei Kollisions-Partner ab (`bank_transaction_failed` war bereits Round 112).
Wie in Round 112: ein Batch, kein großer Schritt — aber alle drei Domains
zusammen, weil sie exakt dieselbe Namenskollision teilen und nur gemeinsam
vollständig auflösbar sind (die Kollision besteht per Definition erst dann
nicht mehr, wenn alle vier Deklarationen umbenannt sind).

- Neue Namespaces `scripts/economy/trading/AuctionEvents.gd` (`EventBus.auction`),
  `scripts/economy/trading/TradeEvents.gd` (`EventBus.trade`),
  `scripts/economy/shop/ShopEvents.gd` (`EventBus.shop`) — registriert in
  `EventBus.gd`/`IEventBus.gd`/`EventBusAdapter.gd`/`MockEventBus.gd` nach dem
  `BankEvents`-Muster (Round 112).
- Zielnamen nach Round-111-Auflösung, einheitliches Schema
  `<domain>_transaction_<verb>_completed`/`<domain>_transaction_failed`:
  - `AuctionHouseService.purchase_completed` → `auction_transaction_purchase_completed`
  - `AuctionHouseService.transaction_failed` → `auction_transaction_failed`
  - `TradeService.transaction_failed` → `trade_transaction_failed` (TradeService
    hatte nie ein `purchase_completed`-Gegenstück, siehe TradeEvents.gd-
    Klassenkommentar — Handel ist kein Kauf/Verkauf)
  - `ShopService.purchase_completed` → `shop_transaction_purchase_completed`
  - `ShopService.transaction_failed` → `shop_transaction_failed`
- **Bewusst außerhalb dieses Batches** (kein Kollisions-Fall, eigener
  künftiger Schritt): `AuctionHouseService.listing_created`/
  `listing_cancelled`/`listings_updated`; `TradeService.trade_completed`/
  `invite_received`/`invite_declined`/`session_*`; `ShopService.sale_completed`.
- Alle drei Services: `_bus: IEventBus` per `deps.get_optional(ServiceKeys.EVENT_BUS)`
  ergänzt (`AuctionHouseService` hatte das Feld bereits, `TradeService`/
  `ShopService` neu), jede Emit-Stelle auf `if is_instance_valid(_bus): _bus.<ns>().emit_<signal>(...)`
  umgestellt (Bank-Konvention aus Round 112, Null-Guard lokal an jeder Stelle
  statt zentralisiert — anders als Bank, weil hier keine gemeinsame private
  Helper-Funktion für alle Fehlerpfade existierte, die sich ohne
  Verhaltensänderung hätte einführen lassen; `AuctionHouseService._fail()`
  ist die eine Ausnahme, die es bereits gab und die den Guard weiterhin
  zentral hält).
- Konsumenten `AuctionHouseUIController.gd`/`TradeUIController.gd`/
  `ShopUIController.gd` auf Path B umgestellt
  (`_ctx.bus().auction()/trade()/shop().<signal>.connect(...)`,
  ADR-012-konform). `ShopUIController.gd`s Connect auf `shop.sale_completed`
  (natives Signal, bewusst außerhalb des Batches) bleibt unverändert stehen.
- `config/BootstrapConfig.tres`: `"event_bus"` zu `optional_deps` von `shop`,
  `trade`, `auction_house` ergänzt (bei `shop` gab es vorher gar keinen
  `optional_deps`-Eintrag) — sonst exakt der Round-98/Round-112-Bug (still
  `null` in Produktion trotz korrektem Code), hier von vornherein vermieden.
- `tests/unit/test_auction_house_service.gd`/`test_trade_service.gd`/
  `test_shop_service.gd`: `ServiceKeys.EVENT_BUS: _bus` (bereits vorhandene
  `MockEventBus`-Instanz) zu den jeweiligen `configure()`-Aufrufen ergänzt —
  **echter, in diesem Round gefundener Bug**: alle drei Testdateien hatten
  bereits eine `MockEventBus`-Instanz angelegt, aber nie tatsächlich in
  `_svc.configure()` durchgereicht, sodass `_bus` im Service `null` geblieben
  wäre und die neu migrierten Signale in den Tests nie gefeuert hätten (kein
  Compile-Fehler, nur stiller Test-Blindflug — dieselbe Bug-Klasse wie der
  BootstrapConfig-Fund oben, nur auf Testseite statt Produktionsseite). Alle
  Signal-Assertions von `_svc.purchase_completed`/`_svc.transaction_failed`
  auf `_bus.<ns>().<neuer_name>` umgestellt.
- Zusätzlich, auf Nutzeranfrage nach Round 112 (nicht Teil der
  `transaction_failed`/`purchase_completed`-Kollision, aber dieselbe Domain,
  daher im selben Round miterledigt): `BankService.deposit_completed`/
  `withdraw_completed` — vorher unverändert, weil sie nie Namenskollisionen
  waren — zusätzlich auf `bank_transaction_deposit_completed`/
  `bank_transaction_withdrawal_completed` migriert (einheitliches Schema mit
  den übrigen Bank-Namen). `BankUIController.gd`/`AuctionHouseUIController.gd`
  entsprechend umgestellt. Dabei nebenbei einen zweiten, unabhängigen Bug
  gefunden und behoben: `"bank"` fehlte seit Round 112 in der
  Boot-Log-Namespace-Liste (`EventBus.gd`, Funktion die beim Start alle
  Namespaces auflistet) — rein kosmetisch (Log-Vollständigkeit), keine
  funktionale Auswirkung, aber inkonsistent mit den übrigen sieben
  registrierten Namespaces.

Ergebnis: `python3 scripts/agent/analyze_native_signals.py` findet
`purchase_completed`/`transaction_failed` in keiner Deklaration mehr — beide
Namen sind vollständig aus der nativen-Signal-Liste verschwunden (vorher: 2
bzw. 3 verbleibende Deklarationen nach Round 112). Aktueller Gesamtstand:
LOCAL 52, CROSS_LAYER 33, NEEDS_HUMAN 2 (`close_requested`/`health_changed`,
beide bereits in Round 111 fachlich aufgelöst, siehe dortige Tabelle — das
Tool kann die Auflösung nur nicht automatisch verifizieren, da sie einen
Typ-Checker bräuchte, den `analyze_native_signals.py` nicht hat).

**Ehrlich offen wie immer:** kein Godot-Editor/Headless-Runner verfügbar,
alles nur strukturell geprüft (Klammern-Balance, Signaturen gegen echte API
abgeglichen, Test-Assertions gegen die neuen Emit-Signaturen abgeglichen),
nicht gegen die echte Godot/GUT-Runtime gelaufen. Mit diesem Batch ist die
komplette 4-Wege-`transaction_failed`/2-Wege-`purchase_completed`-Kollision
aus Round 111 vollständig migriert — kein offener NEEDS_HUMAN-Fall mehr aus
dieser Gruppe. Als Nächstes: nächster economy-Sub-Batch aus den verbleibenden
33 CROSS_LAYER-Signalen (z.B. Currency/Inventory/Equipment — je ein eigenes,
kollisionsfreies Signal) oder eine andere Domain (`progression/`,
`entities/`, `social/`, `networking/`, `world/`).
