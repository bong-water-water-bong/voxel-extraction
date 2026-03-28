extends Node3D
class_name ChunkManager

## Manages chunk loading, unloading, meshing, and LOD.
## Chunks are loaded/unloaded around the player in a sphere.
## Meshing runs on a budget per frame to avoid stutters.

@export var render_distance: int = 8  # Chunks
@export var unload_distance: int = 10  # Chunks (beyond this = freed)
@export var mesh_budget_per_frame: int = 2  # Max chunks meshed per frame
@export var generate_budget_per_frame: int = 4  # Max chunks generated per frame
@export var vertical_chunks: int = 3  # How many chunks tall the world is (0 to N-1)

var terrain_generator: TerrainGenerator
var chunks: Dictionary = {}  # Vector3i -> Chunk
var _mesh_queue: Array[Vector3i] = []
var _generate_queue: Array[Vector3i] = []
var _last_player_chunk: Vector3i = Vector3i(99999, 99999, 99999)  # Force initial load
var _total_chunks_loaded: int = 0

signal chunk_loaded(pos: Vector3i)
signal chunk_unloaded(pos: Vector3i)
signal world_ready()

func _ready() -> void:
	terrain_generator = TerrainGenerator.new(GameManager.get("world_seed") if GameManager.get("world_seed") else 0)

func _process(_delta: float) -> void:
	# Process generation queue
	var generated := 0
	while _generate_queue.size() > 0 and generated < generate_budget_per_frame:
		var pos := _generate_queue.pop_front()
		if chunks.has(pos) and not chunks[pos].is_generated:
			terrain_generator.generate_chunk(chunks[pos])
			_mesh_queue.append(pos)
			generated += 1

	# Process mesh queue
	var meshed := 0
	while _mesh_queue.size() > 0 and meshed < mesh_budget_per_frame:
		var pos := _mesh_queue.pop_front()
		if chunks.has(pos) and chunks[pos].is_dirty:
			chunks[pos].build_mesh()
			meshed += 1

func update_around_player(player_pos: Vector3) -> void:
	var player_chunk := Vector3i(
		int(floor(player_pos.x / Chunk.CHUNK_SIZE)),
		0,  # Only horizontal tracking — vertical loads all layers
		int(floor(player_pos.z / Chunk.CHUNK_SIZE)),
	)

	# Skip if player hasn't moved to a new chunk
	if player_chunk == _last_player_chunk:
		return
	_last_player_chunk = player_chunk

	# Load needed chunks
	var needed: Array[Vector3i] = []
	for x in range(player_chunk.x - render_distance, player_chunk.x + render_distance + 1):
		for z in range(player_chunk.z - render_distance, player_chunk.z + render_distance + 1):
			# Circular loading
			var dx := x - player_chunk.x
			var dz := z - player_chunk.z
			if dx * dx + dz * dz > render_distance * render_distance:
				continue
			for y in vertical_chunks:
				var pos := Vector3i(x, y, z)
				needed.append(pos)
				if not chunks.has(pos):
					_load_chunk(pos)

	# Unload distant chunks
	var to_unload: Array[Vector3i] = []
	for pos in chunks:
		var dx := pos.x - player_chunk.x
		var dz := pos.z - player_chunk.z
		if dx * dx + dz * dz > unload_distance * unload_distance:
			to_unload.append(pos)

	for pos in to_unload:
		_unload_chunk(pos)

func _load_chunk(pos: Vector3i) -> void:
	var chunk := Chunk.new(pos)
	chunks[pos] = chunk
	add_child(chunk)

	# Link neighbors
	_link_neighbors(pos)

	# Queue for generation
	_generate_queue.append(pos)
	_total_chunks_loaded += 1
	chunk_loaded.emit(pos)

func _unload_chunk(pos: Vector3i) -> void:
	if not chunks.has(pos):
		return
	var chunk := chunks[pos]

	# Unlink from neighbors
	_unlink_neighbors(pos)

	chunk.queue_free()
	chunks.erase(pos)
	_total_chunks_loaded -= 1
	chunk_unloaded.emit(pos)

func _link_neighbors(pos: Vector3i) -> void:
	var chunk := chunks[pos]
	var dirs := [
		[Vector3i(1, 0, 0), "neighbor_px", "neighbor_nx"],
		[Vector3i(-1, 0, 0), "neighbor_nx", "neighbor_px"],
		[Vector3i(0, 1, 0), "neighbor_py", "neighbor_ny"],
		[Vector3i(0, -1, 0), "neighbor_ny", "neighbor_py"],
		[Vector3i(0, 0, 1), "neighbor_pz", "neighbor_nz"],
		[Vector3i(0, 0, -1), "neighbor_nz", "neighbor_pz"],
	]
	for dir_info in dirs:
		var neighbor_pos: Vector3i = pos + dir_info[0]
		var our_prop: String = dir_info[1]
		var their_prop: String = dir_info[2]
		if chunks.has(neighbor_pos):
			var neighbor: Chunk = chunks[neighbor_pos]
			chunk.set(our_prop, neighbor)
			neighbor.set(their_prop, chunk)
			# Re-mesh neighbor since border data changed
			if neighbor.is_generated:
				neighbor.is_dirty = true
				if not _mesh_queue.has(neighbor_pos):
					_mesh_queue.append(neighbor_pos)

