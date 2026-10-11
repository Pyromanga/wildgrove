> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-041: Wetter-Events (`weather_changed`)

**Status:** Angenommen — umgesetzt (Round 95)
**Datum:** 2026-07
**Kontext:** Erster der drei in `TODO-offene-probleme.md` unter "🟡 Fehlt
komplett" gebündelten Punkte ("Wetter-Events (`weather_changed`), PvP-Events
(`player_killed_by_player`), Achievement-Events"). PvP-Events und
Achievement-Events sind bewusst NICHT Teil dieses ADRs — beide brauchen
eigene Trigger-Analysen (PvP-Events z.B. Überschneidung mit dem bereits
bestehenden ADR-036-Kill-Pfad) und sind eigenständige Folge-Runden.

## Problem

Die Spielwelt hat mit `WorldTimeService` bereits einen Tag/Nacht-Zyklus
(`day_time`, `day_count`, `time_of_day_changed`-Signal), aber kein Wetter —
`weather_changed` stand im TODO-Dokument als offener Event-Typ, ohne dass
irgendein Code dafür existierte (0 Treffer, verifiziert per Grep vor dieser
Runde).

Die naheliegende erste Idee — ein Service, der periodisch neu würfelt und
das Ergebnis per RPC an alle verbundenen Clients verteilt — kollidiert mit
einer bereits in ADR-035 dokumentierten Lücke: **das Projekt hat aktuell
keinen "an alle Peers gleichzeitig"-Broadcast-Mechanismus.** Jeder bisherige
Server→Client-Sync-Kanal (`NetworkBridge.send_economy_update_for_player()`,
`send_zone_update_for_peer()`, `_rpc_receive_initial_state`) ist gezielt an
genau einen Peer adressiert. Ein globales Wetter bräuchte entweder einen
neuen Broadcast-Mechanismus (grundsätzlich sinnvoll, aber ein eigener, nicht
trivialer Architektur-Schritt — vgl. den bewusst zurückgestellten
"Live-Broadcast bei Auktionshaus-Änderungen"-Punkt in ADR-035) oder eine
andere Lösung, die ohne Netzwerk-Traffic auskommt.

## Optionen

### Option A: Server würfelt, RPC an alle verbundenen Peers
- ✅ Naheliegend, folgt dem Muster von Economy-/Zonen-Sync
- ❌ Braucht einen neuen "für-alle-Peers"-Broadcast-Mechanismus, den es im
  Projekt noch nicht gibt (siehe oben) — wäre kein reiner Feature-Fix mehr,
  sondern zusätzlich ein Infrastruktur-Umbau
- ❌ Neu verbindende Clients bräuchten einen eigenen Sync-Pfad (analog zum
  initialen State-Snapshot), sonst sehen sie erst beim nächsten Wetterwechsel
  überhaupt ein Wetter

### Option B: Deterministischer Wurf pro Peer, kein Netzwerk-Traffic (gewählt)
Jeder Peer würfelt das Wetter lokal selbst — mit demselben Ergebnis wie jeder
andere Peer derselben Welt, weil der Wurf ausschließlich aus bereits
geteilten, deterministischen Werten abgeleitet wird: `WorldData.world_seed`
(pro Welt fest, bereits die Grundlage für `TerrainGenerator`/`ChunkManager`)
und `WorldTimeService.day_count` (bereits gespeichert/wiederhergestellt,
tickt bereits pro Peer unabhängig ohne RPC — exakt dasselbe akzeptierte
Muster wie bei `day_time` selbst, siehe `WorldService.on_tick()`).
- ✅ Kein neuer Netzwerk-Code, kein neuer Broadcast-Mechanismus nötig
- ✅ Neu verbindende Clients berechnen beim Boot automatisch denselben
  aktuellen Stand (`configure()` rollt für den wiederhergestellten
  `day_count` sofort), kein Extra-Sync-Pfad nötig
- ✅ Folgt einem im Projekt bereits etablierten, akzeptierten Prinzip
  (`TerrainGenerator._rng.seed`, `ChunkManager`s Seed-Weitergabe)
- ❌ Setzt voraus, dass `world_seed` und `day_count` auf allen Peers wirklich
  identisch sind — für `world_seed` bereits garantiert (Grundlage der
  gesamten Terrain-Synchronität), für `day_count` gilt dieselbe Annahme wie
  für `day_time` selbst: keine explizite RPC-Garantie, sondern "tickt mit
  derselben Rate auf jedem Peer" — ein bereits bestehendes, akzeptiertes
  Risiko (leichte Drift bei sehr langen Sessions ohne Reconnect), keine neue
  Schwäche, die dieses ADR einführt
- ❌ Kein Mechanismus, das Wetter serverseitig manuell zu erzwingen (z.B. für
  ein Event) — der Wurf ist rein formelgetrieben

### Option C: Server würfelt, Wetter wird Teil des ohnehin bestehenden
`world_state`-Save-Snapshots, den jeder Client beim Boot einmalig abruft
- ✅ Kein neuer Broadcast-Mechanismus nötig für den Erstzustand
- ❌ Löst das Problem für *laufende* Sessions nicht: ein Wetterwechsel
  während des Spielens würde weiterhin keinen Weg zu bereits verbundenen
  Clients finden, ohne denselben Broadcast-Mechanismus wie Option A zu bauen

## Entscheidung

**Option B.** Deterministischer Wurf, kein Netzwerk-Code. Passt zum
bestehenden Muster und löst sowohl den Erstzustand als auch laufende
Wechsel ohne zusätzliche Infrastruktur.

