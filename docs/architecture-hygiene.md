# Architektur-Hygiene: ein Pfad, keine stillen Rückfälle

Regeln (aus dem Quest-Bug 2026-10: Welt-Service bekam `quest` nie, weil die Dep
nicht in `config/BootstrapConfig.tres` deklariert war → still `null`):

1. **Deps deklarieren.** Jede in `configure()` gelesene Dep (`deps.get_optional/require/has`)
   muss in `BootstrapConfig.tres` stehen. Guard: `tests/unit/test_service_deps_declared.gd`.
2. **Ein Dialogsystem.** `DialogueTreeController`. Das Slot-System
   (`QuestNPCDialogController`) ist entfernt (ADR-051 Amendment).
3. **Ein Identitätspfad.** Quest-Slice: `NetworkBridge.get_player_id_for_peer()`;
   leere `player_id` → ERROR + Abbruch, kein Ersatzwert.
4. **Fehlende Pflicht-Abhängigkeit = laut loggen (push_error/ERROR), nicht still weitermachen.**

## Bekannte Schuld (noch offen)
- ~17 duplizierte `_resolve_player_uuid/_local_player_id`-Kopien → ein zentraler Helper.
- `network_bridge` wird in vielen `configure()` gelesen, in Produktion via C8 injiziert (allow-listed im Guard-Test).
- Species-ID-Ableitung und Alt-Save-Defaults an mehreren Stellen.
- Solo/Koop-Gating (Mounts) verteilt.
- GenericAnimal-Species-IDs mit Unterstrich (`test_animal_species_db` rot).
