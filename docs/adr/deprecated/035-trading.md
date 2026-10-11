> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-035: Trading (Handshake-Handel + Auktionshaus)

**Status:** Umgesetzt (Round 89) — Entwurf ursprünglich Round 68 Folge-Session
**Datum:** 2026-07
**Kontext:** Hängt an ADR-033 (Gold). Differenziert bezüglich ADR-034
(Bank) — der Handshake-Handel hängt **nicht** an der Bank (Items müssen
laut ADR-034 vorher abgehoben werden), das Auktionshaus dagegen **kann**
direkt aus Bank oder Inventar listen, siehe Entscheidung unten. Neu:
`TradeService`, `AuctionHouseService`.

## Problem

Zwei unterschiedliche Handelsmodi werden gebraucht: synchroner
Spieler-zu-Spieler-Handel (muss scam-sicher sein) und asynchroner Markt
(muss ohne beide Parteien online funktionieren).

## Optionen

### Option A: Nur direkter Handel, kein Auktionshaus
- ✅ Einfacher
- ❌ Deckt keinen Marktplatz-Bedarf ab, keine Wertfindung/Preisvergleich

### Option B: Beide Modi, geteilte Item-Referenz-Grundlage (gewählt)
- ✅ Deckt synchronen und asynchronen Bedarf ab
- ❌ Zwei Subsysteme statt einem, mehr Angriffsfläche

## Entscheidung

Option B, zwei getrennte Services auf gemeinsamer Grundlage
(`entity_uuid`-Kontrakt aus ADR-023 für Item-Referenzen, keine
client-behaupteten Item-IDs):

### Handshake-Handel (`TradeService`)
Zwei-Stufen-Bestätigung wie in etablierten MMOs (Angebot legen →
beide bestätigen "Ready" → finale Bestätigung erst nach Anzeige des exakt
finalen Angebots beider Seiten → atomarer Serverseitig ausgeführter Swap).
Kritisch für Scam-Schutz: **jede** Änderung am Angebot nach einer Bestätigung
setzt beide Bestätigungen zurück — kein "Bait and Switch" möglich.

### Auktionshaus (`AuctionHouseService`)
- Verkäufer listet Item gegen Gold-Preis. Anders als beim Handshake-Handel
  darf die Quelle **entweder Inventar oder Bank** sein — kein vorheriges
  Abheben aus der Bank nötig, um etwas auktionieren zu können
- **Quellen-Priorität:** existiert der zu listende Item-/Stack-Bestand in
  beiden Speichern (z. B. Spieler hat denselben Item-Typ teils im Inventar,
  teils in der Bank), wird **zuerst aus dem Inventar** entnommen, erst wenn
  das nicht ausreicht, wird auf den Bank-Bestand zurückgegriffen
- Gelistetes Item wird für die Laufzeit der Auktion aus seinem
  Ursprungsspeicher (Inventar oder Bank) entzogen (Escrow), unabhängig von
  der Quelle
- Käufer zahlt server-seitig validiertes Gold, erhält Item; Gold landet
  (abzüglich optionaler Gebühr, Design-Entscheidung, nicht Teil dieses ADRs)
  beim Verkäufer, auch wenn offline (Escrow-Modell)
- Kein direkter Peer-zu-Peer-Kontakt nötig — rein serverautoritative
  Transaktion

Beide Pfade: Absicht-statt-Wert-Muster (ADR-004/Round-45-Lehre), niemals
client-behauptete Mengen/Preise vertrauen.

## Konsequenzen

### Positiv
- Scam-resistentes Handshake-Modell durch Reset-bei-Änderung-Regel
- Auktionshaus deckt asynchronen Handel ohne Zusatzaufwand für Spieler ab

### Negativ / Risiken
- Auktionshaus-Escrow (Item "weg" aus Inventar während gelistet) braucht
  sauberen Rollback-Pfad, falls Auktion storniert wird
- Gebührenmodell/Preisfindung nicht Teil dieses ADRs — offene Design-Frage
  für später

