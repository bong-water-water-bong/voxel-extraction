extends CharacterBody3D
class_name PlayerController

## First-person player controller for voxel extraction.
## WASD movement, sprint, jump, mouse look, interaction.

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 6.0
@export var mouse_sensitivity: float = 0.002
@export var max_health: int = 100
@export var max_stamina: float = 100.0
@export var stamina_drain: float = 20.0
@export var stamina_regen: float = 15.0

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $Camera3D/InteractRay
@onready var hud: Control = $HUD
@onready var hand: Node3D = $Camera3D/Hand

var health: int
var stamina: float
var is_sprinting: bool = false
var is_dead: bool = false
var inventory: Array[Dictionary] = []
var carry_weight: float = 0.0
var max_carry_weight: float = 50.0

signal health_changed(new_health: int)
signal stamina_changed(new_stamina: float)
signal died()
signal item_picked_up(item: Dictionary)
signal extraction_started()

func _ready() -> void:
	health = max_health
	stamina = max_stamina
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -PI / 2, PI / 2)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Sprint
	is_sprinting = Input.is_action_pressed("sprint") and stamina > 0.0
	var speed := sprint_speed if is_sprinting else walk_speed

	# Weight penalty
	var weight_ratio := carry_weight / max_carry_weight
	speed *= lerp(1.0, 0.5, clamp(weight_ratio, 0.0, 1.0))

	# Stamina
	if is_sprinting and is_on_floor():
		stamina = max(0.0, stamina - stamina_drain * delta)
		stamina_changed.emit(stamina)
	elif stamina < max_stamina:
		stamina = min(max_stamina, stamina + stamina_regen * delta)
		stamina_changed.emit(stamina)

	# Movement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

	# Interaction
	if Input.is_action_just_pressed("interact"):
		_try_interact()

	# Extraction
	if Input.is_action_just_pressed("extract"):
		_try_extract()

func _try_interact() -> void:
	if ray.is_colliding():
		var collider = ray.get_collider()
		if collider.has_method("interact"):
			collider.interact(self)

func _try_extract() -> void:
	if ExtractionManager.is_in_extraction_zone(global_position):
		extraction_started.emit()
		ExtractionManager.begin_extraction(self)

func take_damage(amount: int, source: Node3D = null) -> void:
	if is_dead:
		return
	health = max(0, health - amount)
	health_changed.emit(health)
	if health <= 0:
		_die()

func heal(amount: int) -> void:
	health = min(max_health, health + amount)
	health_changed.emit(health)

func pick_up_item(item: Dictionary) -> bool:
	var weight: float = item.get("weight", 1.0)
	if carry_weight + weight > max_carry_weight:
		return false
	inventory.append(item)
	carry_weight += weight
	item_picked_up.emit(item)
	return true

func _die() -> void:
	is_dead = true
	died.emit()
	# Drop loot on death — extraction failed
	for item in inventory:
		LootTable.spawn_dropped_item(item, global_position)
	inventory.clear()
	carry_weight = 0.0
