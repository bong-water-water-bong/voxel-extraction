extends Node
class_name CheaterPunishment

## The Wall of Shame.
## Cheaters get branded: pink avatar, permanent flag, public broadcast.
## Only way out is a new account.

const CHEATER_COLOR := Color(1.0, 0.41, 0.71)  # Hot pink
const CHEATER_SAVE_PATH := "user://cheater_registry.json"

# In-memory registry for current session
static var _flagged_players: Dictionary = {}  # player_id -> flag data

signal cheater_flagged(player_id: String, reason: String)
signal cheater_broadcast(message: String)

func flag_cheater(player_id: String, player_name: String, reason: String, violations: int) -> void:
	var flag_data := {
		"player_id": player_id,
		"player_name": player_name,
		"reason": reason,
		"violations": violations,
		"flagged_at": Time.get_datetime_string_from_system(),
		"permanent": true,
		"avatar_color": [CHEATER_COLOR.r, CHEATER_COLOR.g, CHEATER_COLOR.b],
	}

	_flagged_players[player_id] = flag_data
	_save_registry()

	# Broadcast to all players in the session
	var msg := "[WARDEN] %s has been FLAGGED FOR CHEATING. Reason: %s. Their avatar is now permanently pink." % [player_name, reason]
	cheater_broadcast.emit(msg)
	cheater_flagged.emit(player_id, reason)
	push_warning(msg)

func is_cheater(player_id: String) -> bool:
	if _flagged_players.has(player_id):
		return true
	# Also check persistent storage
	var registry := _load_registry()
	return registry.has(player_id)

func get_cheater_data(player_id: String) -> Dictionary:
	if _flagged_players.has(player_id):
		return _flagged_players[player_id]
	var registry := _load_registry()
	if registry.has(player_id):
		return registry[player_id]
	return {}

func get_avatar_color(player_id: String) -> Color:
	if is_cheater(player_id):
		return CHEATER_COLOR  # Permanent pink. No appeal.
	return Color.WHITE  # Normal

func apply_cheater_debuffs(player: PlayerController) -> void:
	# Cheaters get handicapped too
	player.walk_speed *= 0.7       # slower
	player.sprint_speed *= 0.7     # slower sprint
	player.max_carry_weight *= 0.5 # carry less loot
	# Their name tag gets the shame prefix
	# Handled by UI layer reading is_cheater()

func get_all_cheaters() -> Dictionary:
	var registry := _load_registry()
	# Merge with in-memory
	for id in _flagged_players:
		registry[id] = _flagged_players[id]
	return registry

func _save_registry() -> void:
	var file := FileAccess.open(CHEATER_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[WARDEN] Failed to save cheater registry")
		return
	var all_cheaters := get_all_cheaters()
	file.store_string(JSON.stringify(all_cheaters, "\t"))
	file.close()

func _load_registry() -> Dictionary:
	if not FileAccess.file_exists(CHEATER_SAVE_PATH):
		return {}
	var file := FileAccess.open(CHEATER_SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}
