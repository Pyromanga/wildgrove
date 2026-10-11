# PLAN — Joystick fix, Anklicken + Umrandung, Ego-Perspektive

Status: **A offen · B teilweise (Fix 2026-09-21) · C teilweise · D teilweise (Ebenen, siehe unten)**
(wird pro Phase hier aktualisiert)

### Nachtrag 2026-09-21 (zwischen den Phasen umgesetzt)
* **B — Tap wählte nie ein Ziel an.** Ursache: `emulate_touch_from_mouse` + `emulate_mouse_from_touch`
  → jeder Tap kam als ScreenTouch UND MouseButton, beide lösten `world_tap_requested` aus; der zweite
  Tap schaltete die Auswahl sofort wieder ab. Fix: `TouchInput._mouse_tap_is_redundant()`.
  Zusätzlich traf der Pick-Strahl die 3-m-Erkennungskugeln (`ProximityDetector`) statt der Objekte →
  jetzt AABB-Test gegen die sichtbaren Meshes (`InteractionTargetPicker.pick_from_ray`), Verdeckung
  durch einen Körper-Strahl. Ablauf: Tap = anwählen, Tap auf Gewähltes = Hauptaktion (in Reichweite),
  Tap ins Leere = abwählen. Long-Press-Kontextmenü, `PickLayers`, `SelectionHighlighter` bleiben offen.
* **D — Ebenen + Baumodus ohne Laufen.** `storey` im Bauraster (Ebene 0 = alte Schlüssel, keine
  Migration nötig), Halt-Regeln in `BuildPlacementRules`, Blick-Zielen + Steuerkreuz (`BuildAim`,
  `BuildModeController`). Ebene wird per „Höher/Tiefer" gewählt, nicht (wie geplant) aus dem
  Zielstrahl — Phase C (Ego-Strahl) bleibt davon unberührt.
Grundsatz (Owner): saubere, nachhaltige Umsetzung — keine Workarounds.
Test-Hinweis: Sandbox ohne Godot-Binary (siehe Decision 0005). Alle Tests hier sind
GUT-Tests, die lokal laufen müssen: `make test-gd` bzw. der Befehl aus README.md.

## Befunde (Code = Wahrheit)

1. `fixed_joystick`, `joystick_inverted`, `cam_relative`, `cam_smooth`, `zoom_smooth` stehen
   in `SettingsService.DEFAULTS` und im Settings-Panel, werden aber von KEINEM Code gelesen.
2. Bäume/Erze (`HarvestableEntity`, Node3D) haben keinen Collider → nicht per Raycast pickbar.
   Alle Interagierbaren laufen durch `InteractableComponent` (einzige Stelle, die die Gruppe
   `interactable` setzt).
3. Ziel einer Interaktion = `InteractionSensor.get_closest()` (2,5 m). Button, Kontextmenü und
   `Player.get_context_actions()` lesen genau das. Ein „angewähltes Ziel“ existiert nicht.
4. Bauraster-Schlüssel (`F_cx_cz`, `W<achse>_cx_cz`) haben keine Ebene → übereinander bauen ist
   datenmodellseitig unmöglich, unabhängig von der Kamera.
5. `project.godot`: `emulate_touch_from_mouse` UND `emulate_mouse_from_touch` sind aktiv.
   Tippen muss genau eine Eventquelle (ScreenTouch) auswerten.
6. `TouchInput.JS_RADIUS = 90` und `JoystickVisuals` Basis 180 px sind zwei getrennte Konstanten.

## Phase A — Joystick fix + ganzer Bildschirm für die Kamera

- `JoystickLayout` (RefCounted, rein): Zentrum (normiert 0..1), Größe; Umrechnung in Pixel,
  Safe-Area-Klemmung, Treffertest. Einzige Quelle für `TouchInput` UND `JoystickVisuals`.
- Settings: `joystick_pos_x/_y`, `joystick_size` (ersetzt `fixed_joystick`). Der schwebende
  Modus entfällt. `SettingsService.setting_changed` → Änderungen wirken live.
- Edit-Modus (Settings → „Joystick verschieben“): Joystick per Ziehen platzieren, Zurücksetzen.
- `GestureRecognizer` (RefCounted, rein, testbar): Finger-Zuordnung (Joystick / Kamera / Pinch),
  Tap- und Long-Press-Erkennung mit Schwellen. `TouchInput` bleibt Output-Adapter.
- `joystick_inverted`, `cam_relative`, `cam_smooth`, `zoom_smooth`: verdrahten oder entfernen.

## Phase B — Anklicken + Umrandung

- `InteractableComponent` erzeugt eine Pick-Area auf eigener Kollisionsebene (`PickLayers`).
- `PickRay` (statisch): Bildschirmpunkt → Ray → erster Treffer über Pick+Terrain+Bauteile
  (Terrain verdeckt Objekte dahinter).
- `InteractionTargetState` (RefCounted): gewähltes Ziel > nächstes Ziel. `Player.get_closest_interactable()`
  bzw. `get_context_actions()` lesen den Zustand.
- Ablauf: Tap = anwählen + Umrandung; zweiter Tap / Button = Standardaktion; Tap ins Leere =
  abwählen; Long-Press = Kontextmenü. Außer Reichweite: andere Rahmenfarbe + Hinweis.
  Reichweite = `detection_radius` (identisch zur Server-Prüfung `_max_interaction_range_for`).
- `SelectionHighlighter`: `GeometryInstance3D.material_overlay` (Inverted-Hull-Shader), pro
  Instanz, `MeshCache`-Materialien bleiben unangetastet. Aufräumen bei Despawn/Pool-Rückgabe.
- Kein Auto-Laufen in Version 1 (bewusst).

## Phase C — Ego-Perspektive

- `PlayerCamera`: Zoom läuft fließend bis 0; unter `FIRST_PERSON_THRESHOLD` = Ego-Modus.
  Pitch-Bereich erweitert (Blick nach oben). Ohne Glättung im Ego-Modus.
- Eigener Körper: Sichtbarkeits-Ebene + Kamera-`cull_mask` (Remote-Spieler bleiben sichtbar).
- `PlayerAim`: `get_ground_target()` nutzt im Ego-Modus einen Strahl aus der Bildschirmmitte,
  sonst wie bisher. `GroundToolController`/`BuildModeController` unverändert.
- Fadenkreuz im Ego-Modus. Netzwerk: nur Yaw wird gesendet, Pitch bleibt lokal → kein Protokollwechsel.

## Phase D — Übereinander bauen (Decken, gestapelte Wände)

- Ebene (`level`) im Bauraster-Schlüssel, Höhe = Basis + Ebene × Wandhöhe.
- „Steht auf“-Regel in `BuildPlacementRules` (Grund `unsupported` existiert bereits).
- Ebene ergibt sich aus dem Zielstrahl (Phase C).
- Save-Migration: Alt-Schlüssel ohne Ebene → Ebene 0 (`BuildRegistry.load_save`).

## Reihenfolge / Lieferung

A → B → C → D. Nach jeder Phase: Tests + Docs aktualisiert, ganzes ZIP, Fortschritt in diesem Dokument.
