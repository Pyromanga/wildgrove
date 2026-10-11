> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-031: Rollenbasiertes Permission-System

**Status:** Umgesetzt bis auf Tier-3-Root-Konto (Round 82) — siehe Umsetzungsstand unten
**Datum:** 2026-07
**Kontext:** Fundament für Admin-PvP-Ausnahme (ADR-032) und das später geplante
Moderationswerkzeug (`TODO-offene-probleme.md`, Punkt "Reporting-/
Moderationswerkzeug"). Neu: `PermissionService`, `Role`-Resource.

## Problem

Es gibt aktuell keine Rollen-/Rechte-Ebene. Was existiert, sind
Interaktions-**Guards** (ADR-020) — die prüfen, *ob eine Aktion autoritativ
gültig ist* (z. B. Besitz eines Items), nicht *ob ein Spieler etwas darf,
das andere Spieler nicht dürfen*. Für die Admin-Ausnahme vom PvP-Zwang
(ADR-032) und für ein zukünftiges Moderationswerkzeug braucht es eine echte
Rollen-Ebene, die keine Verwechslung mit den bestehenden Guards ist.

## Optionen

### Option A: Einzelnes `is_admin: bool`-Flag
- ✅ Trivial umzusetzen
- ❌ Nicht erweiterbar — Moderationswerkzeug bräuchte eine eigene,
  inkompatible Lösung nachträglich

### Option B: Volles RBAC von Anfang an (gewählt)
Rollen (`Player`, `Moderator`, `Admin`) mit erweiterbaren
Capability-Sets (`Array[StringName]`), datengetrieben statt hartcodiert.
- ✅ Zukunftssicher fürs Moderationswerkzeug, keine Zweitlösung nötig
- ✅ Neue Capability = Daten-Änderung, kein Code-Umbau
- ❌ Mehr Vorlauf-Komplexität als für den reinen PvP-Anwendungsfall nötig wäre

## Entscheidung

Option B. `PermissionService` (App-Scope nach ADR-009, da Rollen account-weit
gelten, nicht pro Welt/Charakter) mit:

- `Role`-Resource: Name + `Array[StringName]` Capabilities
- Initiale Rollen:
  - **Player** — keine besonderen Capabilities
  - **Moderator** — `kick_player`, `mute_player`, `teleport_self`,
    `teleport_player`, `spectate_player`, `view_reports` (Letzteres als Stub,
    da das Moderationswerkzeug selbst noch nicht existiert — die Capability
    liegt aber schon bereit, damit das Werkzeug später nicht erneut das
    Rollenmodell anfassen muss)
  - **Admin** — alle Moderator-Capabilities + `pvp_immune`, `full_access`
- `PermissionService.has_capability(player_id: String, capability: StringName) -> bool`
  — **ausschließlich serverautoritativ geprüft**, nie clientseitig vertraut
  (gleiches Muster wie Inventar-/Movement-Validierung, Lehre aus Round 45)
- Rolle wird `player_uuid`-verschachtelt persistiert (analog zum Rekeying aus
  ADR-029), nicht `peer_id`-verschachtelt — Rollen dürfen Reconnects
  überleben

### Rollenzuweisung nach Tier (ADR-010)
- **Tier 1 (Solo):** der einzige lokale Spieler ist immer `Admin` — kein
  anderer Spieler existiert, gegen den das relevant wäre.
- **Tier 2 (Hosted Coop):** der Host ist immer `Admin`, passend zum
  informellen Vertrauensmodell aus ADR-010 (Freunde im selben Freundeskreis).
- **Tier 3 (Dedizierter Server):** ein dediziertes `root`/Admin-Konto
  existiert von Anfang an; dessen Passwort **muss** beim Ersteinrichten
  geändert werden (kein Betrieb mit Standard-Passwort möglich — Pflicht-
  Rotation vor erstem produktivem Start, ähnlich zu Erstinbetriebnahme-
  Mustern bei Admin-Panels/Routern).
- **Admin-Terminal-Login:** eigenständige Admin-Session, gestartet über
  Server-Terminal/Konsole statt regulärem Client-Login, aber über **dieselbe
  Session-Bootstrap-Maschinerie** wie jeder reguläre Login (kein
  Sonderpfad). Kein Übernehmen/Hijacken eines bereits verbundenen
  Spieler-Charakters — das würde die feste `player_uuid`/Session-Zuordnung
  aus ADR-025/ADR-029 mitten in der Session aufbrechen, ein Sonderfall, den
  das Autoritätsmodell bewusst vermeidet. Der eigentliche Bedarf dahinter
  ("sehen, was Spieler X gerade sieht") ist bereits durch die
  `spectate_player`-Capability (siehe oben) abgedeckt, ohne
  Autoritäts-Sonderfall. Admin-Konto bekommt einen eigenen, vermutlich
  unsichtbaren/noclip-fähigen Charakter in der Welt.

## Konsequenzen

### Positiv
- Ein Modell für PvP-Ausnahme *und* künftiges Moderationswerkzeug, keine
  Doppelarbeit
- Capability-Strings sind datengetrieben — QA/Design kann Rollen anpassen
  ohne Code-Änderung

### Negativ / Risiken
- Overengineering-Risiko, falls Moderationswerkzeug nie kommt — bewusst in
  Kauf genommen, da Projektinhaber das explizit priorisiert hat
- Rollenzuweisung und Admin-Terminal-Zugang sind jetzt vollständig geklärt
  (siehe Entscheidung) — keine offenen Punkte mehr in diesem ADR

### Mitigationen
- Capability-Liste bewusst minimal gehalten (kein volles Feature-Set für ein
  Tool, das noch nicht designed ist) — nur so viel wie zum jetzigen
  Kenntnisstand plausibel

## Ablösung

—

## Umsetzungsstand (Round 82)

**Neu seit Round 80 (Teil 2 — Tier-Verdrahtung):**
- `ServiceOrchestrator._on_session_requested()` ruft jetzt vor
  `create_character_scope()` `_ensure_default_role_for_tier(player_id)` auf.
  Tier 1 (Solo) und Tier 2 (Host) bekommen dadurch bei ihrem eigenen
  Session-Boot automatisch `PermissionService.ensure_default_role(player_id,
  "admin")` — genau wie unter "Rollenzuweisung nach Tier" oben entschieden.
  Tier 2 Client bekommt keinen Eintrag (Fallback bleibt die Default-Rolle
  `player`).
- Die Tier-Entscheidung selbst ist als reine, statische
  `ServiceOrchestrator._should_get_default_admin(is_server, is_dedicated_server)`
  von den Service-Lookups getrennt und isoliert getestet.
- Tier 3 (Dedizierter Server) bleibt wie geplant ausgeschlossen — siehe
  unverändert gültiger Abschnitt weiter unten zum fehlenden Root-Konto.
- Tests: `tests/unit/test_service_orchestrator_tier_roles.gd`.

Damit ist ADR-031 bis auf das Tier-3-Root-Konto (siehe unten, eigenes Thema:
braucht erst eine Passwort-Auth-Schicht) vollständig umgesetzt.

## Umsetzungsstand (Round 80)

**Umgesetzt:**
- `Role.gd` (Resource, reines Datenmodell — `id`/`display_name`/`capabilities`),
  drei Basis-Rollen als `.tres`-Dateien: `data/roles/player.tres` (keine
  Capabilities), `data/roles/moderator.tres`, `data/roles/admin.tres` —
  Capability-Sets exakt wie oben unter "Entscheidung" festgelegt.
- `PermissionService` (App-Scope, registriert in `BootstrapConfig.tres` unter
  `global_services`, `ServiceKeys.PERMISSION_SERVICE`): `has_capability()`,
  `is_admin()`, `get_role_id()`/`get_capabilities()`, `assign_role()`/
  `revoke_role()`, `ensure_default_role()` (idempotente Erstzuweisung —
  überschreibt nie eine bereits gesetzte Rolle, z.B. eine manuelle
  Moderator-Beförderung).
- Persistenz `player_uuid`-verschachtelt (`user://roles.json`, atomic write,
  gleiches Muster wie `SettingsService`) — überlebt Reconnects, wie gefordert.
- Rollen selbst preload()'t (nicht dynamisch per Pfad geladen) — vermeidet die
  aus `DataManifest`s Klassenkommentar bekannte Android-Export-Falle
  (`DirAccess`/dynamisches `load()` wird vom Exporter nicht erkannt).
- `SessionManager.is_solo()` als neuer öffentlicher Wrapper um das private
  `_has_active_peer()` ergänzt — Baustein für die noch offene Tier-Zuweisung
  unten.
- Tests: `tests/unit/test_permission_service.gd` (Rollen laden, alle drei
  Capability-Sets, `assign_role()`/`revoke_role()`, `ensure_default_role()`s
  Idempotenz, Persistenz-Roundtrip, korrupte/unbekannte Daten in der Datei).

**Bewusst NICHT Teil dieser Runde (siehe TODO-offene-probleme.md):**
- ~~**Tier-basierte Auto-Zuweisung ist noch nicht verdrahtet.**~~ — **erledigt
  in Round 82**, siehe "Umsetzungsstand (Round 82)" oben.
  `ensure_default_role()` existiert und ist getestet, wird aber an keiner
  Stelle im Boot-/Login-Ablauf (`ServiceOrchestrator._on_session_requested()`
  / `SaveSystem.begin_session()`) aufgerufen. Das ist ein eigener, riskanterer
  Schnitt an einer bereits gewachsenen Pipeline — bewusst isoliert für ein
  eigenes Review, statt ihn hier huckepack mitzunehmen.
- **Tier-3-Root-Konto mit Pflicht-Passwort-Rotation existiert nicht.** Das
  Projekt hat aktuell KEIN Passwort-basiertes Login — nur TOFU-Secrets über
  `PlayerCredentialStore` (ADR-029, "beweise, dass diese `player_uuid` zu
  diesem Peer gehört", kein Username/Passwort). Die im ADR beschriebene
  Pflicht-Rotation braucht dafür erst eine eigene Auth-Schicht; ohne die wäre
  ein "Root-Konto" hier nur ein Rollen-Datenbankeintrag ohne echten
  Zugriffsschutz — bewusst nicht vorgetäuscht.
- `kick_player`/`mute_player`/`teleport_player`/`spectate_player`/
  `view_reports` sind als Capability-Strings vorhanden und abfragbar, haben
  aber noch keine Aufrufer (kein Admin-UI, kein Moderationswerkzeug) — wie im
  ADR selbst schon als Stub angekündigt ("die Capability liegt aber schon
  bereit, damit das Werkzeug später nicht erneut das Rollenmodell anfassen
  muss").
