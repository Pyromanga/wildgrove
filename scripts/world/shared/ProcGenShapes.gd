class_name ProcGenShapes
extends RefCounted

## ProcGenShapes — gemeinsame Low-Level-Bausteine für prozedurale Geometrie aus
## Godot-Primitiven (SphereMesh/CapsuleMesh/BoxMesh/CylinderMesh + MeshInstance3D +
## StandardMaterial3D).
##
## Vorher DREIFACH unabhängig voneinander implementiert:
##   - CharacterPartBuilder._mat()/_mi()/_sphere()/_capsule()/_box()/_cylinder()/_place()
##   - AnimalVisualBuilder: derselbe Code direkt inline in build()/_add_legs()
##   - NPCVisualBuilder:    derselbe Code nochmal inline in build()
## Jede neue Tierart / jeder neue NPC-Typ / jedes neue Charakterteil brauchte bisher seine
## eigene Kopie von "Mesh erzeugen, Material einfärben, MeshInstance3D benennen und
## positionieren". Das ist jetzt hier EINMAL gebündelt — CharacterPartBuilder,
## AnimalVisualBuilder und NPCVisualBuilder rufen nur noch diese Funktionen auf.
##
## Bewusst NICHT dasselbe wie BuildPieceDefinition.build_*_mesh(): das Bausystem baut
## Dreiecksnetze von Hand über SurfaceTool (Wände/Dächer/Türme — Geometrie, die Godots
## Primitive-Meshes nicht abbilden), hier geht es um simple Kombinationen aus
## Kugel/Kapsel/Box/Zylinder für organische/humanoide Figuren. Zwei unterschiedliche
## Probleme, zwei unterschiedliche Techniken — aber innerhalb JEDER der beiden Techniken
## jetzt nur noch eine Quelle.
##
## Rein statisch, kein State.

# ─────────────────────────────────────────────
# Material / MeshInstance
# ─────────────────────────────────────────────

static func mat(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

static func mi(mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, node_name: String = "") -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	if not node_name.is_empty():
		inst.name = node_name
	inst.mesh = mesh
	inst.material_override = material
	inst.position = pos
	return inst

# ─────────────────────────────────────────────
# Primitive-Meshes
# ─────────────────────────────────────────────

## Halbkugel: Godot verlangt height == radius bei is_hemisphere.
static func sphere(radius: float, hemisphere: bool = false, segments: int = 16, rings: int = 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius if hemisphere else radius * 2.0
	s.is_hemisphere = hemisphere
	s.radial_segments = segments
	s.rings = rings
	return s

static func capsule(radius: float, height: float, segments: int = 16, rings: int = 4) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.0 + 0.001)
	c.radial_segments = segments
	c.rings = rings
	return c

static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func cylinder(top_r: float, bottom_r: float, height: float, segments: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c

## Kegel = Zylinder mit top_radius 0. Eigener Name, weil an den Aufrufstellen (Ohren,
## Hörner/Geweih, Stacheln, Schwänze) `cone(r, h)` klarer liest als `cylinder(0.0, r, h)`.
static func cone(base_radius: float, height: float, segments: int = 10) -> CylinderMesh:
	return cylinder(0.0, base_radius, height, segments)

# ─────────────────────────────────────────────
# Platzierung auf gekrümmten Oberflächen
# ─────────────────────────────────────────────

## Platziert `node` auf der Oberfläche einer Kugel mit Radius `sphere_radius` um den
## lokalen Ursprung des Elternknotens: (x, y) = Position auf der "Vorderseite"
## (Ebene senkrecht zu +Z), die Tiefe (z) ergibt sich aus der Kugelform. `lift` schiebt
## zusätzlich entlang der Oberflächennormale nach außen — +Z des Nodes zeigt danach aus
## der Kugel heraus. `roll` dreht in der Tangentialebene, `node_scale` skaliert in den
## daraus resultierenden lokalen Achsen.
##
## Extrahiert aus CharacterPartBuilder._place() (dort ursprünglich fest auf HEAD_R
## zugeschnitten) — jetzt mit explizitem `sphere_radius`, damit auch Tierköpfe
## (unterschiedliche Radien je Spezies) denselben Code für Augen-/Ohren-/Schnauzen-
## Platzierung nutzen können statt ihn erneut abzutippen.
static func place_on_sphere(
	node: Node3D, sphere_radius: float, x: float, y: float, lift: float,
	node_scale: Vector3 = Vector3.ONE, roll: float = 0.0
) -> void:
	var z := sqrt(maxf(sphere_radius * sphere_radius - x * x - y * y, 0.0001))
	var surface := Vector3(x, y, z)
	var n := surface.normalized()
	var b := Basis.looking_at(-n, Vector3.UP) * Basis(Vector3.BACK, roll) * Basis.from_scale(node_scale)
	node.transform = Transform3D(b, surface + n * lift)

## Kegel/Stachel, dessen Spitze entlang `dir` von `base` aus zeigt (Basis der Länge
## `length` entlang dieser Richtung verschoben, damit `base` der Ansatzpunkt bleibt statt
## der Kegelmittelpunkt). Extrahiert aus CharacterPartBuilder._spike() — dort ursprünglich
## nur für Frisuren gedacht, jetzt allgemein nutzbar (z.B. Ohren, Geweihsprossen).
static func spike(mesh: Mesh, material: Material, base: Vector3, dir: Vector3, length: float, node_name: String = "") -> MeshInstance3D:
	var d := dir.normalized()
	var node := mi(mesh, material, base + d * (length * 0.5), node_name)
	node.basis = Basis(Quaternion(Vector3.UP, d))
	return node
