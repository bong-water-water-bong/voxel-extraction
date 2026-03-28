extends Node3D
class_name VoxelDestruction

## Handles visual destruction of voxels — debris, particles, sounds.
## When blocks are destroyed, spawn physics debris that tumbles and fades.

@export var debris_lifetime: float = 4.0
@export var debris_per_block: int = 3
@export var debris_velocity: float = 5.0
@export var debris_gravity: float = 15.0
@export var max_active_debris: int = 200

var _active_debris: Array[Node3D] = []
var _debris_pool: Array[MeshInstance3D] = []

func _ready() -> void:
	# Pre-allocate debris pool
	for i in max_active_debris:
		var debris := _create_debris_mesh()
		debris.visible = false
		add_child(debris)
		_debris_pool.append(debris)

func _create_debris_mesh() -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 0.15, 0.15)
	mesh_inst.mesh = box
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_inst

func spawn_block_debris(block_id: int, world_position: Vector3) -> void:
	var color := VoxelData.get_color(block_id)

	for i in debris_per_block:
		var debris := _get_pooled_debris()
		if not debris:
			return  # Pool exhausted

		# Set color
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color.lerp(Color(0.2, 0.2, 0.2), randf() * 0.3)
		mat.roughness = 0.9
		if VoxelData.is_emissive(block_id):
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 2.0
		debris.material_override = mat

		# Position with slight random offset
		debris.global_position = world_position + Vector3(
			randf_range(-0.3, 0.3),
			randf_range(0.0, 0.3),
			randf_range(-0.3, 0.3),
		)

		# Random rotation
		debris.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)

		# Random scale
		var s := randf_range(0.08, 0.2)
		debris.scale = Vector3(s, s, s)

		debris.visible = true
		_active_debris.append(debris)

		# Animate: launch, tumble, fade, return to pool
		_animate_debris(debris, world_position)

func spawn_explosion_debris(destroyed_blocks: Array[Dictionary]) -> void:
	for block_info in destroyed_blocks:
		spawn_block_debris(block_info["block_id"], block_info["position"])

func _animate_debris(debris: MeshInstance3D, origin: Vector3) -> void:
	# Launch direction
	var dir := Vector3(
		randf_range(-1, 1),
		randf_range(0.5, 1.5),
		randf_range(-1, 1),
	).normalized()
	var vel := dir * debris_velocity * randf_range(0.5, 1.5)

	# Spin
	var spin := Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))

	var elapsed := 0.0
	var pos := debris.global_position

	# Use a tween for the animation
	var tween := create_tween()
	tween.set_parallel(true)

	# Fade out over lifetime
	tween.tween_property(debris, "transparency", 1.0, debris_lifetime).set_delay(debris_lifetime * 0.6)

	# Scale down at end
	tween.tween_property(debris, "scale", Vector3.ZERO, debris_lifetime * 0.3).set_delay(debris_lifetime * 0.7)

	tween.set_parallel(false)
	tween.tween_callback(func():
		debris.visible = false
		debris.transparency = 0.0
		debris.scale = Vector3.ONE * 0.15
		_active_debris.erase(debris)
		_debris_pool.append(debris)
	)

	# Physics simulation via process (lighter than RigidBody3D for many pieces)
	_simulate_debris(debris, vel, spin)

func _simulate_debris(debris: MeshInstance3D, velocity: Vector3, spin: Vector3) -> void:
	# Lightweight physics — no RigidBody needed
	var sim_time := 0.0
	var vel := velocity
	var pos := debris.global_position

	# Run physics in a coroutine-style approach via tween steps
	var tween := create_tween()
	var steps := int(debris_lifetime / 0.016)  # ~60fps steps
	var dt := debris_lifetime / float(steps)

	for i in steps:
		vel.y -= debris_gravity * dt
		pos += vel * dt
		# Floor collision at y=0 (approximate)
		if pos.y < 0.1:
			pos.y = 0.1
			vel.y = abs(vel.y) * 0.3  # Bounce
			vel.x *= 0.7
			vel.z *= 0.7

		var target_pos := pos
		var target_rot := debris.rotation + spin * dt * float(i + 1)
		tween.tween_property(debris, "global_position", target_pos, dt)
		tween.parallel().tween_property(debris, "rotation", target_rot, dt)

func _get_pooled_debris() -> MeshInstance3D:
	if _debris_pool.size() > 0:
		return _debris_pool.pop_back()
	# Pool exhausted — reclaim oldest active
	if _active_debris.size() > 0:
		var oldest := _active_debris.pop_front()
		oldest.visible = false
		return oldest
	return null
