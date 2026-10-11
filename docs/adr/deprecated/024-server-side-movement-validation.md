> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-024: Server-seitige Movement-Validierung — der Range-Check bekommt eine geprüfte Position

**Status:** Abgelöst von [ADR-025](025-server-authoritative-movement.md) —
Zielniveau wurde nachträglich explizit höher gesetzt (Server-autoritative
Simulation statt Plausibilitätsfilter). Dieser ADR bleibt als Geschichte stehen:
er dokumentiert den zuerst für ausreichend gehaltenen, proportionalen Ansatz und
die Begründung, warum er verworfen wurde.
**Datum:** 2026-07
**Kontext:** `Player.gd`, `PlayerMover.gd`, `StatModifierService`, `EntityOrchestrator`
(`resolve_for_player()` aus [ADR-023](023-entity-reference-contract.md)). Löst den
TODO-Punkt „Echte Movement-Validierung fehlt" aus `TODO-offene-probleme.md`, der bei
der ADR-023-Recherche entstanden ist.

## Problem

ADR-023 macht ehrlich, was `resolve_for_player()`s Range-Check tatsächlich ist: ein
Plausibilitätsfilter, kein Anti-Cheat — weil die geprüfte Position vom Client selbst
kommt (`Player.gd` setzt die Movement-Authority auf den besitzenden Peer,
`MultiplayerSynchronizer` repliziert `position` von dort). Ein modifizierter Client
könnte eine falsche eigene Position melden und damit jeden Range-Check bestehen,
ohne wirklich in Reichweite zu sein.

Die naheliegende Frage: **ist das schon der Anti-Pattern, oder ist der Fehler nur,
ihn für mehr zu halten, als er ist?** Antwort: Client-autoritatives Movement mit
serverseitigem Vertrauen in die replizierte Position ist ein etabliertes,
branchenübliches Muster für nicht-kompetitive Coop-/Survival-Spiele (Bewegungsgefühl
> Frame-genaue Anti-Cheat-Garantie) — der Anti-Pattern wäre nur, diesen Trade-off
nirgends zu benennen und stillschweigend als Sicherheitsgrenze zu behandeln. Genau
das war die Lücke, die der TODO-Punkt beschreibt.

## Optionen

### Option A: Vollständige Server-Reconciliation (Client sendet Input, Server simuliert)
Client sendet nur Inputs (Bewegungsrichtung, Jump), Server simuliert die eigentliche
Physik autoritativ, Client prediction + Server-Correction bei Abweichung — das
Standardmuster kompetitiver Shooter.
- ✅ Stärkste Garantie — Server-Position ist die einzige Wahrheit, nicht mehr
  client-reported
- ❌ Massiver Umbau: `PlayerMover`, `CharacterBody3D`-Physik, Netzwerk-Timing,
  Client-Prediction/Rollback müssten komplett neu aufgebaut werden
- ❌ Der Aufwand ist für ein Coop-Wirtschafts-/Sammelspiel unverhältnismäßig zur
  tatsächlichen Bedrohung (Bewegungs-Cheating verschafft hier höchstens frühzeitigen
  Zugriff auf entfernte Interactables, kein PvP-Vorteil) — Overkill analog zu
  ADR-004 Option B ("Overkill bevor der erste Gameplay-Loop fertig ist")

### Option B: Status quo — Range-Check bleibt reiner Plausibilitätsfilter, keine weitere Prüfung
Nichts weiter bauen, Limitation bleibt wie in ADR-023 dokumentiert.
- ✅ Kein zusätzlicher Aufwand
- ❌ Lässt eine bekannte, benannte Lücke unbegrenzt offen stehen — widerspricht der
  Regel „was noch nicht so ist wie es sein sollte, bekommt einen TODO, kein
  Weiterleben als Dauerzustand ohne Wiedervorlage"
- ❌ Wird bei wachsendem Spielerkreis zum naheliegenden ersten Cheat (Teleport zu
  jeder Loot-Quelle) — das Risiko wächst mit dem Projekt, die Lösung nicht

### Option C: Server-seitiger Speed-Cap auf die replizierte Position (gewählt)
Server hält pro Spieler die letzte validierte Position + Zeitstempel. Bei jedem
Zugriff auf die Position (u. a. durch `resolve_for_player()`) wird die implizite
Geschwindigkeit (`distance / delta_time`) gegen den **serverseitig bekannten**
`StatModifierService.get_effective_stat("move_speed", ...)`-Wert desselben Spielers
geprüft — dieselbe Quelle, aus der `PlayerMover.get_current_speed()` seinen Wert auf
dem Client zieht, nicht ein geratener fester Grenzwert. Eine Toleranz (Netzwerk-Jitter,
Sync-Rate 20 Hz aus `Player.gd`) verhindert False Positives bei normaler Latenz.

