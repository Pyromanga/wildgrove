# 0010 — ADRs von 0 neu aufbauen statt 43 einzeln zu triagieren

Zeit: 2026-08-02 19:10 UTC
Rolle: manager

## Gewählt
Alle 43 unverifizierten Legacy-ADRs werden als DEPRECATED markiert (nicht gelöscht, adr_tool.py deprecate + Backup). Neue ADRs entstehen ab jetzt nur noch gegründet auf bekannte, aktuell offene Punkte (die 9 Checkbox-Items in TODO-offene-probleme.md), nicht aus Altbestand rekonstruiert.

## Verworfene Alternativen
- Alle 43 einzeln durchgehen: pro ADR entscheiden Check-Script bauen oder deprecaten (mein urspruenglicher Vorschlag, Decision 0008)
- Status quo behalten, nur die 2 verifizierten ADRs (012, 017) als Referenz nutzen

## Begründung
Mensch: 'die adrs von 0 sauber aufzubauen ist besser als sich von legacy Schwachsinn verunsichern zu lassen' -- ADR = Build-File das noch nicht umgesetzt wurde (Projekt-Grundprinzip); ein Neuaufbau ausgehend von echten, aktuell bekannten offenen Punkten ist ehrlicher als 43 Alt-Dokumente einzeln zu rechtfertigen.
