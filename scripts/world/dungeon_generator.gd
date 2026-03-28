extends RefCounted
class_name DungeonGenerator

## Procedural dungeon generation for extraction raids.
##
## Architecture: rooms + corridors + points of interest.
## Each dungeon is a "pack" — a theme with its own rooms, enemies,
## loot tables, and extraction points. The base game ships with
## Dungeon Pack 01: The Undercroft.
##
## Dungeon packs are data-driven — drop a new pack JSON into
## the packs/ folder and it just works.

const MIN_ROOM_SIZE := Vector3i(5, 4, 5)
const MAX_ROOM_SIZE := Vector3i(15, 8, 15)
const CORRIDOR_WIDTH := 3
const CORRIDOR_HEIGHT := 3
const MAX_ROOMS := 20
const MIN_ROOMS := 8

var rng: RandomNumberGenerator
var rooms: Array[DungeonRoom] = []
var corridors: Array[Dictionary] = []
var spawn_room_index: int = -1
var extraction_room_indices: Array[int] = []
var pack: DungeonPack

func _init(dungeon_pack: DungeonPack, seed_val: int = 0) -> void:
	pack = dungeon_pack
	rng = RandomNumberGenerator.new()
	rng.seed = seed_val if seed_val != 0 else randi()

func generate(chunk_manager: ChunkManager) -> DungeonLayout:
	rooms.clear()
	corridors.clear()

	# Step 1: Generate room layout (BSP tree)
	var layout := _generate_room_layout()

	# Step 2: Connect rooms with corridors
	_connect_rooms()

	# Step 3: Assign room purposes
	_assign_room_roles()

	# Step 4: Carve into voxel world
	_carve_dungeon(chunk_manager)

	# Step 5: Place furniture, props, loot containers
	_populate_rooms(chunk_manager)

	# Step 6: Place extraction beacons
	_place_extraction_points(chunk_manager)

	return layout

# ── Room Layout (BSP) ──────────────────────────────────────────

func _generate_room_layout() -> DungeonLayout:
	var layout := DungeonLayout.new()
	var room_count := rng.randi_range(MIN_ROOMS, MAX_ROOMS)

	# Place rooms with collision avoidance
	var attempts := 0
	while rooms.size() < room_count and attempts < room_count * 10:
		attempts += 1
		var room := _generate_room()
		if _room_fits(room):
			rooms.append(room)

	layout.rooms = rooms
	layout.corridors = corridors
	return layout

func _generate_room() -> DungeonRoom:
	var room := DungeonRoom.new()

	# Size
	room.size = Vector3i(
		rng.randi_range(MIN_ROOM_SIZE.x, MAX_ROOM_SIZE.x),
		rng.randi_range(MIN_ROOM_SIZE.y, MAX_ROOM_SIZE.y),
		rng.randi_range(MIN_ROOM_SIZE.z, MAX_ROOM_SIZE.z),
	)

	# Position — spread across the dungeon area
	var spread := 80
	room.position = Vector3i(
		rng.randi_range(-spread, spread),
		rng.randi_range(2, 20),  # Underground
		rng.randi_range(-spread, spread),
	)

	# Room shape variant
	room.shape = rng.randi_range(0, 2) as DungeonRoom.Shape

	return room

func _room_fits(new_room: DungeonRoom) -> bool:
	var margin := 2  # Gap between rooms
	for existing in rooms:
		if _rooms_overlap(new_room, existing, margin):
			return false
	return true

func _rooms_overlap(a: DungeonRoom, b: DungeonRoom, margin: int) -> bool:
	return (
		a.position.x - margin < b.position.x + b.size.x + margin and
		a.position.x + a.size.x + margin > b.position.x - margin and
		a.position.y - margin < b.position.y + b.size.y + margin and
		a.position.y + a.size.y + margin > b.position.y - margin and
		a.position.z - margin < b.position.z + b.size.z + margin and
		a.position.z + a.size.z + margin > b.position.z - margin
	)

# ── Corridors ──────────────────────────────────────────────────

func _connect_rooms() -> void:
	if rooms.size() < 2:
		return

	# Minimum spanning tree — connect all rooms with shortest paths
	var connected: Array[int] = [0]
	var unconnected: Array[int] = []
	for i in range(1, rooms.size()):
		unconnected.append(i)

	while unconnected.size() > 0:
		var best_from := -1
		var best_to := -1
		var best_dist := INF

		for from_idx in connected:
			for to_idx in unconnected:
				var dist := _room_center(rooms[from_idx]).distance_to(
					_room_center(rooms[to_idx])
				)
				if dist < best_dist:
					best_dist = dist
					best_from = from_idx
					best_to = to_idx

		if best_to >= 0:
			_create_corridor(best_from, best_to)
			connected.append(best_to)
			unconnected.erase(best_to)

	# Add a few extra connections for loops (more interesting navigation)
	var extra := rng.randi_range(1, max(1, rooms.size() / 4))
	for i in extra:
		var a := rng.randi_range(0, rooms.size() - 1)
		var b := rng.randi_range(0, rooms.size() - 1)
		if a != b:
			_create_corridor(a, b)

