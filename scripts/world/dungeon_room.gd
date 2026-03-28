extends RefCounted
class_name DungeonRoom

## A single room in a procedural dungeon.

enum Role {
	UNASSIGNED,
	SPAWN,
	COMBAT,
	BOSS,
	LOOT,
	EXTRACTION,
	PUZZLE,
	REST,
}

enum Shape {
	RECTANGULAR,
	CIRCULAR,
	L_SHAPED,
}

var position: Vector3i = Vector3i.ZERO
var size: Vector3i = Vector3i(8, 5, 8)
var role: Role = Role.UNASSIGNED
var shape: Shape = Shape.RECTANGULAR
var enemy_count: int = 0
var enemy_spawn_points: Array[Vector3] = []
var loot_positions: Array[Vector3] = []
var is_boss: bool = false
var is_cleared: bool = false
var doors_locked: bool = false

func volume() -> int:
	return size.x * size.y * size.z

func floor_area() -> int:
	return size.x * size.z

func center() -> Vector3:
	return Vector3(
		position.x + size.x / 2.0,
		position.y + size.y / 2.0,
		position.z + size.z / 2.0,
	)

func floor_center() -> Vector3:
	return Vector3(
		position.x + size.x / 2.0,
		position.y + 1.0,
		position.z + size.z / 2.0,
	)

func contains_point(point: Vector3) -> bool:
	return (
		point.x >= position.x and point.x < position.x + size.x and
		point.y >= position.y and point.y < position.y + size.y and
		point.z >= position.z and point.z < position.z + size.z
	)

func mark_cleared() -> void:
	is_cleared = true
	doors_locked = false
