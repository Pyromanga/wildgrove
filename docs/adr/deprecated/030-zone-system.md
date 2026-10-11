> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-030: Generisches Zonen-System

**Status:** Vorgeschlagen — Entwurf, Round 68 Folge-Session
**Datum:** 2026-07
**Kontext:** Fundament für PvP-Gebiete, Diebes-Zonen (ADR-039), Minigames,
Quest-Trigger. Betrifft neu: `ZoneService`, `ZoneTriggerVolume`, `ZoneConfig`
(Resource). Vorgelagert zu ADR-031 bis ADR-039 — jedes der neuen Wirtschafts-/
PvP-ADRs braucht mindestens den Zonentyp-Check (`is_pvp`, `is_theft_zone`, …).

## Problem

Es existiert aktuell **kein** wiederverwendbares Zonen-Konzept. Was im Code
danach aussieht, ist es nicht:

- `scripts/ui/LayoutManager.gd` — `Rect2`-Helfer für UI-Layout, thematisch
  unverwandt.
- `scripts/progression/quests/triggers/QuestCustomTrigger.gd` — ein Ad-hoc
  `Area2D`/`body_entered`-Trigger, fest verdrahtet auf einen einzelnen
  Quest-Schritt, nicht generisch, keine zentrale Registry.

Jedes neue Feature, das "bin ich gerade in Zone X" braucht (PvP-Aktivierung,
Diebstahl-Erlaubnis, Minigame-Grenzen), würde ohne dieses ADR seinen eigenen
`Area2D`+Signal-Verdrahtung bauen — dieselbe Fragmentierung, die ADR-020 für
Interaktionen und ADR-018 für Events bereits beseitigt haben.

## Optionen

### Option A: Weiterhin Ad-hoc pro Feature
Jedes Feature baut seinen eigenen Trigger wie `QuestCustomTrigger`.
- ✅ Kein Vorlauf-Aufwand
- ❌ N-fache Fragmentierung, keine einheitliche Multiplayer-Autorität, jedes
  Feature erfindet Enter/Exit-Semantik neu

### Option B: Rein datengetriebene Zonen (kein Node/Volume)
Zonen nur als Koordinaten-Polygone in einer zentralen Resource, Prüfung per
Distanz-/Punkt-in-Polygon-Check bei Bedarf (Polling statt Event).
- ✅ Keine zusätzlichen Szene-Nodes
- ❌ Polling-Overhead pro Frame/Interaktion; Position muss ohnehin schon
  server-seitig bekannt sein (ADR-025), aber ständiges Poly-Testing ist
  unnötige CPU-Last gegenüber physik-basierten Trigger-Events

### Option C: Hybrid — Resource-Config + generisches Trigger-Volume + zentraler Service (gewählt)
- `ZoneConfig` (Resource): `zone_id: StringName`, `tags: Array[StringName]`
  (z. B. `"pvp"`, `"safe"`, `"theft"`, `"minigame:capture_the_flag"`), plus
  optionales Metadata-Dictionary für Konsumenten (Quest-ID, Minigame-Regeln).
- `ZoneTriggerVolume` (Node, `Area3D`/`Area2D` je nach Weltdimension): rein
  mechanisch, kennt nur seine `zone_id`, meldet Enter/Exit an `ZoneService`.
- `ZoneService` (ServiceNode, World-Scope nach ADR-009, serverautoritativ wie
  Movement in ADR-025): führt `peer_id → Set[zone_id]` (mehrere Zonen können
  überlappen), broadcastet `zone_entered(peer_id, zone_id)` /
  `zone_exited(peer_id, zone_id)` über einen neuen `EventBus.zones()`-
  Namespace (analog zum Domain-Split aus ADR-018).
- ✅ Eine Quelle der Wahrheit, kein Polling, jedes Feature konsumiert nur
  Events statt eigene Trigger zu bauen
- ✅ Passt zu bestehendem Muster: Resource-Configs (`GameConfig.tres`) +
  zentrale Services + EventBus-Namespacing (ADR-002/018)
- ❌ Overlap-Handling (mehrere Zonen gleichzeitig) muss sauber spezifiziert
  werden, sonst Fehlerquelle bei sich überschneidenden Trigger-Volumes

## Entscheidung

Option C. `ZoneService` läuft **ausschließlich autoritativ** (Server/Host),
analog zur Movement-Autorität aus ADR-025 — Clients dürfen ihre eigene
Zonen-Zugehörigkeit nie selbst bestimmen, da PvP-Aktivierung (ADR-032) und
Diebstahlerlaubnis (ADR-039) direkt davon abhängen. Der Client bekommt nur
die daraus resultierenden UI-Effekte (z. B. "Du betrittst ein PvP-Gebiet")
per Broadcast, nie das Enter/Exit-Event selbst als Entscheidungsgrundlage.

Zonen selbst (welche Gebiete PvP/Diebstahl/Minigame sind) sind laut
Projektinhaber bereits inhaltlich festgelegt — dieses ADR liefert nur die
Mechanik, nicht die konkrete Weltkarten-Belegung.

