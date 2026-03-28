extends Node3D
class_name SpatialAudioManager

## 3D positional audio system for voxel dungeons.
##
## Everything you hear has a position in the world:
## - Footsteps echo off voxel walls
## - Enemy growls from down the corridor
## - Water dripping in the distance
## - The extraction beacon hum getting louder as you approach
## - Boss roars that shake the camera
##
## Uses Godot's AudioStreamPlayer3D with custom attenuation,
## reverb zones, occlusion simulation, and ambient layers.

@export_group("Listener")
@export var listener_node: Node3D  # Usually the player/camera

@export_group("Reverb")
@export var reverb_enabled: bool = true
@export var base_reverb_size: float = 0.4  # Room size affects reverb
@export var base_reverb_dampening: float = 0.3
@export var corridor_reverb_mult: float = 1.8  # Corridors echo more

@export_group("Occlusion")
@export var occlusion_enabled: bool = true
@export var occlusion_ray_count: int = 4  # Rays to check for walls
@export var occlusion_dampen_db: float = -12.0  # How much walls muffle sound
@export var occlusion_lowpass_hz: float = 800.0  # Low-pass when occluded

@export_group("Distance")
@export var max_hear_distance: float = 40.0
@export var reference_distance: float = 2.0

# Pools
var _sfx_pool_3d: Array[AudioStreamPlayer3D] = []
var _ambient_pool: Array[AudioStreamPlayer3D] = []
const SFX_POOL_SIZE: int = 24
const AMBIENT_POOL_SIZE: int = 8

# Reverb zones tracked per room
var _room_reverb_areas: Array[Area3D] = []

# Audio buses
var _bus_master: int = 0
var _bus_sfx: int = -1
var _bus_ambient: int = -1
var _bus_music: int = -1
var _bus_reverb: int = -1

func _ready() -> void:
	_setup_buses()
	_create_pools()

func _setup_buses() -> void:
	# Create audio buses for mixing
	_bus_sfx = AudioServer.bus_count
	AudioServer.add_bus(_bus_sfx)
	AudioServer.set_bus_name(_bus_sfx, "SFX")
	AudioServer.set_bus_send(_bus_sfx, "Master")

	_bus_ambient = AudioServer.bus_count
	AudioServer.add_bus(_bus_ambient)
	AudioServer.set_bus_name(_bus_ambient, "Ambient")
	AudioServer.set_bus_send(_bus_ambient, "Master")
	AudioServer.set_bus_volume_db(_bus_ambient, -6.0)

	_bus_music = AudioServer.bus_count
	AudioServer.add_bus(_bus_music)
	AudioServer.set_bus_name(_bus_music, "Music")
	AudioServer.set_bus_send(_bus_music, "Master")
	AudioServer.set_bus_volume_db(_bus_music, -3.0)

	_bus_reverb = AudioServer.bus_count
	AudioServer.add_bus(_bus_reverb)
	AudioServer.set_bus_name(_bus_reverb, "Reverb")
	AudioServer.set_bus_send(_bus_reverb, "Master")

	# Add reverb effect to the reverb bus
	var reverb := AudioEffectReverb.new()
	reverb.room_size = base_reverb_size
	reverb.damping = base_reverb_dampening
	reverb.spread = 0.8
	reverb.wet = 0.3
	reverb.dry = 0.7
	AudioServer.add_bus_effect(_bus_reverb, reverb)

func _create_pools() -> void:
	# 3D SFX pool
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.unit_size = reference_distance
		player.max_distance = max_hear_distance
		player.max_db = 3.0
		player.emission_angle_enabled = false
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(player)
		_sfx_pool_3d.append(player)

	# Ambient 3D pool (longer sounds, looping)
	for i in AMBIENT_POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.bus = "Ambient"
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.unit_size = reference_distance * 2.0
		player.max_distance = max_hear_distance * 1.5
		player.max_db = 0.0
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(player)
		_ambient_pool.append(player)

func _physics_process(_delta: float) -> void:
	if not occlusion_enabled or not listener_node:
		return
	_update_occlusion()

# ── Play sounds ────────────────────────────────────────────────

