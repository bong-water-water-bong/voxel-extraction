extends Node3D
class_name MotionController

## Per-object and camera-relative motion handling.
## Makes movement feel PHYSICAL, not floaty.
##
## Problems most games have:
## - Objects appear to slide (no acceleration curve)
## - Camera detached from body momentum
## - Turning feels disconnected from movement vector
## - No weight behind movement — a tank moves like a human
##
## This system gives every moving object proper:
## - Acceleration / deceleration curves
## - Momentum preservation through turns
## - Mass-based movement feel
## - Relative velocity awareness (things moving WITH you feel slower)

@export var mass: float = 1.0  # Affects acceleration and momentum
@export var friction: float = 8.0  # Ground friction
@export var air_friction: float = 0.5  # Air resistance
@export var acceleration: float = 40.0  # Ground acceleration
@export var air_acceleration: float = 8.0  # Air control
@export var max_speed: float = 5.0
@export var turn_smoothing: float = 12.0  # How fast direction changes apply

var _current_velocity: Vector3 = Vector3.ZERO
var _target_direction: Vector3 = Vector3.ZERO
var _smooth_direction: Vector3 = Vector3.ZERO
var _momentum: Vector3 = Vector3.ZERO
var _on_ground: bool = true

## Calculate velocity with proper physics-based acceleration.
## Returns the velocity to apply to CharacterBody3D.
func calculate_velocity(
	input_direction: Vector3,
	current_velocity: Vector3,
	on_floor: bool,
	delta: float,
	speed_override: float = -1.0,
) -> Vector3:
	_on_ground = on_floor
	var target_speed := speed_override if speed_override > 0 else max_speed

	# Smooth direction changes — momentum carries through turns
	if input_direction.length_squared() > 0.01:
		_target_direction = input_direction.normalized()
	_smooth_direction = _smooth_direction.lerp(
		_target_direction, delta * turn_smoothing
	).normalized() if _smooth_direction.length_squared() > 0.01 else _target_direction

	var accel := acceleration if on_floor else air_acceleration
	var fric := friction if on_floor else air_friction

	# Mass affects acceleration — heavier = slower to start/stop
	accel /= max(mass, 0.1)

	# Horizontal velocity
	var horizontal := Vector3(current_velocity.x, 0, current_velocity.z)

	if input_direction.length_squared() > 0.01:
		# Accelerate toward target
		var target_velocity := _smooth_direction * target_speed
		horizontal = horizontal.move_toward(target_velocity, accel * delta)
	else:
		# Decelerate with friction
		horizontal = horizontal.move_toward(Vector3.ZERO, fric * delta)

	# Preserve momentum through direction changes (feels physical)
	_momentum = _momentum.lerp(horizontal, delta * 6.0)

	# Blend momentum into velocity for weight feel
	var blended := horizontal.lerp(_momentum, 0.15 / max(mass, 0.1))

	_current_velocity = Vector3(blended.x, current_velocity.y, blended.z)
	return _current_velocity

## Get the relative velocity between this object and another.
## Objects moving with you should appear slower.
## Objects moving against you should appear faster.
func get_relative_velocity(other_velocity: Vector3) -> Vector3:
	return other_velocity - _current_velocity

## Get a speed factor for visual effects (blur, FOV, trails).
## 0.0 = stationary, 1.0 = max speed.
func get_speed_factor() -> float:
	var h := Vector2(_current_velocity.x, _current_velocity.z).length()
	return clamp(h / max_speed, 0.0, 1.5)

## Get the turning rate — useful for footstep sound variation,
## animation blending, and dust/particle direction.
func get_turn_rate() -> float:
	if _smooth_direction.length_squared() < 0.01:
		return 0.0
	return _smooth_direction.cross(_target_direction).y
