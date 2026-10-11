# Gelände, Umgraben & Bauen — Architektur

Stand: dieser Umbau ersetzt den alten `TerrainGenerator` (Pilot). Ziel: eine Basis, die Jahre trägt.

## Kernidee: EINE Wahrheit für das Gelände

```
TerrainField.get_height_at(x, z)   ← Mesh, Kollision, Spawner, Bauen, Graben, Wasser: alle fragen DAS
      │
      ├─ Layer-Stapel (reine Funktionen, Weltkoordinaten):
      │     TerrainBaseLayer         Ebene / Hügel / GEBIRGE / Becken (Kontinent-, Detail-, Ridged-Noise)
      │     TerrainErosionLayer      analytischer Erosionsfilter: verzweigte Rinnen & Grate (nur Hügel/Berge)
      │     TerrainRiverLayer        Flusstäler (Graben + Böschung + Wasser darin) + WASSERFÄLLE, Breite in METERN
      │     TerrainLakeLayer         Bergseen auf eigener Höhe (Rasterzellen, 1 Zelle pro Punkt)
      │     TerrainSpawnPlateauLayer ebnet den Ursprung ein (Dorf/NPCs immer trocken + eben)
      └─ Edit-Deltas (TerrainEditLayer)  Spieler-Änderungen, zuletzt
```

* **Wasser ist eine Eigenschaft, kein Objekt:** Wasser ist überall, wo `Höhe < water_level`.
  Seen, Flüsse, Meer und gegrabene Senken sind dasselbe. Die Oberfläche (`TerrainWaterBuilder`) ist
  eine durchscheinende Ebene **ohne Kollision** — man geht im Wasser auf dem Grund.
* **Kein Raycast nötig:** Bodenhöhe ist eine Funktion. Funktioniert für nicht geladene Chunks,
  auf Servern ohne Grafik und in Tests.
* **Weltkoordinaten überall.** (Der alte Generator war chunk-lokal — Dauer-Fehlerquelle.)
* **Determinismus:** `(TerrainConfig, world_seed)` → immer dieselbe Welt. Teil-Seeds über
  `TerrainSeed.derive()` (FNV-1a, **nicht** `String.hash()` — bewusst versionsstabil; Golden-Werte
  im Test `test_terrain_field.gd` schützen davor, dass bestehende Welten sich ändern).
* **Eine Konfiguration:** `TerrainConfig` (Chunk-Größe, Wasserspiegel, Noise, Fluss, Spawn, Klima).
  Die Auflösung wird aus `TerrainEditLayer.SPACING` abgeleitet → Chunk-Vertices liegen immer auf
  dem Edit-Gitter.

### Neues Geländemerkmal hinzufügen (Krater, Straße, Dorf-Plateau, Strand …)
Neue Klasse `extends TerrainLayer`, `apply(x, z, h) -> float`, in `TerrainField._init()` an der
richtigen Stelle einreihen. Regeln: reine Funktion, Weltkoordinaten, kein Zustand/Zufall/Zeit.
Kein bestehender Layer muss angefasst werden.

## Gebirge, Flüsse & Optik (Stand 2026-10-04)
* **Gebirge** (`TerrainBaseLayer`): eigene Maske (~1,6 km) + *Ridged Multifractal* (Grate statt Beulen) +
  Domain-Warping. Gipfel bis ~80 m, Median-Hang im Gebirge ~22°, 90 % unter ~43° (in einer Python-Simulation
  kalibriert — Hangneigung ≈ Höhe × Frequenz, siehe Kommentare in `TerrainConfig`). Nie im Becken/Meer und nie
  näher als `mountain_spawn_clear` (150 m) am Spawn.
* **Erosion** (`TerrainErosionLayer`, Stand 2026-10-05): analytischer Filter nach runevision, "Fast and Gorgeous
  Erosion Filter" (2026; Vorarbeit Clay John 2018, Fewes 2023). Reine Funktion von (x, z) → chunk-nahtlos, kein
  Simulationsschritt. Streifen laufen entlang des Gefälles, die Hänge der Rinnen steuern die nächste (halb so
  große) Oktave → Verzweigungen. Fade zu Gipfel/Tal-Zielwert hält Gipfel spitz. Gefälle wird grob (±64 m) gemessen:
  bei feinem Abstand verdrehen sich die Streifen am Detail-Rauschen (Simulation: 14-m-Sprünge). 3 Oktaven
  (180/90/45 m), ±8 m Tiefe. Nur über `erosion_start_alt` (6 m); `erosion_enabled = false` schaltet ab.
  **Kosten:** ~4 Basis-Auswertungen + 27 Zell-Hashes pro Vertex, nur wo h > 6 m. `ChunkManager` lädt deshalb
  nach dem ersten Chunk nur weiter, solange `CHUNK_LOAD_BUDGET_MSEC` nicht erreicht ist.
* **Flüsse** (`TerrainRiverLayer`): Wasserspiegel S = Geländehöhe der **Flussmitte** − `river_bank_drop`
  (Newton-Schritt auf die Noise-Nulllinie → Spiegel quer zum Fluss eben). Bett = Parabel `river_depth` unter S,
  Böschung steigt ease-out bis zum Gelände, mindestens `river_bank_min` über dem Wasser (sonst Uferwall).
  Läuft im Hochland aus, verläuft sich zum Meer hin, kein Fluss im Spawn-Bereich. Eine Funktion
  (`_sample()`) liefert Bett UND Wasserspiegel — beide können nicht auseinanderlaufen.
* **Färbung** (`TerrainColorizer.terrain_color()`): Gewässerboden (Sand → Schlick), Ufersaum, Gras → Hügel → Fels,
  Steilhänge immer Fels, Schnee oberhalb ~58–70 % `max_height` (haftet nicht an Wänden). Ränder per
  `jitter` verwischt. Das alte `height_to_color()` bleibt unverändert (Tests).
* **Normalen** werden aus Höhen MIT einem Vertex Rand (`sample_heights_padded()`) berechnet → gleiche Normale
  und Farbe auf beiden Seiten einer Chunk-Grenze (an steilen Hängen sonst sichtbare Nähte).
* **Wasser-Shader**: Tiefenfarbe (flach Türkis → tief Dunkelblau), Fresnel, Schaum an Ufer/Kämmen.
  Die Vertex-Farbe der Wasserfläche trägt jetzt Daten (r = Tiefe, a = Uferkante), keine Farbe mehr.
* `ChunkManager.LOAD_RADIUS` 3 → 4, damit Berge nicht ~190 m vor dem Spieler abgeschnitten wirken.
* **Props** wachsen nicht auf Hängen > 38° und nicht über der Baumgrenze (30–48 m, ausdünnend).

