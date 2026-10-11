# ADR-017: Cross-Scope Service Access — ein einziger Mechanismus

**Status:** Akzeptiert
**Datum:** 2026-07
**Kontext:** Löst die in `docs/audit/AUDIT-05-clean-onion-vs-mutation-onion.md` offen
gelassene Entscheidung. Betrifft `ServiceInitializer.gd`, `BootPipeline.gd`,
`BootstrapConfig.tres`, `NetworkBridge.gd`, `SessionManager.gd`. Voraussetzung für
die Fortsetzung von ADR-015/MIGRATION-015.

## Problem

AUDIT-05 hat mit Datei:Zeile belegt, dass es zwei koexistierende, undokumentierte
Mechanismen gab, um eine Scope-Grenze (App → Character/Session) zu überqueren:

1. **Impliziter Fallback** in `ServiceInitializer.run()`: fehlt eine Dep in der
   eigenen Registry, wird stillschweigend in einer zweiten `fallback_registry`
   nachgeschlagen.
2. **Expliziter Bridge** via `registry.register_resource()`: eine Referenz wird
   vor dem Boot manuell in die Ziel-Registry kopiert.

Da nirgends kodifiziert war, wann welcher gilt, entstanden drei konkrete
Mutationen: `get_local_peer_id()` dreifach implementiert, vier verschiedene
Zugriffsmuster auf `SessionManager`, und eine Stelle, die bei Verwendung still
`null` zurückgeben würde.

## Optionen

### Option A: Mechanismus 1 (impliziter Fallback) zur Norm erklären
- ✅ Kein Migrationsaufwand — ist bereits der meistgenutzte Pfad
- ❌ Bleibt für jeden Nicht-`Service`-Konsumenten (z.B. `UIContext.from_registry()`,
  das direkt `registry.get_service()` aufruft, nie durch `configure(deps)` läuft)
  wirkungslos — genau die Lücke, die Mutation 2 in AUDIT-05 zeigt
- ❌ Nicht greifbar/grep-bar: welche Dep gerade aus welchem Scope kommt, ist erst
  zur Laufzeit sichtbar

### Option B: Mechanismus 2 (expliziter Bridge) zur Norm erklären (gewählt)
- ✅ Eine einzige, explizite, an einer Stelle (`BootPipeline`) sichtbare Liste
  pro Scope-Übergang — beantwortet "was sieht Session von App aus" ohne den
  Code der Consumer zu lesen
- ✅ Funktioniert identisch für `Service`-Consumer (`configure(deps)`) und
  registry-lesende Consumer (`UIContext.from_registry()`), weil die Dep danach
  einfach ein ganz normaler lokaler Registry-Eintrag ist
- ✅ Fehlt eine Bridge, meldet `ServiceInitializer` das jetzt als fehlende Dep
  in der eigenen Registry — kein stilles Cross-Registry-„vielleicht"
- ⚠️ Erfordert, dass jede tatsächlich gebrauchte Cross-Scope-Dep einmal explizit
  in `BootPipeline._bridge_app_services_into_session()` eingetragen wird

## Entscheidung

**Option B.** `ServiceInitializer.run()`/`run_on_ready()` kennen ab sofort nur
noch eine Registry — kein `fallback_registry`-Parameter mehr. `BootPipeline.
boot_character()` bridged vor Phase C2 explizit die Global-Services, die
irgendein Session-Service laut `BootstrapConfig.tres` als Dep deklariert:
`event_bus`, `savesystem`, `data`, `gamemanager`, `session_manager`, `ticker`.

### Konkrete Folgefixes (AUDIT-05 Mutationen)

1. **Mutation 1 (`get_local_peer_id()` dreifach):** `SessionManager` bleibt die
   einzige Stelle, die `multiplayer.get_unique_id()` zu einer peer_id macht.
   `NetworkBridge` bekommt `session_manager` als Dep (`BootstrapConfig.tres`)
   und delegiert `get_local_peer_id()` an sie, statt selbst zu rechnen.
2. **Mutation 2 (vier Zugriffsmuster + stiller Null-Fall):** `SessionManager`
   ist jetzt Teil der Session-Registry-Bridge — `UIContext.from_registry()`
   oder jeder künftige Consumer bekommt eine echte Referenz statt `null`.
3. **Mutation 3 (`NetworkBridge` übernimmt Identitäts-Verantwortung):**
   behoben durch dieselbe Delegation wie Punkt 1.
4. **Test:** `tests/unit/test_identity_access_boundary.gd` verhindert
   (analog zu `test_event_bus_access_boundary.gd`) eine erneute
   `multiplayer.get_unique_id()`-Kopie außerhalb der Whitelist.

`ServiceOrchestrator`/`BootPipeline` selbst dürfen weiterhin direkt auf
`_app_scope`/`app_reg` zugreifen — das ist Boot-Orchestrierung mit dem Scope-
Handle bereits in der Hand, keine Cross-Scope-Frage im Sinne dieses ADR.

## Konsequenzen

### Positiv
- Eine einzige, dokumentierte Regel für "wie überquert Code eine Scope-Grenze"
- Fehlende Cross-Scope-Deps fallen jetzt beim Boot als Warnung auf, nicht erst
  als `null`-Crash tief in einem Service
- Die AUDIT-05-Mutationen sind strukturell geschlossen, nicht nur einzeln gepatcht

### Negativ / Risiken
- Jede neue Cross-Scope-Dep muss in `BootPipeline._bridge_app_services_into_session()`
  ergänzt werden — vergisst man das, bleibt die Dep `null` (mit Log-Warnung,
  kein stiller Fehler, aber ein manueller Schritt)
- `ticker` wird jetzt auch für Solo/Tests in die Session-Registry gebridged,
  auch wenn nicht jeder Session-Service ihn braucht — geringer Overhead,
  kein funktionaler Nachteil

### Mitigationen
- `AppLogger.log_warn()` in `_bridge_app_services_into_session()` macht eine
  vergessene Bridge sofort im Boot-Log sichtbar
- `test_identity_access_boundary.gd` verhindert Rückfall in Mutation 1/3

## Ablösung

Löst keinen vorherigen ADR ab — schließt die in AUDIT-05 offen gelassene Lücke.
Wird abgelöst, falls ADR-015 (lokale Spieler-Identität für UI-Layer) einen
grundsätzlich anderen Identity-Zugriffspfad einführt, der auch Service-Ebene
betrifft.
