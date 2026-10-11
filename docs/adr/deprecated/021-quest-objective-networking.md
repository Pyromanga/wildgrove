> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-021: Netzwerkfähiges Objective-Tracking — Ereignis muss die Autorität erreichen

**Status:** Angenommen
**Datum:** 2026-07 (Entscheidung Round 43; verfeinert und angenommen Round 45)
**Kontext:** `QuestService`, `EventBus`/`IEventBus`, `WorldEvents`, `PlayerEvents`,
`QuestEvents`, `NetworkBridge`. Root-Cause-Fund R-5 aus `TODO-offene-probleme.md`,
eng verwandt mit ADR-020, aber ein eigenständiges Problem (Tracking, nicht
Reward-Auszahlung).

## Problem

`EventBus.gd._ready()` erzeugt seine Namespaces (`player()`, `world()`, `quest()`, …)
einmal pro laufendem Spielprozess — es gibt keinen Sync-Mechanismus zwischen den
Instanzen auf verschiedenen Peers. Von den Signalen, die `QuestService` konsumiert,
haben nur `loot_collected` und `xp_gained` überhaupt ein Netzwerk-Äquivalent —
und zwar indirekt: nicht das Signal selbst, sondern seine *Folgeaktion*
(`request_add_item`/`request_add_xp`) überquert das Netz. `interaction_finished`,
`enemy_killed`, `npc_talked_to`, `custom_objective_triggered` haben **kein**
Äquivalent, auch nicht indirekt.

`QuestService._on_loot_collected()`, `_on_xp_gained()`, `_on_interaction_finished()`,
`_on_enemy_killed()`, `_on_npc_talked_to()` rufen ausnahmslos
`update_objective(quest_id, obj_id, delta)` **ohne** `player_id` auf — der
Default-Parameter greift, alles landet in Spieler 1's Bucket. Für
`loot_collected`/`xp_gained` ist das ein *ignoriertes* Datum (das Signal trägt
`player_id` laut `WorldEvents.gd`/`PlayerEvents.gd` bereits), für die anderen
drei ein *strukturell fehlendes* — die Autorität hat für einen Nicht-Host-Spieler
schlicht nie ein Ereignis, an dem sie Fortschritt ablesen könnte.

Das ist doppelt problematisch: ein Multiplayer-Breaking-Bug (Nicht-Host-Spieler
können quest-relevante Aktionen nie server-seitig abschließen) **und** dieselbe
Vertrauensgrenze wie ADR-020 — sobald das Ereignis die Autorität erreicht, muss
`player_id` gleichzeitig ehrlich durchgereicht werden, sonst wird aus „kann nie
tracken" ein neues „trackt für den falschen Spieler".

### Befund (Round 45 — die vier Fälle sind nicht gleich schwer)

Root-Cause-Nachrecherche vor der Umsetzung ergab: die vier betroffenen Signale
brauchen **nicht** alle denselben Fix. Zwei sind bereits authority-seitig
korrekt emittiert und brauchen nur die Verkabelung, zwei brauchen tatsächlich
den neuen Kanal aus Option C:

- **`loot_collected`/`xp_gained` (kein neuer Kanal nötig):** laufen seit R-1/R-2
  (ADR-020) bereits über `InteractionResolver.resolve()`, aufgerufen aus dem
  authority-geguardeten `_on_interacted()`-Hook — die Autorität sieht das
  Signal auf ihrem **eigenen** lokalen `EventBus` bereits korrekt, inklusive
  echtem `player_id` (das Signal trägt es bereits, siehe oben). Reiner
  Verkabelungsfehler in `QuestService._on_loot_collected()`/`_on_xp_gained()` —
  Handler-Signatur nimmt den dritten Parameter nur nicht entgegen.
- **`enemy_killed` (kein neuer Kanal nötig, aber Signal fehlt `player_id`):**
  `EnemyNPC._die()` feuert ebenfalls nur auf der Autorität (hinter
  `is_multiplayer_authority()`, erreicht nur über den bereits authority-
  geguardeten `_on_interacted()`-Schadenspfad). Die Autorität sieht den Kill
  also bereits korrekt — nur `WorldEvents.emit_enemy_killed(enemy_type_id, position)`
  hat schlicht noch kein `player_id`-Argument. Muss ergänzt werden (Signal +
  Emit-Aufruf + Handler), aber ohne Kanal/RPC — reine lokale Signatur-Erweiterung.
