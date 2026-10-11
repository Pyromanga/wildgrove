# Schmelzen & Schmieden — Architektur

Stand: Integration Bau ↔ Schmieden (vorher nur Daten, kein Service/keine Stationen).

## Kette
```
Hochofen bauen (Stein + Holzkohle, ohne Schmieden beschaffbar)
  → Erz schmelzen (Station "furnace") → Barren
  → Amboss bauen (Eisenbarren) → Waffen/Rüstung schmieden (Station "anvil")
  → Barren fließen auch zurück ins Bauen (Eisentür, Eisenlaterne, Katapult, Friedhofstor, Sonnenuhr)
```

## Bausteine
| Teil | Ort |
|---|---|
| Rezepte (datengetrieben) | `data/smithing_recipes/*.tres`, `DataManifest.SMITHING_RECIPES` |
| Logik (Autorität) | `scripts/economy/crafting/SmithingService.gd` |
| Events | `SmithingEvents` (`smithing_craft_*`, `smithing_station_used`) |
| Stationen | `BuildPieceDefinition.station_kind` + `PropShape.FURNACE/ANVIL`, `data/building/Furnace.tres`, `Anvil.tres` |
| Benutzen | `BuildPiece` — zweite `InteractableComponent` "use_station" |
| Panel | `scripts/economy/crafting/ui/Smithing{Visuals,UIController,Component}.gd` |
| Netzwerk | `NetworkBridge.send_smithing_craft()` / `_rpc_smithing_craft` |
| Haus-Vorlage | `data/building/houses/Smithy.tres` (nur Hochofen; Amboss nachrüsten) |

## Stations-Zugang
`BuildPiece._on_station_used()`: öffnet das Panel nur auf dem Peer des Spielers
(`multiplayer.get_unique_id() == peer_id`) und meldet auf der Autorität
`smithing_station_used`. `SmithingService` erlaubt Rezepte einer Station nur
`STATION_ACCESS_SEC` (180 s) danach. Die Station kommt aus dem Rezept, nie aus der Anfrage.

## Neues Rezept / neue Station
Rezept: neue `.tres` + Eintrag in `SMITHING_RECIPES`. Neue Station: neuer `PropShape`-Wert
**ans Ende** des Enums, Mesh-Builder, `station_kind` in `SmithingRecipe.STATIONS`.

## Rüstung
`ArmorDefinition` (Slot + `armor_value`) wirkt über `EquipmentService` als `FLAT_ADD`-Modifier auf den
Stat `armor`. `CombatSystem.calculate_damage_with_profile(record, profile, target_player_id)` addiert ihn
zur Profil-Rüstung (Gesamt-Clamp 0.85). Genutzt von `EnemyNPC._do_melee()` und dem PvP-Pfad in `Player`.
Der Slot ist pro Teil fest; `EquipmentService.on_equip_confirmed()` prüft das serverseitig
(`_slot_accepts`), sonst ließe sich dasselbe Teil in mehrere Slots legen.

## XP-Bonus über Ausrüstung (für ALLE Skills)
`ItemDefinition.xp_bonus = { skill_id | "all": Faktor }` (0.10 = +10 %). `EquipmentService` legt je
Eintrag einen `PERCENT_ADD`-Modifier auf `xp_gain` bzw. `xp_gain_<skill>`; `SkillSystem.add_action_xp()`
rechnet ihn ein. Das ist die **einzige** Stelle: Ernten/Kämpfen (über `xp_gained`) und Schmieden laufen
darüber, Quest-/Admin-Belohnungen (`request_add_xp()`) bewusst nicht. Neuer Skill mit Aktions-XP → nichts
extra tun, solange er `add_action_xp()` bzw. das `xp_gained`-Event nutzt.

## Weitere Verarbeitungs-Skills (Kochen, Handwerk ...)
`SmithingRecipe.skill_id` (Default `smithing`) bestimmt, wessen Level geprüft und wem die XP gutgeschrieben
werden. Neuer Verarbeitungs-Skill = Skill-`.tres` + Rezepte mit anderem `skill_id` und eigener Station
(`SmithingRecipe.STATIONS`, `BuildPieceDefinition.station_kind`). Der Service heißt noch `Smithing*`;
Umbenennung in `CraftingService` ist rein mechanisch und noch offen (siehe Entscheidung im Chat).

## Offen
- Fehlermeldungen (`smithing_craft_failed`) kommen nur auf der Autorität an.
- Nicht in Godot/am Gerät geprüft: Meshes, Kollision, Haus-Vorlage (Kantenindizes, Ausrichtung).
