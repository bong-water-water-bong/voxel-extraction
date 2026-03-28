extends Node3D

## Game bootstrap — the main scene controller.
## Wires up chunk manager, dungeon generator, player spawning,
## and raid lifecycle. This is what main.tscn runs.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

@onready var chunk_manager: ChunkManager = $ChunkManager
@onready var destruction: VoxelDestruction = $VoxelDestruction
@onready var pack_loader: PackLoader = $PackLoader

var player: PlayerController
var dungeon_layout: DungeonLayout
var dungeon_generator: DungeonGenerator
var current_pack: DungeonPack
var _world_ready: bool = false

func _ready() -> void:
	# Wait a frame for autoloads to initialize
	await get_tree().process_frame
	_start_raid()

func _start_raid() -> void:
	# Load dungeon pack (default to undercroft)
	await get_tree().process_frame  # Let pack loader scan
	current_pack = pack_loader.get_pack("undercroft")
	if not current_pack:
		# Fallback — create default pack
		current_pack = DungeonPack.new()
		push_warning("No pack loaded, using defaults")

	# Generate terrain first (overworld around the dungeon entrance)
	print("[Bootstrap] Generating terrain...")

	# Generate dungeon
	print("[Bootstrap] Generating dungeon: %s" % current_pack.pack_name)
	dungeon_generator = DungeonGenerator.new(current_pack)
	dungeon_layout = dungeon_generator.generate(chunk_manager)

	# Update chunks around spawn point
	var spawn_pos := dungeon_generator.get_spawn_position()
	print("[Bootstrap] Spawn position: %s" % spawn_pos)

	# Force initial chunk generation around spawn
	chunk_manager.update_around_player(spawn_pos)

	# Wait for initial chunks to generate and mesh
	print("[Bootstrap] Building world...")
	for i in 30:  # Give it ~30 frames to build initial chunks
		await get_tree().process_frame
		chunk_manager.update_around_player(spawn_pos)

	# Spawn player
	_spawn_player(spawn_pos)

	# Set up extraction zones
	_setup_extraction_zones()

	# Configure environment from pack
	_apply_pack_environment()

	# Start the raid timer
	GameManager.start_raid(1)

	_world_ready = true
	print("[Bootstrap] Raid started! %s" % current_pack.pack_name)
	print("[Bootstrap] Rooms: %d | Enemies: %d | Extractions: %d" % [
		dungeon_layout.rooms.size(),
		dungeon_layout.get_total_enemies(),
		dungeon_generator.extraction_room_indices.size(),
	])

func _process(_delta: float) -> void:
	if not _world_ready or not player:
		return

	# Keep chunks loaded around player
	chunk_manager.update_around_player(player.global_position)

	# Update extraction panic — ramps up in the last 10 minutes
	if GameManager.state == GameManager.GameState.IN_RAID:
		var time_left := GameManager.get_raid_time_remaining()
		var panic := 0.0
		if time_left < 600.0:  # Last 10 minutes
			panic = 1.0 - (time_left / 600.0)
			panic = clamp(panic * panic, 0.0, 1.0)  # Exponential ramp
		var env := $WorldEnvironment as VoxelWorldEnvironment
		if env:
			env.set_extraction_panic(panic)

func _spawn_player(pos: Vector3) -> void:
	player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = pos
	player.add_to_group("players")

	# Connect signals
	player.died.connect(_on_player_died)
	player.extraction_started.connect(_on_extraction_started)

	print("[Bootstrap] Player spawned at %s" % pos)

func _setup_extraction_zones() -> void:
	var positions := dungeon_generator.get_extraction_positions()
	for i in positions.size():
		var zone := Area3D.new()
		zone.name = "ExtractionZone_%d" % i

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(6, 6, 6)  # Extraction zone radius
		shape.shape = box
		zone.add_child(shape)

		zone.global_position = positions[i]
		zone.collision_layer = 32  # Layer 6: ExtractionZones
		zone.collision_mask = 2  # Layer 2: Player

		add_child(zone)
		ExtractionManager.register_zone(zone)

		print("[Bootstrap] Extraction zone %d at %s" % [i, positions[i]])

func _apply_pack_environment() -> void:
	var env := $WorldEnvironment as VoxelWorldEnvironment
	if not env:
		return
	# Apply pack-specific fog and lighting
	if env.environment:
		env.environment.volumetric_fog_density = current_pack.fog_density
		env.environment.volumetric_fog_albedo = current_pack.fog_color
		env.environment.fog_light_color = current_pack.ambient_color

func _on_player_died() -> void:
	print("[Bootstrap] PLAYER DIED — loot lost!")
	GameManager.player_died(player)
	# Show death screen after delay
	await get_tree().create_timer(2.0).timeout
	_show_results(false)

func _on_extraction_started() -> void:
	print("[Bootstrap] Extraction in progress...")

func _show_results(success: bool) -> void:
	if success:
		print("[Bootstrap] EXTRACTION SUCCESSFUL!")
		print("[Bootstrap] Loot secured: %d items" % player.inventory.size())
	else:
		print("[Bootstrap] RAID FAILED")
		print("[Bootstrap] All loot lost.")
	# TODO: Results UI screen

# ── Debug ──────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				# Debug: print stats
				var stats := chunk_manager.get_stats()
				print("[Debug] Chunks: %d | Mesh queue: %d | Gen queue: %d" % [
					stats["chunks_loaded"], stats["mesh_queue"], stats["generate_queue"]
				])
				if dungeon_layout:
					print("[Debug] Cleared: %.0f%% | Time: %s" % [
						dungeon_layout.get_cleared_percentage(),
						GameManager.get_raid_time_string(),
					])
			KEY_F2:
				# Debug: teleport to nearest extraction
				if player and dungeon_layout:
					var ext := dungeon_layout.get_closest_extraction(player.global_position)
					player.global_position = ext + Vector3.UP * 2
					print("[Debug] Teleported to extraction")
			KEY_F3:
				# Debug: explosion at crosshair
				if player:
					var cam := player.get_node("CameraRig/Camera3D") as Camera3D
					if cam:
						var center := get_viewport().get_visible_rect().size / 2
						var from := cam.project_ray_origin(center)
						var to := from + cam.project_ray_normal(center) * 50.0
						var space := get_world_3d().direct_space_state
						var query := PhysicsRayQueryParameters3D.create(from, to)
						var result := space.intersect_ray(query)
						if result:
							var hit := Vector3i(result.position + result.normal * -0.5)
							var debris := chunk_manager.explosion(hit, 3)
							destruction.spawn_explosion_debris(debris)
							print("[Debug] Explosion at %s — %d blocks destroyed" % [hit, debris.size()])