## Umsetzung (Round 95)

- `scripts/world/weather_time/WeatherService.gd` (neu, `RefCounted`,
  Sibling zu `WorldTimeService`) — `WEATHER_TYPES` (`clear`/`rain`/`storm`/
  `fog`/`snow`, bewusst biom-unabhängig, siehe "Bewusst nicht Teil dieser
  Runde" unten), `roll_for_day(day_count, world_seed)` (idempotent pro Tag,
  `RandomNumberGenerator.seed = world_seed * 1000003 + day_count`),
  `restore()`/`get_save_data()` nach demselben Muster wie
  `WorldTimeService`.
- `WorldEvents.gd`: neues Signal `weather_changed(new_weather, old_weather)`
  + `emit_weather_changed()`.
- `WorldService.gd`: `_weather: WeatherService`-Feld, instanziiert in
  `configure()` direkt neben `_time`; erster Wurf für den (ggf.
  wiederhergestellten) `day_count` am Ende von `configure()`, NACH
  `data.world_seed` final gesetzt UND NACH `_weather.restore()` (Teil von
  `restore_world()`); weitere Würfe in `on_tick()` bei jedem `day_count`-
  Inkrement (derselbe Rollover, der auch `time_of_day_changed` bei
  `WorldTimeService.tick()` auslöst). Neue computed property
  `current_weather` (analog `day_time`/`day_count`).
- `WorldSaveHandler.gd`: `weather`/`weather_last_rolled_day` im Save-Snapshot
  — `weather`-Parameter im Konstruktor ist optional mit Default `null`
  (Rückwärtskompatibilität: bestehende Aufrufer/Tests ohne WeatherService
  bleiben unverändert kompilierbar, Wetter-Keys werden dann einfach
  ausgelassen statt zu crashen).
- Lokale UI-Rückmeldung: `WorldService.on_tick()` ruft bei tatsächlicher
  Wetteränderung `EventBus.ui().emit_notification()` — rein lokal pro Peer,
  kein neuer Netzwerk-Pfad (gleiches Prinzip wie `QuestCustomTrigger.
  hint_text`, Round 73).

**Tests:** `tests/unit/test_weather_service.gd` (neu) — Default-Zustand,
Determinismus über zwei unabhängige Instanzen (simuliert zwei Peers),
statistische Streuung über verschiedene Seeds/Tage, Idempotenz pro Tag,
Signal-Emission nur bei tatsächlicher Änderung, Verhalten ohne EventBus,
Save/Restore-Roundtrip inkl. Alt-Save-Fallback bei unbekanntem/fehlendem
Wetter-Wert. `test_world_save_handler.gd` (+4 Fälle: mit/ohne WeatherService,
Restore-Roundtrip, Alt-Save-Verträglichkeit). `test_world_service.gd` (+2
Fälle: `current_weather`-Property, Save-Data-Keys).

## Konsequenzen

### Positiv
- Erster funktionierender Wetter-Layer, den künftige Systeme (Gameplay-
  Effekte, Visuals, Quests) konsumieren können, ohne selbst Netzwerk-Code
  schreiben zu müssen.
- Kein neuer Netzwerk-Angriffsvektor (keine `any_peer`-RPC, kein zusätzlicher
  State, den ein Client fälschen könnte).

### Negativ / Risiken
- Weiterhin kein Mechanismus, Wetter serverseitig manuell/eventgetrieben zu
  erzwingen — reiner Formelwurf.
- Erbt die bereits akzeptierte `day_count`-Drift-Annahme aus
  `WorldTimeService` (siehe Option B oben) — kein neues Risiko, aber ein
  bestehendes wird durch dieses ADR ein zweites Mal genutzt.

### Mitigationen
- Falls künftig ein "an alle Peers"-Broadcast-Mechanismus für andere Zwecke
  gebaut wird (z.B. für den in ADR-035 zurückgestellten
  Auktionshaus-Live-Broadcast), könnte Wetter optional darauf umgestellt
  werden, um serverseitige Steuerung zu ermöglichen — nicht Teil dieser
  Runde, siehe "Bewusst nicht Teil dieser Runde".

## Bewusst nicht Teil dieser Runde

- Visuelle Wetter-Effekte (Partikelsysteme, Post-Processing, Himmelsfarbe).
- Gameplay-Auswirkungen (z.B. Angel-/Ernte-Boni bei Regen, Sichtweite bei
  Nebel, Bewegungsgeschwindigkeit bei Schnee).
- Biom-Abhängigkeit — `WEATHER_TYPES` ist aktuell ein globaler Pool, die
  Wüste kann genauso `snow` würfeln wie das Wintergebiet. Eine biomabhängige
  Gewichtung wäre eine natürliche Erweiterung von `roll_for_day()`, analog
  zum bereits bestehenden `BiomeDefinition.prop_chances`-Muster
  (ADR-Historie Round 74/75), aber ein eigener, separat zu entscheidender
  Content-Schritt.
- Server-erzwungene/manuelle Wetterwechsel (z.B. Admin-Konsolen-Befehl,
  analog zu `AdminConsole`s Rollen-/Spieler-Befehlen aus ADR-040).
- PvP-Events (`player_killed_by_player`) und Achievement-Events — beide
  weiterhin offen in `TODO-offene-probleme.md`, eigene Folge-Runden.

## Ablösung

[Leer lassen bis dieser ADR durch einen neuen abgelöst wird]
