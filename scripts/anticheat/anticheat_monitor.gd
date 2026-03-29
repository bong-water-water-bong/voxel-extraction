extends Node
class_name AntiCheatMonitor

## The Warden — runtime anti-cheat monitoring system.
## Validates game state integrity every tick, detects speed hacks,
## teleportation, impossible damage, inventory manipulation.

# Thresholds
const MAX_SPEED: float = 12.0  # sprint + slight tolerance
const MAX_TELEPORT_DISTANCE: float = 5.0  # per frame
const MAX_DAMAGE_PER_HIT: int = 200
const MAX_ITEMS_PER_SECOND: int = 5
const INTEGRITY_CHECK_INTERVAL: float = 0.5
const VIOLATION_THRESHOLD: int = 5  # kicks after this many

# State tracking
var _last_position: Vector3 = Vector3.ZERO
var _last_health: int = 0
var _items_picked_this_second: int = 0
var _item_timer: float = 0.0
var _integrity_timer: float = 0.0
var _violation_count: int = 0
var _player: PlayerController = null
var _active: bool = false
var _frame_count: int = 0

# Snapshots for integrity checking
var _health_snapshot: int = 0
var _stamina_snapshot: float = 0.0
var _inventory_hash: int = 0

signal violation_detected(type: String, details: Dictionary)
signal player_kicked(reason: String)

func start_monitoring(player: PlayerController) -> void:
	_player = player
	_last_position = player.global_position
	_last_health = player.health
	_active = true
	_take_snapshot()
	print("[WARDEN] Anti-cheat monitoring active")

func stop_monitoring() -> void:
	_active = false
	_player = null
	print("[WARDEN] Anti-cheat monitoring stopped")

func _process(delta: float) -> void:
	if not _active or _player == null or _player.is_dead:
		return

	_frame_count += 1

	_check_speed_hack(delta)
	_check_teleport()
	_check_health_manipulation()
	_check_item_rate(delta)

	# Periodic deep integrity check
	_integrity_timer += delta
	if _integrity_timer >= INTEGRITY_CHECK_INTERVAL:
		_integrity_timer = 0.0
		_check_integrity()
		_take_snapshot()

	_last_position = _player.global_position

func _check_speed_hack(delta: float) -> void:
	if delta <= 0.0:
		return
	var displacement := _player.global_position - _last_position
	displacement.y = 0  # ignore vertical (falling/jumping)
	var speed := displacement.length() / delta
	if speed > MAX_SPEED and _player.is_on_floor():
		_flag("speed_hack", {"speed": speed, "max": MAX_SPEED})

func _check_teleport() -> void:
	var dist := _player.global_position.distance_to(_last_position)
	# Allow large moves on first few frames (spawn)
	if dist > MAX_TELEPORT_DISTANCE and _frame_count > 60:
		_flag("teleport", {"distance": dist, "from": _last_position, "to": _player.global_position})

func _check_health_manipulation() -> void:
	var current_health: int
	if _player.get("_guarded_health"):
		current_health = _player._guarded_health.get_value()
	else:
		current_health = _player.health

	# Health went UP without a heal call
	if current_health > _last_health and current_health != _player.max_health:
		# Could be legitimate heal — only flag big jumps
		var gain := current_health - _last_health
		if gain > 50:
			_flag("health_manipulation", {"old": _last_health, "new": current_health, "gain": gain})

	_last_health = current_health

func _check_item_rate(delta: float) -> void:
	_item_timer += delta
	if _item_timer >= 1.0:
		if _items_picked_this_second > MAX_ITEMS_PER_SECOND:
			_flag("item_spam", {"items_per_second": _items_picked_this_second})
		_items_picked_this_second = 0
		_item_timer = 0.0

func on_item_picked() -> void:
	_items_picked_this_second += 1

func _check_integrity() -> void:
	# Check GuardedValue violations
	var violations := GuardedValue.get_violations()
	if violations.size() > 0:
		for v in violations:
			_flag("memory_tamper", v)
		GuardedValue.clear_violations()

	# Verify inventory hasn't been injected into
	var current_hash := _hash_inventory()
	if current_hash != _inventory_hash and _frame_count > 120:
		# Inventory changed — that's normal during gameplay
		# But check for impossible items
		_check_impossible_items()

func _take_snapshot() -> void:
	if _player == null:
		return
	if _player.get("_guarded_health"):
		_health_snapshot = _player._guarded_health.get_value()
	else:
		_health_snapshot = _player.health
	_stamina_snapshot = _player.stamina
	_inventory_hash = _hash_inventory()

func _hash_inventory() -> int:
	if _player == null:
		return 0
	var h: int = 0x811C9DC5  # FNV offset basis
	for item in _player.inventory:
		var name_str: String = item.get("name", "")
		for i in name_str.length():
			h = (h ^ name_str.unicode_at(i)) * 0x01000193
		h = h ^ int(item.get("weight", 0) * 1000)
	return h & 0x7FFFFFFF

func _check_impossible_items() -> void:
	for item in _player.inventory:
		var weight: float = item.get("weight", 1.0)
		if weight <= 0.0 or weight > 100.0:
			_flag("impossible_item", {"item": item})
		var rarity: String = item.get("rarity", "common")
		if rarity not in ["common", "uncommon", "rare", "epic", "legendary"]:
			_flag("invalid_rarity", {"item": item, "rarity": rarity})

func _flag(type: String, details: Dictionary) -> void:
	_violation_count += 1
	details["violation_number"] = _violation_count
	details["timestamp"] = Time.get_ticks_msec()
	push_warning("[WARDEN] VIOLATION #%d: %s — %s" % [_violation_count, type, str(details)])
	violation_detected.emit(type, details)

	if _violation_count >= VIOLATION_THRESHOLD:
		var reason := "Too many anti-cheat violations (%d)" % _violation_count
		push_warning("[WARDEN] KICKING PLAYER: %s" % reason)
		player_kicked.emit(reason)

func get_violation_count() -> int:
	return _violation_count

func get_status() -> Dictionary:
	return {
		"active": _active,
		"violations": _violation_count,
		"threshold": VIOLATION_THRESHOLD,
		"frames_monitored": _frame_count,
	}
