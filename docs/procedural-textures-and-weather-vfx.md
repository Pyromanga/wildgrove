# Texturen & Wetter-Optik — Architektur

Stand: erste Runde (2026-09-24). Ziel: "Natur ist auch nur Mathematik" — Detail-Optik für
Blätter, Wasser, Regen, Wind, Steine, Holz, Gras, Sand, Kies komplett aus Noise-Funktionen
berechnet, **keine einzige Bilddatei** im Repo. Ergänzt die bestehende rein-prozedurale
Mesh-Pipeline (`MeshCache`, siehe dortiger Klassenkommentar) um dieselbe Idee für
Oberflächen-Detail und um sichtbare Wetter-Effekte (ADR-041 hatte das bewusst offengelassen:
_"künftige Systeme können darauf aufsetzen"_ — das hier ist dieser Aufsatz).

## Zwei unterschiedliche Techniken, je nach Objekt

```
Terrain/Wasser (kein UV-Layout, ein Vertex pro Heightmap-Punkt)
      → Noise direkt im Fragment-Shader auf Welt-XZ-Position (GLSL)
      → TerrainMeshBuilder / TerrainWaterBuilder

Objekte mit UVs (Bäume, Felsen, Farn — PrimitiveMesh mit Standard-UVs)
      → ProceduralTextureFactory generiert einmalig ein kleines Image (CPU, GDScript)
      → MeshCache.get_textured_material() cacht daraus ein StandardMaterial3D
      → Factory3D/MeshCache-Szenenbauer verwenden es wie jedes andere Material
```

Beide Wege nutzen **dieselbe Hash-Formel** (Integer-Arithmetik statt `FastNoiseLite`,
damit die Optik bit-identisch bleibt, egal welche Godot-Version rendert — analog
`TerrainSeed.derive()`, FNV statt `String.hash()`). Das GLSL-Pendant steht direkt im
Shader-String (kann keine GDScript-Klasse aufrufen), die GDScript-Variante in
`ProceduralTextureFactory._hash2()`.

## ProceduralTextureFactory (`scripts/world/materials/`)

Statische Fabrik, Ergebnis pro Kategorie gecacht (`_cache`-Dictionary, wie
`MeshCache.materials`). Kategorien:

* **Oberflächen** (RGB, kachelbar via `uv1_scale`): `stone()`, `wood()`, `bark()`,
  `moss()`, `grass()`, `sand()`, `gravel()`, `dirt()`, `ore_iron()`, `ore_copper()`,
  `ice()`, `sulfur()`, `wax()`, `glass()`, `charcoal()` — Value-Noise/fbm um 1.0 herum
  (Multiplikator auf `albedo_color`, kein eigener Farbwert), **außer** den sechs
  zuletzt genannten: die backen ihre Farbe (Rostrot/Grünspan/Eisblau/Schwefelgelb/
  Wachs-Amber/Glas-Grün/Glut-Orange) direkt in die Textur statt sie über
  `albedo_color` zu bekommen — ein einzelner Multiplikator kann nicht "grauer Stein
  MIT andersfarbigen Adern" gleichzeitig, deshalb bewusste Ausnahme von der sonstigen
  Konvention. Aufrufer tönen entsprechend mit einem neutralen, hellen Ton statt einer
  kräftigen Farbe (siehe `IronOre._build_visuals()` etc.), sonst verschluckt das die
  gebackenen Adern/Flecken. `ore_iron()`/`ore_copper()` nutzen denselben
  "Marmor-Ader"-Trick (`_build_ore()`): eine Farbe wird dort eingeblendet, wo ein
  zweites fbm-Feld nahe seiner Mittellinie liegt — ergibt dünne, verzweigt wirkende
  Linien statt gerader Striche. `sulfur()` nutzt dieselbe Technik für Trockenrisse
  (Abdunklung statt Einfärbung). `bark()` ist `wood()` plus eine quere Riss-Maske
  (Baumstämme statt gehobeltem Bauholz); `moss()` nutzt eine scharfe statt lineare
  Schwelle für klar abgesetzte Flecken (liegende Stämme im Wald-Biom, siehe
  `MeshCache._build_scene_fallen()`); `ice()` rastert eine gedrehte Koordinatenachse in
  diskrete Stufen für kantige Bruchflächen statt runder Flecken.
* **Sprites** (RGBA, Alpha-Cutout): `leaf_card()` (Blattform + Mittelrippe, `hue_seed`
  für Farbvarianten), `raindrop_streak()` (Regen-Partikel-Billboard),
  `snowflake()` (Schnee-Partikel-Billboard, auch als Rauch/Glühwürmchen-Basis
  zweckentfremdet, siehe `CharcoalKiln._add_smoke()`/`AmbientForestVfx`).

