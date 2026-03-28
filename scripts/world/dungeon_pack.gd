extends Resource
class_name DungeonPack

## A dungeon pack — defines the theme, blocks, enemies, loot, and rules
## for a specific dungeon type. Drop-in content packs.
##
## The base game ships with "The Undercroft".
## Additional packs are DLC / community-created.

@export var pack_id: String = "undercroft"
@export var pack_name: String = "The Undercroft"
@export var description: String = "Ancient stone halls beneath the surface. What sleeps here has been waiting."
@export var author: String = "halo-ai studios"
@export var version: String = "1.0.0"

# Visual theme
@export var wall_block: int = VoxelData.BlockID.COBBLESTONE
@export var floor_block: int = VoxelData.BlockID.STONE
@export var ceiling_block: int = VoxelData.BlockID.MOSSY_STONE
@export var accent_block: int = VoxelData.BlockID.IRON_ORE
@export var light_block: int = VoxelData.BlockID.LANTERN
@export var ambient_color: Color = Color(0.05, 0.04, 0.06)
@export var fog_color: Color = Color(0.08, 0.06, 0.1)
@export var fog_density: float = 0.03

# Generation rules
@export var min_rooms: int = 8
@export var max_rooms: int = 20
@export var min_room_size: Vector3i = Vector3i(5, 4, 5)
@export var max_room_size: Vector3i = Vector3i(15, 8, 15)
@export var depth_range: Vector2i = Vector2i(2, 25)  # Y range for room placement
@export var corridor_width: int = 3
@export var extraction_count: Vector2i = Vector2i(2, 3)

# Difficulty
@export var base_enemy_count: int = 3
@export var enemy_scaling: float = 1.0  # Multiplier per difficulty level
@export var boss_health_multiplier: float = 5.0
@export var loot_quality_bonus: int = 0  # Added to difficulty for loot rolls

# Raid rules
@export var raid_duration: float = 900.0  # 15 minutes
@export var extraction_time: float = 15.0  # Seconds to extract
@export var enemy_surge_on_extract: bool = true

# Enemy types available in this pack
@export var enemy_types: Array[String] = ["skeleton", "crawler", "guardian"]
@export var boss_type: String = "warden"

# Loot table overrides (pack-specific items)
@export var bonus_loot: Array[Dictionary] = []

# Music / audio
@export var ambient_track: String = "undercroft_ambient"
@export var combat_track: String = "undercroft_combat"
@export var boss_track: String = "undercroft_boss"
@export var extraction_track: String = "extraction_tension"

func get_info() -> Dictionary:
	return {
		"id": pack_id,
		"name": pack_name,
		"description": description,
		"author": author,
		"version": version,
		"rooms": "%d-%d" % [min_rooms, max_rooms],
		"duration": "%d min" % [int(raid_duration / 60)],
		"enemies": enemy_types,
		"boss": boss_type,
	}