- **`interaction_finished`/`npc_talked_to` (braucht den neuen Kanal — hier fehlt
  der Guard an der Quelle):** `InteractionExecutor._on_tween_finished()` (Quelle
  von `interaction_finished`) und `QuestNPC._on_interacted()` (Quelle von
  `npc_talked_to`) haben **keinen** `is_multiplayer_authority()`-Guard — sie
  laufen auf jedem Peer lokal, für Animations-/Dialog-Feedback auch bewusst so
  gewollt (siehe `InteractionUIController` etc., die `interaction_finished` pro
  Peer für UI brauchen). Für Quest-Tracking braucht es deshalb einen zweiten,
  authority-seitigen Meldeweg **zusätzlich** zum bestehenden lokalen Signal —
  genau die Rolle von Option C's Kanal.
- **`custom_objective_triggered` (braucht den neuen Kanal, kein entity-basierter
  Ersatz möglich):** `QuestCustomTrigger.gd` ist ein reiner `Area3D`-Proximity-
  Trigger, kein `InteractableComponent`/Entity-Interaktion — `body_entered`
  feuert lokal auf dem Peer, dessen `CharacterBody3D` die Zone betritt (Movement
  ist vor ADR-025/026 noch nicht server-autoritativ). Es gibt hier keinen
  bestehenden authority-geguardeten Hook, den man wiederverwenden könnte (anders
  als bei Harvestable/EnemyNPC) — der generische Kanal ist hier nicht nur die
  bequemere, sondern die einzig praktikable Lösung.

## Optionen

### Option A: `player_id` in allen sechs Handlern nachtragen, Signale weiter lokal
Reicht `player_id` aus dem Signal in `update_objective()` durch, ändert aber
nichts daran, dass `interaction_finished`/`enemy_killed`/`npc_talked_to` nur
lokal auf dem auslösenden Peer gefeuert werden.
- ✅ Behebt sofort die „trackt für Spieler 1 statt für den richtigen Spieler"-Hälfte
- ❌ Behebt die eigentliche Root Cause nicht: für `interaction_finished`/
  `npc_talked_to` (keine Autoritäts-Prüfung an der Emissionsstelle, siehe R-3)
  bleibt der Server ohne echtes Ereignis. Für Nicht-Host-Spieler ändert sich
  nichts — der Bug wird präziser beschrieben, aber nicht kleiner.