## Gewässer, Strände, Wasserfälle (Stand 2026-10-05)
* **Meer/Tiefsee** (`TerrainBaseLayer`): Beckenboden wird mit sinkendem Kontinent-Wert bis −18 m tiefer
  (`basin_deep_floor`/`basin_deep_range`); kleine Becken bleiben flache Seen. **Strände**: `beach_remap()` staucht
  Höhen um 0 m (Hang ×0.35 am Wasser, bis ±5 m zurück auf 1) — Vorzeichen bleibt, Küstenlinie/Wasseranteil unverändert.
* **Flüsse** (`TerrainRiverLayer`): Lauf per Domain-Warping verzerrt (Mäander); Breite nach Höhe (Mündung ×1.5,
  Gebirge ×0.65); reichen bis ~40 m Höhe (vorher ~12 m). Wasserspiegel S = min(Mitte−1.4, Ufer links−0.4,
  Ufer rechts−0.4): auch an Querhängen liegt das Wasser unter BEIDEN Ufern (vorher Damm). Memo-Cache, weil Höhe
  und Wasserspiegel pro Chunk dieselben Punkte brauchen (Basis-Proben nur einmal).
* **Wasserfälle**: wo das Gelände ENTLANG des Flusses steiler als 0.30 ist, wird S zur Treppe
  (`fall_surface()`, Stufe 5.5 m): lange ruhige Becken, dazwischen ~senkrechte Abbrüche. Stufen zeigen immer
  bergab; hinter jedem Abbruch liegt der Fluss in einer Schlucht, die flussabwärts ausläuft. Hohe Uferwände
  werden schmal und steil (`CLIFF_MIN_WIDTH`), mit Felsrauheit (nur nach oben → kein Leck). Wasser-Shader:
  steile Wasserfläche (Normalen aus dem Spiegelfeld, nur nasse Nachbarn) → weiß mit Fallstreifen + Gischt.
* **Bergseen** (`TerrainLakeLayer`): pro 500-m-Zelle ≤ 1 See (Hash), Spiegel = 30 %-Quantil der Randhöhen − 0.3 m,
  Parabelbett, Böschung/Uferwall wie beim Fluss. Nicht an Fluss/Spawn, nicht auf Kuppen. Wasserspiegel kommt aus
  `TerrainField.get_water_level_at()` (Vorrang vor Fluss).
* **Felsstufen** (`TerrainErosionLayer`): an steilen Hängen wird die Höhe zur Treppe (`strata_height()`, 7 m,
  30 % Wandanteil) — Wände im Wechsel mit Simsen. Erosion läuft nicht in Flusstälern (glatte Talsohle).
* **Färbung**: Gewässerboden bis 6 m Tiefe Sand→Schlick; Ufer-Sandstreifen nicht an Steilwänden (dort nasser Fels).
* **Meer-Shader**: Tiefenfarbe bis 10 m, Dünung (Vertex-Verschiebung ≤ 0.28 m, nur in tiefem Wasser).

## Chunks
`ChunkManager` (Streaming) → `TerrainChunkBuilder` (Nodes eines Chunks aus dem Feld) →
`TerrainMeshBuilder` / `TerrainWaterBuilder`. Nachbarn teilen Randvertices bit-genau
(`test_terrain_chunk_builder.gd`). Entities eines Chunks (`ChunkEntitySpawner`) werden beim Entladen
über `EntityOrchestrator.unload_entity()` abgeräumt — **nicht** `despawn_entity()`: das würde
Bäume als abgeerntet markieren und den RespawnService triggern.

## Umgraben
`TerrainEditLayer`: dünn besetzte Deltas auf dem globalen 2-m-Gitter, begrenzt auf −30 m / +4 m, in
`WorldData.terrain_edits` gespeichert (Save-Key `terrain_edits`, ältere Saves laden leer).
Schaufel (`tool_shovel`) → HUD-Buttons Graben/Füllen (`GroundToolController`) → Interaktion mit
Fortschrittsbalken → Event `terrain_edit_requested` → `WorldService.request_terrain_edit()` →
`WorldTerrainEditor` → `ChunkManager.refresh_terrain_points()` (baut nur Terrain/Kollision/Wasser
der betroffenen Chunks neu). Graben liefert **Erde** (`dirt`), Füllen verbraucht sie.
Gegrabene Senken unter dem Wasserspiegel füllen sich sichtbar mit Wasser.

### Schächte, Leitern, Funde
- **Pinsel:** Gitterpunkt-zentriert, flacher Kern (`CORE_RADIUS` 2,9 m → 3x3 Punkte, ~4x4 m ebener
  Boden) mit weichem Rand bis `BRUSH_RADIUS` 5 m. Flach: sanfte Mulde; ab ~4 m Tiefe: steile Wände
  (Schacht). Alter Glockenpinsel: `CORE_RADIUS = 0`, `BRUSH_RADIUS = 3.5`.
- **Leitern:** Item `ladder` (Shop), Button „Leiter“ neben Graben/Füllen. `LadderPlanner` folgt der Wand
  vom Fuß zum Rand (von unten oder vom Rand aus) → `LadderRegistry` (Save-Key `ladders`) → Ansicht
  `Ladder` pro Chunk (Abbauen erstattet alles). Kosten: 1 Item je 4 m. Klettern positionsbasiert
  (`PlayerLadder`, aus `Player._apply_movement`): zur Wand laufen = hoch, weg = runter, Sprung = ab.
  Untere Leitern schließen an obere an (`find_link`). Solo-only wie alle Umbauten.
- **Funde:** nach jedem Graben würfelt `DigFindTable` (Chance 6–24 % je Tiefe; Kupfer/Eisen flach,
  Silber/Gold/Edelsteine tiefer) → `DigFindRegistry` (Save-Key `dig_finds`) → sichtbare Ansicht
  `DigFind`, bergen per Interaktion (Bergbau-XP). Funde folgen dem Boden bei weiterem Graben.
- **Offen:** Wasser in tiefen Schächten (Grundwasser = globaler Wasserspiegel, siehe `TerrainField`).

