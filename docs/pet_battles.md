# Pet-Kämpfe (rundenbasiert, Pokémon-Prinzip)

Eigene Pets kämpfen rundenweise gegen die Tiere von **Dorfbewohnern** (`VillagerNPC` und alle Berufe:
Siedler, Bauer, Wasserträger). Bei Sieg gibt es ein Pet des Gegners, XP und Gold.

## Ablauf
1. Beim Dorfbewohner **„Zum Pet-Kampf herausfordern“** wählen (4. Aktion neben den Taschendieb-Aktionen).
2. **Teamwahl**: alle eigenen Pets mit Kopf-Icon, Typ, Level; Haken = im Kampfteam, **höchstens 10**
   (`PetBattleEngine.MAX_TEAM`). Die Wahl steckt im Pet selbst (`PetComponent.is_in_battle_team()`, Save-Feld
   `battle_team`) und bleibt zwischen Kämpfen erhalten. Beim ersten Mal werden bis zu 3 Pets vorausgewählt.
3. **Kampf**: Gegner oben, eigenes Pet unten, LP-Balken, Log, Attacken (mit Hinweis ×2/×½ gegen den aktuellen
   Gegner), **Wechseln** (kostet die Runde; nach dem Besiegen kostenlos und Pflicht) und **Aufgeben**.
4. **Ende**: alle beteiligten Pets bekommen XP (Verlierer ein Viertel). Bei Sieg zusätzlich Gold und das
   **stärkste Gegner-Tier als neues Pet**, mit dessen Level. LP/Status gelten nur im Kampf (kein Permatod).
   Fenster schließen mitten im Kampf = Aufgeben.
5. Der besiegte Dorfbewohner **ruht 5 Minuten** (`BATTLE_REST_MSEC`) und stellt danach ein **neues Team** auf.

## Regeln
- **Typen** (`PetBattleTypes`): Raubtier, Huftier, Nager, Insekt, Gift, Wasser auf einem Ring: jeder Typ ist gegen die
  nächsten zwei im Ring stark (×2) und gegen die zwei davor schwach (×0,5). Typ aus dem Bauplan (Insekt/Spinne/Schlange/
  Fisch) bzw. der Tabelle `SPECIES_TYPES` (Vierbeiner; unbekannt → Huftier).
- **Werte** (`PetBattleStats`): aus `body_size` (HP/Angriff/Verteidigung), `speed` (Tempo), Typ-Bonus und Level
  (Pokémon-Formel). Keine Pflege pro Art nötig — neue Arten funktionieren automatisch.
- **Attacken** (`PetBattleMoves`): je Typ Rempler + Typ-Basis (Lv 1), Hilfsattacke (Lv 3), Typ-Finale (Lv 5).
  Gift kann vergiften, Hilfsattacken verändern Statusstufen (−6…+6).
- **Gegner** (`PetBattleEncounter`): 1–3 Tiere, Seed aus Dorfbewohner-Name + Kampf-Runde (auf jedem Peer gleich, nichts
  zu übertragen), Level = Durchschnitt des Teams −2…+1. Bauer bevorzugt Huftiere, Wasserträger Wassertiere.
- **Determinismus**: die Engine nutzt einen einzigen `RandomNumberGenerator` mit Seed → gleicher Seed + gleiche
  Eingaben = derselbe Kampf.

## Bausteine
| Datei | Aufgabe |
|---|---|
| `pets/battle/PetBattleTypes.gd` | Typen, Ring-Tabelle, Art → Typ |
| `pets/battle/PetBattleMoves.gd` | Attacken-Tabelle + Freischaltung nach Level |
| `pets/battle/PetBattleStats.gd` | Kampfwerte aus Größe/Tempo/Typ/Level |
| `pets/battle/PetBattleMon.gd` | Ein Kämpfer (Werte, LP, Statusstufen, Gift) |
| `pets/battle/PetBattleEngine.gd` | Rundenlogik, Schaden, KI, Wechseln, Sieg/Niederlage (keine Nodes) |
| `pets/battle/PetBattleSpecies.gd` | Profil/Aussehen **jeder** Art (handgebaute + `AnimalSpeciesDB`) |
| `pets/battle/PetBattleEncounter.gd` | Gegner-Team aus Seed, XP/Gold, Beute-Pet-Config |
| `pets/battle/PetBattleTeam.gd` | Kampfteam-Auswahl (max. 10), Pets → Kämpfer |
| `pets/ui/PetBattle{Component,Controller,Visuals}.gd` | Fenster (Teamwahl/Kampf/Ergebnis), registriert in `HUDBuilder` als `pet_battle` |
| `VillagerNPC.gd` | Aktion `pet_battle`, Kampf-Runde + Ruhepause, `_battle_bias_type()` pro Beruf |
| `UIEvents.gd` | `pet_battle_requested` (NPC → Fenster), `pet_battle_finished` (Fenster → NPC) |
| `PetComponent.gd` | `get_battle_profile()`, `is_in_battle_team()`/`set_battle_team()`, Save-Feld `battle_team` |

(`pets/…` = `scripts/entities/animals/pets/…`)

## Grenzen / Hinweise
- Der Kampf läuft **lokal** beim herausfordernden Spieler (Pets sind client-autoritativ, das Beute-Pet wird lokal
  gespawnt und über den normalen Pet-Spawn-Weg an andere Peers gemeldet). Die über `InteractableComponent` geroutete
  Kopie der Aktion auf dem Server ignoriert die Herausforderung (`peer_id != get_local_peer_id()`).
- Ruhepause/Runde des Dorfbewohners sind **nicht gespeichert** (rein im Speicher): nach Neustart steht er wieder bereit.
- Neue Tierart? Vierbeiner in `PetBattleTypes.SPECIES_TYPES` eintragen (sonst Huftier), sonst nichts —
  `test_all_quadruped_db_species_are_classified_deliberately` erinnert daran.
- Balancing sitzt an einer Stelle: Konstanten in `PetBattleStats`, `PetBattleEngine`, `PetBattleEncounter`.
- Nicht in Godot gestartet (keine Binary in der Entwicklungsumgebung): Logik per Unit-Tests abgedeckt
  (`test_pet_battle_*.gd`), die Oberfläche bitte einmal im Spiel durchspielen.