Neue Kategorie hinzufügen: eigene `_build_*()`-Methode (gibt `Image` zurück) + Eintrag in
`get_textured_material()`s `match` (MeshCache) **und** in `get_swaying_material()`s `match`,
falls die Kategorie auch auf schwingenden Objekten (Kronen/Farn) vorkommen soll — zwei
`match`-Blöcke, weil beide Materialarten unabhängig gecacht werden. Kein bestehender
Aufrufer muss sich ändern.

## Vorher immer einfarbige Platzhalter (Erz, Eis, Schwefel, Wachs, Glas, Kohle)

`IronOre`, `CopperOre`, `Meteorite`, `IceCrystal`, `SulfurCrust`, `WildBeehive`,
`Fulgurite` und `CharcoalKiln` hatten (anders als Bäume/Fels, die über `Factory3D`/
`MeshCache` gehen) **nie** einen texturierten Pfad — `HarvestableEntity._add_placeholder_box()`/
`_add_placeholder_cylinder()` bauten immer nur ein `StandardMaterial3D` mit reiner
Flächenfarbe, ohne Alternative. Beide Helfer haben jetzt einen optionalen dritten
Parameter `texture_category`: gesetzt UND `Factory3D`/`MeshCache` gerade verfügbar →
`MeshCache.get_textured_material()` (dieselbe Stelle, die auch Bäume/Fels bedient);
sonst (Parameter leer, wie bei alle bisherigen Aufrufern, oder `_ctx`/Factory3D fehlt)
unverändert reine Flächenfarbe — rein additiv, kein bestehender Aufrufer ändert sich.

`Meteorite` bekommt dabei die bereits vorhandene `stone()`-Textur (dunkel getönt) statt
einer neuen Kategorie — ein Meteorit ist im Kern einfach dunkles Gestein, keine eigene
Optik nötig.

## Ambient-Bonus: Rauch am Kohlenmeiler

`CharcoalKiln._add_smoke()` — der Inspect-Text nannte den Meiler bereits einen
"rauchenden Erdhügel", visuell kam bisher aber kein Rauch. Kleines, immer aktives
`GPUParticles3D` (kein Ein/Aus nötig, der Meiler "brennt" durchgehend bis er
abgeerntet wird): `snowflake()` als weicher Rauch-Punkt zweckentfremdet, steigt
langsam statt zu fallen (`gravity` zeigt nach oben), weiches Ein-/Ausblenden über
die Lebenszeit via `color_ramp` (gleicher Trick wie bei `AmbientForestVfx.Fireflies`).

## Wind-Sway (Kronen & Farn)

`MeshCache.get_swaying_material()` ersetzt `get_material()`/`get_textured_material()` für
Objekte, die sich im Wind bewegen sollen: Baumkronen (alle vier Laub-/Nadelbaumtypen,
inkl. Schneehaube auf der Winter-Kiefer) und Farn. Ein einziger, einmalig gebauter
`Shader` (`MeshCache._sway_shader`, GLSL-Code in `_build_sway_shader()`) wird von allen
`ShaderMaterial`-Instanzen geteilt — jede trägt nur ihre eigenen Uniform-Werte
(`albedo_color`, optionale Textur aus `ProceduralTextureFactory`, `sway_strength`).

* Zwei überlagerte Sinuskurven aus `TIME`, exakt dasselbe Prinzip wie `WindField`
  (GDScript) — eigenständig in GLSL nachgebaut, weil ein Shader keine GDScript-Klassen
  aufrufen kann (gleiche Einschränkung wie `TerrainMeshBuilder.grain_hash()`).
* Phasenlage kommt aus einem Hash auf die XZ-Weltposition des Objekt-Pivots
  (`MODEL_MATRIX * vec4(0,0,0,1)`), nicht aus `WindField` selbst — dadurch schwingt
  nicht der ganze Wald synchron, ohne dass der Shader mit der GDScript-Wind-Instanz
  reden müsste.
* Nur Vertices mit positivem lokalem Y bewegen sich (`max(VERTEX.y, 0.0)`) — die
  Basis (Ansatzpunkt am Ast/Stamm) bleibt fest, nur der obere Teil pendelt.
* `sway_strength` (Uniform, kein neuer Shader) unterscheidet Nadelbaum (0.6, steifer),
  Laubkrone (1.0, Default) und Farn (1.6, leichtes Blattwerk) — reine Playtesting-Startwerte,
  nicht im echten Spiel begutachtet (siehe "Bekannte Grenzen").