func _create_corridor(from_idx: int, to_idx: int) -> void:
	var from_center := _room_center(rooms[from_idx])
	var to_center := _room_center(rooms[to_idx])

	# L-shaped corridor: go horizontal first, then vertical, then horizontal
	corridors.append({
		"from": from_idx,
		"to": to_idx,
		"from_pos": from_center,
		"to_pos": to_center,
		"width": CORRIDOR_WIDTH,
		"height": CORRIDOR_HEIGHT,
	})

func _room_center(room: DungeonRoom) -> Vector3:
	return Vector3(
		room.position.x + room.size.x / 2.0,
		room.position.y + room.size.y / 2.0,
		room.position.z + room.size.z / 2.0,
	)

# ── Room Roles ─────────────────────────────────────────────────

func _assign_room_roles() -> void:
	if rooms.size() == 0:
		return

	# Spawn room — the one closest to center and largest
	var best_spawn := 0
	var best_score := INF
	for i in rooms.size():
		var center := _room_center(rooms[i])
		var dist := center.length()
		var size_bonus := rooms[i].volume() * -0.1
		var score := dist + size_bonus
		if score < best_score:
			best_score = score
			best_spawn = i
	spawn_room_index = best_spawn
	rooms[best_spawn].role = DungeonRoom.Role.SPAWN

	# Extraction rooms — 2-3 rooms farthest from spawn
	var distances: Array[Dictionary] = []
	for i in rooms.size():
		if i == spawn_room_index:
			continue
		var dist := _room_center(rooms[i]).distance_to(_room_center(rooms[spawn_room_index]))
		distances.append({"index": i, "distance": dist})
	distances.sort_custom(func(a, b): return a["distance"] > b["distance"])

	var extract_count := rng.randi_range(2, min(3, distances.size()))
	for i in extract_count:
		var idx: int = distances[i]["index"]
		rooms[idx].role = DungeonRoom.Role.EXTRACTION
		extraction_room_indices.append(idx)

	# Boss room — between spawn and extraction, large
	for i in rooms.size():
		if rooms[i].role != DungeonRoom.Role.UNASSIGNED:
			continue
		if rooms[i].volume() > 400:
			rooms[i].role = DungeonRoom.Role.BOSS
			break

	# Loot rooms — medium rooms
	var loot_count := 0
	for i in rooms.size():
		if rooms[i].role != DungeonRoom.Role.UNASSIGNED:
			continue
		if rooms[i].volume() > 200 and loot_count < 3:
			rooms[i].role = DungeonRoom.Role.LOOT
			loot_count += 1

	# Rest are combat rooms
	for i in rooms.size():
		if rooms[i].role == DungeonRoom.Role.UNASSIGNED:
			rooms[i].role = DungeonRoom.Role.COMBAT

# ── Carving ────────────────────────────────────────────────────

func _carve_dungeon(cm: ChunkManager) -> void:
	# Carve rooms
	for room in rooms:
		_carve_room(cm, room)

	# Carve corridors
	for corridor in corridors:
		_carve_corridor(cm, corridor)

func _carve_room(cm: ChunkManager, room: DungeonRoom) -> void:
	var wall_block: int = pack.wall_block
	var floor_block: int = pack.floor_block
	var ceiling_block: int = pack.ceiling_block

	for x in range(room.position.x, room.position.x + room.size.x):
		for z in range(room.position.z, room.position.z + room.size.z):
			for y in range(room.position.y, room.position.y + room.size.y):
				var is_wall := (
					x == room.position.x or x == room.position.x + room.size.x - 1 or
					z == room.position.z or z == room.position.z + room.size.z - 1
				)
				var is_floor := y == room.position.y
				var is_ceiling := y == room.position.y + room.size.y - 1

				if is_floor:
					cm.set_block(Vector3i(x, y, z), floor_block)
				elif is_ceiling:
					cm.set_block(Vector3i(x, y, z), ceiling_block)
				elif is_wall:
					cm.set_block(Vector3i(x, y, z), wall_block)
				else:
					cm.set_block(Vector3i(x, y, z), VoxelData.BlockID.AIR)

	# Special blocks based on role
	match room.role:
		DungeonRoom.Role.EXTRACTION:
			# Place beacon in center
			var cx := room.position.x + room.size.x / 2
			var cz := room.position.z + room.size.z / 2
			var cy := room.position.y + 1
			cm.set_block(Vector3i(cx, cy, cz), VoxelData.BlockID.EXTRACTION_BEACON)

		DungeonRoom.Role.LOOT:
			# Lanterns in corners
			for corner in _get_room_corners(room):
				cm.set_block(Vector3i(corner.x, room.position.y + 1, corner.z), VoxelData.BlockID.LANTERN)

		DungeonRoom.Role.SPAWN:
			# Well-lit spawn
			var cx := room.position.x + room.size.x / 2
			var cz := room.position.z + room.size.z / 2
			for offset in [Vector3i(-2, 0, 0), Vector3i(2, 0, 0), Vector3i(0, 0, -2), Vector3i(0, 0, 2)]:
				cm.set_block(
					Vector3i(cx + offset.x, room.position.y + room.size.y - 2, cz + offset.z),
					VoxelData.BlockID.LANTERN,
				)

