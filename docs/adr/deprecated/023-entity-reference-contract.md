> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-023: Entity-Reference-Kontrakt — wie ein Netzwerk-Request eine konkrete Server-Entity referenziert

**Status:** Angenommen — umgesetzt (2026-07)
**Datum:** 2026-07
**Kontext:** `EntityOrchestrator`, `EntityRegistry`, `NetworkContract`, `InteractionExecutor`,
`InteractableComponent`, `WorldService`, `NetworkBridge`. Liegt **unter** ADR-020 und
berührt ADR-021 — wurde beim Versuch entdeckt, ADR-020 konkret genug zu spezifizieren,
um damit anfangen zu können (vgl. AUDIT-05-Methode: eine saubere Schicht legt die
nächste unsaubere frei).

## Problem

ADR-020 (Interaktions-Autorität) verlangt, dass der Client nur noch *Absicht* meldet,
die Autorität aber das Ergebnis berechnet. Beim Konkretisieren zeigt sich: **die
Autorität kann das nur, wenn sie weiß, welches konkrete Objekt gemeint ist — und
dafür gibt es aktuell keinen belastbaren Bezeichner im Request.**

- `InteractableAction.id` (z. B. `"chop"`, `"mine_iron"`) ist ein **Typ**-Bezeichner,
  keiner für eine konkrete Instanz. Zwei Eichen im selben Waldstück haben denselben
  `action.id`, aber unterschiedliche `loot_table`/Position/Zustand (z. B. bereits
  abgeholzt, gerade respawnend).
- `entity_uuid` **existiert bereits** als eindeutiger Instanz-Bezeichner —
  `EntityOrchestrator.spawn_entity()` vergibt ihn über `_generate_uuid()`, das per
  `assert()` ausschließlich auf der Autorität laufen darf. Der Client kennt die UUID
  eines Objekts (aus dem Boot-Snapshot bzw. `entity_spawned`), kann sie aber selbst
  nie erzeugen oder fälschen — exakt die Eigenschaft, die ein vertrauenswürdiger
  Netzwerk-Bezeichner braucht.
- **Trotzdem wird diese UUID heute nirgends für Interaktions-Requests verwendet.**
  `HarvestableEntity._on_interacted()` nutzt sie nur für den *Despawn* (R-6), nicht
  für die Frage „welches Objekt hat XP/Loot ausgelöst". `AnimalCatcher`, `QuestNPC`
  (relevant auch für ADR-021 / `npc_talked_to`) haben dasselbe Muster: die UUID ist
  vorhanden, wird aber nicht bis zum Request durchgereicht.
- Ergänzend fehlt eine **Distanz-/Plausibilitätsprüfung auf der Autorität**:
  `EntityOrchestrator.get_entity(uuid)` liefert den Node zurück, prüft aber nicht,
  ob `player_id` überhaupt in Reichweite dieser Entity ist. Ohne diese Prüfung
  könnte ein Client mit einer bekannten UUID (z. B. aus dem Snapshot) eine
  Interaktion mit einem Objekt am anderen Ende der Karte anfordern.
- Genau dieselbe Lücke – „wie identifiziert ein Request eindeutig ein Server-Objekt,
  und wie wird das serverseitig geprüft" – wiederholt sich in **drei** der bisher
  gefundenen Problemfamilien (ADR-020, R-6, und `npc_talked_to`/`enemy_killed` in
  ADR-021). Das ist dieselbe Struktur wie AUDIT-05: nicht drei Einzelfälle, sondern
  ein fehlender Baustein, dreimal sichtbar geworden.
- Zusätzlicher, kleinerer Befund beim Nachschauen: `NetworkContract.gd` definiert
  bereits eine verbindliche Namenskonvention (`request_*()` → `receive_*_from_network()`
  → `_on_*_confirmed()`), die in den Entwürfen zu ADR-020/021/022 nicht konsequent
  verwendet wurde (dort z. B. `report_domain_event()`, `_rpc_sync_inventory` als neu
  erfundene Namen statt `receive_*_from_network()`). Wird unten mitkorrigiert, damit
  nicht dieselbe Art Mutation entsteht, die AUDIT-05 für `get_local_peer_id()` bereits
  einmal beschrieben hat.

## Optionen

### Option A: Jeder Request bekommt Position/Range mit, Server prüft nur grob
Client sendet `action_id` + eigene Position; Server prüft nur, ob irgendein Objekt
vom Typ `action_id` in der Nähe dieser Position existiert.
- ✅ Kein neuer Bezeichner nötig
- ❌ Rät weiterhin, *welches* Objekt gemeint ist, wenn mehrere vom selben Typ nah
  beieinander stehen (Wald-Fall) — mehrdeutig per Konstruktion
- ❌ Vertraut der vom Client gemeldeten eigenen Position — die Autorität hat die
  Spielerposition eigentlich schon (Movement ist server-seitig repliziert), diese
  zusätzlich vom Client mitschicken zu lassen ist eine weitere unnötige
  Vertrauensannahme