### Mitigationen
- Item-Escrow als eigener, klar abgegrenzter State (`listed_items`),
  getrennt vom regulären Inventar-Bucket, analog zum Bank-Modell aus ADR-034

## Ablösung

—

## Umsetzungsstand (Round 89)

Beide Services aus der Entscheidung sind umgesetzt, jeweils inklusive UI
(Visuals/Controller/Component-Dreiklang, analog `BankComponent`/`ShopComponent`)
und registriert in `HUDBuilder.gd`.

### `TradeService` (`scripts/economy/trading/TradeService.gd`)
- Einstiegspunkt bewusst **nicht** über eine eigene Netzwerk-Route, sondern
  über die bestehende Interaktions-Pipeline (ADR-020/023) — dasselbe Muster
  wie PvP-Angriffe: ein `"trade_request"`-`InteractableComponent` auf dem
  Ziel-Spieler, `TradeService.on_invite_confirmed()` läuft direkt auf der
  Autorität, kein separater `request_invite()`-RPC-Pfad.
- Ab dem offenen Handels-Panel (Angebot ändern/Ready/Bestätigen/Abbrechen)
  läuft es wie Bank/Shop: eigenes `NetworkBridge`-Routing über
  `request_*()`/`on_*_confirmed()`, weil die UI auf dem Peer des jeweiligen
  Spielers läuft, nicht zwingend der Autorität.
- Scam-Schutz exakt wie entschieden: jede Angebotsänderung nach einer
  Ready-/Bestätigungs-Markierung (`on_offer_updated_confirmed()`) setzt beide
  Markierungen für beide Seiten zurück (`_reset_confirmation()`).
  Zwei-Stufen-Gate in `on_confirm_confirmed()` — eine finale Bestätigung ist
  ohne beidseitiges `ready` unmöglich (`"not_ready"`).
- Bewusst **kein Escrow** (anders als Auktionshaus) — Items verlassen das
  Inventar erst im atomaren Swap. `_execute_trade()` validiert beide Angebote
  in `_validate_offer()` gegen den **aktuellen** Bestand neu, bevor irgendetwas
  mutiert wird (Tier-3-Prinzip, ADR-004/Round-45-Lehre) — verhindert
  Bait-and-Switch zwischen Bestätigung und Ausführung; schlägt die
  Neuvalidierung fehl, bricht die Session sauber mit
  `session_cancelled("offer_no_longer_valid")` ab statt mit falschem Zustand
  fortzufahren. `_remove_offer()`/`_add_offer()` rollen bei Teilfehlschlägen
  (z. B. Empfänger-Inventar voll) beide Seiten vollständig zurück.
- Keine Persistenz — Sessions sind reine Laufzeit-Verhandlungen (kein
  `ISaveProvider`, anders als Auktionshaus).
- UI: `TradeVisuals.gd`/`TradeUIController.gd`/`TradeComponent.gd`. Der
  Controller hält **keine eigene Kopie** des Angebots — Single Source of
  Truth ist `TradeService.get_session_for()`, vor jeder Mutation neu
  abgefragt; bei jeder Änderung wird das volle neue Angebot geschickt statt
  eines Patches (genau das, was `on_offer_updated_confirmed()` serverseitig
  ohnehin erwartet). Getrenntes Einladungs-Popup (Annehmen/Ablehnen) vom
  eigentlichen Session-Panel (zwei Angebotsspalten, Item aus Inventar
  hinzufügen, Gold setzen, Bereit/Bestätigen).

### `AuctionHouseService` (`scripts/economy/trading/AuctionHouseService.gd`)
- Quellen-Priorität wie entschieden: `_resolve_listing_source()` prüft zuerst
  das Inventar, erst wenn das nicht reicht die Bank (`get_bank_item_instance()`
  — `BankService` hat kein `has_item()`, deshalb der direkte Zugriff auf die
  rohe `ItemInstance`).
- Escrow ab dem Moment des Listens: Item wird sofort aus der Ursprungsquelle
  entnommen (`_inventory.remove_item()` bzw. `_bank.remove_item_for_listing()`)
  und lebt bis Kauf/Storno ausschließlich in `_listings`. Storno gibt an
  **genau die Quelle** zurück, aus der entnommen wurde (`listing.source`),
  nicht pauschal ins Inventar.