* Schneehaube auf der Winter-Kiefer nutzt bewusst denselben `sway_strength`/dieselbe
  X/Z-Position wie der Nadelkegel darunter (gleicher Hash → gleiche Phase), damit sie
  nicht optisch vom schwingenden Ast abhebt.

## Terrain & Wasser

* `TerrainMeshBuilder`: Fragment-Shader moduliert `ALBEDO`/`ROUGHNESS` mit zwei
  Noise-Frequenzen (grob = Flecken, fein = Korn) auf `world_pos.xz` — `world_pos` kommt
  aus dem Vertex-Shader (`MODEL_MATRIX * VERTEX`), weil `VERTEX` selbst chunk-lokal ist.
  Reine Funktion der Weltposition → keine Nähte zwischen Chunks möglich.
* `TerrainWaterBuilder`: fbm-Noise mit `TIME`-Offset (Wellen laufen), zweites versetztes
  Sample als billiger Gradient (Kräuselung ohne echte Normal-Map), Schaum-Schwelle an
  Wellenkämmen + an der ohnehin vorhandenen Ufer-Alpha-Kante (weiche Gischt statt hartem
  Farbschnitt).

## Wetter-Optik (`scripts/world/weather_time/`)

* `WindField`: deterministischer Wind aus `world_seed` + Zeit (zwei überlagerte
  Sinuskurven) — reine Optik, bewusst **nicht** netzwerksynchronisiert (Peers dürfen
  optisch leicht auseinanderlaufen, betrifft keine Spiellogik).
* `WeatherVfx`: Node3D, folgt dem lokalen Spieler (`follow()`), hört auf
  `WorldEvents.weather_changed` und schaltet `GPUParticles3D` für Regen/Schnee um
  (Texturen aus `ProceduralTextureFactory`). **Liest nur** — `WeatherService.current_weather`
  bleibt die einzige Wahrheit, genau wie zuvor. Verdrahtet in
  `WorldService.on_world_scene_ready()`, freigegeben in `on_cleanup()`. Auf einem
  dedizierten Server (Tier 3, kein lokaler Spieler) bleibt sie inaktiv (`active=false`).
* `AmbientForestVfx`: gleiches Muster wie `WeatherVfx`, aber biom-/tageszeitgesteuert statt
  wettergesteuert:
  - treibendes, fallendes Laub (`ProceduralTextureFactory.leaf_card()`, drei Hue-Varianten
    auf drei separate `GPUParticles3D`-Kinder verteilt), aktiv in `"forest"`/`"dense_forest"`.
  - Glühwürmchen (selbstleuchtende, warme Punkte mit `emission_enabled` statt nur hellem
    Albedo, damit `Environment.glow_enabled` — siehe unten — sie tatsächlich zum Leuchten
    bringt), aktiv nur in `"dense_forest"` **und** nachts (`WorldTimeService.day_time`
    außerhalb 05:30–20:30, siehe `NIGHT_START_HOUR`/`NIGHT_END_HOUR`).
  - Beide Checks laufen alle 1.5 s (`AMBIENT_CHECK_INTERVAL`), nicht pro Frame.
  - Löst den bisherigen toten Code — `leaf_card()` existierte bereits, wurde aber
    nirgends aufgerufen.
  - Gleiches `spawn_local_player`-Gate, gleiche Verdrahtungs-/Cleanup-Stelle wie
    `_weather_vfx`.

## Nebel & Sonnenhelligkeit je Wetter

`WorldFactory._add_environment()` erzeugt seit jeher eine `WorldEnvironment` + `Sun`
(`DirectionalLight3D`) für die Overworld — anders als eine frühere Version dieser Doku
behauptete, fehlt hier also **nichts** an Grundausstattung; nur die *Kopplung* an das
Wetter fehlte. Die gibt es jetzt: `WeatherVfx` bekommt in `configure()` optional die
`Environment`-Resource übergeben (nachgeschlagen in `WorldService.on_world_scene_ready()`,
direkt nachdem `WorldFactory.create_world()`s Kinder in `world_root` verschoben wurden)
und passt bei `weather_changed` `fog_density`/`fog_light_color` an — weich über mehrere
`_process()`-Frames interpoliert (`FOG_LERP_SPEED`), kein harter Szenenschnitt.
Sonnenhelligkeit setzt `WeatherVfx` **nicht mehr direkt** (siehe nächster Abschnitt) —
sie berechnet nur noch einen Dimm-Faktor (`get_sun_factor()`), den `DayNightCycle` liest.

* `"fog"` bekommt die dichteste, hellste Nebelfarbe — die einzige Wetterlage, bei der
  Nebel selbst der Effekt ist statt nur Randnotiz.
