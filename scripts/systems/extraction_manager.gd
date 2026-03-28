extends Node

## Manages extraction zones and the extraction process.
## Players must reach an extraction point, hold position, and survive
## a timed extraction while enemies converge on the zone.

@export var extraction_time: float = 20.0  # Seconds to extract
@export var enemy_surge_multiplier: float = 3.0  # Enemies ramp up during extraction

var extraction_zones: Array[Area3D] = []
var active_extraction: Dictionary = {}  # player -> {timer, zone}

signal extraction_progress(player: PlayerController, progress: float)
signal extraction_complete(player: PlayerController)
signal extraction_cancelled(player: PlayerController)
signal extraction_surge()  # Tells enemy spawner to send a wave

func register_zone(zone: Area3D) -> void:
	extraction_zones.append(zone)

func unregister_zone(zone: Area3D) -> void:
	extraction_zones.erase(zone)

func is_in_extraction_zone(pos: Vector3) -> bool:
	for zone in extraction_zones:
		if zone and zone.get_overlapping_bodies().size() > 0:
			return true
	return false

func begin_extraction(player: PlayerController) -> void:
	if active_extraction.has(player):
		return

	active_extraction[player] = {
		"timer": extraction_time,
		"started": true
	}
	# Alert enemies — extraction surge incoming
	extraction_surge.emit()

func cancel_extraction(player: PlayerController) -> void:
	if active_extraction.has(player):
		active_extraction.erase(player)
		extraction_cancelled.emit(player)

func _process(delta: float) -> void:
	var completed: Array[PlayerController] = []

	for player in active_extraction:
		var data: Dictionary = active_extraction[player]
		data["timer"] -= delta
		var progress := 1.0 - (data["timer"] / extraction_time)
		extraction_progress.emit(player, progress)

		if data["timer"] <= 0.0:
			completed.append(player)

	for player in completed:
		active_extraction.erase(player)
		extraction_complete.emit(player)
		GameManager.extraction_complete(player)