- Gold läuft nicht über Escrow — Käufer zahlt server-seitig validiertes Gold
  direkt über `CurrencyService`; das Gold erreicht den Verkäufer auch wenn
  dieser offline ist.
- Persistenz über eigenen `"auction_house"`-Save-Bucket (`ISaveProvider`),
  da Listings über Server-Neustarts hinweg gültig bleiben müssen — anders
  als `TradeService`.
- **Bewusst nicht Teil dieser Runde (Round 89):** Live-Broadcast an alle
  Spieler mit offenem Marktplatz bei Listing-Änderungen — es gab damals
  keinen „an alle verbundenen Peers"-RPC-Mechanismus im Projekt (nur
  gezielte `rpc_id()`-Sends an einzelne Spieler). `request_listings_snapshot()`
  liefert Pull-statt-Push nur an den anfragenden Spieler. **Umgesetzt in
  Round 97, siehe „Umsetzungsstand (Round 97)" unten** — der Blocker ist mit
  ADR-042 behoben.
- UI: `AuctionHouseVisuals.gd`/`AuctionHouseUIController.gd`/
  `AuctionHouseComponent.gd` — öffnet klassisch über den NPC
  (`auction_house_opened`, wie Bank/Shop), nicht wie `TradeService` über
  einen Spieler-zu-Spieler-Interaktions-Umweg. Listen-Formular zeigt
  Inventar **und** Bank kombiniert an (beide erlaubte Quellen laut
  Entscheidung oben) — welche Quelle tatsächlich entnommen wird, entscheidet
  weiterhin `_resolve_listing_source()` serverseitig; die UI kennt die
  tatsächliche Quelle bewusst nicht vorab.

### Build-Verdrahtung
- Beide Panels in `HUDBuilder.gd` registriert (`registry["trade_panel"]`,
  `registry["auction_house_panel"]`).
- **Nachträglich beim Zusammenpacken gefundener Bug:** `BootPipeline.gd`s
  Phase-C8-Late-Inject-Liste für `inject_network_bridge()` enthielt
  `ServiceKeys.TRADE`/`ServiceKeys.AUCTION_HOUSE` nicht — beide Services
  hätten dadurch nie eine echte `NetworkBridge`-Instanz erhalten und wären
  im Mehrspieler-Betrieb dauerhaft auf dem Tier-1-„kein Peer"-Pfad
  hängengeblieben. Behoben, beide Keys in der Liste ergänzt.

### Tests
`tests/unit/test_trade_service.gd` (Einladung: Erfolg/Selbst-Einladung/
bereits-in-Session, Annehmen/Ablehnen inkl. „inzwischen anderweitig
beschäftigt"; Angebot ändern inkl. Ready/Confirmed-Reset und
Validierungsfehlern; Zwei-Stufen-Gate `"not_ready"`; atomarer Swap
Erfolgsfall; Neuvalidierung bei `_execute_trade()` bricht sauber ab, wenn
sich der Bestand zwischen Angebot und Ausführung ändert; Abbrechen;
Abfrage-API) und `tests/unit/test_auction_house_service.gd` (Listen aus
Inventar/Bank inkl. Quellen-Priorität bei beiden ausreichenden Quellen,
Validierungsfehler; Kaufen Erfolgsfall + alle Fehlerpfade inkl.
Gold-Rollback bei vollem Inventar; Stornieren mit Rückgabe an die jeweils
richtige Quelle; Abfrage-API; Save-Round-Trip). Beide Files folgen dem in
`test_bank_service.gd`/`test_shop_service.gd` etablierten Muster: echte
Kollaboratoren (`InventorySystem`/`CurrencyService`/`BankService`) statt
Stubs, damit die eigentlich interessanten Pfade (Rollback, Neuvalidierung,
Quellen-Priorität) gegen echten Zustand statt gegen einen wegabstrahierten
Stub laufen. Kein NetworkBridge konfiguriert -> Tier-1-„kein Peer"-Pfad,
Nicht-Autoritäts-Guards bewusst ungetestet (brauchen einen echten
`MultiplayerPeer`, gleiche Einschränkung wie bei `test_shop_service.gd`).

