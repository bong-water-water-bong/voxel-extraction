class_name GuardedFloat
extends RefCounted

## Same as GuardedValue but for floats.
## Stores as scaled integers to avoid float comparison issues.

const SCALE: int = 10000  # 4 decimal places of precision

var _inner: GuardedValue

func _init(initial_value: float = 0.0, value_name: String = "") -> void:
	_inner = GuardedValue.new(int(initial_value * SCALE), value_name)

func set_value(val: float) -> void:
	_inner.set_value(int(val * SCALE))

func get_value() -> float:
	return float(_inner.get_value()) / float(SCALE)
