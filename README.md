# WildGrove 🌿

> A 3D mobile RPG built around four combined concepts: open-world exploration with
> light puzzle/boss encounters, a numeric skill-and-leveling progression system, seasonal
> farming and resource gathering, and a village/wildlife layer with NPC relationships.

This README describes what the project *is* and how to run it. **Neu hier?**
Lies zuerst `docs/manager/START_HIER.md` — die kürzeste, einfachste Erklärung,
wie an diesem Projekt gearbeitet wird. Für *why* it's built the way
it is, see `docs/adr/` (Architecture Decision Records) and `docs/architecture.md`. For a
critical, evidence-based read on the current state of the codebase — including open bugs and
where documentation doesn't match code — see `docs/audit/`.

---

## Design pillars

WildGrove combines four gameplay concepts into one world, rather than four separate game
modes:

- **Exploration & encounters** — an open 3D world with discoverable areas, light
  environmental puzzles, and tiered enemy encounters including boss-scale fights.
- **Skill progression** — a numeric skill system (e.g. woodcutting, mining, farming, combat)
  where repeated actions grant XP and unlock capability over time, independent of a single
  "character level."
- **Farming & seasons** — plantable, growable, harvestable resources tied to an in-world
  time/season cycle.
- **Village & relationships** — NPCs with individual relationship state, a wildlife/resource
  encyclopedia, and player-driven world development over time.

Controls target touch-first mobile play: a virtual joystick for movement, tap-to-interact /
context-sensitive action buttons for everything else.

---

## Getting started

### Prerequisites

- [Godot 4.6.3](https://godotengine.org/download/)
- Android SDK (API 34) + NDK 23, if building for device
- Java 17+, if building for device

### Open the project

```bash
git clone <your-repo-url>
cd wildgrove
# Open in Godot 4 by selecting this folder as the project
```

### Run tests locally

The project uses [GUT](https://github.com/bitwes/Gut) (`addons/gut/`) for unit tests.

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

**Current status, as of this audit:** test coverage is uneven across systems — see
`docs/audit/AUDIT-01-pain-points-and-review-verification.md` for the specific gaps before
assuming a passing local run means the relevant system actually works end to end.

---

## Project structure

This reflects the structure as it actually exists, not an aspirational target.

```
wildgrove/
├── project.godot              Godot project configuration
├── export_presets.cfg         Android export settings
├── config/                    Bootstrap/game configuration resources
├── scenes/                    Main.tscn, World.tscn, MainMenu.tscn
├── scripts/
│   ├── core/                  Boot pipeline, service registry/factory/orchestrator
│   ├── services/               Gameplay services (inventory, skills, quests, combat, save…)
│   ├── world/                  Entities: terrain, chunks, animals, NPCs, combat, water
│   ├── player/                  Player movement, camera, input, visuals
│   ├── interaction/             Interactable objects and the interaction pipeline
│   ├── quest/                   Quest data definitions
│   ├── ui/                      HUD, controllers, components, visuals
│   ├── events/                  EventBus and its typed namespaces
│   ├── interfaces/core/         Narrow context interfaces (IEntityContext, IUIContext, …)
│   ├── resources/               Typed Resource data classes (items, stats, skills, …)
│   ├── logger/                  Logging
│   └── debug/                   In-game debug terminal (production-shipped tooling)
├── data/                       .tres data assets (items, skills, combat profiles, quests)
├── tests/unit/                  GUT unit tests
├── addons/gut/                  GUT test framework
└── docs/
    ├── adr/                      Architecture Decision Records
    ├── audit/                    Independent architecture/code audits (this round + future)
    ├── architecture.md            Layer model and boot pipeline reference
    ├── ci-pipeline.md             Documented CI/CD workflow (see below)
    └── (principles.md, services.md, history.md, MIGRATION*.md)
```

---

## CI/CD

A GitHub Actions workflow builds an Android debug APK on push/PR (when the commit message
contains "App") or via manual dispatch, runs the unit test suite, and creates a GitHub
Release on tag push. The workflow itself is documented in full, with critique, in
[`docs/ci-pipeline.md`](docs/ci-pipeline.md) — that document is the authoritative reference
for what the pipeline does and does not currently verify. **Changes to the CI pipeline
require a conversation with the project owner first** — see that document for why.

---

## Current focus

Architecture and tooling work has outpaced gameplay verification. Before adding new systems,
the priority is: confirm the existing core loop (skills/XP, inventory, quests, combat) is
correct end to end, with real test coverage, and make the CI pipeline actually gate on that
coverage rather than reporting green regardless of test outcome. See `docs/audit/` for the
specifics. `AGENT.md` has standing instructions for any agent working in this repo; the
active task brief for a given round lives in `ReviewAgent.md` (audit) or `ImplementAgent.md`
(bug-fix execution).

---

## Technical details

| Area | Choice |
|---|---|
| Engine | Godot 4.6.3 |
| Language | GDScript |
| Target platform | Android (arm64) |
| Rendering | GL Compatibility (mobile) |
| Min. Android | API 24 (Android 7.0) |
| Target Android | API 34 (Android 14) |
