# Nester, Hügel und ihre NPCs (Stand 2026-10-10)

Sechs Nest-/Hügel-Typen, jeweils mit **Weltobjekt + Interaktion + Quest-NPC**. Aufbau folgt den
Hain-Skills (`docs/skill-writing-guide.md`): ein Objekt ist eine `HarvestableEntity`-Subklasse, die
XP und Loot über `InteractableData` vergibt. Die NPCs sind `QuestNPC`-Subklassen mit Dialogbaum
(`docs/quest-writing-guide.md`, erzeugt mit `quest_npc_scaffold.py`).

## Überblick

| Nest | `type_id` / Klasse | Skill (XP) | Biome | Respawn | Loot | NPC (Kultur) |
|---|---|---|---|---|---|---|
| Ameisenhügel | `ant_hill` / `AntHill` | `entomology` (20) | Wald, dichter Wald | 6 min | Ameisensäure | Ameisenfrau Myrmex (griechisch) |
| Termitenhügel | `termite_mound` / `TermiteMound` | `entomology` (25) | Wüste | 7 min | Termitenlehm | Baumeisterin Rudo (Shona, Simbabwe) |
| Maulwurfshügel | `mole_hill` / `MoleHill` | `digging` (15, bestehender Skill) | Wiese, Wald | 4 min | Maulwurferde | Feldmesser Lucius (römisch) |
| Bienennest | `wild_beehive` / `WildBeehive` (**unverändert**, existierte schon) | `beekeeping` (25) | Wiese, Wald | 6 min | Honigwabe | Zeidlerin Gerlinde (fränkisch) |
| Wespennest | `wasp_nest` / `WaspNest` | `entomology` (25) | Wiese, Wald, dichter Wald | 7 min | Wespenpapier | Papiermeisterin Lian (chinesisch) |
| Hornissennest | `hornet_nest` / `HornetNest` | `entomology` (35) | Wald, dichter Wald, toter Wald | 9 min | Hornissenpapier | Orakel Sigrun (nordisch) |

Neu: Skill `entomology` (Insektenkunde), 5 Items (`formic_acid`, `termite_clay`, `molehill_soil`,
`wasp_paper`, `hornet_paper`), 5 LootTables, 12 Quests.

## Fakten (Zwei-Ebenen-Regel) und Belege

| Nest | Fakt im `inspect_text` | Belegt? | Prüfung |
|---|---|---|---|
| Ameise | Ameisensäure heißt so, weil man sie 1671 erstmals aus Ameisen gewann (lat. *formica*) | ✔ | Mehrere Nachschlagewerke/Hochschul-Seite (Uni Bristol „Molecule of the Month“): John Ray 1671, Destillation von Ameisen |
| Termite | Hügel aus Erde, Speichel, Kot; höchste gemessene ≈ 8 m | ✔ Höhe + Erde / ☐ Speichel+Kot (nur eine Quelle) | Guinness-Rekordseite (Kathedralen-Termiten ≈ 8 m; 8,7 m Somalia 1968, dort auch Speichel/Kot) + Boden-Studien (Uni Gent, Uganda: Hügel bestehen aus Erde). Zweite Quelle für Speichel/Kot nachziehen |
| Maulwurf | Hügel = Aushub der Gänge, dient zugleich der Belüftung | ✔ | NABU-Artikel „Beim Maulwurf zu Besuch“ + Gartenjournal/BN-Pressemitteilung (Aushub, Belüftung) |
| Wespe | Wespen kauen Holz zu Papierbrei; Réaumur ≈ 1720 → Papier aus Holz | ✔ | Espace pour la vie (Réaumur 1720) + Engines of Our Ingenuity, Univ. Houston (Réaumur 1719; erst 1850er Holzschliff-Papier) |
| Hornisse | „Drei Stiche töten einen Menschen“ ist ein Mythos; Gift nicht stärker als Wespe/Biene | ✔ | Stiftung Warentest + Blick (Wissenschafts-Zitat) + NABU Sachsen; **Schutz-Hinweis**: Allergien bleiben gefährlich, deshalb Abstand zu bewohnten Nestern |
| Biene | Schwänzeltanz (bestehender Skill-Text) | ✔ | siehe `skill-writing-guide.md` |

**Nicht belegt (☐ / Flavor, im Spiel als Sage oder Spielwelt-Gag markiert):**
Myrmex-Verwandlung durch Athene (Überlieferung, nicht in zwei Quellen geprüft); Zeidlerei im
Nürnberger Reichswald (Allgemeinwissen); „Papier seit 1900 Jahren“ (Allgemeinwissen, Han-Zeit);
Rudo/Great-Zimbabwe-Trockenmauer (Allgemeinwissen). Vor einer Faktenänderung nachziehen.

