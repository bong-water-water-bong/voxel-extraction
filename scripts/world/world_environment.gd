extends WorldEnvironment
class_name VoxelWorldEnvironment

## Realistic environment setup — no raytracing, all rasterized.
## SDFGI for GI, SSAO, SSR, volumetric fog, glow, tonemap.
## This is what makes voxels look photorealistic.

@export var time_of_day: float = 0.4  # 0.0 = midnight, 0.5 = noon, 1.0 = midnight
@export var day_cycle_speed: float = 0.0  # 0 = static, >0 = realtime cycle
@export var extraction_panic: float = 0.0  # 0-1, increases fog/red tint as time runs out

@onready var sun: DirectionalLight3D = $Sun
@onready var env: Environment = environment

# Sky colors across the day
const SKY_COLORS := {
	"dawn": Color(0.9, 0.5, 0.3),
	"day": Color(0.4, 0.6, 0.9),
	"dusk": Color(0.8, 0.3, 0.2),
	"night": Color(0.02, 0.02, 0.06),
}

func _ready() -> void:
	_setup_environment()
	_setup_sun()
	_apply_time_of_day()

func _process(delta: float) -> void:
	if day_cycle_speed > 0.0:
		time_of_day = fmod(time_of_day + delta * day_cycle_speed / 600.0, 1.0)
		_apply_time_of_day()

	# Panic mode — extraction timer running out
	if extraction_panic > 0.0:
		_apply_panic()

func _setup_environment() -> void:
	env = Environment.new()
	environment = env

	# Background
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.45, 0.75)
	sky_mat.sky_horizon_color = Color(0.55, 0.65, 0.8)
	sky_mat.ground_bottom_color = Color(0.1, 0.08, 0.06)
	sky_mat.ground_horizon_color = Color(0.4, 0.35, 0.3)
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.15
	env.sky.sky_material = sky_mat

	# Tonemap — ACES for cinematic look
	env.tonemap_mode = Environment.TONE_MAP_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0

	# SDFGI — signed distance field global illumination (NO raytracing)
	env.sdfgi_enabled = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.5
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = 1.2
	env.sdfgi_bounce_feedback = 0.5
	env.sdfgi_read_sky_light = true

	# SSAO — screen space ambient occlusion
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 2.5
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.3

	# SSR — screen space reflections
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2

	# SSIL — screen space indirect lighting
	env.ssil_enabled = true
	env.ssil_radius = 5.0
	env.ssil_intensity = 1.0

	# Volumetric fog
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.9, 0.9, 0.95)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_emission_energy = 0.0
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 200.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 1.0
	env.volumetric_fog_ambient_inject = 0.0

	# Glow / bloom
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.2

	# Fog (distance)
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.65, 0.75)
	env.fog_light_energy = 0.3
	env.fog_sun_scatter = 0.3
	env.fog_density = 0.001
	env.fog_sky_affect = 0.5

	# Adjustments
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.05

func _setup_sun() -> void:
	if not sun:
		sun = DirectionalLight3D.new()
		add_child(sun)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.4
	sun.light_angular_distance = 1.0
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 200.0
	sun.light_bake_mode = Light3D.BAKE_STATIC

func _apply_time_of_day() -> void:
	if not sun:
		return
	# Sun angle based on time
	var angle := (time_of_day - 0.25) * TAU  # 0.25 = sunrise
	sun.rotation_degrees.x = rad_to_deg(angle)
	sun.rotation_degrees.y = -30.0

	# Sun intensity
	var sun_height := sin(angle)
	sun.light_energy = max(0.0, sun_height * 1.4)

	# Color temperature shift
	if sun_height > 0.0:
		var warmth := 1.0 - sun_height
		sun.light_color = Color(1.0, lerp(0.95, 0.7, warmth), lerp(0.85, 0.4, warmth))
	else:
		sun.light_energy = 0.0

	# Ambient at night
	if env:
		var night_factor := clamp(-sun_height, 0.0, 1.0)
		env.ambient_light_energy = lerp(0.3, 0.05, night_factor)
		env.ambient_light_color = lerp(Color(0.6, 0.65, 0.8), Color(0.05, 0.05, 0.15), night_factor)

func _apply_panic() -> void:
	if not env:
		return
	# Red fog creeping in as extraction timer runs out
	env.volumetric_fog_density = lerp(0.02, 0.08, extraction_panic)
	env.volumetric_fog_albedo = lerp(
		Color(0.9, 0.9, 0.95),
		Color(0.8, 0.2, 0.1),
		extraction_panic * 0.6
	)
	env.fog_light_color = lerp(
		Color(0.6, 0.65, 0.75),
		Color(0.6, 0.15, 0.05),
		extraction_panic * 0.4
	)
	# Bloom intensifies
	env.glow_intensity = lerp(0.8, 2.0, extraction_panic)

func set_extraction_panic(value: float) -> void:
	extraction_panic = clamp(value, 0.0, 1.0)
