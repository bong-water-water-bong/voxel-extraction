extends Node

## Platform-specific configuration.
## Detects platform at runtime and adjusts settings.
## Mobile gets lighter shaders, bigger UI, auto-aim, touch controls.
## Desktop gets full quality. dealer adapts difficulty per platform.

enum Platform {
	DESKTOP,
	MOBILE_IOS,
	MOBILE_ANDROID,
	CONSOLE,  # Future
}

var current_platform: Platform = Platform.DESKTOP
var is_mobile: bool = false

# Platform-specific overrides
var render_scale: float = 1.0
var shadow_quality: int = 3  # 0=off, 1=low, 2=med, 3=high
var sdfgi_enabled: bool = true
var ssao_enabled: bool = true
var ssil_enabled: bool = true
var ssr_enabled: bool = true
var volumetric_fog: bool = true
var max_enemies_per_room: int = 8
var ui_scale: float = 1.0
var auto_aim: bool = false
var haptic_feedback: bool = false
var target_fps: int = 60

# Mobile-specific
var touch_controls: bool = false
var reduced_draw_distance: bool = false
var simplified_water: bool = false
var chunk_render_distance: int = 6

func _ready() -> void:
	_detect_platform()
	_apply_platform_settings()

func _detect_platform() -> void:
	var os_name := OS.get_name()
	match os_name:
		"iOS":
			current_platform = Platform.MOBILE_IOS
			is_mobile = true
		"Android":
			current_platform = Platform.MOBILE_ANDROID
			is_mobile = true
		_:
			current_platform = Platform.DESKTOP
			is_mobile = false

func _apply_platform_settings() -> void:
	match current_platform:
		Platform.DESKTOP:
			_desktop_settings()
		Platform.MOBILE_IOS:
			_ios_settings()
		Platform.MOBILE_ANDROID:
			_android_settings()

func _desktop_settings() -> void:
	render_scale = 1.0
	shadow_quality = 3
	sdfgi_enabled = true
	ssao_enabled = true
	ssil_enabled = true
	ssr_enabled = true
	volumetric_fog = true
	max_enemies_per_room = 8
	ui_scale = 1.0
	auto_aim = false
	touch_controls = false
	chunk_render_distance = 6
	target_fps = 60

func _ios_settings() -> void:
	# iPhone — capable but needs optimization
	render_scale = 0.85
	shadow_quality = 2
	sdfgi_enabled = false  # Too heavy for mobile
	ssao_enabled = true    # Mobile SSAO is fine
	ssil_enabled = false   # Skip on mobile
	ssr_enabled = false    # Skip on mobile
	volumetric_fog = false # Use simpler fog
	max_enemies_per_room = 5
	ui_scale = 1.4         # Bigger touch targets
	auto_aim = true
	haptic_feedback = true
	touch_controls = true
	reduced_draw_distance = true
	simplified_water = true
	chunk_render_distance = 4
	target_fps = 60

func _android_settings() -> void:
	# Android — wider hardware range, be conservative
	render_scale = 0.75
	shadow_quality = 1
	sdfgi_enabled = false
	ssao_enabled = false
	ssil_enabled = false
	ssr_enabled = false
	volumetric_fog = false
	max_enemies_per_room = 4
	ui_scale = 1.5
	auto_aim = true
	haptic_feedback = true
	touch_controls = true
	reduced_draw_distance = true
	simplified_water = true
	chunk_render_distance = 3
	target_fps = 30  # Conservative for Android

func get_dealer_difficulty_modifier() -> float:
	"""dealer uses this to scale difficulty on mobile."""
	match current_platform:
		Platform.MOBILE_IOS:
			return 0.75  # 25% easier on iPhone
		Platform.MOBILE_ANDROID:
			return 0.65  # 35% easier on Android
		_:
			return 1.0   # Full difficulty on desktop

func get_quality_preset_name() -> String:
	match current_platform:
		Platform.DESKTOP: return "Ultra"
		Platform.MOBILE_IOS: return "High (Mobile)"
		Platform.MOBILE_ANDROID: return "Medium (Mobile)"
		_: return "Custom"