* `"storm"` dimmt die Sonne am stärksten (0.5×) und färbt den Nebel am dunkelsten.
* `"rain"`/`"snow"` sind sanfte Zwischenstufen, `"clear"` fährt beides auf den
  Ausgangszustand zurück.
* `Environment.glow_enabled` ist jetzt global an (moderat: `glow_intensity=0.35`,
  `glow_hdr_threshold=1.2`) — Grundvoraussetzung dafür, dass die neuen Glühwürmchen
  (siehe oben) tatsächlich als Leuchtpunkte wirken statt als flache helle Flecken.

## Tag/Nacht-Zyklus (`DayNightCycle`)

`WorldTimeService.day_time` (0..24, tickt bereits seit Langem) hatte bisher keinen
visuellen Verbraucher — `Sun.rotation_degrees`/`light_energy` waren in `WorldFactory`
fest einprogrammiert, `WorldEvents.time_of_day_changed` wurde gefeuert, aber nirgends
gehört. `DayNightCycle` (neuer Node, gleiches Verdrahtungs-/Cleanup-Muster wie
`WeatherVfx`/`AmbientForestVfx`) schließt diese Lücke:

* Sonnen-Elevation läuft linear über `day_time` (06:00 Horizont/Sonnenaufgang, 12:00
  Zenit, 18:00 Horizont/Sonnenuntergang, 00:00 "unter" dem Horizont) — reine X-Rotation,
  der Azimut (Y) bleibt fest bei `SUN_YAW_DEG`, kein zweiter Freiheitsgrad ohne
  spürbaren Zusatznutzen für ein stilisiertes Mobile-Tageslicht.
* Sonnenhelligkeit/Umgebungslicht/Himmelsfarbe folgen `_compute_day_factor()` — 0
  (volle Nacht) bis 1 (voller Tag), mit `smoothstep`-Übergang an Morgen-/Abenddämmerung
  und einem Plateau von 8:00–18:30 statt eines spitzen Sinus-Maximums nur um 12 Uhr.
* **Ein Schreiber pro Property**, damit sich `WeatherVfx` und `DayNightCycle` nicht pro
  Frame gegenseitig überschreiben: `DayNightCycle` ist der einzige, der auf
  `Sun.light_energy`/`Sun.rotation_degrees`/`Environment.ambient_light_energy`/
  Himmelsfarben schreibt und multipliziert dafür seine eigene Tag/Nacht-Basishelligkeit
  mit `WeatherVfx.get_sun_factor()` (statt dass beide unabhängig auf `light_energy`
  schreiben). Nebel (`env.fog_*`) bleibt umgekehrt exklusiv bei `WeatherVfx`.
* Dieselben Tag/Nacht-Eckwerte tauchen jetzt an zwei Stellen auf: `AmbientForestVfx`
  (`NIGHT_START_HOUR`/`NIGHT_END_HOUR`, harter Cutoff für Glühwürmchen) und
  `DayNightCycle` (`DAY_START`/`DAY_FULL`/`DUSK_START`/`NIGHT_FULL`, weicher Übergang
  fürs Licht) — bewusst nicht in eine gemeinsame Konstante ausgelagert: unterschiedliche
  Anforderungen (Glühwürmchen brauchen nur ein Ja/Nein, Licht einen Verlauf), eine
  gemeinsame Quelle wäre hier Kopplung ohne echten Nutzen. Bei einer Anpassung der
  "wann ist Nacht"-Uhrzeiten beide Stellen im Blick behalten.

## Lichtschächte/God-Rays (experimentell, hinter Settings)

Volumetrischer Nebel (`Environment.volumetric_fog_enabled`) macht Lichtstrahlen der Sonne
selbst sichtbar — genau der "Lichtschacht durchs Kronendach"-Look, den der normale
`fog_*`-Nebel oben nicht kann (der färbt nur die Ferne ein, streut aber kein Licht
sichtbar im Raum). Kostet dafür einen vollen Froxel-Raymarch pro Frame, spürbar teurer
als alles andere in dieser Optik-Schicht — für ein Touch-first-Mobile-Projekt (siehe
README) kein Feature, das man niemandem fest aufzwingen sollte.

Deshalb jetzt hinter dem Settings-Key `"volumetric_fog"` (`SettingsService.DEFAULTS`,
Default `false`) statt fest verdrahtet oder komplett weggelassen: Settings-Panel →
"Grafik (experimentell)" → "Lichtschächte im Wald", ein reiner An/Aus-Schalter (bewusst
keine Stärke-Regler, gegen "Anschlag" auf Geräten, die es nicht wegstecken).
`DayNightCycle` liest den Wert einmal beim Weltaufbau und hört danach live auf
`SettingsService.setting_changed` — Umschalten wirkt sofort, kein Weltneustart nötig.
Dichte ist bei Aktivierung fest auf einen niedrigen Wert gesetzt
(`DayNightCycle.VOLUMETRIC_FOG_DENSITY`), nicht einstellbar.

