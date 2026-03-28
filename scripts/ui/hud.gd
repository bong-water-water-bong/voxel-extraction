extends CanvasLayer
class_name HUD

## In-raid HUD — health, stamina, raid timer, extraction progress,
## minimap, loot weight, crosshair. Dark glass aesthetic.

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/TopBar/HealthBar
@onready var stamina_bar: ProgressBar = $MarginContainer/VBoxContainer/TopBar/StaminaBar
@onready var timer_label: Label = $MarginContainer/VBoxContainer/TopBar/TimerLabel
@onready var weight_label: Label = $MarginContainer/VBoxContainer/BottomBar/WeightLabel
@onready var extraction_bar: ProgressBar = $ExtractionProgress
@onready var extraction_label: Label = $ExtractionProgress/Label
@onready var warning_label: Label = $WarningLabel
@onready var crosshair: TextureRect = $Crosshair
@onready var interact_prompt: Label = $InteractPrompt
@onready var debug_label: Label = $DebugLabel

var player: PlayerController

func _ready() -> void:
	extraction_bar.visible = false
	warning_label.visible = false
	interact_prompt.visible = false

	# Connect signals
	GameManager.raid_timer_updated.connect(_on_timer_updated)
	GameManager.raid_warning.connect(_on_raid_warning)
	GameManager.state_changed.connect(_on_state_changed)
	ExtractionManager.extraction_progress.connect(_on_extraction_progress)
	ExtractionManager.extraction_cancelled.connect(_on_extraction_cancelled)
	ExtractionManager.extraction_complete.connect(_on_extraction_complete)

func bind_player(p: PlayerController) -> void:
	player = p
	player.health_changed.connect(_on_health_changed)
	player.stamina_changed.connect(_on_stamina_changed)
	player.item_picked_up.connect(_on_item_picked_up)
	_on_health_changed(player.health)
	_on_stamina_changed(player.stamina)

func _process(_delta: float) -> void:
	if player:
		weight_label.text = "%.1f / %.1f kg" % [player.carry_weight, player.max_carry_weight]

func _on_health_changed(new_health: int) -> void:
	health_bar.value = new_health
	if new_health < 30:
		health_bar.modulate = Color(1, 0.3, 0.3)
	else:
		health_bar.modulate = Color(0.3, 1, 0.3)

func _on_stamina_changed(new_stamina: float) -> void:
	stamina_bar.value = new_stamina

func _on_timer_updated(time_remaining: float) -> void:
	var minutes := int(time_remaining) / 60
	var seconds := int(time_remaining) % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]
	if time_remaining < 120:
		timer_label.modulate = Color(1, 0.3, 0.2)
	elif time_remaining < 300:
		timer_label.modulate = Color(1, 0.8, 0.2)
	else:
		timer_label.modulate = Color(1, 1, 1)

func _on_raid_warning(message: String) -> void:
	warning_label.text = message
	warning_label.visible = true
	var tween := create_tween()
	tween.tween_property(warning_label, "modulate:a", 1.0, 0.2)
	tween.tween_interval(3.0)
	tween.tween_property(warning_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func(): warning_label.visible = false)

func _on_extraction_progress(_player: PlayerController, progress: float) -> void:
	extraction_bar.visible = true
	extraction_bar.value = progress * 100.0
	extraction_label.text = "EXTRACTING... %d%%" % [int(progress * 100)]

func _on_extraction_cancelled(_player: PlayerController) -> void:
	extraction_bar.visible = false

func _on_extraction_complete(_player: PlayerController) -> void:
	extraction_bar.visible = false
	warning_label.text = "EXTRACTED!"
	warning_label.modulate = Color(0, 1, 0.5)
	warning_label.visible = true

func _on_state_changed(new_state: GameManager.GameState) -> void:
	match new_state:
		GameManager.GameState.DEAD:
			warning_label.text = "YOU DIED"
			warning_label.modulate = Color(1, 0.2, 0.1)
			warning_label.visible = true

func _on_item_picked_up(item: Dictionary) -> void:
	# Flash the item name
	var rarity_name := LootTable.get_rarity_name(item.get("rarity", 0))
	var color := LootTable.get_rarity_color(item.get("rarity", 0))
	interact_prompt.text = "+ %s (%s)" % [item.get("name", "Item"), rarity_name]
	interact_prompt.modulate = color
	interact_prompt.visible = true
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(interact_prompt, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): interact_prompt.visible = false)

func show_interact_prompt(text: String) -> void:
	interact_prompt.text = text
	interact_prompt.modulate = Color(1, 1, 1, 1)
	interact_prompt.visible = true

func hide_interact_prompt() -> void:
	interact_prompt.visible = false
