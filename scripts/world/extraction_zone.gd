extends Area3D
class_name ExtractionZone

## An extraction point in the world.
## Players enter the zone and hold F to begin extraction.
## During extraction, enemies surge toward the zone.

@export var zone_name: String = "Extract Alpha"
@export var is_active: bool = true

@onready var marker: MeshInstance3D = $Marker
@onready var particles: GPUParticles3D = $Particles

func _ready() -> void:
	ExtractionManager.register_zone(self)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _exit_tree() -> void:
	ExtractionManager.unregister_zone(self)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController and is_active:
		# Show extraction prompt on HUD
		print("[%s] Press F to extract" % zone_name)

func _on_body_exited(body: Node3D) -> void:
	if body is PlayerController:
		ExtractionManager.cancel_extraction(body)