**Ehrlich offen:** kein Godot-Editor/Headless-Runner in der
Entwicklungsumgebung verfügbar — Tests sind strukturell korrekt gegen die
tatsächlichen Service-APIs geschrieben, aber noch nicht gegen die echte
Godot/GUT-Runtime gelaufen (gleiche Einschränkung wie an anderer Stelle im
Projekt dokumentiert, siehe TODO-Punkt „ADR-029 Plan-Schritt 4").

## Umsetzungsstand (Round 97) — Live-Broadcast für `AuctionHouseService`

Schließt den in Round 89 zurückgestellten Punkt ("Live-Broadcast an alle
Spieler mit offenem Marktplatz"), jetzt möglich durch ADR-042
(`NetworkBridge.broadcast_to_all_peers()`).

- Jede Listing-Änderung (`on_list_item_confirmed()`, `on_buy_confirmed()`,
  `on_cancel_listing_confirmed()`) sendet zusätzlich zur bestehenden
  gezielten Bestätigung an den Akteur (`_send_to()`) jetzt einen vollen
  Listings-Snapshot per `broadcast_to_all_peers()` an ALLE aktuell
  verbundenen Spieler (`_broadcast_listings_update()`). Fehlgeschlagene
  Aktionen (`_fail()`) broadcasten bewusst NICHT — es hat sich nichts am
  öffentlichen Zustand geändert, das andere Spieler etwas anginge.
- Bewusst ein **voller Snapshot statt eines Patches** — exakt dasselbe
  Format, das `request_listings_snapshot()` (Pull-Pfad) ohnehin schon
  liefert (`kind == "auction_house"`, `event == "listings_snapshot"`).
  Client-seitig verarbeitet `_on_economy_state_received()` beide Quellen
  identisch — ist jetzt sowohl an `economy_state_received` (1:1) als auch
  an `broadcast_event_received` (ADR-042, an alle) angeschlossen, da beide
  Signale dieselbe Signatur (`kind: String, payload: Dictionary`) haben.
- **Pull-Pfad (`request_listings_snapshot()`) bleibt unverändert bestehen**
  — er ist weiterhin der richtige Weg für den initialen Zustand beim ersten
  Öffnen des Marktplatz-Panels. Der Broadcast liefert nur *Änderungen* an
  Spieler, die das Panel bereits offen haben; ein Client, der das Panel
  noch nie geöffnet hatte (inkl. spät beigetretener Spieler, siehe ADR-042
  „Kein Sync-Pfad für spät joinende Clients"), bekommt seinen ersten Stand
  weiterhin über den Pull-Request beim Öffnen, nicht über den Broadcast.
  Damit ist der von ADR-042 offen gelassene Late-Join-Sync-Punkt für den
  Auktionshaus-Fall bereits durch den bestehenden Pull-Pfad abgedeckt —
  kein zusätzlicher Baustein nötig.
- Tests: `tests/unit/test_auction_house_service.gd` (+5, Spy-`NetworkBridge`
  analog `test_zone_service.gd`s `SpyNetworkBridge`-Muster: Broadcast bei
  Listen/Kaufen/Stornieren mit korrektem Snapshot-Inhalt, kein Broadcast bei
  fehlgeschlagenem Kauf, `broadcast_event_received` routet clientseitig
  korrekt in `listings_updated`).

**Ehrlich offen:** wie in jeder Runde seit 89 — kein Godot-Editor/
Headless-Runner verfügbar, nur strukturell geprüft. Bewusst weiterhin nicht
Teil dieser Runde: Gebührenmodell/Preisfindung (siehe Round-89-Notiz),
Rate-Limiting des Broadcasts bei sehr vielen kurz aufeinanderfolgenden
Änderungen (für die aktuelle Spielergröße unproblematisch, siehe ADR-042
„Negativ/Risiken").
