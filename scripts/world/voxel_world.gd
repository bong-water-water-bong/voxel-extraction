extends Node3D
class_name VoxelWorld

## Procedural voxel world generation.
## Handles chunk loading, terrain generation, and destruction.
## Will integrate with Zylann's godot_voxel module for production.

@export var chunk_size: int = 16
@export var world_height: int = 64
@export var render_distance: int = 8
@export var seed_value: int = 0

var noise: FastNoiseLite
var loaded_chunks: Dictionary = {}  # Vector2i -> chunk node
var destruction_map: Dictionary = {}  # Vector3i -> bool (destroyed voxels)

signal chunk_loaded(chunk_pos: Vector2i)
signal chunk_unloaded(chunk_pos: Vector2i)
signal voxel_destroyed(world_pos: Vector3i)

func _ready() -> void:
	if seed_value == 0:
		seed_value = randi()
	noise = FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 4

func generate_around(center: Vector3) -> void:
	var chunk_pos := Vector2i(
		int(center.x) / chunk_size,
		int(center.z) / chunk_size
	)
	# Load chunks within render distance
	for x in range(chunk_pos.x - render_distance, chunk_pos.x + render_distance + 1):
		for z in range(chunk_pos.y - render_distance, chunk_pos.y + render_distance + 1):
			var pos := Vector2i(x, z)
			if not loaded_chunks.has(pos):
				_load_chunk(pos)

	# Unload distant chunks
	var to_unload: Array[Vector2i] = []
	for pos in loaded_chunks:
		if pos.distance_to(chunk_pos) > render_distance + 2:
			to_unload.append(pos)
	for pos in to_unload:
		_unload_chunk(pos)

func _load_chunk(pos: Vector2i) -> void:
	var chunk := _generate_chunk(pos)
	loaded_chunks[pos] = chunk
	add_child(chunk)
	chunk_loaded.emit(pos)

func _unload_chunk(pos: Vector2i) -> void:
	if loaded_chunks.has(pos):
		loaded_chunks[pos].queue_free()
		loaded_chunks.erase(pos)
		chunk_unloaded.emit(pos)

func _generate_chunk(pos: Vector2i) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d_%d" % [pos.x, pos.y]
	chunk.position = Vector3(pos.x * chunk_size, 0, pos.y * chunk_size)

	# Placeholder: generate CSG boxes for each column
	# Will be replaced with proper voxel mesh generation
	for x in chunk_size:
		for z in chunk_size:
			var world_x := pos.x * chunk_size + x
			var world_z := pos.y * chunk_size + z
			var height := _get_terrain_height(world_x, world_z)
			_create_column(chunk, x, z, height)

	return chunk

func _get_terrain_height(world_x: int, world_z: int) -> int:
	var n := noise.get_noise_2d(float(world_x), float(world_z))
	return int((n + 1.0) * 0.5 * world_height * 0.4) + 4

func _create_column(chunk: Node3D, x: int, z: int, height: int) -> void:
	# Simple column — will be replaced with proper meshing
	var box := CSGBox3D.new()
	box.size = Vector3(1, height, 1)
	box.position = Vector3(x + 0.5, height * 0.5, z + 0.5)
	# Color based on height
	var mat := StandardMaterial3D.new()
	if height < 8:
		mat.albedo_color = Color(0.2, 0.35, 0.5)  # Water-ish
	elif height < 15:
		mat.albedo_color = Color(0.3, 0.55, 0.2)  # Grass
	elif height < 22:
		mat.albedo_color = Color(0.5, 0.4, 0.3)  # Dirt/stone
	else:
		mat.albedo_color = Color(0.7, 0.7, 0.75)  # Snow/peak
	box.material = mat
	chunk.add_child(box)

func destroy_voxel(world_pos: Vector3i) -> void:
	destruction_map[world_pos] = true
	voxel_destroyed.emit(world_pos)
	# TODO: update chunk mesh to reflect destroyed voxel
	# TODO: particle effect, sound, physics debris

func is_voxel_destroyed(world_pos: Vector3i) -> bool:
	return destruction_map.has(world_pos)
