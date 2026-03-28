extends Node3D
class_name ThirdPersonCamera

## Third-person camera with proper relative motion.
##
## Camera orbits the player with collision avoidance,
## smooth follow with momentum, and context-sensitive framing.
## Think God of War / Dark Souls camera done right.

@export_group("Orbit")
@export var distance: float = 4.0  # Default distance from player
@export var distance_min: float = 1.5  # Closest zoom
@export var distance_max: float = 8.0  # Farthest zoom
@export var height_offset: float = 1.6  # Camera looks at this height above player origin
@export var shoulder_offset: float = 0.6  # Over-the-shoulder offset (0 = centered)
@export var mouse_sensitivity: float = 0.002

@export_group("Follow")
@export var follow_speed: float = 12.0  # How fast camera follows player
@export var follow_damping: float = 0.85  # Momentum damping (lower = more floaty)
@export var auto_center_speed: float = 1.5  # How fast camera re-centers behind player when moving
@export var auto_center_delay: float = 2.0  # Seconds of no mouse input before auto-centering

@export_group("Collision")
@export var collision_margin: float = 0.3  # Push camera forward this much past collision
@export var collision_smooth: float = 15.0  # How fast camera adjusts for collision
@export var collision_mask: int = 1  # Physics layers to collide with

@export_group("Sprint")
@export var sprint_distance: float = 5.5  # Pull camera back when sprinting
@export var sprint_fov: float = 78.0
@export var base_fov: float = 70.0
@export var aim_fov: float = 50.0
@export var aim_distance: float = 2.5
@export var aim_shoulder_offset: float = 1.0
@export var fov_smooth: float = 8.0

@export_group("Combat")
@export var lock_on_enabled: bool = true
@export var lock_on_range: float = 20.0
@export var lock_on_smooth: float = 6.0

@export_group("Impact")
@export var landing_impact_scale: float = 0.08
@export var hit_shake_intensity: float = 0.05
@export var hit_shake_duration: float = 0.2

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $CollisionRay

# State
var _yaw: float = 0.0
var _pitch: float = -0.2  # Slightly looking down
var _current_distance: float = 4.0
var _target_distance: float = 4.0
var _follow_velocity: Vector3 = Vector3.ZERO
var _last_mouse_time: float = 0.0
var _is_aiming: bool = false
var _lock_target: Node3D = null
var _shake_offset: Vector3 = Vector3.ZERO
var _landing_offset: float = 0.0
var _landing_velocity: float = 0.0
var _was_on_floor: bool = true
var _last_player_velocity: Vector3 = Vector3.ZERO
var _smooth_shoulder: float = 0.6
var _target_shoulder: float = 0.6

# Pitch limits
const PITCH_MIN: float = -1.2  # Looking up
const PITCH_MAX: float = 0.8  # Looking down

func _ready() -> void:
	_current_distance = distance
	_target_distance = distance
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clamp(_pitch, PITCH_MIN, PITCH_MAX)
		_last_mouse_time = 0.0

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = max(distance_min, _target_distance - 0.5)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = min(distance_max, _target_distance + 0.5)

