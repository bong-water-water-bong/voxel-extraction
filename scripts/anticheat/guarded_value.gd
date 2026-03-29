class_name GuardedValue
extends RefCounted

## Encrypted in-memory value storage.
## XOR-encrypts values with rotating keys so memory scanners
## never see the real number. Includes integrity verification.

var _encrypted: int = 0
var _key: int = 0
var _checksum: int = 0
var _decoy: int = 0  # fake value for scanners to find
var _name: String = ""

static var _violations: Array[Dictionary] = []
static var _master_salt: int = 0

static func init_master_salt() -> void:
	_master_salt = randi() ^ (Time.get_ticks_msec() * 31337)

func _init(initial_value: int = 0, value_name: String = "") -> void:
	if _master_salt == 0:
		init_master_salt()
	_name = value_name
	set_value(initial_value)

func set_value(val: int) -> void:
	# Rotate key every write
	_key = randi() ^ Time.get_ticks_msec() ^ _master_salt
	if _key == 0:
		_key = 0xDEADBEEF
	_encrypted = val ^ _key
	_checksum = _compute_checksum(val)
	# Decoy looks real but is garbage — honeypot for scanners
	_decoy = val + randi_range(-5, 5)

func get_value() -> int:
	var val: int = _encrypted ^ _key
	if _compute_checksum(val) != _checksum:
		_report_violation("integrity_fail", _name, val)
		return 0  # return safe value on tamper
	return val

func _compute_checksum(val: int) -> int:
	# Simple hash — not cryptographic, just tamper detection
	return ((val * 2654435761) ^ _master_salt) & 0x7FFFFFFF

static func _report_violation(type: String, name: String, value: int) -> void:
	var v := {
		"type": type,
		"name": name,
		"value": value,
		"time": Time.get_ticks_msec(),
		"frame": Engine.get_process_frames(),
	}
	_violations.append(v)
	push_warning("[ANTICHEAT] Violation: %s on '%s' (value=%d)" % [type, name, value])

static func get_violations() -> Array[Dictionary]:
	return _violations

static func clear_violations() -> void:
	_violations.clear()
