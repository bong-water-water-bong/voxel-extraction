extends RefCounted
class_name TerrainGenerator

## Procedural terrain generation for extraction raids.
## Generates biomes, caves, structures, ore veins, and POIs.
## Each raid map is seeded — same seed = same layout.

var world_seed: int
var height_noise: FastNoiseLite
var cave_noise: FastNoiseLite
var biome_noise: FastNoiseLite
var ore_noise: FastNoiseLite
var detail_noise: FastNoiseLite

enum Biome {
	FOREST,
	WASTELAND,
	CAVES,
	RUINS,
	FROZEN,
	FUNGAL,
}

const BIOME_CONFIGS: Dictionary = {
	Biome.FOREST: {
		"base_height": 20, "height_amp": 15, "tree_density": 0.02,
		"surface": VoxelData.BlockID.GRASS, "subsurface": VoxelData.BlockID.DIRT,
	},
	Biome.WASTELAND: {
		"base_height": 14, "height_amp": 8, "tree_density": 0.0,
		"surface": VoxelData.BlockID.ASH, "subsurface": VoxelData.BlockID.GRAVEL,
	},
	Biome.CAVES: {
		"base_height": 30, "height_amp": 10, "tree_density": 0.0,
		"surface": VoxelData.BlockID.STONE, "subsurface": VoxelData.BlockID.STONE,
	},
	Biome.RUINS: {
		"base_height": 16, "height_amp": 6, "tree_density": 0.005,
		"surface": VoxelData.BlockID.COBBLESTONE, "subsurface": VoxelData.BlockID.DIRT,
	},
	Biome.FROZEN: {
		"base_height": 22, "height_amp": 12, "tree_density": 0.005,
		"surface": VoxelData.BlockID.SNOW, "subsurface": VoxelData.BlockID.DIRT,
	},
	Biome.FUNGAL: {
		"base_height": 18, "height_amp": 20, "tree_density": 0.0,
		"surface": VoxelData.BlockID.MOSS, "subsurface": VoxelData.BlockID.CLAY,
	},
}

func _init(seed_val: int = 0) -> void:
	world_seed = seed_val if seed_val != 0 else randi()

	height_noise = FastNoiseLite.new()
	height_noise.seed = world_seed
	height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	height_noise.frequency = 0.008
	height_noise.fractal_octaves = 5
	height_noise.fractal_lacunarity = 2.0
	height_noise.fractal_gain = 0.5

	cave_noise = FastNoiseLite.new()
	cave_noise.seed = world_seed + 1
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cave_noise.frequency = 0.04
	cave_noise.fractal_octaves = 3

	biome_noise = FastNoiseLite.new()
	biome_noise.seed = world_seed + 2
	biome_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	biome_noise.frequency = 0.003
	biome_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	biome_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE

	ore_noise = FastNoiseLite.new()
	ore_noise.seed = world_seed + 3
	ore_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ore_noise.frequency = 0.08

	detail_noise = FastNoiseLite.new()
	detail_noise.seed = world_seed + 4
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = 0.05
	detail_noise.fractal_octaves = 2

func generate_chunk(chunk: Chunk) -> void:
	var cx := chunk.chunk_position.x * Chunk.CHUNK_SIZE
	var cy := chunk.chunk_position.y * Chunk.CHUNK_SIZE
	var cz := chunk.chunk_position.z * Chunk.CHUNK_SIZE

	for x in Chunk.CHUNK_SIZE:
		for z in Chunk.CHUNK_SIZE:
			var wx := cx + x
			var wz := cz + z

			var biome := _get_biome(wx, wz)
			var config: Dictionary = BIOME_CONFIGS[biome]
			var terrain_height := _get_height(wx, wz, config)

			for y in Chunk.CHUNK_SIZE:
				var wy := cy + y
				var block := _determine_block(wx, wy, wz, terrain_height, biome, config)
				chunk.set_block(x, y, z, block)

	# Second pass: structures and decorations
	_generate_structures(chunk, cx, cy, cz)
	_generate_ores(chunk, cx, cy, cz)

	chunk.is_generated = true
	chunk.is_dirty = true

