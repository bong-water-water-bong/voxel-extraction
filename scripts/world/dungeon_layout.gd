extends RefCounted
class_name DungeonLayout

## The complete layout of a generated dungeon.
## Used by the game to spawn enemies, place loot, track room state.

var rooms: Array[DungeonRoom] = []
var corridors: Array[Dictionary] = []
var spawn_position: Vector3 = Vector3.ZERO
var extraction_positions: Array[Vector3] = []

func get_room_at(point: Vector3) -> DungeonRoom:
	for room in rooms:
		if room.contains_point(point):
			return room
	return null

func get_rooms_by_role(role: DungeonRoom.Role) -> Array[DungeonRoom]:
	var result: Array[DungeonRoom] = []
	for room in rooms:
		if room.role == role:
			result.append(room)
	return result

func get_uncleared_combat_rooms() -> Array[DungeonRoom]:
	var result: Array[DungeonRoom] = []
	for room in rooms:
		if room.role == DungeonRoom.Role.COMBAT and not room.is_cleared:
			result.append(room)
	return result

func get_closest_extraction(from: Vector3) -> Vector3:
	var closest := Vector3.ZERO
	var min_dist := INF
	for pos in extraction_positions:
		var dist := from.distance_to(pos)
		if dist < min_dist:
			min_dist = dist
			closest = pos
	return closest

func get_total_enemies() -> int:
	var total := 0
	for room in rooms:
		total += room.enemy_count
	return total

func get_cleared_percentage() -> float:
	var total := 0
	var cleared := 0
	for room in rooms:
		if room.role in [DungeonRoom.Role.COMBAT, DungeonRoom.Role.BOSS]:
			total += 1
			if room.is_cleared:
				cleared += 1
	if total == 0:
		return 100.0
	return (float(cleared) / float(total)) * 100.0

func get_minimap_data() -> Array[Dictionary]:
	"""Return simplified room data for minimap rendering."""
	var data: Array[Dictionary] = []
	for room in rooms:
		data.append({
			"position": Vector2(room.position.x, room.position.z),
			"size": Vector2(room.size.x, room.size.z),
			"role": room.role,
			"cleared": room.is_cleared,
		})
	return data
