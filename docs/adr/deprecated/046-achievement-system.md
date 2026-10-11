> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-046: Achievement-System — erste Umsetzung

**Status:** Angenommen — umgesetzt (Round 102)
**Datum:** 2026-07
**Kontext:** Seit ADR-018 (Round 53) als fehlend dokumentiert, seither in
jeder Runde seit 96 explizit als größter verbleibender Brocken
zurückgestellt ("bräuchte vor jedem Event-Namespace erst ein tatsächliches
Achievement-System"). Erste Umsetzung als eigene Design-Runde, wie zuvor
angekündigt.

## Entscheidung

`AchievementService` (`scripts/progression/achievements/
AchievementService.gd`) mit drei Bausteinen:

### Datenmodell

Feste, im Code hinterlegte `DEFINITIONS`-Liste (kein Resource-/Editor-
Workflow in dieser Runde) — pro Achievement: `name`, `description`,
`target` (Zähler-Ziel), `category`. Fünf Beispiel-Achievements über drei
bereits existierende Domänen (Combat, Economy, Social), um die
Infrastruktur nicht mit leerem Inhalt auszuliefern:
`first_blood`/`pvp_veteran` (Combat), `first_sale`/`auctioneer`
(Economy), `community_watch` (Social).

Fortschritt: einfacher Integer-Zähler pro `(player_id, achievement_id)`
(`grant_progress()`), automatisches Freischalten bei Erreichen von
`target` (`_unlock()`).

### Trigger-Quellen — bewusst nur drei, alle nachweislich autoritäts-only

`AchievementService` verbindet sich in `configure()` direkt mit drei
bestehenden Service-Signalen:
- `PvPDeathLossService.death_loss_applied`
- `AuctionHouseService.listing_created`
- `ReportService.report_submitted`

Alle drei feuern **ausschließlich auf der Autorität** — jeweils hinter
einem `_require_authority()`-Guard in ihrem jeweiligen
`on_..._confirmed()`. Das ist kein Zufall, sondern die Voraussetzung dafür,
dass `AchievementService` diese Signale überhaupt gefahrlos als
Trigger-Quelle nutzen kann, ohne selbst jeden einzelnen Aufruf erneut zu
prüfen, ob der Aufrufer wirklich die Autorität ist.

**Bewusst NICHT `ChatService.message_received` als Trigger-Quelle** —
dieses Signal feuert auf JEDEM Client (auch Empfängern einer Nachricht),
nicht nur der Autorität. Einen Achievement-Fortschritt daran zu hängen
würde genau den Fehler machen, den `grant_progress()`s eigener
`_require_authority()`-Guard verhindern soll: ein Client würde lokal
"Fortschritt" berechnen, der nie zur autoritativen Wahrheit wird.

### Multiplayer-Benachrichtigung

`grant_progress()`/`_unlock()` selbst laufen nur auf der Autorität
(`_require_authority()`, exakt dasselbe Muster wie `AuctionHouseService`/
`ReportService`/`PvPDeathLossService`). Der Host sieht sein eigenes Unlock
direkt über das lokal emittierte `achievement_unlocked`-Signal. Ein
entfernter Client wird zusätzlich per neuem, dediziertem RPC-Paar
benachrichtigt: `NetworkBridge.send_achievement_unlocked_for_player()`/
`_rpc_receive_achievement_unlocked()` + Signal
`achievement_unlocked_received` — analog `send_chat_message_for_player()`
(ADR-043). Reine Autorität→Ziel-Spieler-Zustellung, kein Broadcast (ein
Unlock ist fachlich privat zum jeweiligen Spieler, wie ein Whisper).

**Bewusst KEIN Tier-1-Fallback-Zweig in `send_achievement_unlocked_for_
player()`** (im Unterschied zu `send_chat_message()`/`send_report_
submit()`): es gibt keinen Client-Request, den diese Funktion
stellvertretend lokal ausführen müsste — Achievements werden ausschließlich
durch autoritative Spiel-Logik ausgelöst, nie durch einen Client-Request.
Entsprechend braucht `NetworkBridge` auch **keine Rückreferenz** auf
`AchievementService` (kein `_achievement`-Feld, kein Eintrag in dessen
`configure()`) — einfacher als das Chat-/Report-Paar.

### Persistenz

`SAVE_KEY = "achievements"` — Fortschritt UND freigeschaltete IDs
überleben Sitzungen, Save-Interface exakt nach `AuraService`/
`ReportService`-Muster.

## Optionen (verworfen)

- **Resource-/Editor-Workflow für Definitionen** (`.tres`-Dateien pro
  Achievement) — verworfen für diese Runde: für fünf Beispiel-Achievements
  überdimensioniert, verfrühte Infrastruktur ohne echten Bedarf. Eine
  feste Code-Liste ist für den Umfang dieser Runde ausreichend und
  einfacher zu testen.
- **Belohnungen (Item/Gold/Titel) beim Freischalten** — verworfen: hätte
  eine Kopplung an `RewardDispatcher` gebraucht und die Frage
  aufgeworfen, WELCHE Belohnung zu WELCHEM Achievement gehört — eine
  Design-Entscheidung, die eigenständig verdient, nicht nebenbei in der
  Infrastruktur-Runde getroffen zu werden.
- **`ChatService.message_received` als Trigger-Quelle** — verworfen, siehe
  "Entscheidung" oben (Multiplayer-Korrektheit).
- **Achievement-Fortschritt lokal auf jedem Client selbst berechnen**
  (statt zentral auf der Autorität) — verworfen: würde bei
  unterschiedlichen Clients zu unterschiedlichem, nicht synchronisiertem
  Fortschritt führen. Derselbe Grund, aus dem jeder andere autoritative
  Service hier (Trading, PvP, Reports) zentral auf der Autorität rechnet.

## Konsequenzen

### Positiv
- Erste konkrete Nutzung der seit mehreren Runden bestehenden
  Signal-Infrastruktur (`death_loss_applied`, `listing_created`,
  `report_submitted`) als tatsächliche Cross-System-Verbindung — genau der
  Anwendungsfall, für den u. a. `EventBus.combat` (Round 98) gedacht war.
- Klar erweiterbar: ein neues Achievement bedeutet einen neuen
  `DEFINITIONS`-Eintrag + ggf. einen neuen `grant_progress()`-Aufruf an
  einer bestehenden oder neuen autoritativen Signal-Quelle — kein
  struktureller Umbau nötig.
- Folgt konsequent etablierten Konventionen (`_require_authority()`,
  Save-Interface, gezielte RPC-Benachrichtigung) — kein neues Muster für
  künftige Wartung.

### Negativ / Risiken
- Nur drei Trigger-Quellen — viele denkbare Achievements (Sammel-/
  Erkundungs-/Skill-bezogen) haben noch keine autoritative Signal-Quelle,
  an die sich `AchievementService` anschließen könnte, ohne dass diese
  Quelle selbst erst nachgezogen wird.
- Kein Pull-/Sync-Pfad — ein Client sieht nur LIVE-Unlocks während er
  verbunden ist, nicht seinen historischen Gesamtstand nach einem
  Neustart oder späten Beitritt (siehe unten).

## Bewusst nicht Teil dieser Runde

- Kein Resource-/Editor-Workflow für Definitionen (siehe oben).
- Keine Belohnungen beim Freischalten (siehe oben).
- Kein Chat/Social als Trigger-Quelle (siehe oben, Multiplayer-Korrektheit).
- **Kein Snapshot-/Sync-Pfad** — kein `request_achievement_snapshot()`
  analog `request_listings_snapshot()` (ADR-035). Ein Client, der später
  beitritt oder die App neu startet, sieht seinen vollständigen
  Fortschritt/seine Unlocks aktuell nicht, ohne dass die Autorität ihn
  aktiv anfragt. Nur die Live-Unlock-Benachrichtigung
  (`achievement_unlocked_received`) ist verdrahtet.
- Kein UI-Panel/Fortschrittsanzeige, kein `UIContext`-Eintrag.
- Keine versteckten/geheimen Achievements (kein `hidden`-Flag).
- Keine weiteren Trigger-Quellen über die genannten drei hinaus (Chat
  explizit ausgeschlossen, siehe oben; andere Systeme wie Quests/Skills/
  Angeln wurden für diese Runde nicht angebunden).

**Ehrlich offen:** wie in jeder Runde seit 89 — kein Godot-Editor/
Headless-Runner in dieser Entwicklungsumgebung verfügbar, nur strukturell
geprüft (Guard-Reihenfolge, Signalverbindungen gegen die drei echten
Quell-Services abgeglichen), nicht gegen eine echte Zwei-Peer-Verbindung
gelaufen.

## Umsetzungsstand (Round 103) — Statistiken/Belohnungen/Datengetriebene Definitionen/Sync-Pfad

Schließt vier der fünf in Round 102 offen gelassenen Punkte, explizit
angefordert.

- **Vierte Trigger-Quelle: `StatsService.stat_changed`** (siehe
  [ADR-047](047-statistics.md)) — vier neue stat-basierte Achievements
  (`wanderer`/`high_jumper`/`gravity_defier`/`monster_hunter`),
  `STAT_ACHIEVEMENT_MAP` bildet `stat_name → Array[achievement_id]` ab.
  `grant_progress()` von `int` auf `float` umgestellt (nötig für
  Meter-Werte) — betrifft auch `get_progress()`/`achievement_progress`.
- **Datengetriebene Definitionen** — neues `AchievementDefinition.gd`
  (Resource-Script) + `data/achievements/*.tres` (9 Dateien) +
  `DataManifest.ACHIEVEMENTS` + `DataService._load_achievements()`/
  `get_achievement()`/`get_all_achievements()` — exakt dasselbe Muster wie
  Quests/Items/Skills/CombatProfiles. `DEFAULT_DEFINITIONS` (der
  Code-Fallback aus Round 102) bleibt bestehen und wird von
  DataService-Definitionen ERGÄNZT/ÜBERSCHRIEBEN, nicht komplett ersetzt —
  funktioniert damit weiterhin ohne DataService (z. B. in Unit-Tests ohne
  vollen Service-Graphen). **Ehrlich offen:** die `.tres`-Dateien folgen
  exakt dem bewährten Muster, aber ob sie im Godot-Editor korrekt als
  `AchievementDefinition`-Ressourcen im Inspector erscheinen, ließ sich
  ohne Editor-Zugriff nicht verifizieren.
- **Belohnungen** — optionales `reward_gold`-Feld pro Definition, bei
  Unlock direkt über `CurrencyService.request_add_gold()` vergeben.
  Bewusst NICHT über `RewardDispatcher` (dessen `dispatch()` ist an
  `QuestReward`/`quest_id` gekoppelt — fachfremder Typ für Achievements).
  Kein Item-/XP-Reward-Feld in dieser Runde.
- **Snapshot-Sync für spät joinende Clients** — neu:
  `request_snapshot()`/`on_snapshot_requested()` +
  `NetworkBridge.send_achievement_snapshot_request()`/
  `_rpc_achievement_snapshot_request()` (Client→Autorität, Pull) und
  `send_achievement_snapshot_for_player()`/`achievement_snapshot_received`
  (Autorität→Ziel-Spieler, Antwort) — exakt wie
  `AuctionHouseService.request_listings_snapshot()` (ADR-035). Schließt
  die in Round 102 „Bewusst nicht Teil dieser Runde" genannte Lücke
  vollständig.
- **`NetworkBridge`-Kreis geschlossen:** `network_bridge`s eigene
  `ServiceDefinition` bekommt jetzt doch einen `"achievement"`-Eintrag in
  `optional_deps` (Round 102 hatte das bewusst ausgelassen, mit der
  Begründung "kein Tier-1-Fallback-Zweig nötig" — das stimmte für die
  reine Unlock-Benachrichtigung, aber der neue Snapshot-Request-Pfad
  braucht die Rückreferenz, exakt wie bei chat/report).

**Bewusst weiterhin NICHT Teil dieser Runde:** kein UI-Panel — siehe
ADR-047 "Bewusst nicht Teil dieser Runde" für die Begründung, warum ein
`.tscn`-Panel ohne Godot-Editor-Zugriff nicht blind gebaut wurde (höchstes
Risiko, etwas nicht mehr Verifizierbares zu bauen, von allen offenen
Punkten). Keine versteckten Achievements, kein Item-/XP-Reward.

**Tests:** `tests/unit/test_achievement_service.gd` (+14 — Stats-Trigger,
Belohnungen inkl. Fehlen-der-CurrencyService-Fall, Snapshot-Request/
-Antwort, DataService-Merge-Verhalten inkl. "Override" und "neue ID"),
`tests/unit/test_stats_service.gd` (neu, 16 Tests).

**Ehrlich offen (Round 103):** zusätzlich zum bereits oben Genannten —
der `Player.gd`-Bewegungs-Tracking-Eingriff (siehe ADR-047) ist der
riskanteste blinde Codepfad dieser gesamten Session; bewusst minimal/
additiv gehalten, aber nicht gegen echte Godot-Physik getestet.

## Umsetzungsstand (Round 104) — UI-Panel + Client-Empfangs-Fund

Explizite Vorgabe ("nächstes UI von Achievement vor Tutorial/Onboarding").
Schließt den letzten in Round 102/103 zurückgestellten Punkt.

**Entscheidung gegen `.tscn`:** Round 103 hatte das UI-Panel bewusst
zurückgestellt, mit der Begründung, ein blind (ohne Godot-Editor)
gebautes `.tscn` sei das höchste Risiko im gesamten Achievement-System.
Diese Sorge betrifft ausschließlich Editor-Scene-Dateien — sie gilt nicht
für den programmatischen HUD-Panel-Weg, den das Projekt bereits für
Skill/Quest/Shop/Bank/Trade/Auktionshaus produktiv nutzt (reine
GDScript-Node-Konstruktion in einer `*Visuals`-Klasse, kein `.tscn`).
Das Achievement-Panel folgt exakt diesem bereits mehrfach verifizierten
Muster — das ursprüngliche Risiko entfällt dadurch vollständig, statt nur
gemindert zu werden.

**Gebaut:**
- `scripts/progression/achievements/ui/AchievementPanelVisuals.gd` —
  Toggle-Button 🏆 (nächster freier Slot nach Skill 112–192/Quest
  208–288 → 304–384), Panel mit Kategorien-Sektionen (combat/economy/
  social/stats → deutsche Label), Fortschrittsbalken + Gold-Belohnungs-
  Anzeige pro Zeile, gesperrt (🔒, gedimmt)/freigeschaltet (✅, voll
  sichtbar) visuell unterschieden.
- `AchievementPanelController.gd` — analog SkillPanelController: lauscht
  auf `achievement_unlocked`/`achievement_progress`/`achievements_synced`,
  filtert konsequent auf `ctx.get_local_player_id()`. Fragt beim Öffnen
  einmalig `request_snapshot()` an (deckt sowohl späten Client-Join als
  auch einen einfachen Prozess-Neustart ab). Unlock zusätzlich als Toast
  über den bestehenden `NotificationController`
  (`ctx.bus().ui().emit_notification()`) — kein neues Toast-System.
- `AchievementPanelComponent.gd` + Registrierung in `HUDBuilder.build_all()`.
- `IUIContext`/`UIContext`: neuer Getter `get_achievement_service()`,
  aufgelöst in `from_registry()` analog den anderen Facade-Gettern.

**Unerwarteter Fund beim Bauen, sofort mitgefixt (kein reiner UI-Task
mehr):** `NetworkBridge.achievement_unlocked_received`/
`achievement_snapshot_received` (beide seit Round 103 vorhanden) hatten
NIE einen Listener — die Payloads kamen auf einem Nicht-Autoritäts-Peer
technisch an, aber nirgends im Code wurde reagiert. Ohne Fix hätte das
neue Panel auf jedem Client außer dem Host dauerhaft leer/veraltet
angezeigt, weil `AchievementService`s lokaler State (`_progress`/
`_unlocked`) dort nie befüllt worden wäre. Fix in `AchievementService.gd`
(siehe Klassenkommentar "CLIENT-EMPFANG"):
- `_on_remote_unlock_received(payload)` / `_on_remote_snapshot_received(payload)`
  — übernehmen Server-Payloads direkt in `_progress`/`_unlocked`, OHNE
  über `grant_progress()`/`_unlock()` zu laufen (die sind über
  `_require_authority()` für Nicht-Autorität gesperrt — hier wird nichts
  neu entschieden, nur ein bereits autoritativ getroffenes Ergebnis
  gespiegelt). Re-emittieren dieselben lokalen Signale wie die Autorität
  (`achievement_unlocked`/`achievement_progress`), plus neues
  `achievements_synced(player_id)` für den vollständigen Snapshot-Fall.
- `_connect_network_receive()` — verbunden sowohl in `configure()` als
  auch in `inject_network_bridge()` (Phase-C8-Late-Inject, exakt wie bei
  chat/report/pvp_death_loss), analog `AuctionHouseService.
  _connect_economy_sync()`.
- Neuer optionaler Dep `session_manager` (app-scoped, über
  `fallback_registry` auflösbar wie bei `WorldService`) — liefert
  `_local_player_id()` für die beiden Handler; `BootstrapConfig.tres`
  entsprechend ergänzt.

**Tests:** `tests/unit/test_achievement_service.gd` (+10 — Signal-Connect
in `configure()`/`inject_network_bridge()`, Remote-Unlock setzt Fortschritt/
Unlock UND re-emittiert lokal, fehlender SessionManager loggt Fehler statt
zu crashen, Remote-Snapshot überschreibt Fortschritt/Unlocked, `achievements_
synced` feuert für die richtige player_id, `on_cleanup()` trennt beide
Signale). `tests/unit/test_achievement_panel_controller.gd` (neu, 9 Tests
— Signal-Connect, initialer Render aller Definitionen gesperrt, Unlock/
Progress/Sync jeweils mit player_id-Filter-Gegenprobe, Toast-Inhalt inkl.
Gold-Betrag).

**Bewusst nicht Teil dieser Runde:** kein `hidden`-Flag/Blur für noch
nicht erreichte Achievements (alle Definitionen sind immer sichtbar,
nur der Fortschritt ist gesperrt) — deckt sich mit ADR-046s bereits
bestehender Entscheidung gegen versteckte Achievements. Kein
Kill-Feed-artiges "andere Spieler haben X freigeschaltet" — Unlocks
bleiben unverändert privat. Keine Sortierung/Filterung im Panel selbst
über Kategorien hinaus.

