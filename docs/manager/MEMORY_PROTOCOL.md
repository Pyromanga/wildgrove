# MEMORY_PROTOCOL.md

Das Gedächtnis des Manager-Systems liegt vollständig im Repo, in zwei
Formen — bewusst kein externer Speicher, damit es mit dem `.zip`-Export
mitreist und in jeder neuen Session ohne Setup verfügbar ist.

## Wo

| Was | Wo | Format |
|---|---|---|
| Entscheidungen | `data/manager/decisions/NNNN-slug.md` + `INDEX.md` | Markdown, append-only |
| Metriken | `data/manager/metrics.jsonl` | JSON Lines, append-only |
| Protokolle/Rollen | `docs/manager/*.md` | Markdown, editierbar (das ist "Struktur", kein Log) |

Warum die Trennung "append-only Log" vs. "editierbare Struktur-Docs": Logs
lügen nicht rückwirkend — wenn sich Rollen ändern, wird das NICHT in altes
Decision-File reingeschrieben, sondern eine neue Decision mit
`--supersedes 0003` legt fest, was jetzt gilt. `MANAGER.md`/`ROADMAP.md`
selbst dürfen dagegen direkt editiert werden, weil sie den aktuellen Stand
beschreiben sollen, nicht die Historie.

## Vergessen — was das hier bedeutet

"Vergessen" heißt NICHT löschen. Es heißt: aus dem aktiven Kontext raus, den
`make brief` anzeigt, aber in der Historie bleibt es nachvollziehbar.
Konkret:

- Eine Decision, die durch eine neuere ersetzt wurde, bekommt im
  `INDEX.md` den Status `superseded by 00NN` statt gelöscht zu werden.
- `session_brief.py` zeigt standardmäßig nur **aktive** (nicht-superseded)
  Decisions der letzten N Einträge — das ist das "Vergessen" für den
  Alltag. `session_brief.py --full` zeigt alles, für den Fall, dass eine
  alte Begründung wieder gebraucht wird.
- `metrics.jsonl` wird nie gekürzt (zu billig, um es zu müssen); Auswertungen
  können sich aber auf ein Zeitfenster beschränken (`--since`), damit alte
  Ausreißer nicht ewig den Erfolgsrate-Schnitt verzerren.

## Meta-Review — Kadenz

`metrik-master` macht einen Meta-Review, wenn eine der beiden zutrifft:
- **Alle 15 neuen Decisions** seit dem letzten Meta-Review (Zähler steht im
  `INDEX.md`-Header), ODER
- **Der Mensch fragt danach.**

Kein festes Zeitintervall (Tage/Wochen), weil die Session-Kadenz vom
Menschen abhängt (Kontextlimits, siehe `MANAGER.md` §0) — ein Intervall
nach Decision-Anzahl ist robuster als eins nach Kalenderzeit.

## Self-Healing

Wenn `session_brief.py` beim Einlesen von `data/manager/decisions/` oder
`metrics.jsonl` auf ein kaputtes/unlesbares Element trifft: **nicht
abstürzen**, den defekten Eintrag überspringen, in der Ausgabe explizit als
"⚠ konnte nicht gelesen werden: <Datei>" melden, und mit dem Rest normal
weitermachen. Eine Session, die wegen eines fehlerhaften Log-Eintrags
komplett blockiert, ist schlimmer als ein Log-Eintrag, der fehlt.