### Ebnen-Modus (Schaufel) & Wasserwagen
Ziel: Bauplatz vorbereiten. Zwei Bausteine, beide auf dem Terrain-Gitter (2 m) und ohne Physik.
* **Wasserwagen** (`LevelGauge` rein/testbar, `LevelGaugeOverlay` = Farbnetz auf dem Gelände):
  Abweichung `d = Boden − Bezugshöhe`. Grün `|d| ≤ 0,10 m`; zu hoch = warm (gelb→orange→rot,
  „abtragen"), zu tief = kühl (cyan→blau→violett, „auffüllen"). Dazu eine Zeile im HUD
  („höher +0,42 m · tiefer −0,18 m · 63 % eben"). Das Netz folgt der Geländehöhe, blendet zum Rand aus
  und wird nur bei Zielwechsel/alle 300 ms neu gebaut.
  * **Baumodus:** Schalter „Wasserwagen" unten rechts im Steuerkreuz. Bezug = Mittel der vier Gitterecken
    der anvisierten Zelle (= die Höhe, auf die ein Boden dort einebnen würde, `BuildPlacementRules`).
    Bleibt zwischen Bauteilen/Sitzungen an.
  * **Ebnen-Modus:** Bezug = gesetzte Ebene (siehe unten), automatisch an.
* **Ebnen-Modus** (`TerrainPlanePlanner`, `WorldTerrainEditor.plan_plane/apply_plane_plan`,
  `WorldService.request_terrain_plane`): Schalter „Ebene" über den Schaufel-Knöpfen. ⌖ setzt die Ebene auf die
  Bodenhöhe am Zielpunkt, ▲▼ verschieben sie um 0,25 m. Im Modus werden „Graben"/„Füllen" zu
  **„Abtragen"** (nur zu hohe Punkte, nie unter die Ebene) und **„Auffüllen"** (nur zu tiefe, nie darüber);
  **„Ebnen"** macht beides. Gleicher Pinsel (Kern + weicher Rand), gleiche Schritthöhe (0,5 m/Aktion) und
  gleiche Bauwerks-Sperre wie Graben; wiederholte Züge konvergieren auf die Ebene, kein Überschwingen.
  Event: `terrain_plane_requested(player_id, target, plane_y, direction)`.
* **Material beim Ebnen:** Erde wandert innerhalb der Fläche von hoch nach tief; nur Überschuss/Fehlbetrag
  zählt, in der Einheit einer vollen Grabaktion (`TerrainPlanePlanner.unit_volume`, 1 Item je Einheit —
  Ebnen ist also nie ergiebiger als Graben). Bruchteile merkt `WorldService._plane_credit` je Spieler
  (nur Sitzung, < 1 Item). Fehlbeträge werden in ganzen Items vorab bezahlt (Reihenfolge Sand/Kies/Erde,
  das gewählte Material muss die volle Menge liefern); abgetragene Punkte verlieren ihr Material-Override,
  aufgefüllte bekommen das verbrauchte Material. XP und Funde wie beim Graben, sobald netto abgetragen wird.
* **Nächste Schritte:** Plane/Gauge-Zustand speichern; Wasserwagen auch ohne Schaufel im Bau-Menü;
  „Ebene aus Bauteil" (Ebene = Oberkante eines vorhandenen Bodens).

## Bauen
Daten-getrieben: `data/building/*.tres` (`BuildPieceDefinition`) + Eintrag in `DataManifest.BUILD_PIECES`.
* **Wahrheit = Records** (`BuildRegistry` in `WorldData.build_registry`, Save-Key `build_pieces`).
  Die 3D-Nodes (`BuildPiece`) sind nur eine **Ansicht**: `WorldBuildHandler` erzeugt sie beim Laden
  eines Chunks und entfernt sie beim Entladen.
* **Raster:** Zellen 2 m (= Terrain-Gitter). Boden = 1 Zelle, Wand = 1 Zellkante (`BuildGrid`).
* **Regeln an EINER Stelle:** `BuildPlacementRules.check()` — benutzt vom echten Bauen UND von der
  Vorschau (Geist), der Geist kann nie „grün" zeigen, wo das Bauen scheitert.
* **Böden ebnen das Gelände** unter sich ein (Delta-Schicht), Wände stehen auf Boden oder auf
  ebenem Untergrund; nicht im/am Wasser (`in_water`).
* UI: Toolbar-Button 🔨 → Bau-Menü (`BuildPanel*`) → Baumodus (`BuildMode*`, ⟳ drehen / ✔ bauen /
  ✕ beenden). Abreißen: am Bauteil „Abreißen" wählen (Rückgabe 75 % Material). Nicht möglich,
  solange etwas darauf steht (`supports_others`, `BuildRegistry.has_dependents`).
* **Zielen ohne Laufen** (`BuildAim`): Der Geist folgt dem **Blick** (Kamera-Mittelstrahl ↔ Gelände,
  max. 9 m um den Spieler). Steuerkreuz rechts: ▲▼◀▶ = eine Rasterzelle, relativ zur Kamera auf
  Weltachsen gerastet; der erste Schritt **fixiert** den Geist, „Blick" hebt die Fixierung auf.
  „Höher/Tiefer" wählt die Ebene.
* **Ebenen (`storey`, 0..`BuildGrid.MAX_STOREY`):** Ebene 0 hat die alten Schlüssel (`F_cx_cz`,
  `W<a>_cx_cz`) → alte Spielstände bleiben gültig. Ebene n>0 hängt `_L<n>` an. Höhe einer Ebene =
  `BuildGrid.LEVEL_HEIGHT` (2,5 m = Wandhöhe). Halt: Boden auf n braucht eine Wand auf n-1 an einer
  seiner Kanten; Wand auf n steht auf einem Boden der Ebene n (Nachbarzelle) oder auf der Wand
  darunter. Obere Ebenen ebnen kein Gelände ein.

### Neues Bauteil
Gleiche Art (Boden/Wand/Dach/Tür/Fenster/Treppe): nur neue `.tres` + Manifest-Eintrag. **Neue
Art**: neuer `BuildPieceDefinition.Kind`, Schlüsselraum + `snap()` in `BuildGrid`, Regeln in
`BuildPlacementRules`, Geometrie in `BuildPieceDefinition.get_box_*`/eigene Mesh-Funktion +
Zweig in `BuildPiece._build_geometry()` (Marker „ERWEITERUNG").

### Tür & Fenster (DOOR/WINDOW)
Wandartig (`BuildPieceDefinition.is_wall_like()`): TEILEN sich Schlüsselraum und
Platzierungsregeln 1:1 mit `WALL` (`BuildGrid.snap()`, `BuildPlacementRules.check()`) — sitzen
also auf derselben Zellkante und schließen sich mit einer normalen Wand (und miteinander) aus.
`BuildGrid.parse_key()` liefert für ihre Schlüssel weiterhin `Kind.WALL`: strukturell tragen sie
genauso wie eine Wand (halten Böden/Dächer der Ebene darüber). Einziger Unterschied ist die
Geometrie: `get_door_boxes()`/`get_window_boxes()` liefern mehrere Einzel-Boxen (Pfosten, Sturz,
bei Fenstern zusätzlich Brüstung) statt einer durchgehenden Wandbox — die Öffnung dazwischen hat
weder Mesh noch Kollision, man kann also wirklich hindurchgehen. `BuildPiece._add_framed()`
rendert jede Box einzeln (mit eigener Kollision), `BuildGhost`/`build_framed_mesh()` fassen
dieselben Boxen zu einem Vorschau-Mesh zusammen.

### Treppe (STAIRS)
Belegt wie Boden/Dach eine ganze Zelle (Schlüssel `T_<cx>_<cz>`, keine eigene Achsen-Codierung
im Schlüssel — pro Zelle/Ebene passt ohnehin nur eine Treppe), verbindet aber Ebene `n` begehbar
mit Ebene `n+1`. Rotation nutzt (anders als Wand/Dach) die volle Drehung (4 statt 2 Schritte):
`axis` speichert die Blickrichtung des Aufstiegs. Auflager: Ebene 0 braucht wie ein Boden festen,
nicht zu steilen Untergrund (Basis an der NIEDRIGSTEN Ecke, damit die Treppe nicht ins Gelände
ragt — kein Einebnen, die Treppe folgt dem Gelände nicht); Ebene `n>0` braucht wie ein oberer
Boden eine Wand der Ebene `n-1` an einer Zellkante. `height` sollte `BuildGrid.LEVEL_HEIGHT`
entsprechen (wie die Wandhöhe), damit sie ihre Ebene sauber überbrückt. Geometrie:
`build_stairs_mesh()` (STAIR_STEPS gestapelte Stufen) — Kollision besteht aus eigenen
Stufen-Boxen (`BuildPiece._add_stairs()`), nicht einer durchgehenden Rampe: bei
LEVEL_HEIGHT/CELL wäre eine Rampe zu steil zum flüssigen Gehen, echte Stufen lassen sich mit dem
üblichen „Step"-Verhalten einer `CharacterBody3D` hochlaufen. Trägt wie ein Dach nie etwas
(`BuildRegistry.has_dependents()` greift für `STAIRS` nicht), ist also immer abreißbar.

**Form (`stairs_shape`, `BuildPieceDefinition.StairsShape`):** `STRAIGHT` (Standard, siehe oben)
oder `SPIRAL` (Wendeltreppe) — dieselbe Zelle, dieselben Schlüssel/Auflagerregeln, nur die
Geometrie unterscheidet sich. `SPIRAL` windet sich über `SPIRAL_TURNS` Umdrehungen um einen
dünnen Mittelpfosten (`build_spiral_stairs_mesh()`, dieselbe Keil-Technik wie die Zinnen der
Türme, `_add_radial_block()`), Kollision sind rotierte Stufen-Boxen
(`BuildPiece._add_spiral_stairs_collision()`) statt der geraden Reihe. Braucht wegen der
kleineren Grundfläche pro Stockwerk weniger Platz als `STRAIGHT` — passt deshalb in Turmschäfte
(`TOWER_ROUND`/`TOWER_SQUARE`) und mehrstöckige Häuser.

### Dach (ROOF)
Satteldach-Segment über einer Zelle, First-Ausrichtung über Rotation wie bei Wänden (Achse 0/1).
Schlüssel `R_<cx>_<cz>` (wie Boden, kein eigener Achsen-Schlüsselraum — pro Zelle passt ohnehin
nur ein Dach). Auflager: **Wände derselben Ebene** rund um die Zelle (`BuildPlacementRules.
_check_roof`), nicht die Ebene darunter wie bei Böden/Wänden auf `storey>0` — ein Dach schließt
sein eigenes Stockwerk nach oben ab. Traufhöhe = höchste Wandoberkante der Zelle.
**Überhang (Stand 2026-10-09, Reichweite 3):** Eine Zelle ohne eigene Wand darf überdacht werden, wenn über eine lückenlose Kette
bereits stehender Dächer (Nachbarzellen, gleiche Ebene) höchstens `ROOF_OVERHANG_REACH` (= 3) Zellen entfernt ein Dach liegt, das von einer
Wand getragen wird. Die Traufhöhe übernimmt das nächste tragende Dach (bei gleich nahen das höchste). Vorher: nur 1 Zelle, keine Ketten; zwischenzeitlich 2.
Die Kette muss aus Dächern bestehen — über eine Lücke hinweg gibt es keinen Halt. Reihenfolge zählt weiter: je näher an der Wand, desto
früher (Vorlagen werden vom Generator nach Kettenlänge sortiert, daher drehungsunabhängig). Dadurch brauchen große Innenräume
(Kirchenschiff, Halle) keine Wand in jeder Zelle. Geometrie ist
ein echtes Prisma (`BuildPieceDefinition.build_roof_mesh()`, First entlang lokal X bei `height`
über der Traufe), gemeinsame Quelle für `BuildPiece` und `BuildGhost` wie beim Boden/Wand-Muster.
Trägt nie etwas (`BuildRegistry.has_dependents()`), ist also immer abreißbar.

### Auskragung: Balkone und Erker (2026-10-09)
Ein Boden auf Ebene n>0 braucht nicht mehr zwingend eine Wand der Ebene n-1 an einer eigenen Kante: Er darf stehen, wenn über eine
lückenlose Kette von Böden derselben Ebene höchstens `BuildRegistry.FLOOR_CANTILEVER_REACH` (= 3) Zellen entfernt ein wandgetragener
Boden liegt (`BuildRegistry.floor_support_top()`, EINE Regel für Boden, Treppe und Requisite auf oberen Ebenen). Oberkante = die des nächsten
tragenden Bodens. Wände auf einem Balkonboden stehen wie bisher auf einem Boden der Nachbarzelle (`floors_adjacent_to_wall`).
**Abriss-Schutz:** `has_dependents()` sperrt das Entfernen eines oberen Bodens (neben „Wände darauf“) auch dann, wenn ein anderer Boden der
Ebene dadurch seinen Halt verlöre (Simulation mit `ignore_key`), also keine schwebenden Balkone. Grenzen: Treppen/Requisiten auf einem
Balkon werden (wie schon auf normalen oberen Böden) beim Abriss des Trägers nicht mitgeprüft; Statik gibt es nicht (Gewicht egal).

### Requisiten (TARGET, `PropShape`)
Freistehende Bauteile (Schlüssel `P_<cx>_<cz>`, volle Drehung über `axis`), die keinen Halt brauchen —
ein Kind, viele Formen: `prop_shape` wählt die Geometrie (`BuildPieceDefinition.build_prop_mesh()`),
neue Form = neuer `PropShape`-Wert + `build_..._mesh()` + `.tres`, kein Platzierungscode. `height`
bedeutet je Form etwas anderes (siehe Klassenkommentar `PropShape`).

| PropShape | Bauteile (`data/building/`) | Kollision |
|---|---|---|
| `STAND_DISC` | Zielscheibe | Hüllbox |
| `WELL` | Brunnen | Hüllbox |
| `TOWER_ROUND` / `TOWER_SQUARE` | Steinturm (rund), Holzturm (eckig) | Hüllbox (voll) |
| `CROSS` / `GRAVESTONE_STELE` / `GRAVESTONE_SLAB` | Wegkreuz, Grabkreuz, Grabstein, Grabplatte | Hüllbox |
| `CHAPEL` | Steinkapelle, Holzkapelle | **Einzelboxen — begehbar** |
| `SIGNPOST` | Wegweiser | Hüllbox nur um den Pfosten |
| `LAMP_POST` | Straßenlaterne (Eisen), Holzlaterne | Hüllbox nur um den Pfosten |
| `BARREL` | Fass | Hüllbox |
| `MARKET_STALL` | Marktstand rot/blau (nur Farbdaten) | Hüllbox |
| `BAKE_OVEN` / `WORKBENCH` | Backofen, Werkbank | Hüllbox |
| `CRATE` / `SACKS` | Kistenstapel, Sackstapel | Hüllbox |
| `BENCH` / `TABLE` | Bank mit Lehne, Tisch mit Hockern | Hüllbox |
| `CART` / `BANNER` | Handkarren (mit Ladung ab `height` > 0.72), Fahnenmast (rot/blau) | Hüllbox |
| `PILLAR` / `FIREPIT` | Säule (Stein/Holz über die Farbe), Feuerstelle (Glut, **kein** Licht) | Hüllbox |
| `TROUGH` / `WOODPILE` | Wasser-/Futtertrog (nur Daten: Füllfarbe), Holzstapel | Hüllbox |
| `GARDEN_BED` / `SCARECROW` | Kräuter-/Blumenbeet (nur Daten: Pflanzenfarbe), Vogelscheuche | Hüllbox |
| `WEAPON_RACK` | Waffenständer (Speere, Schild) | Hüllbox |

**Mehrere Mesh-Flächen** (`CHAPEL`, `SIGNPOST`, `LAMP_POST`): jede Surface hat eine Rolle
(`PropSurface`, `prop_surface_roles()`): `MAIN` = `color`, `ACCENT` = `accent_color` (Dach,
Schilder), `GLOW` = emissive Leuchtfläche (`PROP_GLOW_COLOR`: Laternenglas, Kapellenfenster,
Kerzen). `build_prop_materials()` liefert die Materialien in Surface-Reihenfolge, `BuildPiece`
setzt sie per `set_surface_override_material()`; der Geist färbt weiter einheitlich nach
Baubarkeit. Alle älteren Formen bleiben einflächig (`[MAIN]`). Die neuen Meshes sind flach
schattiert (`_begin_flat_surface()`, smooth group −1).

**Kapelle:** Eingang = lokal +Z (Drehung stellt die Richtung ein). Statt der Hüllbox liefert
`get_prop_collision_boxes()` Seitenwände, Rückwand, Türpfosten, Sturz und Bodenplatte — Tür und
Innenraum sind frei. Wände reichen `CHAPEL_FOUNDATION` (0,6 m) unter y=0 (Hanglage). Die Grundfläche
(2,0 × 2,6 m) ragt in der Tiefe je 0,3 m über die Zelle hinaus, das Dach seitlich 0,18 m — Nachbar-
zellen nicht dicht daneben verbauen. Dach und Dachreiter kollidieren nicht. `height` = Wandhöhe;
Gesamthöhe `chapel_total_height()`.

**Wegweiser:** drei pfeilförmige Schilder (`SIGNPOST_BOARDS`), die in verschiedene Richtungen
zeigen; ausgerichtet wird der ganze Wegweiser über die Drehung. Die Schilder hängen über Kopfhöhe
und haben keine Kollision. Beschriftung gibt es (noch) nicht.

**Straßenlaterne / Licht:** `light_range > 0` an der `.tres` erzeugt zusätzlich ein `OmniLight3D`
(`BuildPiece._add_prop_light()`, warm, ohne Schatten, in der Mitte des Glases — `lamp_glass_bounds()`
ist die gemeinsame Quelle für Mesh und Lichtposition). Es gibt noch keinen Tag/Nacht-Zyklus
(Sonne/Himmel sind statisch, `WorldTimeService` zählt nur die Zeit): die Lichter brennen daher
immer. Alle Lichter sind in der Gruppe `night_lights` — der Haken, an dem ein späterer Zyklus sie
nur nachts einschaltet. Renderer ist GL Compatibility: sehr viele Laternen in Sichtweite kosten
Leistung (Limit für gleichzeitig gerenderte Lichter), daher `light_range` moderat halten.

## Schreibpfad (UI → Welt)
UI/Entities emittieren **nur Wünsche** über den EventBus (`terrain_edit_requested`,
`build_place_requested`, `build_remove_requested`). `WorldService` prüft (Solo, Reichweite, Material,
Regeln) und führt über die testbaren Hilfsklassen aus. Die UI liest nur (`ctx.get_world().preview_build()`).

## Bekannte Grenzen (bewusst, siehe „Nächste Schritte")
* **Solo-only.** In Mehrspieler-Sitzungen sind Umbauten aus und unsichtbar (sonst sehen Host und
  Clients verschiedene Welten); der Spielstand behält die Daten. Koop = Records/Deltas über
  `NetworkBridge.broadcast_to_all_peers` + Snapshot beim Beitritt (Erweiterungspunkt im
  WorldService-Abschnitt „Gelände & Bauen").
* Bäume/Erze, die schon in einem Chunk stehen, folgen einer späteren Geländeänderung nicht (sie
  stehen weiter auf der alten Höhe, bis der Chunk neu geladen wird). Graben nahe Bauwerken ist gesperrt.
* Kein Schwimmen/Ertrinken/Waten-Verlangsamung: `TerrainField.get_water_depth_at()` ist der Haken dafür.
* Bauteile haben keine Trefferpunkte/Besitzrechte (`owner` wird schon gespeichert).
* Zweistufige Entity-Höhen (Bäume auf Bauteilen) fehlen. Statik: nur die einfache Regel „nichts abreißen, worauf noch etwas steht" (konservativ, kein Lastpfad).

---

## Landschaftsdichte: Props, Gras, Büsche, Zufallsgebäude (2026-10-05)

| Was | Wo | Wie |
|---|---|---|
| Bäume/Pilze/Steine | `ChunkEntitySpawner._spawn_props()` | Entities; Versuche pro Chunk aus `BiomeDefinition.prop_attempts_min/max`, Hainbildung (`GROVE_*`), Mindestabstand, **echtes gewichtetes Sampling** (`_roll_weighted_type`). Globaler Regler: `PROP_DENSITY_MULT`. |
| Gras, Büsche | `ChunkVegetationBuilder` | Je Chunk ein `MultiMeshInstance3D` (`Grass`, `Bushes`), keine Kollision/Interaktion. Dichte: `BiomeDefinition.grass_per_chunk/bush_per_chunk`. Höhen aus dem Raster von `TerrainChunkBuilder.build()`. Wird bei Geländeänderung neu gebaut. |
| Gebäude | `ChunkStructurePlanner` (Plan) → `ChunkStructureBuilder` (Geometrie) | Deterministisch pro Chunk (16 %), nur wo `structure_types` gesetzt ist, nie im Spawn-Sperrring, nur auf fast ebenem Land. Typen: `cottage`, `barn`, `well`, `ruin`. |
| Gebäude-NPCs | `SettlerNPC`/`FarmerNPC`/`WaterCarrierNPC` | Beklaubare Dorfbewohner (erben von `VillagerNPC`); Name/Zeile aus der Spawn-Position. |

**Dörfer, Straßen und Siedlungsgebäude** (logisch verknüpfte Strukturen, Kartenmarkierung): siehe [`settlements.md`](settlements.md).

Neuer Gebäudetyp = Eintrag in `ChunkStructurePlanner.TYPES` + `match`-Zweig in `ChunkStructureBuilder.build()` + (optional) NPC-Typ in `NPC_TYPE_BY_STRUCTURE`/`NPC_SLOTS`.
Bekannte Grenzen: Gras/Büsche ragen durch vom Spieler gebaute Böden; Büsche sind begehbar (keine Kollision); Welt-Neugenerierung ändert Prop-Positionen (Abgeerntetes aus alten Saves passt nicht mehr zu neuen Positionen).

---

## Berufs-Requisiten & Berufs-Gebäude (Stand 2026-10-06)
Idee: klein anfangen (Requisiten), daraus größere Strukturen (Vorlagen) bauen.
* **Vier Handwerks-Requisiten** (`PropShape.BARREL … WORKBENCH`, Kind `TARGET`, kein neuer Platzierungscode),
  zusätzlich zu den Schmiede-Stationen `FURNACE`/`ANVIL`. Gemeinsame Regeln: `height` = Gesamthöhe (durch
  `craft_prop_height()` auf eine Mindesthöhe begrenzt), Hüllbox = `craft_prop_footprint()` × `craft_prop_height()`,
  Vorderseite = lokal +Z, alles passt in eine Zelle. Neue Enum-Werte nur **hinten anhängen** (die `.tres`
  speichern die Zahl). Flächen: Fass/Stand/Werkbank `[MAIN, ACCENT]`, Backofen `[MAIN, GLOW]`.
* **Sechs neue Vorlagen** (klein → groß, `data/building/houses/`; die Schmiede mit Hochofen/Amboss steht in
  `Smithy.tres`): Bäckerei (3×2), Zimmerei (4×2), Marktplatz (5×3), Taverne (4×3), Bauernhof (5×4),
  Handwerkerviertel (6×5, 88 Teile; kleine Schmiede mit Hochofen, Amboss-Platz frei zum Nachrüsten).
  Erzeugt und validiert von `tools/building_templates/generate_craft_templates.py` (`--check` = nur prüfen):
  Schlüsselkollisionen, Dach-Auflager, blockierte Türen, Reichweite (`REACH` 10 m, gemessen von der Mitte).
  Requisiten-Blickrichtung `axis`: 0 = Süden (+Z), 1 = Osten, 2 = Norden, 3 = Westen.
* **Tests:** `test_build_system.gd` (Abschnitt „Handwerks-Requisiten“): Registrierung, Rollen, Höhe = höchster
  Mesh-Punkt, Mesh bleibt im Footprint, Vorlagen-Konsistenz (inkl. `smithy`). **Nicht in Godot gelaufen**
  (kein Binary in der Sandbox) — die Geometrie wurde zusätzlich per Python-Nachrechnung aus dem GDScript geprüft.
* **Bekannt:** Große Vorlagen verlangen, dass der Spieler nahe der Mitte steht (`REACH` gilt je Teil).
  `VillageChurch` war unbaubar (zwei Dachzellen ohne Wand rundherum) — behoben durch den Dach-Überhang oben,
  abgesichert durch `test_village_church_roofs_are_all_placeable_with_overhang`. Der Generator
  `generate_craft_templates.py` prüft weiterhin STRENG (jede Dachzelle mit eigener Wand), die neuen Vorlagen
  brauchen den Überhang also nicht.

### Blumen + Sense (2026-10-06)

- **Blumen:** `BiomeDefinition.flower_per_chunk/flower_colors`; `ChunkVegetationBuilder` setzt sie als MultiMesh (`Flowers`) in Farbflecken (`FLOWER_PATCHES`), Farbe/Mitte/Stiel im Shader über `UV.x`/`INSTANCE_CUSTOM`.
- **Sense (`tool_scythe`, Shop 22 Gold, `ToolType.SCYTHE`):** `GroundToolController` zeigt mit ausgerüsteter Sense den Knopf „Mähen“ → Aktion `mow_ground` (Tempo-Stat `mow_speed`) → Event `grass_cut_requested` → `WorldService.request_grass_cut()` (nur Solo wie Graben; Reichweite 5 m, Radius `MOW_RADIUS` 2,4 m).
- **Ertrag:** Heu (`hay`, 1 je ~5 Büschel, max 8) und Wildblumen (`wildflower`, 1 je 2 Blumen, max 5). Ohne Gras/Blumen im Kreis: Meldung, nichts verbraucht.
- **Mähkreise:** `ChunkManager.cut_vegetation()` baut die betroffenen Chunks aus dem gecachten Höhenraster neu (Gras + Blumen fehlen im Kreis, Büsche bleiben). Kreise halten `GRASS_REGROW_SEC` (420 s Spielzeit), überleben Chunk-Entladen, werden nicht gespeichert.
- **Determinismus:** `ChunkVegetationBuilder` zieht alle Zufallswerte eines Büschels VOR den Prüfungen — ein Mähen/Graben verschiebt den Rest der Wiese nicht.
- Offen: kein XP für Mähen, keine Vorschau des Mähkreises (wie `TerrainEditGhost` beim Graben), im Koop nicht verfügbar.

---

## Torbögen, Zinnenmauer, Kleinigkeiten (Stand 2026-10-06)
Ziel: Dörfer, Städte und Burgen aus wenigen, kombinierbaren Grundformen füllen.
* **Torbogen = Öffnungsform, kein neuer Typ.** `DOOR`/`WINDOW`-Bauteile haben `opening_shape`
  (`RECT` = wie bisher, `ARCH` = Rundbogen), `opening_width` und `opening_height` (Bogenscheitel ab Basis;
  0 = Standardwerte). Der Bogen entsteht in `_arch_frame_boxes()` aus Pfosten bis zum Ansatz, `ARCH_STEPS`
  gestuften Boxpaaren, einer Scheitelbox und der Restwand — Optik und Kollision aus derselben Box-Liste wie die
  Tür, keine eigene Mesh-Pipeline. Die Öffnung ist der echten Kurve einbeschrieben (nie breiter, nie blockiert),
  die Wand daneben bleibt dicht. Neue Torformen/Breiten sind damit reine `.tres`:
  `stone_gate_arch` (1.7 m breit, Scheitel 2.3), `stone_arch_door`, `wood_arch_door`, `stone_arch_window`,
  `wood_arch_window`. Platzierung/Regeln = normale Tür/Fenster (gleicher Kantenschlüssel wie Wände).
* **Zinnenmauer = `WALL` mit `wall_top = CRENELLATED`** (`stone_wall_crenel`). `get_wall_boxes()` liefert Körper +
  halbe/ganze/halbe Zinne (alles innerhalb `height`, Auflager/Dach-Regeln unverändert); `BuildPiece` und
  `BuildGhost` nutzen sie wie die Tür-Boxen. An den Zellkanten ergeben zwei Segmente eine ganze Zinne.
* **Acht Kleinigkeiten** (`PropShape.CRATE … FIREPIT`, Kind `TARGET`, gleiche Regeln wie die Handwerks-Requisiten):
  Kiste, Sack, Bank, Tisch, Handkarren, Fahne (rot/blau), Säule (Stein/Holz), Feuerstelle.
* **Drei Vorlagen:** Torbogen (5 Felder), Stadttor (zwei Türme, 14 m), Dorfplatz (5×5). Generator + Validator:
  `tools/building_templates/generate_craft_templates.py`.
* **Dach-Überhang:** siehe oben — erlaubt große Hallen mit einem Dach ohne Wand in jeder Zelle.
* **Grenzen:** Der Bogen ist gestuft (5 Stufen), nicht glatt; eine Torkante ist 1 Zelle (2 m) breit — breitere Tore
  = mehrere Bögen nebeneinander (siehe unten). Torflügel sind starr (kein Öffnen/Schließen per Interaktion).

### Hof und Wehr: Stall, Garten, Scheune, Kaserne, Wehrhof (2026-10-09)

Wunsch: Strukturen und Gebäude weiter ausbauen, klein anfangen und hochbauen. Thematische Lücken waren Reittiere
(`docs/mounts.md` hatte keinen Stall), Landwirtschaft/Kräuterkunde (Beete) und der Wehrbau oberhalb des Wachpostens.
* **Fünf neue Requisiten-Formen** (`PropShape.TROUGH … WEAPON_RACK`, hinten an die Enum angehängt → gespeicherte
  `prop_shape`-Zahlen bleiben gültig; Kind `TARGET`, Hüllbox, eine Zelle, `is_craft_prop()`): Trog, Holzstapel, Hochbeet,
  Vogelscheuche, Waffenständer. Wasser-/Futtertrog und Kräuter-/Blumenbeet sind nur Farbdaten
  (`trough_water`/`trough_feed`, `garden_bed_herbs`/`garden_bed_flowers`).
* **Sechs Vorlagen, klein nach groß** (`DataManifest.HOUSE_TEMPLATES`, erzeugt von `generate_craft_templates.py`):
  Kräutergarten (5×3), Stall (4×2), Scheune (5×3, Bogentor), Mauereck mit Eckturm (Baustein für Stadt-/Burgmauern),
  Kaserne (5×3 Stein, großer Bruder des Wachpostens), Wehrhof (6×5, vier Ecktürme, Torturm, Hofeinrichtung).
* **Generator kennt jetzt den Dach-Überhang** (wie `BuildPlacementRules._check_roof`, Reichweite 2) und schreibt Dächer nach
  Kettenlänge sortiert (eigene Wand zuerst, Reichweite 3). Wichtig, weil `WorldBuildHandler` in Dateireihenfolge baut und ein Überhang sein tragendes
  Nachbardach schon braucht — so stimmt die Reihenfolge für jede Drehung des Hauses. Bestehende Vorlagen bleiben
  bitgleich (alle ihre Dächer haben eine eigene Wand).
* **Festhalle (7×5):** nur die Langseiten sind Wand, die Giebelseiten offen zwischen Holzsäulen, ein Dach für alles — Beispiel für die
  gelockerte Dachregel (mittlere Dachreihe hängt 2 Zellen von der Wand).
* **Tests:** `test_build_system.gd` deckt die neuen Formen (Mesh-Höhe, Grundfläche, Kollision, Flächenrollen) und die sechs
  Vorlagen ab; Scheune und Kaserne haben zusätzlich einen Dach-Platzierungstest wie die Kirche.
* **Behobene Altlasten:** Aschenschale des Hochofens ragte 0,14 m aus der Hüllbox (jetzt 0,08 m); der Bogenfenster-Test
  tastete genau auf geteilten Kanten ab (Gleitkomma-Zufall), Proben liegen jetzt zwischen den Kanten.
* **Offen / nicht headless prüfbar:** Optik der neuen Formen im Editor ansehen (Proportionen, Farben); Stall hat noch keine
  Spielfunktion (Reittiere „parken" dort nicht), Beete tragen noch keine Samen (siehe `docs/herbalism-and-gardening.md`,
  baubares Beet mit Samenwahl).

### Bäume in echten Proportionen (2026-10-07)

Vorher: Eiche 2 m Stamm + 2 Astgruppen + ~28 Einzelblätter (≈ 3 m hoch bei 1,8 m Spieler). Jetzt:

| Teil | Wo | Wie |
|---|---|---|
| Astwerk | `TreeSkeleton` (rein, testbar) | Stamm + rekursive Verzweigung über 3 Ebenen (Haupt-/Seitenäste/Zweige), Blattanker an den Enden. Tanne: Astkränze (`conifer`). `min_y` hält hängende Weidenzweige über dem Boden. |
| Zusammenbau | `MeshCache._assemble_tree()` | Nur 4–6 Nodes je Baum (MultiMesh): `Branches`, `Twigs` (nah), `Leaves0..2` (nah), `CrownFar` (fern), `Snow`. |
| Laub | `ProceduralTextureFactory.foliage_card()` | EINE Karte = Büschel aus vielen Blättern (bzw. Nadelzweig) statt Einzelblatt; 3 Farbvarianten je Art. |
| Größen | `MeshCache._build_scene_*` | Eiche ≈ 10 m, Ahorn ≈ 8,5 m, Weide ≈ 8 m, Tanne ≈ 14 m; Sapling ≈ 1,7 m, Jungbaum ≈ 5 m (`TREE_STAGE_*`). |
| Nah/Fern | `LOD_NEAR_DISTANCE` = 55 m | Laub-Karten + Zweige nah, Kronenkugeln fern. |
| Platz | `ChunkEntitySpawner.PROP_RADIUS_TREE` | Bäume halten 4,8 m Abstand zueinander, kleine Props 2,4 m. |

Richtwerte pro ausgewachsenem Baum (Simulation des Algorithmus): Eiche ≈ 340 Karten / 193 Äste, Ahorn ≈ 290 / 166, Weide ≈ 270 / 292, Tanne ≈ 500 / 335. Performance-Regler: `cards_per_tip` je Art in `_build_scene_*`, `TREE_STAGE_CARDS`, `LOD_NEAR_DISTANCE`.
Offen: Bäume haben (wie vorher) keine Stamm-Kollision; Sapling-Setzlinge bleiben ein Verzweigungs-Modell der kleinen Stufe.

### Dichte Wälder (2026-10-08)

Wunsch: Wälder "richtig dicht an dicht". `BiomeRegistry`: `forest` 40–60, `dense_forest` 64–96 Prop-Versuche pro Chunk (≈ 21 bzw. 33–42 Bäume), Mindestabstand zwischen Stämmen nur 3 m (`ChunkEntitySpawner.PROP_RADIUS_TREE` 1,5; kleine Props 0,8). Eichenkronen reichen ≈ 6–7 m: es entsteht ein geschlossenes Blätterdach.
**Performance-Regler (nicht ungeprüft lassen!):** jeder Baum ist eine Entity (+ 4–6 MultiMesh-Nodes). Dichter Wald ≈ 65 Entities pro Chunk. Bei Rucklern zuerst `ChunkEntitySpawner.PROP_DENSITY_MULT` (z. B. 0.7), dann `LOD_NEAR_DISTANCE` (MeshCache) und `cards_per_tip` je Art senken. Biom-Regel: Summe der `prop_chances` ≤ 1.0 (Test `test_prop_chance_sums_stay_within_one_per_biome`).


## Strukturen: Bau-Modus & Nutzung (2026-10-06)

**Abreißen nur im Bau-Modus.** `BuildModeState` (statisch, lokal) gilt als aktiv, solange das Bau-Menü
offen ist oder ein Bauteil/Haus platziert wird (`BuildPanelController`/`BuildModeController` setzen je eine
Quelle). Wechsel kommen als `UIEvents.build_mode_changed`. `BuildPiece._apply_build_mode()` schaltet die
Abreißen-Komponente (`InteractableComponent.set_enabled()`) und hält die Gruppe `interactable` aktuell: ohne
aktive Aktion ist das Bauteil kein Ziel (kein Label, nicht antippbar). Stationen/Nutzaktionen bleiben immer an.
Reine UI — die Autorität prüft Abreißen weiter selbst (Reichweite/Berechtigung im `WorldBuildHandler`).

**Nutzung von Strukturen** (`BuildPieceDefinition.use_*`: `use_label`, `use_duration`, `use_consumes`,
`use_gives`, `use_cooldown`, `use_animation`). Leeres `use_label` = keine Nutzung. `BuildPiece` hängt eine
weitere `InteractableComponent` an; `StructureUse` (zustandslos wie `InteractionResolver`) verbraucht/gibt
Items nur auf der Autorität, mit Cooldown je Spieler und Rollback bei vollem Inventar. Der Client bekommt
nur eine Vorab-Rückmeldung aus dem lokalen Inventar. Neue nutzbare Struktur (Mühle: Korn → Mehl) = nur Daten.

**Brunnen:** `data/building/Well.tres` — „Wasser schöpfen“: 1 `bucket` → 1 `water_bucket` (Eimer im Shop, 15).
Animation `well_bucket`: Eimer und Seil sind eigene Nodes (`build_well_mesh(height, false)` ohne Eimer),
`BuildPiece.play_well_bucket_animation()` senkt den Eimer, streckt das Seil und zieht ihn hoch; gestartet über
`InteractableComponent.progress_started`, nur auf dem handelnden Peer (rein visuell, keine Replikation).
Offen: der Wassereimer hat noch keinen Verbraucher (z.B. Felder gießen); `content_forge.py` kennt noch keinen
Bauteil-Typ, `Well.tres` wurde deshalb von Hand ergänzt.


### Torflügel, breite Tore, Wehrgang, Ebenen in Vorlagen (Stand 2026-10-06)
* **Torflügel (`leaf_state`, `LeafState`)** an `DOOR`-Bauteilen, für RECT und ARCH: `NONE` (Standard, offener Durchgang),
  `OPEN` (zwei Flügel hochkant nach außen +Z geklappt, Durchgang bleibt frei, Flügel bleiben innerhalb der Zelle),
  `CLOSED` (Flügel füllen die Öffnung, sperrt den Durchgang bis zum Abreißen). Gleiche Box-Liste für Optik und Kollision
  (`get_door_boxes()` → `_leaf_boxes()`). Teile: `wood_door_open/_closed`, `wood_gate_open/_closed`, `stone_gate_open/_closed`.
* **Breite Tore:** `stone_gate_arch_wide` (1.9 m Öffnung, Scheitel 2.4); mehrere Torkanten nebeneinander ergeben ein
  breites Tor mit schmalen Pfeilern (Vorlage `city_gate_grand`: drei Bögen = 6 m Durchfahrt).
* **Wehrgang = Boden auf Ebene 1 über der Mauer.** `stone_walkway` (`FLOOR`, `skirt` 2.3 → massiver Mauerkörper unter dem
  Gang) liegt in der Zelle neben der Mauerkante und bündig auf der Mauerkrone (Ebene-1-Boden braucht eine Wand der Ebene 0
  an einer Zellkante, `_check_floor_upper`). Außen die niedrige Zinnenbrüstung `stone_parapet` (WALL, 1.3 m,
  `wall_top = CRENELLATED`, steht auf der Mauer darunter), innen z. B. `wood_fence` auf Ebene 1 (steht am Gang-Boden).
* **Treppe auf die Mauerkrone:** normale `stone_stairs` auf Ebene 0, `axis` = Aufstiegsrichtung (0 = +Z/Süden, 1 = +X,
  2 = −Z/Norden, 3 = −X), Zelle direkt vor dem Gang; an der Landekante darf KEIN Geländer stehen.
* **Vorlagen mit Ebenen:** Jeder Eintrag in `HouseTemplateDefinition.pieces` darf `"storey": n` (Offset zur Hausebene,
  Default 0) tragen. `WorldBuildHandler._house_layout()` baut Ebene für Ebene (Boden → Wand/Tür/Fenster → Dach/Treppe/
  Requisite), `house_ghost_pieces()` hebt die Geister je Eintrag auf die richtige Höhe; Drehen lässt `storey` unberührt.
  Neue Vorlagen: `wall_walk` (6 Felder Mauer mit Wehrgang + Treppe), `city_gate_grand` (drei Tore, zwei Türme, Wehrgang).
* **Tests:** `test_world_build_handler.gd` baut alle ausgelieferten Berufs-/Tor-Vorlagen (und die `village_church`) gegen
  die ECHTEN Regeln in allen vier Drehungen; dazu Ebenen-Reihenfolge, fehlendes Auflager und Geister-Höhe.