func play_at(
	stream: AudioStream,
	world_position: Vector3,
	volume_db: float = 0.0,
	pitch_scale: float = 1.0,
	bus_override: String = "",
) -> AudioStreamPlayer3D:
	"""Play a one-shot 3D sound at a world position."""
	var player := _get_free_sfx()
	if not player:
		return null

	player.stream = stream
	player.global_position = world_position
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	if bus_override != "":
		player.bus = bus_override
	else:
		player.bus = "SFX"
	player.play()
	return player

func play_footstep(
	world_position: Vector3,
	surface_block: int,
	is_sprinting: bool = false,
) -> void:
	"""Play a footstep sound based on surface material."""
	# TODO: load actual footstep samples per material
	# For now, use pitch/volume variation by surface
	var pitch := 1.0
	var volume := -6.0

	match surface_block:
		VoxelData.BlockID.STONE, VoxelData.BlockID.COBBLESTONE:
			pitch = randf_range(0.9, 1.1)
			volume = -4.0
		VoxelData.BlockID.DIRT, VoxelData.BlockID.GRASS:
			pitch = randf_range(0.8, 1.0)
			volume = -8.0
		VoxelData.BlockID.METAL_PLATE:
			pitch = randf_range(1.1, 1.3)
			volume = -2.0  # Metal rings
		VoxelData.BlockID.SAND:
			pitch = randf_range(0.7, 0.9)
			volume = -10.0  # Soft
		VoxelData.BlockID.SNOW:
			pitch = randf_range(0.85, 0.95)
			volume = -9.0
		VoxelData.BlockID.WATER:
			pitch = randf_range(0.6, 0.8)
			volume = -3.0  # Splash

	if is_sprinting:
		volume += 3.0
		pitch *= 1.1

	# Would play actual footstep stream here
	# play_at(footstep_stream, world_position, volume, pitch)

func play_ambient_loop(
	stream: AudioStream,
	world_position: Vector3,
	volume_db: float = -6.0,
) -> AudioStreamPlayer3D:
	"""Start a looping ambient sound at a position (water, fire, machinery)."""
	var player := _get_free_ambient()
	if not player:
		return null

	player.stream = stream
	player.global_position = world_position
	player.volume_db = volume_db
	player.play()
	return player

func play_enemy_sound(
	stream: AudioStream,
	enemy_position: Vector3,
	alert_level: float = 1.0,
) -> void:
	"""Play enemy sound with alert-based volume scaling."""
	var volume := lerp(-12.0, 0.0, alert_level)
	play_at(stream, enemy_position, volume, randf_range(0.85, 1.15))

func play_impact(
	world_position: Vector3,
	block_id: int,
	force: float = 1.0,
) -> void:
	"""Play block destruction/impact sound."""
	var pitch := 1.0
	var volume := lerp(-6.0, 3.0, clamp(force, 0.0, 1.0))

	# Material affects sound
	if VoxelData.is_solid(block_id):
		match block_id:
			VoxelData.BlockID.GLASS, VoxelData.BlockID.ICE:
				pitch = randf_range(1.2, 1.6)  # Shatter
			VoxelData.BlockID.METAL_PLATE, VoxelData.BlockID.RUST_METAL:
				pitch = randf_range(0.5, 0.8)  # Clang
			VoxelData.BlockID.STONE, VoxelData.BlockID.COBBLESTONE:
				pitch = randf_range(0.7, 1.0)  # Crumble
			VoxelData.BlockID.WOOD_LOG, VoxelData.BlockID.WOOD_PLANK:
				pitch = randf_range(0.8, 1.1)  # Crack

	# Would play actual impact stream here
	# play_at(impact_stream, world_position, volume, pitch)

func play_extraction_beacon(beacon_position: Vector3) -> AudioStreamPlayer3D:
	"""Start the extraction beacon hum — gets louder as you approach."""
	# TODO: looping beacon hum sound
	return play_ambient_loop(null, beacon_position, -3.0) if null else null

# ── Occlusion ──────────────────────────────────────────────────

