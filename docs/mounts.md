# Reittiere (Pferd, Esel)

Gefangene Pferde/Esel lassen sich besteigen und machen den Reiter schneller als zu Fuß.

## Ablauf
1. Wildpferd (`horse`) oder Wildesel (`donkey`) fangen (normaler `AnimalCatcher`-Weg) → es wird ein Pet.
2. Steht ein eigenes Reittier ≤ `MountDefinitions.MOUNT_RANGE` (4 m) entfernt, erscheint über dem Sprung-Knopf **Aufsteigen**.
3. Beim Reiten: Tempo × `speed_mult`, der Reiter sitzt `seat_height` höher, das Tier hängt am Reiter.
   Der Knopf heißt dann **Absteigen**. Tod und Teleport steigen automatisch ab.

## Bausteine
| Datei | Aufgabe |
|---|---|
| `scripts/entities/animals/pets/MountDefinitions.gd` | Datentabelle: welche Arten reitbar sind, Tempo-Faktor, Sitzhöhe, Folge-Tempo |
| `scripts/entities/player/PlayerMount.gd` | Reit-Zustand + Regeln (`can_mount`), Pet an Reiter hängen |
| `Player.gd` | `try_mount()`, `dismount()`, `is_mounted()`, Tempo-Faktor in `_apply_movement()`, `_update_mount()` |
| `PetComponent.gd` | `species_id` (im Save), `is_ridden()`/`set_ridden()`, geritten = keine eigene Bewegung |
| `pets/ui/Mount{Component,Controller,Visuals}.gd` | Auf-/Absteigen-Knopf (alle 0,2 s Prüfung), registriert in `HUDBuilder` als `mount` |
| `WorldService.is_solo_world()` | Solo-Prüfung |

## Regeln / Grenzen
- **Nur Solo.** Koop-Vorhersage/Abgleich kennen den Zusatz-Faktor nicht und würden den Reiter zurückziehen; `try_mount` liefert dort `"not_solo"`.
- Nur eigene Pets (`owner_peer_id`), nur Arten aus `MountDefinitions`.
- Reittiere haben **keine Pet-Fähigkeiten** (`PetAbilities`: `horse`/`donkey` → `[]`) — sie warten eng beim Besitzer.
- Alt-Saves ohne `species_id`: das Pet ist dann kein Reittier (neu fangen).
- Geritten: Kollision des Tieres aus (Layer/Mask 0), danach wiederhergestellt.

## Neue Reittiere
1. Art in `tools/animal_species/generate_animal_species_db.py` anlegen (id ohne `_`), Generator laufen lassen.
2. Eintrag in `MountDefinitions.DEFINITIONS`, Fähigkeiten in `PetAbilities` auf `[]`.
3. `tests/unit/test_mounts.gd` prüft, dass jede Reitart in `AnimalSpeciesDB` existiert.

## Offene Feinabstimmung (visuell, nicht headless prüfbar)
Sitzhöhe (`seat_height`), Kamerahöhe beim Reiten und Lauf-Animation des Reiters im Sitzen.
