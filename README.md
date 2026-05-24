# WildGrove 🌿

> RuneScape × Animal Crossing × Stardew Valley × Zelda — 3D Mobile RPG

## Spielkonzept

Ein einzigartiges Mobile-RPG das die besten Elemente kombiniert:

- **Zelda** — Hauptstory, Dungeons mit Rätseln, Bossgegner, offene 3D-Welt
- **RuneScape** — Skill-System (Holzfällen, Fischen, Zaubern, Kampf), Quests, Crafting
- **Stardew Valley** — Farming, Jahreszeiten, NPC-Beziehungen mit Mini-Quests
- **Animal Crossing** — Dorfbau, Enzyklopädie (Fische, Insekten, Pflanzen), Echtzeit-Uhr

**Steuerung:** Virtueller Joystick (links) + Click & Point / Tap-Aktionen

---

## Erste Schritte

### Voraussetzungen

- [Godot 4.3](https://godotengine.org/download/) installieren
- Android SDK (API 34) + NDK 23
- Java 17+

### Projekt öffnen

```bash
git clone https://github.com/DEIN-USERNAME/wildgrove.git
cd wildgrove
# Godot 4 öffnen und den Projektordner auswählen
```

### Projektstruktur anlegen

Nach dem Klonen die folgende Ordnerstruktur erstellen:

```
wildgrove/
├── .github/
│   └── workflows/
│       └── build-apk.yml       ← GitHub Actions (APK Build)
├── project.godot               ← Godot Projektkonfiguration
├── export_presets.cfg          ← Android Export-Einstellungen
├── scenes/
│   ├── Main.tscn               ← Einstiegspunkt
│   ├── world/
│   │   ├── WorldMap.tscn       ← Offene 3D-Welt
│   │   └── Dungeon.tscn        ← Zelda-artige Dungeons
│   ├── player/
│   │   └── Player.tscn         ← Spielerfigur + Kamera
│   ├── ui/
│   │   ├── HUD.tscn            ← Joystick, HP, Skills
│   │   └── Inventory.tscn      ← Inventar / Skills-Menü
│   ├── village/
│   │   └── Village.tscn        ← Dorf (Animal Crossing)
│   └── farm/
│       └── Farm.tscn           ← Farmland (Stardew)
├── scripts/
│   ├── player/
│   │   ├── PlayerController.gd ← Bewegung, Joystick
│   │   └── PlayerStats.gd      ← HP, Skills, XP
│   ├── systems/
│   │   ├── SkillSystem.gd      ← RuneScape Skills
│   │   ├── QuestSystem.gd      ← Quest-Verwaltung
│   │   ├── FarmSystem.gd       ← Farming-Logik
│   │   └── RelationSystem.gd   ← NPC-Beziehungen
│   └── world/
│       ├── TimeSystem.gd       ← Tag/Nacht, Jahreszeiten
│       └── WorldGen.gd         ← Welt-Generierung
├── assets/
│   ├── icon.png
│   ├── audio/
│   └── textures/
└── addons/
    └── (Third-Party Plugins)
```

---

## GitHub Actions — Automatischer APK Build

### Einrichten

1. Die Datei `.github/workflows/build-apk.yml` in dein Repo kopieren
2. `git push` → GitHub baut automatisch eine APK
3. APK unter **Actions → Dein Workflow → Artifacts** herunterladen

### APK auf Handy testen

```bash
# Via ADB (USB-Debugging aktiviert)
adb install WildGrove-debug.apk

# Oder: APK-Datei direkt auf das Handy übertragen und öffnen
# (Einstellungen → Unbekannte Quellen erlauben)
```

### Release-APK (signiert)

Für einen Release-Build `git tag v0.1.0 && git push --tags`.
Der Release-Job erstellt automatisch ein GitHub Release mit der APK.

---

## Entwicklungsplan

### Phase 1: Foundation (aktuell)
- [x] GitHub CI/CD Pipeline
- [ ] Godot Projekt-Grundstruktur
- [ ] Spieler-Controller (3D, Joystick)
- [ ] Basis-Welt (Terrain)
- [ ] Mobile HUD

### Phase 2: Core Systems
- [ ] Skill-System (RuneScape)
- [ ] Farming-System (Stardew)
- [ ] NPC + Dialoge
- [ ] Dorfbau-System (AC)

### Phase 3: Content
- [ ] Erster Dungeon (Zelda)
- [ ] 5 Hauptquests
- [ ] Fisch/Insekten/Pflanzen-Enzyklopädie
- [ ] Tag/Nacht + Jahreszeiten

### Phase 4: Polish
- [ ] Sound & Musik
- [ ] Partikeleffekte
- [ ] Google Play Store

---

## Technische Details

| Bereich | Technologie |
|---|---|
| Engine | Godot 4.3 |
| Sprache | GDScript |
| Zielplattform | Android (arm64) |
| Rendering | GL Compatibility (Mobile) |
| Min. Android | API 24 (Android 7.0) |
| Target Android | API 34 (Android 14) |
| Auflösung | 1080×1920 (skaliert) |
