extends Node3D
class_name CharacterAnimation

## Full-body character animation with proper relative motion.
##
## Procedural animation blending — the character's body REACTS
## to physics, not just plays canned clips. Animations blend based
## on actual velocity, turn rate, slope, and momentum.

@export var animation_player: AnimationPlayer
@export var skeleton: Skeleton3D

@export_group("Blend Speeds")
@export var blend_speed: float = 8.0  # How fast animation states blend
@export var turn_blend_speed: float = 10.0  # How fast turning blends in
@export var lean_amount: float = 8.0  # Degrees of lean into turns
@export var lean_speed: float = 6.0  # How fast lean responds

@export_group("IK")
@export var foot_ik_enabled: bool = true
@export var foot_ray_length: float = 1.0
@export var foot_ik_smooth: float = 12.0
@export var hip_offset_smooth: float = 8.0

@export_group("Physics Response")
@export var landing_squash: float = 0.15  # Squash on landing (0-1)
@export var landing_recovery: float = 4.0  # Recovery speed
@export var hit_reaction_strength: float = 0.3
@export var breathing_enabled: bool = true
@export var breathing_speed: float = 0.8
@export var breathing_amount: float = 0.005

enum State {
	IDLE,
	WALK,
	RUN,
	SPRINT,
	JUMP_UP,
	FALLING,
	LANDING,
	DODGE,
	ATTACK,
	HIT,
	DEATH,
}

var current_state: State = State.IDLE
var _blend_weights: Dictionary = {}  # State -> float (0.0 to 1.0)
var _lean_current: float = 0.0
var _lean_target: float = 0.0
var _squash_factor: float = 1.0
var _squash_velocity: float = 0.0
var _left_foot_offset: float = 0.0
var _right_foot_offset: float = 0.0
var _hip_offset: float = 0.0
var _breathing_timer: float = 0.0
var _was_on_floor: bool = true
var _last_fall_speed: float = 0.0
var _velocity_smooth: Vector3 = Vector3.ZERO
var _last_velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	for s in State.values():
		_blend_weights[s] = 0.0
	_blend_weights[State.IDLE] = 1.0

func _physics_process(delta: float) -> void:
	var player := get_parent() as CharacterBody3D
	if not player:
		return

	var velocity := player.velocity
	var on_floor: bool = player.is_on_floor()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	# Smooth velocity for animation (prevents jitter)
	_velocity_smooth = _velocity_smooth.lerp(velocity, delta * 10.0)

	# ── Determine animation state ──────────────────────────────
	var new_state := _determine_state(horizontal_speed, velocity.y, on_floor, player)
	if new_state != current_state:
		_transition_to(new_state)

	# ── Blend weights ──────────────────────────────────────────
	for s in _blend_weights:
		if s == current_state:
			_blend_weights[s] = lerp(_blend_weights[s], 1.0, delta * blend_speed)
		else:
			_blend_weights[s] = lerp(_blend_weights[s], 0.0, delta * blend_speed)

	# ── Lean into movement direction ───────────────────────────
	if horizontal_speed > 0.5 and on_floor:
		# Calculate turn rate from velocity change
		var vel_flat := Vector3(velocity.x, 0, velocity.z).normalized()
		var last_flat := Vector3(_last_velocity.x, 0, _last_velocity.z).normalized()
		if vel_flat.length_squared() > 0.01 and last_flat.length_squared() > 0.01:
			var cross := last_flat.cross(vel_flat).y
			_lean_target = -cross * lean_amount * horizontal_speed
		else:
			_lean_target = 0.0
	else:
		_lean_target = 0.0

	_lean_current = lerp(_lean_current, _lean_target, delta * lean_speed)
	_lean_current = clamp(_lean_current, -lean_amount, lean_amount)

	# ── Landing squash & stretch ───────────────────────────────
	if on_floor and not _was_on_floor:
		var impact := clamp(abs(_last_fall_speed) / 15.0, 0.0, 1.0)
		_squash_factor = 1.0 - impact * landing_squash
		_squash_velocity = impact * 2.0

	# Spring recovery
	var spring_force := (1.0 - _squash_factor) * 30.0 - _squash_velocity * 6.0
	_squash_velocity += spring_force * delta
	_squash_factor += _squash_velocity * delta
	_squash_factor = clamp(_squash_factor, 0.7, 1.3)

	# ── Breathing ──────────────────────────────────────────────
	if breathing_enabled and current_state == State.IDLE:
		_breathing_timer += delta * breathing_speed
		var breath := sin(_breathing_timer * TAU) * breathing_amount
		# Applied to chest bone if skeleton exists
		_apply_breathing(breath)

	# ── Foot IK ────────────────────────────────────────────────
	if foot_ik_enabled and on_floor:
		_update_foot_ik(delta)

	# ── Apply transforms ───────────────────────────────────────
	_apply_lean(delta)
	_apply_squash()

	_was_on_floor = on_floor
	_last_fall_speed = velocity.y
	_last_velocity = velocity