### Option B: Eigener Bezeichner-Typ nur für Interaktionen (`interaction_token`)
Ein neues, interaktionsspezifisches Token, das beim Anzeigen der Kontext-Aktion vom
Client generiert und dem Server mitgeteilt wird.
- ✅ Löst ADR-020 lokal
- ❌ Erfindet einen zweiten Identitäts-Mechanismus neben der bereits existierenden
  `entity_uuid` — löst R-6 und ADR-021 nicht mit, die dieselbe Frage stellen. Genau
  die „Mutations-Zwiebel", die AUDIT-05 beschreibt: dieselbe Information (welches
  Objekt ist gemeint) über mehrere unabhängige Bezeichner-Schemata.

### Option C: `entity_uuid` als einziger, kanonischer Objekt-Bezeichner über alle Netzwerk-Requests hinweg (gewählt)
`entity_uuid` (bereits server-vergeben, bereits im Client bekannt über Snapshot/
`entity_spawned`) wird zum **einzigen** Weg, wie ein Netzwerk-Request auf ein
konkretes Weltobjekt verweist — für Interaktionen (ADR-020), Despawn-Requests (R-6)
und Quest-Trigger mit Objekt-Bezug (`npc_talked_to`, `enemy_killed` in ADR-021).
Ergänzt um eine gemeinsame, kleine Autoritäts-Prüfung:

```
EntityOrchestrator.resolve_for_player(uuid: String, player_id: int, max_range: float) -> Node3D
```

— schlägt intern `get_entity(uuid)` nach (bereits vorhanden) und prüft zusätzlich
Distanz zwischen der (server-seitigen, replizierten) Spielerposition und der Entity.
`null` bei unbekannter UUID oder außerhalb der Reichweite — der Aufrufer (z. B. der
`InteractionResolver` aus ADR-020) muss dann ohne Wirkung abbrechen.

Namenskonvention wird an `NetworkContract.gd` angeglichen: der Client ruft
`request_interact(uuid, action_id, player_id)` auf, `NetworkBridge` empfängt über
`receive_interact_from_network(uuid, action_id, player_id)`, die eigentliche
Mutation läuft in `_on_interaction_confirmed(...)` — dieselbe Dreiteilung wie die
bestehenden Server-autoritativen Systeme, kein neu erfundenes Namensschema.

- ✅ Eine Bezeichner-Quelle für „welches Objekt ist gemeint" statt drei
- ✅ Nutzt eine bereits bestehende, bereits vertrauenswürdige Eigenschaft
  (`_generate_uuid()` ist Autorität-only) — keine neue Infrastruktur nötig
- ✅ Die Range-Prüfung schließt eine Lücke, die vorher gar nicht existierte
  (aktuell keine Prüfung), nicht nur eine Verschiebung des Problems
- ✅ Zieht ADR-020, R-6 und den objektbezogenen Teil von ADR-021 auf denselben
  Mechanismus — weniger Code, eine Stelle zum Testen statt drei
- ❌ `resolve_for_player()` muss die Spielerposition serverseitig zuverlässig
  kennen — das setzt voraus, dass `Player`-Bewegung tatsächlich repliziert bzw.
  autoritativ bekannt ist (zu verifizieren, siehe Risiken unten)
- ❌ Größerer Umbau als Option B, weil er nicht nur ADR-020 löst, sondern die
  Schnittstelle rückwirkend auch für R-6/ADR-021 ändert

## Entscheidung

**Option C.** `entity_uuid` wird zum einzigen kanonischen Objekt-Bezeichner für
Netzwerk-Requests, ergänzt um eine Autoritäts-seitige Distanzprüfung. ADR-020 und
der objektbezogene Teil von ADR-021 werden entsprechend präzisiert (siehe dortige
Anpassungshinweise unten). Namensgebung folgt `NetworkContract.gd`
(`request_*` → `receive_*_from_network` → `_on_*_confirmed`) statt neu erfundener
Bezeichner.

## Konsequenzen

### Positiv
- Eine einzige, bereits vertrauenswürdige Identitätsquelle für alle
  objektbezogenen Netzwerk-Requests — kein drittes/viertes Bezeichner-Schema bei
  zukünftigen Features (Fischen, Crafting-Stationen, Handel).
- Schließt eine bisher nicht existierende Reichweiten-Prüfung — reduziert
  Angriffsfläche über ADR-020 hinaus (auch für R-6-Despawn-Requests).
- Löst die in ADR-020/021/022-Entwürfen versehentlich neu erfundene
  RPC-Namensgebung auf — Angleich an `NetworkContract.gd`, bevor Code entsteht,
  der die dritte Namenskonvention im Projekt einführt.

### Negativ / Risiken
- **Verifiziert (kein offenes Risiko mehr):** Die Autorität kennt die Position
  jedes Spielers — `Player.gd` setzt die Movement-Authority auf den jeweils
  besitzenden Peer, `MultiplayerSynchronizer` repliziert `position` von dort an
  alle Peers inkl. Server. **Aber:** diese Position ist client-reported (üblicher
  Trade-off für responsives Movement, kein Bug). `resolve_for_player()`s
  Range-Check ist damit ehrlich ein **Plausibilitätsfilter**, kein hartes
  Anti-Cheat — ein modifizierter Client könnte weiterhin eine falsche eigene
  Position melden. Das wird nicht in diesem ADR mitgelöst (siehe TODO-Eintrag
  unten) — es wird auch nicht durch einen großzügigeren `max_range`-Fallback
  verdeckt, das wäre nur ein weiterer Workaround an derselben Stelle.