## Schutz-Haltung (bewusste Designentscheidung)

Ameisen (Rote Waldameisen), Hornissen und Maulwürfe sind in Deutschland geschützt. Das Spiel
modelliert deshalb **keine Zerstörung**:
- Wespen-/Hornissennest: Interaktion heißt „Verlassenes Nest bergen“ (Nester werden in unserem Klima nur eine Saison genutzt).
- Ameisenhügel: „Ameisensäure sammeln“ (ein Tropfen, kein Aufgraben).
- Maulwurfshügel: nur Erde vom Haufen.
- Pets ignorieren die Nest-Typen (`PetAbilities` listet sie bewusst nicht).
Test: `test_occupied_nest_objects_only_offer_the_abandoned_nest`.

## NPCs und Quests

NPCs stehen auf einer dritten Reihe im Startdorf (`z=-13`, `x=8…28`, gleiches Raster wie die Reihen `z=-5`/`z=-9`
in `WorldSpawner.spawn_all()`). Jeder hat eine 2-Stufen-Kette (`build_quest_giver()`).

| NPC (`npc_id`) | Entity-Typ | Quest 1 (Ziel) | Quest 2 (Ziel) |
|---|---|---|---|
| Myrmex (`myrmex_ant`) | `myrmex_npc` | `quest_myrmex_acid` (3 Ameisensäure) | `quest_myrmex_scholar` (Insektenkunde 3) |
| Rudo (`rudo_builder`) | `rudo_builder_npc` | `quest_rudo_clay` (3 Termitenlehm) | `quest_rudo_wall` (6 Stein) |
| Lucius (`lucius_surveyor`) | `surveyor_npc` | `quest_lucius_boundary` (4 Maulwurferde) | `quest_lucius_survey` (Graben 3) |
| Gerlinde (`gerlinde_zeidler`) | `zeidler_npc` | `quest_gerlinde_combs` (3 Honigwaben) | `quest_gerlinde_master` (Imkerei 3) |
| Lian (`lian_paper`) | `papermaker_npc` | `quest_lian_wasp_paper` (3 Wespenpapier) | `quest_lian_fibre` (4 Farnfasern) |
| Sigrun (`sigrun_oracle`) | `hornet_oracle_npc` | `quest_sigrun_myth` (2 Hornissenpapier) | `quest_sigrun_scholar` (Insektenkunde 4) |

Running Gag: „Nicht meine Abteilung (Nest-Edition)“, siehe `quest-writing-guide.md` Abschnitt 3.

## Neues Nest hinzufügen (Checkliste)

1. Item(s), Skill (falls neu) und LootTable mit `content_forge.py` anlegen (`filename` **ohne** `.tres`, das Tool hängt es selbst an).
2. `scripts/world/objects/<Nest>.gd` (`extends HarvestableEntity`; Visuals über `_add_placeholder_cone/_ellipsoid/_box`).
3. `WorldEntityRegistry`: `KNOWN_PROP_TYPES` **und** `register_definition()`.
4. `BiomeRegistry`: Biom nach Fach-Logik wählen; `WorldService.configure()`: `respawn.register_config()`.
5. NPC mit `quest_npc_scaffold.py`, dann Registry + `WorldSpawner` von Hand.
6. `tests/unit/test_nest_content.gd`-Tabellen ergänzen.

## Offen / nicht verifiziert

- **Godot-Tests wurden nicht ausgeführt** (keine Godot-Binary in der Bearbeitungsumgebung). Geprüft: statisch (Tabs, Klammern),
  `content_forge`-Validierung, `service_graph.py` (49 Findings, identisch zur Basis).
- Szene/Visuals sind Primitiv-Placeholder (Kegel/Ellipsoid); Optik im Spiel noch nicht angesehen.
- `z=-13` im Startdorf ist gegen die Dörfer-Doku (Startdorf Hainau = fester Knoten ohne generierte Häuser) geprüft, **nicht** im laufenden Spiel.
- Ob das Spawn-Raster pro Biom (Chancen 0,3–1,2 %) die Dichte gut trifft, ist ungetestet.
- Die kulturellen Rollen (Shona-Baumeisterin, chinesische Papiermeisterin, fränkische Zeidlerin) bitte gegenlesen
  (`quest-writing-guide.md`, Abschnitt 1: „kurz nachfragen statt raten“).