Nie in einer laufenden Godot-Instanz begutachtet (kein Runtime hier verfügbar, wie der
Rest dieser Optik-Schicht) — ob der Effekt auf einem echten Mobilgerät spielbar bleibt,
ist unklar; genau dafür ist es ein Opt-in-Schalter statt eines Standardverhaltens.

## Bekannte Grenzen (bewusst, erste Runde)

* Wind-Sway (siehe eigener Abschnitt oben) ist auf Kronen/Farn umgesetzt, aber mit
  Schätzwerten für `sway_strength` parametrisiert (nie in einer laufenden Godot-Instanz
  begutachtet, hier nicht verfügbar) — beim ersten Playtest wahrscheinlich nachzujustieren,
  keine neue Architektur nötig dafür (reiner Uniform-Wert pro Aufrufstelle in `MeshCache`).
* Terrain-Gras selbst (die Bodenfläche, nicht Farn) hat keinen Sway — es ist eine
  Vertex-eingefärbte Heightmap-Fläche ohne einzelne Grashalme als Geometrie (siehe
  `TerrainMeshBuilder`), Sway bräuchte dort eigene Halm-Geometrie statt nur eine Textur.
* Nebel/Sonnenlicht-Kopplung (siehe eigener Abschnitt oben) ist ebenfalls mit
  Schätzwerten parametrisiert, nicht playgetestet.
* Kein Regen-Spritzer/Pfützen-Decal beim Auftreffen, keine nassen Oberflächen (Terrain
  bleibt optisch trocken auch bei "storm").
* Lichtschächte/God-Rays gibt es jetzt (siehe eigener Abschnitt oben), aber nur hinter
  einem Settings-Schalter und ungetestet auf echter Mobile-Hardware — bewusst kein
  Standardverhalten.
* Regen/Schnee/Laub/Glühwürmchen folgen aktuell nur dem lokalen Spieler, nicht anderen
  sichtbaren Peers.
* `ore_iron()`/`ore_copper()`/`ice()`/`sulfur()`/`wax()`/`glass()`/`charcoal()` (siehe
  eigener Abschnitt oben) sind wie der Rest dieser Optik-Schicht nie in einer laufenden
  Godot-Instanz gesehen worden — insbesondere die Ader-/Riss-Schwellwerte
  (`smoothstep(0.0, 0.06, ...)` bzw. `0.045`) sind Schätzwerte; zu dünn/zu dick sichtbare
  Adern sind der wahrscheinlichste erste Justierbedarf. `wax()` bildet keine echten
  Sechsecke nach (reiner Fleck-Noise wie `stone()`, nur amberfarben) — eine echte
  Wabenstruktur wäre ein Voronoi-Muster und deutlich aufwändiger als der Rest dieser
  Kategorie, bewusst zurückgestellt.
* Baumkronen zeigen jetzt Nah/Fern-LOD (`MeshCache.LOD_NEAR_DISTANCE`): aus der Nähe echte
  `leaf_card()`-Blattkarten-Cluster mit Form pro Baumart (`LeafShape`), aus der Ferne die
  alte, billige Kugel — überblendet weich über `visibility_range_*_margin`, kein eigener
  Tick nötig. Damit betrifft der vorige Punkt ("Baumkronen sind einfarbige Kugeln") nur noch
  die Fern-Variante, was beabsichtigt ist (auf die Entfernung ohnehin nicht unterscheidbar).
* `AmbientForestVfx.NIGHT_START_HOUR`/`NIGHT_END_HOUR` (Glühwürmchen, harter Cutoff) und
  `DayNightCycle.DAY_START`/`DAY_FULL`/`DUSK_START`/`NIGHT_FULL` (Licht, weicher Verlauf)
  sind beide grob geschätzt, nicht playgetestet, und bewusst nicht dieselbe Konstante
  (siehe DayNightCycle-Abschnitt oben) — bei Anpassung beide Stellen im Blick behalten.
* `DayNightCycle` dreht nur die Elevation (X), der Azimut (Y) bleibt fest — die Sonne
  geht also immer an derselben Himmelsrichtung auf/unter, wandert nicht übers Jahr
  o.ä. (für ein stilisiertes Tageslicht bewusst nicht nachgebildet).