- **Verifiziert (kein offenes Risiko mehr):** `World.tscn` enthält keine
  statisch platzierten Interactables — jeder aktuell registrierte Typ
  (`WorldEntityRegistry.register_all()`) entsteht über
  `EntityOrchestrator.spawn_entity()` und hat damit garantiert eine `entity_uuid`.
  Vollständige Abdeckung heute. Damit das beim Wachsen des Projekts so bleibt,
  wird es als Regel in `principles.md` kodifiziert (siehe Mitigationen), nicht
  als stillschweigende Annahme belassen.
- `max_range` ist ein neuer Balance-Parameter (zu großzügig = wirkungslos als
  Filter, zu knapp = false positives bei Latenz/Ungenauigkeit). Kein
  Kompatibilitäts-Default, der „vorerst" sehr großzügig gesetzt und dann
  vergessen wird — das wäre derselbe Fehler wie der `player_id = 1`-Default
  in Miniaturform.

### Mitigationen
- `resolve_for_player()` bekommt einen expliziten, dokumentierten Default für
  `max_range` pro Interaktionsart (nicht ein globaler Fallback-Wert) und wird in
  `NetworkContract.gd` als serverautoritative Prüfung gelistet — mit Kommentar,
  dass sie ein Plausibilitätsfilter ist, kein Movement-Anti-Cheat.
- Neue Regel in `docs/principles.md`: „Jedes Interactable/jede Entity mit
  Netzwerk-Bezug entsteht über `EntityOrchestrator.spawn_entity()` — keine
  statische Platzierung in einer `.tscn` außerhalb des Orchestrators." Macht
  die heute zufällig vollständige `entity_uuid`-Abdeckung zu einer geprüften
  Regel statt einer stillen Annahme, die beim Wachsen des Projekts unbemerkt
  bricht.

## Anpassungshinweise für ADR-020/021 (nicht Teil dieses ADRs, hier nur vermerkt)

- **ADR-020, Option B:** Request wird zu `request_interact(uuid, action_id, player_id)`
  statt `action_id, player_id` — `InteractionResolver` löst `InteractableData` über
  `EntityOrchestrator.resolve_for_player(uuid, player_id, max_range)` auf, nicht über
  eine vom Client gesendete Referenz.
- **ADR-021, Option C:** Der generische Domain-Event-Kanal bekommt für
  `npc_talked_to`/`enemy_killed` optional ein `entity_uuid`-Feld im Payload, damit
  die Autorität (falls später gebraucht, z. B. für „welcher NPC genau") denselben
  Resolver nutzen kann statt einen eigenen Bezug zu erfinden.
- Beide ADRs werden **nach** Freigabe dieses ADRs textlich nachgezogen, nicht
  parallel — sonst entsteht genau die Art Divergenz, die dieser ADR vermeiden soll.

## Umsetzung

- `EntityOrchestrator.resolve_for_player(uuid, player_id, max_range) -> Node3D`
  implementiert: löst `uuid` über `get_entity()` auf, prüft anschließend
  Distanz zwischen dem Player-Node mit passendem `owner_peer_id` und der
  Entity. `null` bei unbekannter UUID, fehlendem Player oder Überschreiten
  von `max_range` — jeweils mit `log_warn` inkl. Kontext.
- `_find_player_by_id(player_id)` als privater Helfer — identisches Muster zu
  `IEntityContext.get_local_player()` / `PetComponent._find_owner()`, hier
  serverseitig für einen beliebigen `player_id` statt für den lokalen Peer.
- `NetworkContract.gd` dokumentiert `resolve_for_player()` jetzt im
  server-autoritativen Abschnitt inkl. Plausibilitätsfilter-Hinweis.
- `docs/principles.md` Abschnitt 11 kodifiziert die Orchestrator-only-Spawn-
  Regel bereits (war zum Zeitpunkt der Umsetzung schon vorhanden).
- Tests: `tests/unit/test_entity_orchestrator.gd` (neu) — deckt alle drei
  Null-Fälle (unbekannte UUID, fehlender Player, außerhalb Reichweite) sowie
  den Erfolgspfad ab.
- **Bewusst nicht Teil dieser Umsetzung** (siehe „Anpassungshinweise für
  ADR-020/021" oben): die eigentliche Umstellung von `InteractionExecutor`/
  `InteractableComponent`/Despawn-Requests/Quest-Trigger auf
  `resolve_for_player()` erfolgt mit der jeweiligen ADR-020/021-Umsetzung,
  nicht hier — dieser ADR liefert nur den Mechanismus.

## Ablösung

[Leer lassen bis dieser ADR durch einen neuen abgelöst wird]