func _get_biome(wx: int, wz: int) -> Biome:
	var n := biome_noise.get_noise_2d(float(wx), float(wz))
	# Map noise value to biome
	if n < -0.5:
		return Biome.FROZEN
	elif n < -0.2:
		return Biome.FOREST
	elif n < 0.1:
		return Biome.RUINS
	elif n < 0.3:
		return Biome.WASTELAND
	elif n < 0.6:
		return Biome.CAVES
	else:
		return Biome.FUNGAL

func _get_height(wx: int, wz: int, config: Dictionary) -> int:
	var n := height_noise.get_noise_2d(float(wx), float(wz))
	var detail := detail_noise.get_noise_2d(float(wx), float(wz)) * 3.0
	var base: int = config["base_height"]
	var amp: int = config["height_amp"]
	return int(base + (n + 1.0) * 0.5 * amp + detail)

func _determine_block(
	wx: int, wy: int, wz: int,
	terrain_height: int, biome: Biome, config: Dictionary,
) -> int:
	# Bedrock floor
	if wy <= 0:
		return VoxelData.BlockID.BEDROCK

	# Above terrain = air
	if wy > terrain_height:
		# Water level at y=12
		if wy <= 12 and biome != Biome.FROZEN:
			return VoxelData.BlockID.WATER
		elif wy <= 12 and biome == Biome.FROZEN:
			return VoxelData.BlockID.ICE
		return VoxelData.BlockID.AIR

	# Cave carving
	var cave_val := cave_noise.get_noise_3d(float(wx), float(wy), float(wz))
	var cave_threshold := 0.55
	# Bigger caves underground
	if wy < terrain_height - 10:
		cave_threshold = 0.45
	if abs(cave_val) < (1.0 - cave_threshold):
		# Lava at bottom of deep caves
		if wy < 5:
			return VoxelData.BlockID.LAVA
		return VoxelData.BlockID.AIR

	# Surface layer
	if wy == terrain_height:
		return config["surface"]

	# Subsurface (3 blocks deep)
	if wy > terrain_height - 4:
		return config["subsurface"]

	# Deep stone
	if wy < terrain_height - 4:
		# Mossy stone near caves in forest/fungal
		if biome in [Biome.FOREST, Biome.FUNGAL]:
			if abs(cave_val) < 0.6:
				return VoxelData.BlockID.MOSSY_STONE
		return VoxelData.BlockID.STONE

	return VoxelData.BlockID.STONE

func _generate_structures(chunk: Chunk, cx: int, cy: int, cz: int) -> void:
	for x in Chunk.CHUNK_SIZE:
		for z in Chunk.CHUNK_SIZE:
			var wx := cx + x
			var wz := cz + z
			var biome := _get_biome(wx, wz)
			var config: Dictionary = BIOME_CONFIGS[biome]

			# Trees
			var tree_density: float = config["tree_density"]
			if tree_density > 0.0:
				# Use hash for deterministic placement
				var h := _hash2d(wx, wz)
				if h < tree_density:
					var terrain_height := _get_height(wx, wz, config)
					var tree_base_y := terrain_height + 1 - cy
					if tree_base_y >= 0 and tree_base_y < Chunk.CHUNK_SIZE - 8:
						_place_tree(chunk, x, tree_base_y, z, biome)

			# Fungal mushroom pillars
			if biome == Biome.FUNGAL:
				var h := _hash2d(wx + 7777, wz + 7777)
				if h < 0.008:
					var terrain_height := _get_height(wx, wz, config)
					var base_y := terrain_height + 1 - cy
					if base_y >= 0 and base_y < Chunk.CHUNK_SIZE - 12:
						_place_mushroom(chunk, x, base_y, z)