### Option B: Jedes Quest-relevante Signal bekommt sein eigenes `_rpc_*`-Paar
Für `interaction_finished`, `npc_talked_to`, `custom_objective_triggered` je
einen eigenen `rpc_id(1, "_rpc_report_interaction_finished", …)`-artigen Weg in
`NetworkBridge` bauen, analog zu den sechs bestehenden RPCs.
- ✅ Naheliegend, folgt dem bisherigen Muster von `NetworkBridge`
- ❌ Ist exakt die Struktur, die zu R-1..R-7 als *Sammlung von Einzelfällen*
  geführt hat: sechs Vorgänge im Netz, alles andere lokale Illusion. Jedes neue
  Quest-Trigger-Signal (z. B. zukünftig „Fisch gefangen") würde erneut ein
  eigenes RPC-Paar brauchen — die Kategorie „Ereignis muss die Autorität
  informieren" bleibt unbenannt und wird bei jedem neuen Feature erneut vergessen.

### Option C: Generischer „Autorität-informieren"-Kanal für Domain-Events (gewählt)
Statt für jedes Signal ein eigenes RPC zu bauen: ein einziger, generischer
Kanal `NetworkBridge.report_domain_event(event_name: String, payload: Dictionary, player_id: int)`,
der auf der Autorität an eine Registry von `QuestService`-Handlern (und künftigen
Konsumenten) weitergereicht wird. `interaction_finished`, `enemy_killed`,
`npc_talked_to`, `custom_objective_triggered` werden **an der Quelle** (dort wo
sie heute schon emittiert werden, nach dem R-3-Guard aus ADR-020) zusätzlich
über diesen Kanal gemeldet, mit dem echten `player_id` als Pflichtparameter —
kein Default, kein Fallback auf 1.

**Verfeinerung (Round 45):** siehe Befund oben — `loot_collected`/`xp_gained`/
`enemy_killed` erreichen die Autorität bereits nativ und brauchen `report_domain_event()`
nicht, nur `interaction_finished` (für INTERACT-Objectives)/`npc_talked_to`/
`custom_objective_triggered` rufen den Kanal tatsächlich auf.

**Sicherheitsanforderung, nicht optional:** `_rpc_report_domain_event()` (die
Empfangsseite auf der Autorität) darf `player_id` **niemals** aus dem
Client-Payload übernehmen — genau der Fehler, der gerade in Round 45
(„Server validiert RPC-Werte nicht") als Root Cause identifiziert und behoben
wurde. `player_id` wird serverseitig aus `_sender_as_player_id()`
(`multiplayer.get_remote_sender_id()`) abgeleitet, exakt wie bei den
bestehenden `_rpc_start_quest`/`_rpc_complete_quest`-Handlern. Der
`player_id`-Parameter in der Signatur oben existiert nur für den Tier-1-Pfad
(kein Peer → Wert kommt vom lokalen Aufrufer, es gibt niemand anderen, der ihn
fälschen könnte) — im Tier-2/3-RPC-Pfad wird er verworfen und durch den
sender-abgeleiteten Wert ersetzt. `event_name` und `payload` bleiben
client-gemeldete Nutzdaten (welches Ereignis, welche IDs) — das ist unkritisch,
weil `on_quest_complete_confirmed()` (SEC-03) den tatsächlichen Abschluss
ohnehin serverseitig gegen den getrackten Fortschritt re-validiert, nicht dem
Trigger-Ereignis selbst vertraut. Ein falsch gemeldetes Ereignis kann höchstens
einen Objective-Zähler fälschlich erhöhen, nie direkt einen Reward auslösen.
- ✅ Eine Erweiterung, kein wiederholtes Muster — der nächste Quest-Trigger
  braucht keinen neuen RPC-Typ, nur einen neuen `event_name`
- ✅ Macht die bisher unbenannte Kategorie „Ereignis, das die Autorität über
  etwas informieren muss, das clientseitig passiert ist" (siehe
  EventBus-Sweep im TODO) explizit und wiederverwendbar
- ✅ `player_id` ist an jeder dieser Stellen ein Pflichtparameter — es gibt
  keinen Default-1-Pfad mehr, der stillschweigend für Solo *und* Multiplayer
  gleich funktioniert, aber aus verschiedenen Gründen
- ❌ Etwas mehr Indirektion (Dictionary-Payload statt typisierter RPC-Argumente)
  — wird durch eine dünne, typisierte Wrapper-Schicht pro `event_name` in
  `QuestService` selbst ausgeglichen, nicht durch Schwächung der Typisierung

## Entscheidung

**Option C.** Ein generischer Domain-Event-Kanal statt eines sechsten/siebten/
achten Einzel-RPCs — bestätigt (Round 45): kein entity-basierter Ersatz ist für
`custom_objective_triggered` möglich (siehe Befund oben), ein generischer Kanal
ist hier keine vorzeitige Abstraktion, sondern die einzig praktikable Lösung.
`player_id` wird an jeder beteiligten Stelle Pflichtparameter — im Netzwerkfall
serverseitig aus dem RPC-Sender abgeleitet, nie aus Client-Payload übernommen.
Tatsächlich betroffen von der Kanal-Implementierung sind nur `interaction_finished`
(für INTERACT-Objectives)/`npc_talked_to`/`custom_objective_triggered` — `loot_collected`/
`xp_gained`/`enemy_killed` bekommen ihren Fix separat, ohne den Kanal (siehe
Umsetzungsplan).

## Konsequenzen

### Positiv
- Nicht-Host-Spieler können Quest-Objectives serverseitig tatsächlich
  abschließen — aktuell strukturell unmöglich.
- Neue Quest-Trigger-Typen brauchen keine neue Netzwerk-Infrastruktur, nur
  einen neuen `event_name` im bestehenden Kanal.
- Deckt sich mit dem Despawn-Request aus R-6 (ADR-020) — derselbe Kanal kann
  `entity_despawn_requested` mit übertragen, statt dass R-6 sein eigenes Sonder-RPC
  bekommt.

### Negativ / Risiken
- `update_objective()` und alle sechs Handler verlieren ihren Default-Parameter
  `player_id: int = 1`. Jeder bestehende Call-Ort (auch in Tests) muss den
  echten Wert übergeben — es gibt bewusst **keinen** Kompatibilitäts-Fallback
  „alter Aufruf ohne player_id funktioniert weiter wie bisher", weil genau
  dieser Fallback laut TODO die Quelle des Bugs ist (Default greift, alles
  landet in Spieler 1's Bucket).
- Tests, die aktuell `QuestService` isoliert ohne echten `NetworkBridge`
  ansprechen, müssen den Domain-Event-Kanal entweder über eine echte
  Tier-1-Instanz (kein Peer gesetzt → direkter Aufruf, kein Mock) oder über
  einen echten zweiten `ENetMultiplayerPeer` in einem Integrationstest abdecken.

### Mitigationen
- Kein testspezifischer Bypass des Kanals: Tier 1 durchläuft denselben Code-Pfad
  wie Tier 2/3 (siehe `NetworkContract`, ADR-004) — `report_domain_event()` ruft
  im Solo-Fall den Handler direkt auf, im Multiplayer-Fall über `rpc_id(1, …)`,
  exakt wie die bestehenden `send_*()`-Methoden in `NetworkBridge`.
- Der offene „Kein echter Zwei-Peer-Integrationstest"-Punkt aus dem TODO
  (`test_network_bridge.gd`/`test_session_manager.gd` laufen komplett gemockt)
  wird durch diesen ADR nicht mitgelöst, ist aber die logische Voraussetzung,
  um R-5 überhaupt gegen echte zwei Peers statt gegen Mocks zu verifizieren —
  siehe TODO, Punkt „Kein echter Zwei-Peer-Integrationstest".

## Umsetzungsplan (Round 45, vor Code-Umsetzung dokumentiert)

Reihenfolge nach Risiko, kleinste/sicherste Änderung zuerst:

1. **`loot_collected`/`xp_gained`-Verkabelung** (kein Kanal, kein Signatur-Umbau):
   `QuestService._on_loot_collected(item_id, quantity, player_id)`/
   `_on_xp_gained(skill_name, _amount, player_id)` nehmen den dritten Parameter
   entgegen und reichen ihn an `update_objective(quest_id, obj_id, delta, player_id)`
   weiter, statt den Default zu nutzen.
2. **`enemy_killed` bekommt `player_id`:** `WorldEvents.emit_enemy_killed()`
   und das Signal selbst bekommen ein drittes Argument `player_id: int`;
   `EnemyNPC._die()`/der `killer_player_id`-Aufrufer (bereits vorhanden für
   `emit_loot_collected`/`emit_xp` an derselben Stelle, siehe ADR-020) übergibt
   den bereits bekannten Wert. `QuestService._on_enemy_killed()` nimmt ihn entgegen.
3. **Neuer Kanal `NetworkBridge.report_domain_event(event_name, payload, player_id)`**
   plus `_rpc_report_domain_event()`-Empfänger (player_id aus `_sender_as_player_id()`,
   siehe Sicherheitsanforderung oben) plus Tier-1-Direktpfad (kein Peer → Handler
   direkt, analog zu allen bestehenden `send_*()`).
4. **`interaction_finished` für INTERACT-Objectives:** `QuestService` abonniert
   für Quest-Tracking-Zwecke **nicht** mehr direkt `_bus.world().interaction_finished`
   (das bleibt für UI-Konsumenten unverändert lokal) — stattdessen ruft
   `InteractionExecutor._on_tween_finished()` zusätzlich
   `network_bridge.report_domain_event("interaction_finished", {"action_id": ..., "label": ...}, player_id)`
   auf. `QuestService` registriert dafür einen Handler in der neuen Registry statt
   eines direkten Signal-Connects.
5. **`npc_talked_to`:** `QuestNPC._on_interacted()` ruft zusätzlich
   `report_domain_event("npc_talked_to", {"npc_id": npc_id}, player_id)` auf —
   `_player_id` (bisher bewusst ungenutzt, siehe Kommentar in `QuestNPC.gd`)
   wird hier zum ersten Mal tatsächlich gebraucht.
6. **`custom_objective_triggered`:** `QuestCustomTrigger._on_body_entered()`
   braucht zuerst den `player_id` des eintretenden Spielers (`body` ist der
   `Player`-Node — `player_id` muss von dort gelesen werden, z. B. über
   `ctx.get_owner_peer_id()`-Äquivalent, siehe die 2026-07-Lösung im TODO-Kopf
   zu `owner_peer_id`), dann `report_domain_event("custom_objective_triggered", {"signal_key": signal_key}, player_id)`.
7. **`QuestService`/`QuestObjectiveHandler`:** `update_objective()` und alle
   sechs Handler verlieren den Default `player_id: int = 1` — jeder Call-Ort
   (inkl. Tests) muss den echten Wert übergeben.
8. **Tests:** neue Unit-Tests für `report_domain_event()` (Tier 1 + Tier 2 via
   Mock, analog zu `test_network_bridge_contract.gd`), Regressionstests für
   jeden der sechs Handler mit `player_id != 1`, Test dass
   `_rpc_report_domain_event()` `player_id` aus dem Payload ignoriert und den
   Sender-Wert nimmt (Security-Regressionstest, analog zu
   `test_no_rpc_add_item_or_add_xp_surface()` aus Round 45).

## Umsetzungsstand (Round 46) — BUG-26: Doppel-Count bei `npc_talked_to`

Nach der Round-45-Umsetzung des obigen Plans zeigte eine Nachkontrolle einen
Interaktions-Effekt zwischen ADR-020 und ADR-021, der beim Schreiben des Plans
nicht berücksichtigt war: `npc_talked_to` läuft über `QuestNPC._on_interacted()`,
und dieser Hook wird — anders als bei `interaction_finished`/
`custom_objective_triggered`, die keinen entity-gebundenen Autoritäts-Hook haben —
für einen Nicht-Host-Spieler durch `InteractableComponent._handle_completion()`
(ADR-020) **zweimal** aufgerufen: einmal lokal auf dem Client (reines
UI-Feedback, ADR-020 dokumentiert das ausdrücklich als "wirkungslos" — aber
`report_domain_event()` dort war eben doch eine Wirkung, nur clientseitig über
RPC), einmal erneut auf der Autorität über
`WorldService.resolve_and_dispatch_interaction()`, das denselben Hook direkt
aufruft. Beide Aufrufe meldeten unabhängig voneinander dasselbe Domain-Event —
TALK-Objectives zählten pro Gespräch doppelt.

**Betrifft nur `npc_talked_to`**, nicht die anderen beiden Fälle:
- `interaction_finished` wird ausschließlich in `InteractionExecutor._on_tween_finished()`
  gemeldet — einem Service, der pro Peer genau einmal pro abgeschlossener
  Aktion läuft, unabhängig von einem entity-gebundenen `_on_interacted()`-Hook.
- `custom_objective_triggered` hat keinen entity-gebundenen Autoritäts-Hook
  (reiner `Area3D`-Trigger, siehe Befund oben) — es gibt keinen zweiten Pfad,
  der denselben Trigger ein zweites Mal an die Autorität melden könnte.

**Fix:** `QuestNPC._on_interacted()` bekommt denselben Autoritäts-Guard wie
`HarvestableEntity._on_interacted()`/`EnemyNPC._on_interacted()` (dort war er
bereits vorhanden — `QuestNPC` war die einzige Ausnahme). Lokales Feedback
(Dialog-Anzeige) bleibt für jeden Peer bestehen; Quest-Tracking (Bus-Emit +
`report_domain_event()`) läuft nur noch, wenn `is_multiplayer_authority()`
wahr ist — exakt einmal pro Interaktion, unabhängig davon ob Tier 1/Host
(direkter Aufruf) oder Tier 2/3 Nicht-Host (über `resolve_and_dispatch_interaction()`).

**Tests:** `tests/unit/test_quest_npc.gd` — zwei neue Regressionstests:
Nicht-Autorität meldet kein Domain-Event (lokales Feedback bleibt aber
erhalten), und der volle Round-Trip (Nicht-Autorität + Autorität nacheinander)
meldet zusammen genau ein Event statt zwei.

**Nebenbei behoben:** `tests/unit/test_quest_service.gd` kompilierte nicht
mehr, nachdem `update_objective()` in Round 45 (Umsetzungsplan Punkt 7) den
Default für `player_id` verloren hat — zehn Testaufrufe riefen die Methode
weiterhin mit nur drei Argumenten auf. Alle zehn Aufrufe ergänzt um den
expliziten Tier-1-Wert `player_id=1`, kein Verhaltensunterschied zu vorher
(Default war ohnehin `1`).

## Umsetzungsstand (Round 47) — Fehlender Autoritäts-Guard in `QuestCustomTrigger`

Nachkontrolle des Round-45-Umsetzungsplans (Punkt 6) ergab: `report_domain_event()`
wurde zwar korrekt verkabelt, aber `QuestCustomTrigger._on_body_entered()` bekam
nie einen Autoritäts-Guard — anders als `HarvestableEntity`/`EnemyNPC`/`QuestNPC`
(nach dem Round-46-Fix), die alle vor ihrem jeweiligen quest-relevanten Hook
`is_multiplayer_authority()` prüfen. `body_entered` feuert auf einem `Area3D`
lokal, auf jedem Peer, für jeden Body, der die Zone in dessen eigener
Physik-Simulation überlappt — seit ADR-025/026 also auch für fremde Spieler,
die dieser Client nur über `RemotePlayerInterpolator` interpoliert, nie selbst
simuliert (Player.gd-Rollenteilung, Fall 3: "fremder Spieler auf meinem
Client"). Jeder Client, der zufällig mitbekommt, wie ein *anderer* Spieler die
Zone durchquert, feuerte `report_domain_event()` — und weil
`_rpc_report_domain_event()` `player_id` serverseitig bewusst aus dem
RPC-Sender ableitet, nie aus dem Payload (Sicherheitsanforderung oben, exakt
weil ein rohes Payload-Feld fälschbar wäre), schrieb sich der unbeteiligte
Beobachter das Objective serverseitig selbst gut.

**Fix:** `_on_body_entered()` verwirft den Aufruf jetzt, bevor irgendetwas
emittiert oder gemeldet wird, außer einer von zwei Fällen trifft zu — dieselbe
Rollenteilung wie `Player.gd _physics_process()` (ADR-025 "Tier-Kollaps"):
`NetworkBridge.is_server()` (Autorität/Tier-1-Solo) ODER der eintretende Body
gehört diesem Client selbst (`owner_peer_id == multiplayer.get_unique_id()`,
Client-Side-Prediction-Fall). Ohne injizierte `NetworkBridge` bleibt das
Verhalten unverändert (reiner Solo-/Test-Kontext, kein anderer Peer könnte
mitlesen). Der Guard greift *vor* `_has_triggered = true`/`monitoring = false`,
damit ein verworfener Fall-3-Eintritt einen späteren legitimen Eintritt auf
demselben Peer nicht blockiert.

**Tests:** `tests/unit/test_quest_custom_trigger.gd` — vier neue Fälle: fremder
Spieler + Nicht-Autorität meldet weder Domain-Event noch lokales Signal (und
verbraucht `trigger_once` nicht); eigener Spieler meldet weiterhin auch ohne
Autorität; Autorität meldet unabhängig vom `owner_peer_id`.

## Ablösung

[Leer lassen bis dieser ADR durch einen neuen abgelöst wird]
