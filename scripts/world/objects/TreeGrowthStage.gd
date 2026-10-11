class_name TreeGrowthStage
extends RefCounted

## TreeGrowthStage — wählt deterministisch (aus der Weltposition, NICHT per Zufall — jeder Peer
## muss an derselben Chunk-Position denselben Baum in derselben Größe sehen, ohne RPC/Sync) das
## Wachstumsstadium eines Baums (siehe MeshCache.TreeStage). Wunsch "Bäume in verschiedenen
## Stadien darstellen": ein natürlicher Wald besteht nicht nur aus ausgewachsenen Bäumen — eine
## Minderheit Sapling/Jungbaum sorgt für Abwechslung, ohne dass irgendein Baum je "wächst" (kein
## Zeit-/Speicherzustand nötig — der Wert ist bei jedem Neuladen exakt derselbe).
##
## Verteilung bewusst zugunsten von MATURE (der Wald soll nicht wie eine Baumschule aussehen):
## ~12% SAPLING, ~23% YOUNG, ~65% MATURE.

const SAPLING_THRESHOLD: float = 0.12
const YOUNG_THRESHOLD: float = 0.35  ## SAPLING_THRESHOLD + Anteil YOUNG

## Echtes Nachwachsen "über Spieltage hinweg" (Folge-Wunsch, ergänzt die obige statische
## Varietät): ein Baum, der (wieder-)gepflanzt wurde (siehe WorldService._respawn_spawn(), das
## WorldData.planted_day setzt), ist ab da SAPLING, ab SAPLING_DAYS Tagen YOUNG, ab YOUNG_DAYS
## Tagen (insgesamt) MATURE. Bewusst kurz gehalten (Spieltage sind mit time_speed=0.05 ~8h
## Echtzeit pro Spieltag, siehe WorldTimeService) — soll innerhalb einer normalen
## Spielsitzung/-woche sichtbar vorankommen, keine Wochen-Wartezeit sein.
const SAPLING_DAYS: int = 2
const YOUNG_DAYS: int = 5

## Wachstumsstadium aus dem Alter in Spieltagen.
static func for_age(age_days: int) -> int:
	if age_days < SAPLING_DAYS:
		return 0  # MeshCache.TreeStage.SAPLING
	if age_days < YOUNG_DAYS:
		return 1  # MeshCache.TreeStage.YOUNG
	return 2      # MeshCache.TreeStage.MATURE

## Zentrale Anlaufstelle für OakTree/WillowTree/MapleTree/PineTree._build_visuals(): kombiniert
## echtes Nachwachsen (`planted_day` >= 0 — Alter in Tagen zählt, siehe for_age()) mit der
## statischen Positions-Varietät oben (`planted_day` == -1, originaler Weltbestand beim
## Chunk-Laden, der nie über WorldService._respawn_spawn() lief — siehe dortiger Kommentar) in
## EINEM Aufruf, damit die Baum-Skripte nicht selbst zwischen beiden Fällen unterscheiden müssen.
static func suffix_for_tree(pos: Vector3, planted_day: int, current_day: int, salt: int = 0) -> String:
	if planted_day < 0:
		return suffix_for_position(pos, salt)
	var age: int = maxi(0, current_day - planted_day)
	match for_age(age):
		0: return "_sapling"
		1: return "_young"
		_: return ""

## Liefert MeshCache.TreeStage (0=SAPLING, 1=YOUNG, 2=MATURE) für eine Weltposition. `salt`
## erlaubt mehreren Baumarten an derselben Position unterschiedliche (aber weiterhin
## deterministische) Werte zu bekommen, falls sie je dieselbe Zellmitte teilen sollten.
static func for_position(pos: Vector3, salt: int = 0) -> int:
	var h: float = _hash(pos, salt)
	if h < SAPLING_THRESHOLD:
		return 0  # MeshCache.TreeStage.SAPLING
	if h < YOUNG_THRESHOLD:
		return 1  # MeshCache.TreeStage.YOUNG
	return 2      # MeshCache.TreeStage.MATURE

## Wie for_position(), liefert aber direkt das Schlüssel-Suffix, das Factory3D.create_simple_tree()
## bzw. PineTree für den passenden MeshCache-Szenenschlüssel braucht ("" für MATURE — der
## unveränderte, rückwärtskompatible Schlüssel, "_young", "_sapling") statt des rohen Enum-Werts.
static func suffix_for_position(pos: Vector3, salt: int = 0) -> String:
	match for_position(pos, salt):
		0: return "_sapling"
		1: return "_young"
		_: return ""

## Einfacher, deterministischer Positions-Hash → [0, 1). Dieselbe sin()-basierte
## Pseudo-Rauschen-Technik wie in ProceduralTextureFactory, nur auf Vector3 statt auf
## Pixel-Koordinaten — kein Random-Objekt, kein Seed-Zustand, exakt reproduzierbar.
static func _hash(pos: Vector3, salt: int) -> float:
	var v: float = pos.x * 12.9898 + pos.z * 78.233 + float(salt) * 37.719
	var s: float = sin(v) * 43758.5453
	return s - floor(s)
