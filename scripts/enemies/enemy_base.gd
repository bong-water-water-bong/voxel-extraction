extends CharacterBody3D
class_name EnemyBase

## Base enemy AI — patrol, detect, chase, attack.
## Subclass for specific enemy types (melee, ranged, boss).

enum State { IDLE, PATROL, ALERT, CHASE, ATTACK, DEAD }

@export var max_health: int = 50
@export var move_speed: float = 3.5
@export var chase_speed: float = 6.0
@export var attack_damage: int = 15
@export var attack_range: float = 2.0
@export var detection_range: float = 15.0
@export var attack_cooldown: float = 1.5
@export var patrol_radius: float = 10.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var health: int
var state: State = State.IDLE
var target: PlayerController = null
var attack_timer: float = 0.0
var home_position: Vector3
var patrol_target: Vector3

signal damaged(amount: int)
signal died(enemy: EnemyBase)
signal alert_nearby(position: Vector3)

func _ready() -> void:
	health = max_health
	home_position = global_position
	_pick_patrol_point()

func _physics_process(delta: float) -> void:
	match state:
		State.IDLE:
			_idle_behavior(delta)
		State.PATROL:
			_patrol_behavior(delta)
		State.ALERT:
			_alert_behavior(delta)
		State.CHASE:
			_chase_behavior(delta)
		State.ATTACK:
			_attack_behavior(delta)
		State.DEAD:
			return

	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()

func _idle_behavior(_delta: float) -> void:
	_scan_for_players()
	# Randomly start patrolling
	if randf() < 0.01:
		state = State.PATROL
		_pick_patrol_point()

func _patrol_behavior(_delta: float) -> void:
	_scan_for_players()
	nav_agent.target_position = patrol_target
	if nav_agent.is_navigation_finished():
		state = State.IDLE
		return
	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	_face_direction(direction)

func _alert_behavior(_delta: float) -> void:
	# Brief pause before chasing
	await get_tree().create_timer(0.5).timeout
	if target and is_instance_valid(target) and not target.is_dead:
		state = State.CHASE
	else:
		state = State.IDLE

func _chase_behavior(_delta: float) -> void:
	if not target or not is_instance_valid(target) or target.is_dead:
		state = State.IDLE
		target = null
		return

	var dist := global_position.distance_to(target.global_position)
	if dist <= attack_range:
		state = State.ATTACK
		velocity.x = 0
		velocity.z = 0
		return

	if dist > detection_range * 1.5:
		state = State.IDLE
		target = null
		return

	nav_agent.target_position = target.global_position
	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()
	velocity.x = direction.x * chase_speed
	velocity.z = direction.z * chase_speed
	_face_direction(direction)

func _attack_behavior(delta: float) -> void:
	if not target or not is_instance_valid(target) or target.is_dead:
		state = State.IDLE
		target = null
		return

	var dist := global_position.distance_to(target.global_position)
	if dist > attack_range * 1.5:
		state = State.CHASE
		return

	_face_direction((target.global_position - global_position).normalized())
	attack_timer -= delta
	if attack_timer <= 0.0:
		_perform_attack()
		attack_timer = attack_cooldown

func _perform_attack() -> void:
	if target and is_instance_valid(target):
		target.take_damage(attack_damage, self)

func _scan_for_players() -> void:
	var players := get_tree().get_nodes_in_group("players")
	for node in players:
		if node is PlayerController and not node.is_dead:
			var dist := global_position.distance_to(node.global_position)
			if dist <= detection_range:
				target = node
				state = State.ALERT
				alert_nearby.emit(global_position)
				return

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	health -= amount
	damaged.emit(amount)
	if health <= 0:
		_die()
	elif state == State.IDLE or state == State.PATROL:
		# Getting hit wakes us up
		_scan_for_players()
		if not target:
			state = State.ALERT

func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	died.emit(self)
	# Drop loot
	var loot := LootTable.generate_loot(GameManager.difficulty, randi_range(1, 3))
	for item in loot:
		LootTable.spawn_dropped_item(item, global_position)
	# Cleanup after death animation
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.5)
	await tween.finished
	queue_free()

func _pick_patrol_point() -> void:
	var offset := Vector3(
		randf_range(-patrol_radius, patrol_radius),
		0,
		randf_range(-patrol_radius, patrol_radius)
	)
	patrol_target = home_position + offset

func _face_direction(direction: Vector3) -> void:
	if direction.length_squared() > 0.001:
		var look_target := global_position + direction
		look_target.y = global_position.y
		look_at(look_target, Vector3.UP)
