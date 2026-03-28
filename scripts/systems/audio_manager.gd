extends Node

## Central audio manager — handles SFX, music, and ambient layers.

var music_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_pool_size: int = 16

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)

	ambient_player = AudioStreamPlayer.new()
	ambient_player.bus = "Ambient"
	add_child(ambient_player)

	for i in sfx_pool_size:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		sfx_pool.append(player)

func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	for player in sfx_pool:
		if not player.playing:
			player.stream = stream
			player.volume_db = volume_db
			player.play()
			return

func play_music(stream: AudioStream, fade_time: float = 2.0) -> void:
	if music_player.playing:
		var tween := create_tween()
		tween.tween_property(music_player, "volume_db", -40.0, fade_time)
		await tween.finished
	music_player.stream = stream
	music_player.volume_db = -40.0
	music_player.play()
	var tween := create_tween()
	tween.tween_property(music_player, "volume_db", 0.0, fade_time)

func play_ambient(stream: AudioStream) -> void:
	ambient_player.stream = stream
	ambient_player.play()

func stop_music(fade_time: float = 2.0) -> void:
	if music_player.playing:
		var tween := create_tween()
		tween.tween_property(music_player, "volume_db", -40.0, fade_time)
		await tween.finished
		music_player.stop()
