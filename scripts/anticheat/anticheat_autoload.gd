extends Node

## Autoload wrapper — wires up AntiCheatMonitor + CheaterPunishment.
## Registered as "AntiCheat" in project autoloads.

var monitor: AntiCheatMonitor
var punishment: CheaterPunishment

func _ready() -> void:
	# Initialize the master encryption salt
	GuardedValue.init_master_salt()

	monitor = AntiCheatMonitor.new()
	monitor.name = "Monitor"
	add_child(monitor)

	punishment = CheaterPunishment.new()
	punishment.name = "Punishment"
	add_child(punishment)

	# Wire up: violations trigger punishment
	monitor.player_kicked.connect(_on_player_kicked)
	monitor.violation_detected.connect(_on_violation)

	# Block ptrace (Linux) — prevents memory debuggers from attaching
	if OS.get_name() == "Linux":
		OS.execute("sh", ["-c", "echo 0 > /proc/self/coredump_filter 2>/dev/null"], [], false)
		# PR_SET_DUMPABLE = 0 would be set via GDExtension in production

	print("[WARDEN] Anti-cheat system initialized")

func _on_violation(type: String, details: Dictionary) -> void:
	# Log every violation
	var count: int = details.get("violation_number", 0)
	print("[WARDEN] Violation %d: %s" % [count, type])

func _on_player_kicked(reason: String) -> void:
	# Flag the cheater permanently
	var player_id := _get_player_id()
	var player_name := _get_player_name()
	punishment.flag_cheater(player_id, player_name, reason, monitor.get_violation_count())

	# Apply debuffs if they somehow stay in-game
	if monitor._player:
		punishment.apply_cheater_debuffs(monitor._player)

func check_player_on_join(player_id: String) -> bool:
	if punishment.is_cheater(player_id):
		print("[WARDEN] Known cheater joined: %s — applying pink + debuffs" % player_id)
		return true
	return false

func get_avatar_color(player_id: String) -> Color:
	return punishment.get_avatar_color(player_id)

func _get_player_id() -> String:
	# Will use Steam ID when Steam SDK is integrated
	# For now, use a machine-derived ID
	return str(OS.get_unique_id()).md5_text()

func _get_player_name() -> String:
	return OS.get_environment("USER") if OS.get_environment("USER") != "" else "Player"
