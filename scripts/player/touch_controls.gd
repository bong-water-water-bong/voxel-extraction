extends CanvasLayer
class_name TouchControls

## Mobile touch input — virtual joystick, camera drag, action buttons.
## Automatically enabled when running on iOS/Android.
## Desktop players never see this.

@export var joystick_radius: float = 80.0
@export var joystick_dead_zone: float = 0.15
@export var camera_sensitivity: float = 0.004
@export var auto_aim_enabled: bool = true
@export var auto_aim_range: float = 15.0
@export var auto_aim_angle: float = 0.4  # Radians — generous on mobile

# UI elements
@onready var joystick_bg: TextureRect = $JoystickBG
@onready var joystick_knob: TextureRect = $JoystickKnob
@onready var btn_attack: TouchScreenButton = $BtnAttack
@onready var btn_interact: TouchScreenButton = $BtnInteract
@onready var btn_extract: TouchScreenButton = $BtnExtract
@onready var btn_sprint: TouchScreenButton = $BtnSprint
@onready var btn_inventory: TouchScreenButton = $BtnInventory

# State
var _joystick_active: bool = false
var _joystick_touch_index: int = -1
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_output: Vector2 = Vector2.ZERO
var _camera_touch_index: int = -1
var _camera_last_pos: Vector2 = Vector2.ZERO
var _camera_delta: Vector2 = Vector2.ZERO
var _is_mobile: bool = false

signal move_input(direction: Vector2)
signal camera_input(delta: Vector2)
signal attack_pressed()
signal interact_pressed()
signal extract_pressed()
signal sprint_toggled(active: bool)
signal inventory_pressed()

func _ready() -> void:
	_is_mobile = _detect_mobile()
	visible = _is_mobile

	if not _is_mobile:
		# Desktop — disable all touch UI
		set_process(false)
		set_process_input(false)
		return

	# Position joystick bottom-left
	if joystick_bg:
		_joystick_center = Vector2(150, get_viewport().get_visible_rect().size.y - 150)
		joystick_bg.position = _joystick_center - joystick_bg.size / 2

func _detect_mobile() -> bool:
	var os_name := OS.get_name()
	return os_name in ["iOS", "Android"]

func _input(event: InputEvent) -> void:
	if not _is_mobile:
		return

	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	var screen_half := get_viewport().get_visible_rect().size.x / 2.0

	if event.pressed:
		# Left half = joystick
		if event.position.x < screen_half and _joystick_touch_index == -1:
			_joystick_touch_index = event.index
			_joystick_active = true
			_joystick_center = event.position

		# Right half = camera
		elif event.position.x >= screen_half and _camera_touch_index == -1:
			_camera_touch_index = event.index
			_camera_last_pos = event.position
	else:
		# Released
		if event.index == _joystick_touch_index:
			_joystick_touch_index = -1
			_joystick_active = false
			_joystick_output = Vector2.ZERO
			move_input.emit(Vector2.ZERO)
			_reset_joystick_visual()

		elif event.index == _camera_touch_index:
			_camera_touch_index = -1
			_camera_delta = Vector2.ZERO

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _joystick_touch_index:
		# Joystick movement
		var offset := event.position - _joystick_center
		var distance := offset.length()

		if distance > joystick_radius:
			offset = offset.normalized() * joystick_radius

		_joystick_output = offset / joystick_radius

		# Apply dead zone
		if _joystick_output.length() < joystick_dead_zone:
			_joystick_output = Vector2.ZERO

		move_input.emit(_joystick_output)
		_update_joystick_visual(offset)

	elif event.index == _camera_touch_index:
		# Camera rotation
		_camera_delta = (event.position - _camera_last_pos) * camera_sensitivity
		_camera_last_pos = event.position
		camera_input.emit(_camera_delta)

func _reset_joystick_visual() -> void:
	if joystick_knob and joystick_bg:
		joystick_knob.position = joystick_bg.position + joystick_bg.size / 2 - joystick_knob.size / 2

func _update_joystick_visual(offset: Vector2) -> void:
	if joystick_knob:
		var center := joystick_bg.position + joystick_bg.size / 2 if joystick_bg else _joystick_center
		joystick_knob.position = center + offset - joystick_knob.size / 2

func get_move_vector() -> Vector2:
	"""Get the current joystick direction. Used by player controller."""
	return _joystick_output

func get_camera_delta() -> Vector2:
	"""Get camera rotation delta this frame. Consumed after read."""
	var delta := _camera_delta
	_camera_delta = Vector2.ZERO
	return delta

func is_mobile() -> bool:
	return _is_mobile

# ── Auto-Aim ──────────────────────────────────────────────────

func get_auto_aim_target(
	camera: Camera3D, player_pos: Vector3, enemies: Array[Node3D],
) -> Optional:
	"""Find the best enemy to auto-aim at on mobile."""
	if not auto_aim_enabled or not _is_mobile:
		return null

	var best_target: Node3D = null
	var best_score: float = -INF

	var cam_forward := -camera.global_basis.z

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var to_enemy := (enemy.global_position - player_pos)
		var distance := to_enemy.length()

		if distance > auto_aim_range:
			continue

		# Angle between camera forward and enemy direction
		var angle := cam_forward.angle_to(to_enemy.normalized())
		if angle > auto_aim_angle:
			continue

		# Score: closer + more centered = better target
		var score := (1.0 - distance / auto_aim_range) + (1.0 - angle / auto_aim_angle)
		if score > best_score:
			best_score = score
			best_target = enemy

	return best_target