func _unlink_neighbors(pos: Vector3i) -> void:
	var dirs := [
		[Vector3i(1, 0, 0), "neighbor_nx"],
		[Vector3i(-1, 0, 0), "neighbor_px"],
		[Vector3i(0, 1, 0), "neighbor_ny"],
		[Vector3i(0, -1, 0), "neighbor_py"],
		[Vector3i(0, 0, 1), "neighbor_nz"],
		[Vector3i(0, 0, -1), "neighbor_pz"],
	]
	for dir_info in dirs:
		var neighbor_pos: Vector3i = pos + dir_info[0]
		var their_prop: String = dir_info[1]
		if chunks.has(neighbor_pos):
			chunks[neighbor_pos].set(their_prop, null)

# ── World Interaction ──────────────────────────────────────────

func get_block(world_pos: Vector3i) -> int:
	var chunk_pos := Vector3i(
		int(floor(float(world_pos.x) / Chunk.CHUNK_SIZE)),
		int(floor(float(world_pos.y) / Chunk.CHUNK_SIZE)),
		int(floor(float(world_pos.z) / Chunk.CHUNK_SIZE)),
	)
	if chunks.has(chunk_pos):
		var local := world_pos - chunk_pos * Chunk.CHUNK_SIZE
		return chunks[chunk_pos].get_block(local.x, local.y, local.z)
	return VoxelData.BlockID.AIR

func set_block(world_pos: Vector3i, block_id: int) -> void:
	var chunk_pos := Vector3i(
		int(floor(float(world_pos.x) / Chunk.CHUNK_SIZE)),
		int(floor(float(world_pos.y) / Chunk.CHUNK_SIZE)),
		int(floor(float(world_pos.z) / Chunk.CHUNK_SIZE)),
	)
	if chunks.has(chunk_pos):
		var local := world_pos - chunk_pos * Chunk.CHUNK_SIZE
		chunks[chunk_pos].set_block(local.x, local.y, local.z, block_id)
		if not _mesh_queue.has(chunk_pos):
			_mesh_queue.append(chunk_pos)

func destroy_block(world_pos: Vector3i) -> int:
	var chunk_pos := Vector3i(
		int(floor(float(world_pos.x) / Chunk.CHUNK_SIZE)),
		int(floor(float(world_pos.y) / Chunk.CHUNK_SIZE)),
		int(floor(float(world_pos.z) / Chunk.CHUNK_SIZE)),
	)
	if chunks.has(chunk_pos):
		var local := world_pos - chunk_pos * Chunk.CHUNK_SIZE
		var block := chunks[chunk_pos].destroy_block(local.x, local.y, local.z)
		_queue_remesh(chunk_pos)
		return block
	return VoxelData.BlockID.AIR

func explosion(world_center: Vector3i, radius: int) -> Array[Dictionary]:
	"""Destroy blocks in a sphere across chunk boundaries."""
	var all_destroyed: Array[Dictionary] = []
	var affected_chunks: Dictionary = {}

	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				if x * x + y * y + z * z <= radius * radius:
					var wp := world_center + Vector3i(x, y, z)
					var block := destroy_block(wp)
					if block != VoxelData.BlockID.AIR:
						all_destroyed.append({
							"block_id": block,
							"position": Vector3(wp),
						})

	return all_destroyed

func _queue_remesh(chunk_pos: Vector3i) -> void:
	if not _mesh_queue.has(chunk_pos):
		_mesh_queue.append(chunk_pos)
	# Also remesh neighbors that share a border
	for offset in [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
		var neighbor_pos := chunk_pos + offset
		if chunks.has(neighbor_pos) and not _mesh_queue.has(neighbor_pos):
			chunks[neighbor_pos].is_dirty = true
			_mesh_queue.append(neighbor_pos)

func get_spawn_position() -> Vector3:
	"""Find a safe spawn point on the terrain surface."""
	# Try center of world
	for attempt in 10:
		var wx := randi_range(-16, 16)
		var wz := randi_range(-16, 16)
		# Scan down from top
		for wy in range(Chunk.CHUNK_SIZE * vertical_chunks - 1, 0, -1):
			var block := get_block(Vector3i(wx, wy, wz))
			var above := get_block(Vector3i(wx, wy + 1, wz))
			var above2 := get_block(Vector3i(wx, wy + 2, wz))
			if VoxelData.is_solid(block) and above == VoxelData.BlockID.AIR and above2 == VoxelData.BlockID.AIR:
				return Vector3(wx + 0.5, wy + 1.5, wz + 0.5)
	# Fallback
	return Vector3(0, 50, 0)

func get_stats() -> Dictionary:
	return {
		"chunks_loaded": _total_chunks_loaded,
		"mesh_queue": _mesh_queue.size(),
		"generate_queue": _generate_queue.size(),
	}
