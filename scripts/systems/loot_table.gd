extends Node

## Loot generation and drop system.
## Items have rarity, weight, and value. Higher difficulty = better loot.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_COLORS := {
	Rarity.COMMON: Color(0.7, 0.7, 0.7),
	Rarity.UNCOMMON: Color(0.2, 0.8, 0.2),
	Rarity.RARE: Color(0.2, 0.4, 1.0),
	Rarity.EPIC: Color(0.6, 0.2, 0.9),
	Rarity.LEGENDARY: Color(1.0, 0.8, 0.0),
}

const RARITY_WEIGHTS := {
	Rarity.COMMON: 50,
	Rarity.UNCOMMON: 30,
	Rarity.RARE: 13,
	Rarity.EPIC: 5,
	Rarity.LEGENDARY: 2,
}

# Base item definitions — will be loaded from JSON later
var item_database: Array[Dictionary] = [
	{"id": "scrap_metal", "name": "Scrap Metal", "rarity": Rarity.COMMON, "weight": 1.0, "value": 10, "category": "material"},
	{"id": "circuit_board", "name": "Circuit Board", "rarity": Rarity.UNCOMMON, "weight": 0.5, "value": 35, "category": "material"},
	{"id": "crystal_shard", "name": "Crystal Shard", "rarity": Rarity.RARE, "weight": 0.3, "value": 120, "category": "material"},
	{"id": "void_core", "name": "Void Core", "rarity": Rarity.EPIC, "weight": 2.0, "value": 500, "category": "artifact"},
	{"id": "ancient_relic", "name": "Ancient Relic", "rarity": Rarity.LEGENDARY, "weight": 5.0, "value": 2000, "category": "artifact"},
	{"id": "med_kit", "name": "Med Kit", "rarity": Rarity.COMMON, "weight": 1.5, "value": 25, "category": "consumable"},
	{"id": "stim_pack", "name": "Stim Pack", "rarity": Rarity.UNCOMMON, "weight": 0.5, "value": 50, "category": "consumable"},
	{"id": "rusty_blade", "name": "Rusty Blade", "rarity": Rarity.COMMON, "weight": 3.0, "value": 15, "category": "weapon"},
	{"id": "plasma_pistol", "name": "Plasma Pistol", "rarity": Rarity.RARE, "weight": 2.5, "value": 200, "category": "weapon"},
	{"id": "voxel_disruptor", "name": "Voxel Disruptor", "rarity": Rarity.LEGENDARY, "weight": 4.0, "value": 3000, "category": "weapon"},
]

func generate_loot(difficulty: int, count: int = 3) -> Array[Dictionary]:
	var loot: Array[Dictionary] = []
	for i in count:
		var rarity := _roll_rarity(difficulty)
		var candidates := item_database.filter(func(item): return item["rarity"] == rarity)
		if candidates.size() > 0:
			var item: Dictionary = candidates[randi() % candidates.size()].duplicate()
			loot.append(item)
	return loot

func _roll_rarity(difficulty: int) -> Rarity:
	var total_weight := 0
	var adjusted_weights := {}
	for rarity in RARITY_WEIGHTS:
		# Higher difficulty shifts weights toward rarer items
		var weight: int = RARITY_WEIGHTS[rarity]
		if rarity >= Rarity.RARE:
			weight += difficulty * 2
		adjusted_weights[rarity] = weight
		total_weight += weight

	var roll := randi() % total_weight
	var cumulative := 0
	for rarity in adjusted_weights:
		cumulative += adjusted_weights[rarity]
		if roll < cumulative:
			return rarity
	return Rarity.COMMON

func spawn_dropped_item(item: Dictionary, position: Vector3) -> void:
	# TODO: instantiate a pickup scene at position with the item data
	print("Dropped: %s at %s" % [item.get("name", "unknown"), position])

func get_rarity_color(rarity: Rarity) -> Color:
	return RARITY_COLORS.get(rarity, Color.WHITE)

func get_rarity_name(rarity: Rarity) -> String:
	match rarity:
		Rarity.COMMON: return "Common"
		Rarity.UNCOMMON: return "Uncommon"
		Rarity.RARE: return "Rare"
		Rarity.EPIC: return "Epic"
		Rarity.LEGENDARY: return "Legendary"
	return "Unknown"