func _physics_process(delta: float) -> void:
	var player := get_parent() as CharacterBody3D
	if not player:
		return

	var player_pos := player.global_position + Vector3.UP * height_offset
	var velocity := player.velocity
	var on_floor: bool = player.is_on_floor() if player.has_method("is_on_floor") else true
	var is_sprinting: bool = player.get("is_sprinting") if player.get("is_sprinting") != null else false
	_is_aiming = Input.is_action_pressed("aim")

	_last_mouse_time += delta

	# ── Auto-center behind player when moving ──────────────────
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 1.0 and _last_mouse_time > auto_center_delay:
		var move_angle := atan2(-velocity.x, -velocity.z)
		_yaw = lerp_angle(_yaw, move_angle, delta * auto_center_speed)

	# ── Target distance based on state ─────────────────────────
	if _is_aiming:
		_target_distance = aim_distance
		_target_shoulder = aim_shoulder_offset
	elif is_sprinting:
		_target_distance = sprint_distance
		_target_shoulder = shoulder_offset
	else:
		_target_distance = distance
		_target_shoulder = shoulder_offset

	_current_distance = lerp(_current_distance, _target_distance, delta * 8.0)
	_smooth_shoulder = lerp(_smooth_shoulder, _target_shoulder, delta * 8.0)

	# ── Lock-on ────────────────────────────────────────────────
	if _lock_target and is_instance_valid(_lock_target):
		var to_target := (_lock_target.global_position - player_pos).normalized()
		var target_yaw := atan2(-to_target.x, -to_target.z)
		var target_pitch := -asin(to_target.y)
		_yaw = lerp_angle(_yaw, target_yaw, delta * lock_on_smooth)
		_pitch = lerp(_pitch, clamp(target_pitch, PITCH_MIN, PITCH_MAX), delta * lock_on_smooth)

	# ── Calculate orbit position ───────────────────────────────
	var orbit_rotation := Vector3(_pitch, _yaw, 0.0)
	var orbit_basis := Basis.from_euler(orbit_rotation)
	var camera_offset := orbit_basis * Vector3(_smooth_shoulder, 0.0, _current_distance)
	var target_pos := player_pos + camera_offset

	# ── Collision avoidance ────────────────────────────────────
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		player_pos, target_pos, collision_mask
	)
	query.exclude = [player.get_rid()] if player is CollisionObject3D else []
	var result := space_state.intersect_ray(query)
	if result:
		var hit_dist := player_pos.distance_to(result.position) - collision_margin
		var collision_dist := max(distance_min, hit_dist)
		var collision_offset := orbit_basis * Vector3(_smooth_shoulder, 0.0, collision_dist)
		target_pos = player_pos + collision_offset

	# ── Smooth follow with momentum ───────────────────────────
	var follow_force := (target_pos - global_position) * follow_speed
	_follow_velocity = _follow_velocity * follow_damping + follow_force * delta
	global_position += _follow_velocity

	# ── Landing impact ─────────────────────────────────────────
	if on_floor and not _was_on_floor:
		var fall_speed := abs(_last_player_velocity.y)
		if fall_speed > 4.0:
			var impact := clamp((fall_speed - 4.0) / 15.0, 0.0, 1.0)
			_landing_offset = -impact * landing_impact_scale
			_landing_velocity = -impact * 1.5
	# Spring recovery
	var spring := -_landing_offset * 40.0 - _landing_velocity * 8.0
	_landing_velocity += spring * delta
	_landing_offset += _landing_velocity * delta
	_was_on_floor = on_floor
	_last_player_velocity = velocity

	# ── Look at player ─────────────────────────────────────────
	var look_target := player_pos + Vector3(0, _landing_offset, 0) + _shake_offset
	if camera:
		camera.look_at(look_target, Vector3.UP)

	# ── FOV ────────────────────────────────────────────────────
	var target_fov := base_fov
	if _is_aiming:
		target_fov = aim_fov
	elif is_sprinting:
		target_fov = sprint_fov
	if camera:
		camera.fov = lerp(camera.fov, target_fov, delta * fov_smooth)

	# ── Shake decay ────────────────────────────────────────────
	_shake_offset = _shake_offset.lerp(Vector3.ZERO, delta * 10.0)

# ── Public API ─────────────────────────────────────────────────

func camera_shake(intensity: float, duration: float = 0.2) -> void:
	_shake_offset = Vector3(
		randf_range(-1, 1) * intensity,
		randf_range(-1, 1) * intensity,
		randf_range(-1, 1) * intensity * 0.3,
	)

func lock_on(target: Node3D) -> void:
	_lock_target = target

func release_lock() -> void:
	_lock_target = null

func get_aim_direction() -> Vector3:
	"""Get the direction the camera is facing — for shooting/abilities."""
	if camera:
		return -camera.global_basis.z
	return Vector3.FORWARD

func get_flat_direction() -> Vector3:
	"""Get camera forward on the XZ plane — for movement relative to camera."""
	var forward := -Basis.from_euler(Vector3(0, _yaw, 0)).z
	return forward.normalized()

func get_right_direction() -> Vector3:
	"""Get camera right on the XZ plane."""
	return get_flat_direction().cross(Vector3.UP).normalized()