func _update_occlusion() -> void:
	"""Check if active sounds are occluded by voxel walls."""
	if not listener_node:
		return

	var listener_pos := listener_node.global_position
	var space := get_world_3d().direct_space_state
	if not space:
		return

	for player in _sfx_pool_3d:
		if not player.playing:
			continue

		var sound_pos := player.global_position
		var direction := (listener_pos - sound_pos)
		var distance := direction.length()

		if distance < 0.1:
			continue

		# Cast rays between sound and listener
		var occluded := false
		var query := PhysicsRayQueryParameters3D.create(
			sound_pos, listener_pos, 1  # World collision layer
		)
		var result := space.intersect_ray(query)
		if result:
			# Wall between sound and listener
			occluded = true

		# Apply occlusion effect
		if occluded:
			# Muffle: reduce volume and apply low-pass conceptually
			player.volume_db = max(player.volume_db + occlusion_dampen_db * 0.1, -40.0)
			player.attenuation_filter_cutoff_hz = occlusion_lowpass_hz
			player.attenuation_filter_db = -12.0
		else:
			player.attenuation_filter_cutoff_hz = 20500.0  # No filter
			player.attenuation_filter_db = 0.0

# ── Reverb Zones ───────────────────────────────────────────────

func register_room_reverb(room_position: Vector3, room_size: Vector3) -> void:
	"""Create a reverb zone for a dungeon room. Bigger room = bigger reverb."""
	# Room volume affects reverb character
	var volume := room_size.x * room_size.y * room_size.z
	var reverb_size := clamp(volume / 2000.0, 0.2, 0.9)

	# Create an AudioListener area for this room
	var area := Area3D.new()
	area.name = "ReverbZone"

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = room_size
	shape.shape = box
	area.add_child(shape)

	area.global_position = room_position
	area.monitoring = false
	area.monitorable = true

	# Store reverb params
	area.set_meta("reverb_size", reverb_size)
	area.set_meta("reverb_wet", clamp(reverb_size * 0.5, 0.1, 0.6))

	add_child(area)
	_room_reverb_areas.append(area)

func update_reverb_for_position(pos: Vector3) -> void:
	"""Update the reverb bus based on which room the listener is in."""
	if not reverb_enabled:
		return

	var best_size := base_reverb_size
	var best_wet := 0.3

	for area in _room_reverb_areas:
		if not is_instance_valid(area):
			continue
		# Simple AABB check
		var shape := area.get_child(0) as CollisionShape3D
		if shape and shape.shape is BoxShape3D:
			var box: BoxShape3D = shape.shape
			var half := box.size * 0.5
			var local_pos := pos - area.global_position
			if abs(local_pos.x) < half.x and abs(local_pos.y) < half.y and abs(local_pos.z) < half.z:
				best_size = area.get_meta("reverb_size", base_reverb_size)
				best_wet = area.get_meta("reverb_wet", 0.3)
				break

	# Not in any room = corridor (more reverb)
	# Update reverb effect on the bus
	var effect := AudioServer.get_bus_effect(_bus_reverb, 0) as AudioEffectReverb
	if effect:
		effect.room_size = best_size
		effect.wet = best_wet

# ── Pool Management ────────────────────────────────────────────

func _get_free_sfx() -> AudioStreamPlayer3D:
	for player in _sfx_pool_3d:
		if not player.playing:
			return player
	# All busy — steal the farthest one
	if listener_node and _sfx_pool_3d.size() > 0:
		var farthest: AudioStreamPlayer3D = _sfx_pool_3d[0]
		var max_dist := 0.0
		for player in _sfx_pool_3d:
			var dist := player.global_position.distance_to(listener_node.global_position)
			if dist > max_dist:
				max_dist = dist
				farthest = player
		farthest.stop()
		return farthest
	return null

func _get_free_ambient() -> AudioStreamPlayer3D:
	for player in _ambient_pool:
		if not player.playing:
			return player
	return null

func get_stats() -> Dictionary:
	var active_sfx := 0
	for p in _sfx_pool_3d:
		if p.playing:
			active_sfx += 1
	var active_ambient := 0
	for p in _ambient_pool:
		if p.playing:
			active_ambient += 1
	return {
		"active_sfx": active_sfx,
		"active_ambient": active_ambient,
		"reverb_zones": _room_reverb_areas.size(),
	}
