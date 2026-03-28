extends RefCounted
class_name VoxelData

## Voxel type definitions and block registry.
## Every block in the world is an ID. This maps IDs to properties.

enum BlockID {
	AIR = 0,
	STONE = 1,
	DIRT = 2,
	GRASS = 3,
	SAND = 4,
	GRAVEL = 5,
	CLAY = 6,
	SNOW = 7,
	ICE = 8,
	WATER = 9,
	LAVA = 10,
	WOOD_LOG = 11,
	WOOD_PLANK = 12,
	LEAVES = 13,
	COBBLESTONE = 14,
	MOSSY_STONE = 15,
	IRON_ORE = 16,
	COPPER_ORE = 17,
	CRYSTAL_ORE = 18,
	VOID_STONE = 19,
	BEDROCK = 20,
	METAL_PLATE = 21,
	RUST_METAL = 22,
	GLASS = 23,
	LANTERN = 24,
	EXTRACTION_BEACON = 25,
	BONE = 26,
	ASH = 27,
	FUNGUS = 28,
	MOSS = 29,
}

## Block properties — each block type has physical and visual traits
const BLOCK_PROPERTIES: Dictionary = {
	BlockID.AIR:               {"name": "Air",               "solid": false, "transparent": true,  "emissive": false, "hardness": 0,   "color": Color(0, 0, 0, 0)},
	BlockID.STONE:             {"name": "Stone",             "solid": true,  "transparent": false, "emissive": false, "hardness": 4,   "color": Color(0.45, 0.43, 0.40)},
	BlockID.DIRT:              {"name": "Dirt",              "solid": true,  "transparent": false, "emissive": false, "hardness": 1,   "color": Color(0.40, 0.28, 0.18)},
	BlockID.GRASS:             {"name": "Grass",             "solid": true,  "transparent": false, "emissive": false, "hardness": 1,   "color": Color(0.30, 0.52, 0.22)},
	BlockID.SAND:              {"name": "Sand",              "solid": true,  "transparent": false, "emissive": false, "hardness": 1,   "color": Color(0.76, 0.70, 0.50)},
	BlockID.GRAVEL:            {"name": "Gravel",            "solid": true,  "transparent": false, "emissive": false, "hardness": 2,   "color": Color(0.50, 0.48, 0.45)},
	BlockID.CLAY:              {"name": "Clay",              "solid": true,  "transparent": false, "emissive": false, "hardness": 1,   "color": Color(0.60, 0.55, 0.50)},
	BlockID.SNOW:              {"name": "Snow",              "solid": true,  "transparent": false, "emissive": false, "hardness": 1,   "color": Color(0.90, 0.92, 0.95)},
	BlockID.ICE:               {"name": "Ice",               "solid": true,  "transparent": true,  "emissive": false, "hardness": 2,   "color": Color(0.70, 0.85, 0.95)},
	BlockID.WATER:             {"name": "Water",             "solid": false, "transparent": true,  "emissive": false, "hardness": 0,   "color": Color(0.15, 0.30, 0.60, 0.6)},
	BlockID.LAVA:              {"name": "Lava",              "solid": false, "transparent": true,  "emissive": true,  "hardness": 0,   "color": Color(0.90, 0.30, 0.05)},
	BlockID.WOOD_LOG:          {"name": "Wood Log",          "solid": true,  "transparent": false, "emissive": false, "hardness": 2,   "color": Color(0.40, 0.28, 0.15)},
	BlockID.WOOD_PLANK:        {"name": "Wood Plank",        "solid": true,  "transparent": false, "emissive": false, "hardness": 2,   "color": Color(0.55, 0.40, 0.22)},
	BlockID.LEAVES:            {"name": "Leaves",            "solid": true,  "transparent": true,  "emissive": false, "hardness": 0,   "color": Color(0.20, 0.45, 0.15)},
	BlockID.COBBLESTONE:       {"name": "Cobblestone",       "solid": true,  "transparent": false, "emissive": false, "hardness": 5,   "color": Color(0.40, 0.38, 0.35)},
	BlockID.MOSSY_STONE:       {"name": "Mossy Stone",       "solid": true,  "transparent": false, "emissive": false, "hardness": 4,   "color": Color(0.35, 0.42, 0.30)},
	BlockID.IRON_ORE:          {"name": "Iron Ore",          "solid": true,  "transparent": false, "emissive": false, "hardness": 6,   "color": Color(0.50, 0.40, 0.35)},
	BlockID.COPPER_ORE:        {"name": "Copper Ore",        "solid": true,  "transparent": false, "emissive": false, "hardness": 5,   "color": Color(0.55, 0.42, 0.28)},
	BlockID.CRYSTAL_ORE:       {"name": "Crystal Ore",       "solid": true,  "transparent": true,  "emissive": true,  "hardness": 7,   "color": Color(0.50, 0.30, 0.80)},
	BlockID.VOID_STONE:        {"name": "Void Stone",        "solid": true,  "transparent": false, "emissive": true,  "hardness": 10,  "color": Color(0.10, 0.05, 0.15)},
	BlockID.BEDROCK:           {"name": "Bedrock",           "solid": true,  "transparent": false, "emissive": false, "hardness": 255, "color": Color(0.15, 0.14, 0.13)},
	BlockID.METAL_PLATE:       {"name": "Metal Plate",       "solid": true,  "transparent": false, "emissive": false, "hardness": 8,   "color": Color(0.60, 0.62, 0.65)},
	BlockID.RUST_METAL:        {"name": "Rust Metal",        "solid": true,  "transparent": false, "emissive": false, "hardness": 6,   "color": Color(0.50, 0.30, 0.18)},
	BlockID.GLASS:             {"name": "Glass",             "solid": true,  "transparent": true,  "emissive": false, "hardness": 1,   "color": Color(0.70, 0.80, 0.90, 0.3)},
	BlockID.LANTERN:           {"name": "Lantern",           "solid": true,  "transparent": true,  "emissive": true,  "hardness": 2,   "color": Color(1.00, 0.85, 0.50)},
	BlockID.EXTRACTION_BEACON: {"name": "Extraction Beacon", "solid": true,  "transparent": true,  "emissive": true,  "hardness": 255, "color": Color(0.00, 0.80, 1.00)},
	BlockID.BONE:              {"name": "Bone",              "solid": true,  "transparent": false, "emissive": false, "hardness": 3,   "color": Color(0.85, 0.80, 0.70)},
	BlockID.ASH:               {"name": "Ash",               "solid": true,  "transparent": false, "emissive": false, "hardness": 1,   "color": Color(0.30, 0.28, 0.27)},
	BlockID.FUNGUS:            {"name": "Fungus",            "solid": true,  "transparent": true,  "emissive": true,  "hardness": 1,   "color": Color(0.30, 0.65, 0.40)},
	BlockID.MOSS:              {"name": "Moss",              "solid": true,  "transparent": false, "emissive": false, "hardness": 1,   "color": Color(0.25, 0.50, 0.20)},
}

static func is_solid(block_id: int) -> bool:
	if BLOCK_PROPERTIES.has(block_id):
		return BLOCK_PROPERTIES[block_id]["solid"]
	return false

static func is_transparent(block_id: int) -> bool:
	if BLOCK_PROPERTIES.has(block_id):
		return BLOCK_PROPERTIES[block_id]["transparent"]
	return true

static func is_emissive(block_id: int) -> bool:
	if BLOCK_PROPERTIES.has(block_id):
		return BLOCK_PROPERTIES[block_id]["emissive"]
	return false

static func get_color(block_id: int) -> Color:
	if BLOCK_PROPERTIES.has(block_id):
		return BLOCK_PROPERTIES[block_id]["color"]
	return Color.MAGENTA  # Missing block = magenta (obvious error)

static func get_hardness(block_id: int) -> int:
	if BLOCK_PROPERTIES.has(block_id):
		return BLOCK_PROPERTIES[block_id]["hardness"]
	return 0

static func get_name(block_id: int) -> String:
	if BLOCK_PROPERTIES.has(block_id):
		return BLOCK_PROPERTIES[block_id]["name"]
	return "Unknown"
