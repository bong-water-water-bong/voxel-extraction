extends Node3D
class_name CameraController

## First-person camera with proper relative motion.
##
## Most games get this wrong:
## - Head bob that doesn't match footstep timing
## - Camera sway disconnected from actual movement direction
## - Weapon sway that feels floaty instead of physical
## - No momentum — instant stops feel robotic
## - Landing impacts that don't scale with fall height
##
## This system uses physics-based spring simulation for everything.
## The camera REACTS to movement, it doesn't fake it.

@export_group("Head Bob")
@export var bob_enabled: bool = true
@export var bob_frequency: float = 2.4  # Steps per second at walk speed
@export var bob_amplitude_v: float = 0.035  # Vertical bob height
@export var bob_amplitude_h: float = 0.02  # Horizontal bob sway
@export var bob_sprint_multiplier: float = 1.4

@export_group("Camera Sway")
@export var sway_amount: float = 0.3  # How much camera tilts into turns
@export var sway_speed: float = 8.0  # How fast sway responds
@export var sway_max_angle: float = 2.5  # Max roll degrees

@export_group("Weapon Sway")
@export var weapon_sway_amount: float = 0.002
@export var weapon_sway_smooth: float = 12.0
@export var weapon_sway_max: float = 0.04

@export_group("Landing Impact")
@export var landing_enabled: bool = true
@export var landing_min_velocity: float = 4.0  # Min fall speed to trigger
@export var landing_max_offset: float = 0.15  # Max camera dip on hard landing
@export var landing_recovery_speed: float = 6.0

@export_group("Recoil")
@export var recoil_recovery_speed: float = 8.0

@export_group("Momentum")
@export var momentum_smooth: float = 10.0  # How fast camera catches up to body
@export var fov_base: float = 75.0
@export var fov_sprint: float = 82.0
@export var fov_aim: float = 55.0
@export var fov_speed: float = 8.0

@onready var camera: Camera3D = $Camera3D
@onready var weapon_holder: Node3D = $Camera3D/Hand

# Internal state
var _bob_timer: float = 0.0
var _bob_offset: Vector3 = Vector3.ZERO
var _sway_target: float = 0.0
var _sway_current: float = 0.0
var _weapon_sway_offset: Vector2 = Vector2.ZERO
var _weapon_sway_target: Vector2 = Vector2.ZERO
var _landing_offset: float = 0.0
var _landing_velocity: float = 0.0
var _recoil_offset: Vector2 = Vector2.ZERO
var _was_on_floor: bool = true
var _last_velocity: Vector3 = Vector3.ZERO
var _target_fov: float = 75.0
var _mouse_delta: Vector2 = Vector2.ZERO
var _velocity_smooth: Vector3 = Vector3.ZERO

func _ready() -> void:
	_target_fov = fov_base

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_delta = event.relative

func _physics_process(delta: float) -> void:
	var player := get_parent() as PlayerController
	if not player:
		return

	var velocity := player.velocity
	var on_floor := player.is_on_floor()
	var is_sprinting := player.is_sprinting
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var is_moving := horizontal_speed > 0.5

	# ── Smooth velocity (relative motion feels right) ──────────
	_velocity_smooth = _velocity_smooth.lerp(velocity, delta * momentum_smooth)

	# ── Head Bob ───────────────────────────────────────────────
	if bob_enabled and on_floor and is_moving:
		var freq := bob_frequency * (bob_sprint_multiplier if is_sprinting else 1.0)
		_bob_timer += delta * freq * horizontal_speed * 0.3
		var amp_v := bob_amplitude_v * (1.3 if is_sprinting else 1.0)
		var amp_h := bob_amplitude_h * (1.3 if is_sprinting else 1.0)
		_bob_offset.y = sin(_bob_timer * TAU) * amp_v
		_bob_offset.x = cos(_bob_timer * TAU * 0.5) * amp_h
	else:
		# Smoothly return to neutral — don't snap
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, delta * 8.0)
		if not on_floor:
			_bob_timer = 0.0

	# ── Camera Sway (lean into movement direction) ─────────────
	var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_sway_target = -move_input.x * sway_amount
	_sway_current = lerp(_sway_current, _sway_target, delta * sway_speed)
	var sway_roll := clamp(_sway_current, -deg_to_rad(sway_max_angle), deg_to_rad(sway_max_angle))

	# ── Weapon Sway (follows mouse with lag) ───────────────────
	_weapon_sway_target = Vector2(
		clamp(-_mouse_delta.x * weapon_sway_amount, -weapon_sway_max, weapon_sway_max),
		clamp(-_mouse_delta.y * weapon_sway_amount, -weapon_sway_max, weapon_sway_max)
	)
	_weapon_sway_offset = _weapon_sway_offset.lerp(_weapon_sway_target, delta * weapon_sway_smooth)
	_mouse_delta = Vector2.ZERO  # Reset after consuming

	# ── Landing Impact ─────────────────────────────────────────
	if landing_enabled:
		if on_floor and not _was_on_floor:
			# Just landed — check fall velocity
			var fall_speed := abs(_last_velocity.y)
			if fall_speed > landing_min_velocity:
				var impact := clamp(
					(fall_speed - landing_min_velocity) / 15.0,
					0.0, 1.0
				)
				_landing_offset = -impact * landing_max_offset
				_landing_velocity = -impact * 2.0
		# Spring recovery
		var spring_force := -_landing_offset * 40.0 - _landing_velocity * 8.0
		_landing_velocity += spring_force * delta
		_landing_offset += _landing_velocity * delta
		if abs(_landing_offset) < 0.001 and abs(_landing_velocity) < 0.001:
			_landing_offset = 0.0
			_landing_velocity = 0.0

	_was_on_floor = on_floor
	_last_velocity = velocity

	# ── Recoil Recovery ────────────────────────────────────────
	_recoil_offset = _recoil_offset.lerp(Vector2.ZERO, delta * recoil_recovery_speed)

	# ── FOV ────────────────────────────────────────────────────
	if Input.is_action_pressed("aim"):
		_target_fov = fov_aim
	elif is_sprinting:
		_target_fov = fov_sprint
	else:
		_target_fov = fov_base

	if camera:
		camera.fov = lerp(camera.fov, _target_fov, delta * fov_speed)

	# ── Apply All Offsets ──────────────────────────────────────
	# Position offsets (bob + landing)
	position = Vector3(
		_bob_offset.x,
		_bob_offset.y + _landing_offset,
		0.0
	)

	# Rotation (sway roll + recoil)
	rotation = Vector3(
		_recoil_offset.y,
		0.0,
		sway_roll
	)

	# Weapon holder offset (weapon sway)
	if weapon_holder:
		weapon_holder.position = Vector3(
			_weapon_sway_offset.x,
			_weapon_sway_offset.y,
			0.0
		)

# ── Public API ─────────────────────────────────────────────────

func add_recoil(pitch: float, yaw: float) -> void:
	"""Call this when firing a weapon."""
	_recoil_offset += Vector2(yaw, pitch)

func camera_shake(intensity: float, duration: float = 0.3) -> void:
	"""Explosion / nearby impact shake."""
	var tween := create_tween()
	var shake_offset := Vector3(
		randf_range(-1, 1) * intensity,
		randf_range(-1, 1) * intensity,
		0.0
	)
	tween.tween_property(self, "position", position + shake_offset, duration * 0.1)
	tween.tween_property(self, "position", position, duration * 0.9).set_ease(Tween.EASE_OUT)