func _place_tree(chunk: Chunk, x: int, y: int, z: int, biome: Biome) -> void:
	var trunk_height := 4 + (randi() % 3)

	# Trunk
	for ty in trunk_height:
		if y + ty < Chunk.CHUNK_SIZE:
			chunk.set_block(x, y + ty, z, VoxelData.BlockID.WOOD_LOG)

	# Canopy (sphere of leaves)
	var canopy_radius := 2
	var canopy_y := y + trunk_height
	for lx in range(-canopy_radius, canopy_radius + 1):
		for ly in range(-1, canopy_radius + 1):
			for lz in range(-canopy_radius, canopy_radius + 1):
				if lx * lx + ly * ly + lz * lz <= canopy_radius * canopy_radius + 1:
					var bx := x + lx
					var by := canopy_y + ly
					var bz := z + lz
					if bx >= 0 and bx < Chunk.CHUNK_SIZE and by >= 0 and by < Chunk.CHUNK_SIZE and bz >= 0 and bz < Chunk.CHUNK_SIZE:
						if chunk.get_block(bx, by, bz) == VoxelData.BlockID.AIR:
							var leaf_type := VoxelData.BlockID.LEAVES
							if biome == Biome.FROZEN:
								leaf_type = VoxelData.BlockID.SNOW
							chunk.set_block(bx, by, bz, leaf_type)

func _place_mushroom(chunk: Chunk, x: int, y: int, z: int) -> void:
	var stem_height := 6 + (randi() % 5)

	# Stem
	for sy in stem_height:
		if y + sy < Chunk.CHUNK_SIZE:
			chunk.set_block(x, y + sy, z, VoxelData.BlockID.WOOD_LOG)

	# Cap (flat disc)
	var cap_y := y + stem_height
	var cap_radius := 3
	for cx_off in range(-cap_radius, cap_radius + 1):
		for cz_off in range(-cap_radius, cap_radius + 1):
			if cx_off * cx_off + cz_off * cz_off <= cap_radius * cap_radius:
				var bx := x + cx_off
				var bz := z + cz_off
				if bx >= 0 and bx < Chunk.CHUNK_SIZE and bz >= 0 and bz < Chunk.CHUNK_SIZE:
					if cap_y < Chunk.CHUNK_SIZE:
						chunk.set_block(bx, cap_y, bz, VoxelData.BlockID.FUNGUS)
					if cap_y + 1 < Chunk.CHUNK_SIZE and abs(cx_off) < cap_radius - 1 and abs(cz_off) < cap_radius - 1:
						chunk.set_block(bx, cap_y + 1, bz, VoxelData.BlockID.FUNGUS)

func _generate_ores(chunk: Chunk, cx: int, cy: int, cz: int) -> void:
	for x in Chunk.CHUNK_SIZE:
		for y in Chunk.CHUNK_SIZE:
			for z in Chunk.CHUNK_SIZE:
				var wx := cx + x
				var wy := cy + y
				var wz := cz + z

				if chunk.get_block(x, y, z) != VoxelData.BlockID.STONE:
					continue

				var ore_val := ore_noise.get_noise_3d(float(wx), float(wy), float(wz))

				# Iron — common, any depth
				if ore_val > 0.7 and wy < 40:
					chunk.set_block(x, y, z, VoxelData.BlockID.IRON_ORE)
				# Copper — mid-depth
				elif ore_val > 0.75 and wy < 30:
					chunk.set_block(x, y, z, VoxelData.BlockID.COPPER_ORE)
				# Crystal — deep, rare
				elif ore_val > 0.82 and wy < 20:
					chunk.set_block(x, y, z, VoxelData.BlockID.CRYSTAL_ORE)
				# Void stone — very deep, very rare
				elif ore_val > 0.9 and wy < 10:
					chunk.set_block(x, y, z, VoxelData.BlockID.VOID_STONE)

func _hash2d(x: int, z: int) -> float:
	var n := sin(float(x) * 127.1 + float(z) * 311.7) * 43758.5453
	return n - floor(n)