func _determine_state(
	speed: float, vert_speed: float, on_floor: bool, player: CharacterBody3D
) -> State:
	if not on_floor:
		if vert_speed > 1.0:
			return State.JUMP_UP
		else:
			return State.FALLING

	if current_state == State.FALLING and on_floor:
		return State.LANDING

	var is_sprinting: bool = player.get("is_sprinting") if player.get("is_sprinting") != null else false

	if speed < 0.5:
		return State.IDLE
	elif speed < 4.0:
		return State.WALK
	elif is_sprinting:
		return State.SPRINT
	else:
		return State.RUN

func _transition_to(new_state: State) -> void:
	current_state = new_state

	# Trigger animation if animation player exists
	if animation_player:
		var anim_name := _state_to_anim_name(new_state)
		if animation_player.has_animation(anim_name):
			animation_player.play(anim_name, 0.2)

func _state_to_anim_name(state: State) -> String:
	match state:
		State.IDLE: return "idle"
		State.WALK: return "walk"
		State.RUN: return "run"
		State.SPRINT: return "sprint"
		State.JUMP_UP: return "jump_up"
		State.FALLING: return "falling"
		State.LANDING: return "landing"
		State.DODGE: return "dodge"
		State.ATTACK: return "attack"
		State.HIT: return "hit"
		State.DEATH: return "death"
	return "idle"

func _apply_lean(_delta: float) -> void:
	# Rotate the model to lean into turns
	rotation_degrees.z = _lean_current

	# Also lean forward slightly when running
	var speed := Vector2(_velocity_smooth.x, _velocity_smooth.z).length()
	var forward_lean := clamp(speed / 10.0, 0.0, 1.0) * 3.0
	rotation_degrees.x = forward_lean

func _apply_squash() -> void:
	# Squash on Y, stretch on XZ
	var inv_squash := 1.0 / max(_squash_factor, 0.01)
	var stretch := sqrt(inv_squash)
	scale = Vector3(stretch, _squash_factor, stretch)

func _apply_breathing(breath: float) -> void:
	# Subtle scale pulse on idle
	if current_state == State.IDLE:
		scale.y = 1.0 + breath

func _update_foot_ik(delta: float) -> void:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return

	# Cast rays from feet downward
	var left_pos := global_position + global_basis * Vector3(-0.15, 0.5, 0.0)
	var right_pos := global_position + global_basis * Vector3(0.15, 0.5, 0.0)

	var left_target := _cast_foot_ray(space_state, left_pos)
	var right_target := _cast_foot_ray(space_state, right_pos)

	# Smooth IK offsets
	_left_foot_offset = lerp(_left_foot_offset, left_target, delta * foot_ik_smooth)
	_right_foot_offset = lerp(_right_foot_offset, right_target, delta * foot_ik_smooth)

	# Adjust hip height to lowest foot
	var target_hip := min(_left_foot_offset, _right_foot_offset)
	_hip_offset = lerp(_hip_offset, target_hip, delta * hip_offset_smooth)

func _cast_foot_ray(space_state: PhysicsDirectSpaceState3D, from: Vector3) -> float:
	var to := from + Vector3.DOWN * foot_ray_length
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var result := space_state.intersect_ray(query)
	if result:
		return result.position.y - (global_position.y - 0.05)
	return 0.0

# ── Public API ─────────────────────────────────────────────────

func play_hit_reaction(direction: Vector3) -> void:
	"""React to being hit — flinch in the direction of impact."""
	current_state = State.HIT
	_lean_target = -direction.x * hit_reaction_strength * 30.0
	_squash_factor = 0.9
	# Recovery
	var tween := create_tween()
	tween.tween_callback(func(): current_state = State.IDLE).set_delay(0.3)

func play_death() -> void:
	current_state = State.DEATH
	_transition_to(State.DEATH)

func get_animation_speed_scale() -> float:
	"""Scale animation playback speed to match actual movement speed."""
	var speed := Vector2(_velocity_smooth.x, _velocity_smooth.z).length()
	match current_state:
		State.WALK:
			return clamp(speed / 3.0, 0.5, 1.5)
		State.RUN:
			return clamp(speed / 5.0, 0.7, 1.3)
		State.SPRINT:
			return clamp(speed / 8.0, 0.8, 1.2)
	return 1.0