## Konsequenzen

### Positiv
- Einheitlicher Konsumationspunkt für alle folgenden ADRs (032, 036, 039)
- Kein Wildwuchs an Ad-hoc-`Area2D`-Triggern mehr

### Negativ / Risiken
- Overlap mehrerer Zonen (z. B. PvP-Zone innerhalb einer größeren
  Minigame-Zone) muss definiert sein: additiv (alle Tags gelten) statt
  Priorität — sonst Sonderfälle
- `QuestCustomTrigger.gd` wird nicht ersetzt in diesem ADR (bewusst
  out-of-scope), aber langfristig Migrationskandidat auf `ZoneTriggerVolume`

### Mitigationen
- Overlap-Semantik: additiv/Set-basiert (siehe Entscheidung), keine
  Prioritätsauflösung nötig, da Konsumenten selbst filtern (PvP-Check fragt
  nur nach `"pvp"`-Tag, ignoriert andere)

## Ablösung

—

## Implementierungsnotizen (Round 70)

Erste Umsetzung: `ZoneEvents` (neuer `EventBus.zones()`-Namespace),
`ZoneConfig` (Resource), `ZoneService` (`extends Service`, ADR-003 —
peer_id-gekeyt, siehe Klassenkommentar für Abgrenzung zu den player_id-
Save-Bucket-Services aus ADR-029), `ZoneTriggerVolume` (Area3D, Vorbild
`QuestCustomTrigger`). Registriert in `ServiceKeys`/`BootstrapConfig.tres`
als Session-Service, `WorldService` verdrahtet `zone_triggers`-Gruppe
(`_wire_zone_triggers()`) bei `on_ready()`/`inject_network_bridge()`.
Tests: `test_zone_service.gd`, `test_zone_trigger_volume.gd`.

Autoritäts-Guard bewusst OHNE "eigener Spieler"-Ausnahme (anders als
`QuestCustomTrigger`): Movement ist seit ADR-025 server-autoritativ
simuliert, die Autorität sieht jeden Area3D-Overlap bereits selbst.

Bewusst nicht Teil dieser Runde (offen für Folge-Runden):
- Broadcast der Zonen-Mitgliedschaft an Remote-Clients für UI-Feedback
  (NetworkBridge-Kanal fehlt noch — aktuell nur autoritätsseitig sichtbar).
- Migration von `QuestCustomTrigger` auf `ZoneTriggerVolume`/Tags (out of
  scope laut Entwurf oben).
- Tatsächliche Zonen-Platzierung in den Weltszenen (Level-Design, keine
  Mechanik).

## Implementierungsnotizen (Round 72) — Client-Broadcast

Ergänzt: `ZoneService.report_enter()`/`report_exit()` pushen jetzt zusätzlich
zum lokalen `EventBus.zones()`-Signal per `NetworkBridge.send_zone_update_for_peer()`
gezielt an den betroffenen Client (kein Broadcast an alle — nur der
betroffene Spieler selbst bekommt seine eigene Mitgliedschaft mitgeteilt,
analog zu `send_economy_update_for_player()`). Empfänger-Seite
(`_rpc_receive_zone_update()`) ruft dieselbe `ZoneService`-API auf, die auch
`ZoneTriggerVolume` auf der Autorität nutzt — kein separater Client-
Mutationspfad, ein Client hat also nach Empfang exakt denselben lokalen
`ZoneService`-Zustand wie die Autorität für seinen eigenen `peer_id`.

Verdrahtung folgt der etablierten Konvention gegen Zyklen im
`ServiceDependencyResolver` (siehe `NetworkBridge`↔`WorldService`): einseitige
`configure()`-Dep-Kante `network_bridge → zone_service`, Umkehrung
(`ZoneService.inject_network_bridge()`) über denselben Phase-C8-Late-Inject
wie `WorldService`/`Inventory`/`Quest`/etc. (`BootPipeline.gd`).

**Nicht getestet:** `_rpc_receive_zone_update()`s `multiplayer.is_server()`-
Guard — aus demselben strukturellen Grund wie `_rpc_receive_economy_update()`/
`_rpc_receive_initial_state()` (beide ebenfalls ungetestet): das Verhalten
von `multiplayer.is_server()` ohne echten `MultiplayerPeer` ist in einer
reinen Tier-1-Testumgebung nicht zuverlässig verifizierbar, siehe
TODO-offene-probleme.md „Tests gegen die echte Godot/GUT-Runtime". Die
Sende-Seite (`ZoneService` → `send_zone_update_for_peer()`) ist per Spy
getestet (`test_zone_service.gd`), der eigentliche `rpc_id()`-Transport nicht
(gleiche Lücke wie überall sonst im Netzwerk-Layer).

Weiterhin offen: tatsächliche Zonen-Platzierung (Level-Design),
`QuestCustomTrigger`-Migration (out of scope).