func _carve_corridor(cm: ChunkManager, corridor: Dictionary) -> void:
	var from: Vector3 = corridor["from_pos"]
	var to: Vector3 = corridor["to_pos"]
	var width: int = corridor["width"]
	var height: int = corridor["height"]
	var wall_block: int = pack.wall_block
	var floor_block: int = pack.floor_block

	# L-shaped: horizontal X, then vertical Y, then horizontal Z
	var mid := Vector3(to.x, from.y, from.z)
	var mid2 := Vector3(to.x, to.y, from.z)

	_carve_corridor_segment(cm, from, mid, width, height, floor_block, wall_block)
	_carve_corridor_segment(cm, mid, mid2, width, height, floor_block, wall_block)
	_carve_corridor_segment(cm, mid2, to, width, height, floor_block, wall_block)

func _carve_corridor_segment(
	cm: ChunkManager, from: Vector3, to: Vector3,
	width: int, height: int, floor_block: int, wall_block: int,
) -> void:
	var steps := int(from.distance_to(to)) + 1
	if steps == 0:
		return
	var dir := (to - from).normalized()

	for step in steps:
		var pos := from + dir * step
		var bx := int(round(pos.x))
		var by := int(round(pos.y))
		var bz := int(round(pos.z))

		for dx in range(-width / 2, width / 2 + 1):
			for dz in range(-width / 2, width / 2 + 1):
				# Floor
				cm.set_block(Vector3i(bx + dx, by, bz + dz), floor_block)
				# Air above floor
				for dy in range(1, height):
					cm.set_block(Vector3i(bx + dx, by + dy, bz + dz), VoxelData.BlockID.AIR)
				# Ceiling
				cm.set_block(Vector3i(bx + dx, by + height, bz + dz), wall_block)

# ── Population ─────────────────────────────────────────────────

func _populate_rooms(cm: ChunkManager) -> void:
	for room in rooms:
		match room.role:
			DungeonRoom.Role.COMBAT:
				room.enemy_count = rng.randi_range(2, 5)
				room.enemy_spawn_points = _get_random_floor_positions(room, room.enemy_count)
			DungeonRoom.Role.BOSS:
				room.enemy_count = 1
				room.is_boss = true
				room.enemy_spawn_points = [_room_center(room)]
			DungeonRoom.Role.LOOT:
				room.loot_positions = _get_random_floor_positions(room, rng.randi_range(3, 6))

func _place_extraction_points(_cm: ChunkManager) -> void:
	# Extraction zones are placed as Area3D nodes during scene setup
	# The beacon blocks are already placed during carving
	pass

# ── Helpers ────────────────────────────────────────────────────

func _get_room_corners(room: DungeonRoom) -> Array[Vector3i]:
	var corners: Array[Vector3i] = []
	var x1 := room.position.x + 1
	var x2 := room.position.x + room.size.x - 2
	var z1 := room.position.z + 1
	var z2 := room.position.z + room.size.z - 2
	corners.append(Vector3i(x1, room.position.y + 1, z1))
	corners.append(Vector3i(x2, room.position.y + 1, z1))
	corners.append(Vector3i(x1, room.position.y + 1, z2))
	corners.append(Vector3i(x2, room.position.y + 1, z2))
	return corners

func _get_random_floor_positions(room: DungeonRoom, count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for i in count:
		positions.append(Vector3(
			rng.randf_range(room.position.x + 2, room.position.x + room.size.x - 2),
			room.position.y + 1.5,
			rng.randf_range(room.position.z + 2, room.position.z + room.size.z - 2),
		))
	return positions

func get_spawn_position() -> Vector3:
	if spawn_room_index >= 0 and spawn_room_index < rooms.size():
		var room := rooms[spawn_room_index]
		return Vector3(
			room.position.x + room.size.x / 2.0,
			room.position.y + 1.5,
			room.position.z + room.size.z / 2.0,
		)
	return Vector3(0, 20, 0)

func get_extraction_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for idx in extraction_room_indices:
		positions.append(_room_center(rooms[idx]))
	return positions