Überschreitet die implizite Geschwindigkeit den erlaubten Wert deutlich, gilt die
Position für diesen Tick als **nicht validiert** — `resolve_for_player()` fällt in
diesem Fall auf die letzte validierte Position zurück (nicht auf einen Fallback-Wert
wie „Reichweite ignorieren", sondern auf die zuletzt geprüfte, echte Position) und
loggt einen Warn-Eintrag mit Spieler-ID + gemessener Geschwindigkeit.

- ✅ Nutzt eine bereits vorhandene, bereits geteilte Wahrheitsquelle (`move_speed`
  via `StatModifierService`) statt einer neuen, zweiten Konstante
- ✅ Deckt den offensichtlichen Fall (Speed-/Teleport-Hack) günstig ab, ohne die
  Movement-Architektur umzubauen
- ✅ Proportional zur tatsächlichen Bedrohung in diesem Genre (siehe Option A)
- ❌ Deckt keinen Cheat ab, der knapp unter dem Cap bleibt (z. B. wiederholtes,
  leicht-über-legitim schnelles Bewegen) — bewusst akzeptierter Rest-Trade-off,
  dokumentiert statt verschwiegen
- ❌ Zusätzlicher State pro Spieler (letzte validierte Position + Zeitstempel) —
  klein, aber ein neuer, expliziter serverseitiger State, kein zustandsloser Check

## Entscheidung

**Option C.** Server-seitiger Speed-Cap gegen die bereits vorhandene
`move_speed`-Quelle, mit expliziter, geloggter Fallback-auf-letzte-validierte-Position
statt eines Range-Check-Bypasses. Option A (volle Reconciliation) ist für dieses Genre
unverhältnismäßig, Option B (nichts tun) lässt eine benannte Lücke unbegrenzt offen.

## Konsequenzen

### Positiv
- `resolve_for_player()` aus ADR-023 bekommt eine geprüfte statt einer blind
  vertrauten Position — der Range-Check wird dadurch strenger, ohne dass ADR-023
  selbst geändert werden muss (reine Vorbedingung, gleiche Schnittstelle).
- Deckt den naheliegendsten, billigsten Cheat (Speed-Hack/Teleport) ab, ohne die
  Movement-Architektur des Spiels umzubauen.
- Macht den bewusst akzeptierten Rest-Trade-off (kein Schutz gegen knapp-unter-Cap-
  Cheats) explizit statt implizit — falls das später doch relevant wird (z. B. PvP-
  Feature aus dem TODO „Fehlt komplett"), ist der Punkt bereits dokumentiert und
  keine Überraschung.

### Negativ / Risiken
- Speed-Buffs/-Debuffs (`speed_modifier_changed`) müssen server- UND clientseitig
  exakt denselben `StatModifierService`-Stand haben, sonst erzeugt der Cap
  False Positives genau bei Spielern mit aktivem Buff — das ist derselbe
  Rücksync-Bedarf wie in ADR-022, nicht isoliert von dort zu betrachten.
- Toleranzwert (Jitter-Puffer) ist ein weiterer Balance-Parameter — muss explizit
  hergeleitet (aus der 20-Hz-Sync-Rate) und dokumentiert werden, kein geschätzter
  Platzhalter, der „vorerst" großzügig gesetzt wird.

### Mitigationen
- Speed-Modifier-Zustand wird über denselben Rücksync-Mechanismus aktuell gehalten,
  den ADR-022 für Economy-Mutationen einführt — kein zweiter, separater Sync-Pfad
  nur für Stats.
- Toleranz wird explizit als `SYNC_INTERVAL_SEC * safety_factor` dokumentiert
  (nicht als Magic Number), analog zum bereits bestehenden Muster in
  `NetworkBridge`s `SNAPSHOT_TIMEOUT_SEC`/`SNAPSHOT_MAX_RETRIES`.
- Der akzeptierte Rest-Trade-off (kein Schutz gegen knapp-unter-Cap-Bewegung) wird
  in `NetworkContract.gd` als Kommentar an der neuen Prüfmethode vermerkt — nicht
  nur hier im ADR, damit er auch ohne ADR-Lektüre am Code sichtbar ist.

## Ablösung

Abgelöst von [ADR-025](025-server-authoritative-movement.md) und
[ADR-026](026-client-side-prediction-reconciliation.md) (2026-07). Der hier
gewählte proportionale Ansatz (Speed-Cap als Plausibilitätsfilter) wurde explizit
als nicht ausreichend zurückgewiesen — Zielniveau ist Server-autoritative
Simulation mit Client-Prediction, nicht ein enger gezogener Filter auf eine
weiterhin client-autoritative Position.
