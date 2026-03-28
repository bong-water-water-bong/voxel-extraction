extends Node

## Global game state manager.
## Handles raid lifecycle: deploy -> loot -> extract or die.

enum GameState {
	MENU,
	DEPLOYING,
	IN_RAID,
	EXTRACTING,
	EXTRACTED,
	DEAD,
}

var state: GameState = GameState.MENU
var raid_timer: float = 0.0
var raid_duration: float = 2400.0  # 40 minute levels
var difficulty: int = 1
var players: Array[PlayerController] = []

signal state_changed(new_state: GameState)
signal raid_timer_updated(time_remaining: float)
signal raid_warning(message: String)

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if state == GameState.IN_RAID:
		raid_timer -= delta
		raid_timer_updated.emit(raid_timer)

		# Warnings at time thresholds
		if raid_timer <= 600.0 and raid_timer > 599.0:
			raid_warning.emit("10 MINUTES REMAINING")
		elif raid_timer <= 300.0 and raid_timer > 299.0:
			raid_warning.emit("5 MINUTES — START HEADING TO EXTRACTION")
		elif raid_timer <= 120.0 and raid_timer > 119.0:
			raid_warning.emit("2 MINUTES — GET TO EXTRACTION NOW")
		elif raid_timer <= 60.0 and raid_timer > 59.0:
			raid_warning.emit("60 SECONDS — RUN")
		elif raid_timer <= 30.0 and raid_timer > 29.0:
			raid_warning.emit("30 SECONDS — EXTRACT OR LOSE EVERYTHING")
		elif raid_timer <= 0.0:
			_raid_expired()

func start_raid(selected_difficulty: int = 1) -> void:
	difficulty = selected_difficulty
	raid_timer = raid_duration
	state = GameState.DEPLOYING
	state_changed.emit(state)
	# After deploy animation, transition to IN_RAID
	await get_tree().create_timer(3.0).timeout
	state = GameState.IN_RAID
	state_changed.emit(state)

func extraction_complete(player: PlayerController) -> void:
	state = GameState.EXTRACTED
	state_changed.emit(state)
	# Player keeps their loot — transfer to stash
	for item in player.inventory:
		_add_to_stash(item)

func player_died(player: PlayerController) -> void:
	state = GameState.DEAD
	state_changed.emit(state)
	# Loot is lost — already dropped in player_controller._die()

func _raid_expired() -> void:
	# Time's up — everything is lost
	state = GameState.DEAD
	state_changed.emit(state)
	raid_warning.emit("TIME'S UP — YOU DIDN'T MAKE IT OUT")

func _add_to_stash(item: Dictionary) -> void:
	# TODO: persistent stash storage
	print("Stashed: ", item.get("name", "unknown"))

func get_raid_time_remaining() -> float:
	return max(0.0, raid_timer)

func get_raid_time_string() -> String:
	var minutes := int(raid_timer) / 60
	var seconds := int(raid_timer) % 60
	return "%02d:%02d" % [minutes, seconds]
