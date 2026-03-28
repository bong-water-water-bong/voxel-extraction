extends Node
class_name PackLoader

## Loads dungeon packs from the packs/ directory.
## Drop a folder with pack.json into packs/ and it's playable.
## This is the DLC / mod system.

const PACKS_DIR := "res://packs/"
const USER_PACKS_DIR := "user://packs/"  # Community / downloaded packs

var loaded_packs: Dictionary = {}  # pack_id -> DungeonPack

func _ready() -> void:
	_scan_packs(PACKS_DIR)
	_scan_packs(USER_PACKS_DIR)

func _scan_packs(base_path: String) -> void:
	var dir := DirAccess.open(base_path)
	if not dir:
		return

	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var pack_file := base_path + folder + "/pack.json"
			if FileAccess.file_exists(pack_file):
				_load_pack(pack_file, folder)
		folder = dir.get_next()

func _load_pack(path: String, folder_name: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("Failed to open pack: %s" % path)
		return

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_warning("Failed to parse pack JSON: %s" % path)
		return

	var data: Dictionary = json.data
	var pack := DungeonPack.new()

	# Core info
	pack.pack_id = data.get("pack_id", folder_name)
	pack.pack_name = data.get("pack_name", folder_name)
	pack.description = data.get("description", "")
	pack.author = data.get("author", "Unknown")
	pack.version = data.get("version", "1.0.0")

	# Theme
	var theme: Dictionary = data.get("theme", {})
	pack.wall_block = _block_name_to_id(theme.get("wall_block", "cobblestone"))
	pack.floor_block = _block_name_to_id(theme.get("floor_block", "stone"))
	pack.ceiling_block = _block_name_to_id(theme.get("ceiling_block", "mossy_stone"))
	pack.accent_block = _block_name_to_id(theme.get("accent_block", "iron_ore"))
	pack.light_block = _block_name_to_id(theme.get("light_block", "lantern"))

	var amb: Array = theme.get("ambient_color", [0.05, 0.04, 0.06])
	pack.ambient_color = Color(amb[0], amb[1], amb[2])
	var fog: Array = theme.get("fog_color", [0.08, 0.06, 0.1])
	pack.fog_color = Color(fog[0], fog[1], fog[2])
	pack.fog_density = theme.get("fog_density", 0.03)

	# Generation
	var gen: Dictionary = data.get("generation", {})
	pack.min_rooms = gen.get("min_rooms", 8)
	pack.max_rooms = gen.get("max_rooms", 20)

	# Difficulty
	var diff: Dictionary = data.get("difficulty", {})
	pack.base_enemy_count = diff.get("base_enemy_count", 3)
	pack.enemy_scaling = diff.get("enemy_scaling", 1.0)
	pack.boss_health_multiplier = diff.get("boss_health_multiplier", 5.0)
	pack.loot_quality_bonus = diff.get("loot_quality_bonus", 0)

	# Raid
	var raid: Dictionary = data.get("raid", {})
	pack.raid_duration = raid.get("duration_seconds", 900.0)
	pack.extraction_time = raid.get("extraction_time_seconds", 15.0)
	pack.enemy_surge_on_extract = raid.get("enemy_surge_on_extract", true)

	# Enemies
	var enemies: Dictionary = data.get("enemies", {})
	pack.enemy_types = enemies.get("types", ["skeleton"])
	pack.boss_type = enemies.get("boss", "warden")

	# Loot
	var loot: Dictionary = data.get("loot", {})
	pack.bonus_loot = loot.get("bonus_items", [])

	# Audio
	var audio: Dictionary = data.get("audio", {})
	pack.ambient_track = audio.get("ambient", "")
	pack.combat_track = audio.get("combat", "")
	pack.boss_track = audio.get("boss", "")
	pack.extraction_track = audio.get("extraction", "")

	loaded_packs[pack.pack_id] = pack
	print("[PackLoader] Loaded: %s v%s by %s" % [pack.pack_name, pack.version, pack.author])

func get_pack(pack_id: String) -> DungeonPack:
	return loaded_packs.get(pack_id)

func get_all_packs() -> Array[DungeonPack]:
	var packs: Array[DungeonPack] = []
	for pack in loaded_packs.values():
		packs.append(pack)
	return packs

func get_pack_list() -> Array[Dictionary]:
	"""For UI — list all available packs with their info."""
	var list: Array[Dictionary] = []
	for pack in loaded_packs.values():
		list.append(pack.get_info())
	return list

func _block_name_to_id(block_name: String) -> int:
	# Map string names to BlockID enum
	match block_name.to_lower():
		"stone": return VoxelData.BlockID.STONE
		"dirt": return VoxelData.BlockID.DIRT
		"grass": return VoxelData.BlockID.GRASS
		"sand": return VoxelData.BlockID.SAND
		"gravel": return VoxelData.BlockID.GRAVEL
		"cobblestone": return VoxelData.BlockID.COBBLESTONE
		"mossy_stone": return VoxelData.BlockID.MOSSY_STONE
		"iron_ore": return VoxelData.BlockID.IRON_ORE
		"crystal_ore": return VoxelData.BlockID.CRYSTAL_ORE
		"void_stone": return VoxelData.BlockID.VOID_STONE
		"metal_plate": return VoxelData.BlockID.METAL_PLATE
		"rust_metal": return VoxelData.BlockID.RUST_METAL
		"lantern": return VoxelData.BlockID.LANTERN
		"bone": return VoxelData.BlockID.BONE
		"ash": return VoxelData.BlockID.ASH
		"fungus": return VoxelData.BlockID.FUNGUS
		"moss": return VoxelData.BlockID.MOSS
		"snow": return VoxelData.BlockID.SNOW
		"ice": return VoxelData.BlockID.ICE
		_: return VoxelData.BlockID.STONE
