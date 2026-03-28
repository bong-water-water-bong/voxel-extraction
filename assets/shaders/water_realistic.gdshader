shader_type spatial;

// Realistic water on voxel geometry.
// Real wave simulation, refraction, caustics, foam, depth fade,
// subsurface scattering — all on flat voxel faces.
// The juxtaposition of blocky geometry and photorealistic water IS the look.

render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx, diffuse_burley;

// Core water properties
group_uniforms water;
uniform vec4 shallow_color : source_color = vec4(0.1, 0.4, 0.5, 0.7);
uniform vec4 deep_color : source_color = vec4(0.02, 0.08, 0.15, 0.95);
uniform float depth_fade_distance : hint_range(0.5, 20.0) = 5.0;
uniform float clarity : hint_range(0.0, 1.0) = 0.6;

// Wave simulation — two layers of Gerstner waves
group_uniforms waves;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.8;
uniform float wave_strength : hint_range(0.0, 0.5) = 0.08;
uniform vec2 wave_direction_1 : hint_range(-1.0, 1.0) = vec2(1.0, 0.6);
uniform vec2 wave_direction_2 : hint_range(-1.0, 1.0) = vec2(-0.7, 1.0);
uniform float wave_frequency_1 : hint_range(0.5, 10.0) = 3.0;
uniform float wave_frequency_2 : hint_range(0.5, 10.0) = 5.0;
uniform float wave_amplitude_1 : hint_range(0.0, 0.2) = 0.04;
uniform float wave_amplitude_2 : hint_range(0.0, 0.1) = 0.02;

// Surface detail
group_uniforms surface;
uniform sampler2D normal_map_1 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map_2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(0.1, 4.0) = 1.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.8;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.9;

// Refraction
group_uniforms refraction;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.02;

// Foam
group_uniforms foam;
uniform vec4 foam_color : source_color = vec4(0.9, 0.95, 1.0, 0.8);
uniform float foam_threshold : hint_range(0.0, 2.0) = 0.5;
uniform float foam_softness : hint_range(0.01, 1.0) = 0.3;
uniform float foam_scale : hint_range(1.0, 20.0) = 8.0;

// Caustics
group_uniforms caustics;
uniform float caustic_strength : hint_range(0.0, 2.0) = 0.5;
uniform float caustic_scale : hint_range(1.0, 20.0) = 8.0;
uniform float caustic_speed : hint_range(0.0, 2.0) = 0.5;

// Subsurface scattering
group_uniforms subsurface;
uniform vec4 sss_color : source_color = vec4(0.0, 0.6, 0.4, 1.0);
uniform float sss_strength : hint_range(0.0, 2.0) = 0.4;

varying vec3 world_pos;
varying float vertex_height;

// ── Noise functions ───────────────────────────────────────────

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x),
		f.y
	);
}

float voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_dist = 1.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = vec2(hash(i + neighbor), hash((i + neighbor) * 1.3));
			min_dist = min(min_dist, length(neighbor + point - f));
		}
	}
	return min_dist;
}

// ── Gerstner wave ─────────────────────────────────────────────

vec3 gerstner_wave(vec2 pos, vec2 direction, float frequency, float amplitude, float speed, float time) {
	float phase = dot(normalize(direction), pos) * frequency + time * speed;
	float s = sin(phase);
	float c = cos(phase);
	return vec3(
		direction.x * amplitude * c,
		amplitude * s,
		direction.y * amplitude * c
	);
}

// ── Caustic pattern ───────────────────────────────────────────

float caustic_pattern(vec2 uv, float time) {
	float v1 = voronoi(uv * caustic_scale + time * caustic_speed);
	float v2 = voronoi(uv * caustic_scale * 1.3 - time * caustic_speed * 0.8 + 3.7);
	// Sharp caustic lines from voronoi edges
	float c = pow(1.0 - v1, 3.0) + pow(1.0 - v2, 3.0);
	return c * 0.5;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Gerstner wave displacement — waves on voxel water surface
	vec3 wave1 = gerstner_wave(world_pos.xz, wave_direction_1, wave_frequency_1, wave_amplitude_1, wave_speed, TIME);
	vec3 wave2 = gerstner_wave(world_pos.xz, wave_direction_2, wave_frequency_2, wave_amplitude_2, wave_speed * 1.3, TIME);

	vec3 displacement = wave1 + wave2;
	VERTEX.y += displacement.y * wave_strength;
	VERTEX.x += displacement.x * wave_strength * 0.3;
	VERTEX.z += displacement.z * wave_strength * 0.3;

	vertex_height = displacement.y;

	// Compute wave normal from displacement
	float dx = wave_strength * (
		-wave_direction_1.x * wave_frequency_1 * wave_amplitude_1 * cos(dot(normalize(wave_direction_1), world_pos.xz) * wave_frequency_1 + TIME * wave_speed) +
		-wave_direction_2.x * wave_frequency_2 * wave_amplitude_2 * cos(dot(normalize(wave_direction_2), world_pos.xz) * wave_frequency_2 + TIME * wave_speed * 1.3)
	);
	float dz = wave_strength * (
		-wave_direction_1.y * wave_frequency_1 * wave_amplitude_1 * cos(dot(normalize(wave_direction_1), world_pos.xz) * wave_frequency_1 + TIME * wave_speed) +
		-wave_direction_2.y * wave_frequency_2 * wave_amplitude_2 * cos(dot(normalize(wave_direction_2), world_pos.xz) * wave_frequency_2 + TIME * wave_speed * 1.3)
	);
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
	// ── Scrolling normal maps for micro detail ────────────────
	vec2 uv1 = world_pos.xz * normal_scale + TIME * wave_speed * 0.05 * wave_direction_1;
	vec2 uv2 = world_pos.xz * normal_scale * 1.4 - TIME * wave_speed * 0.03 * wave_direction_2;

	vec3 n1 = texture(normal_map_1, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_map_2, uv2).rgb * 2.0 - 1.0;

	// Blend normals (Reoriented Normal Mapping)
	vec3 detail_normal = normalize(vec3(
		n1.xy * normal_strength + n2.xy * normal_strength * 0.6,
		1.0
	));
	NORMAL_MAP = detail_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;

	// ── Depth-based effects ───────────────────────────────────
	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 world_depth_pos = INV_PROJECTION_MATRIX * ndc;
	world_depth_pos /= world_depth_pos.w;
	float depth = -world_depth_pos.z - (-VERTEX.z);
	depth = max(depth, 0.0);
	float depth_factor = clamp(depth / depth_fade_distance, 0.0, 1.0);

	// ── Color from depth ──────────────────────────────────────
	vec3 water_color = mix(shallow_color.rgb, deep_color.rgb, depth_factor);

	// ── Refraction ────────────────────────────────────────────
	vec2 refraction_offset = detail_normal.xy * refraction_strength;
	vec3 refracted = texture(SCREEN_TEXTURE, SCREEN_UV + refraction_offset).rgb;
	water_color = mix(refracted, water_color, mix(shallow_color.a, deep_color.a, depth_factor));

	// ── Caustics (projected onto underwater surfaces) ─────────
	float caustics = caustic_pattern(world_pos.xz, TIME) * caustic_strength;
	caustics *= (1.0 - depth_factor);  // Fade with depth
	water_color += vec3(caustics) * vec3(0.6, 0.8, 1.0);

	// ── Foam at edges (where water meets voxels) ──────────────
	float foam_noise = noise(world_pos.xz * foam_scale + TIME * 0.5);
	float foam_mask = smoothstep(foam_threshold, foam_threshold - foam_softness, depth);
	foam_mask *= foam_noise;
	// Wave crest foam
	float crest_foam = smoothstep(0.02, 0.06, vertex_height) * 0.5;
	foam_mask = max(foam_mask, crest_foam);
	water_color = mix(water_color, foam_color.rgb, foam_mask * foam_color.a);

	// ── Subsurface scattering ─────────────────────────────────
	float sss = pow(max(dot(VIEW, NORMAL), 0.0), 3.0) * sss_strength;
	sss *= (1.0 - depth_factor);
	water_color += sss_color.rgb * sss;

	// ── Fresnel (more reflective at glancing angles) ──────────
	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 5.0);
	fresnel = mix(0.02, 1.0, fresnel);  // Schlick approximation

	ALBEDO = water_color;
	ALPHA = mix(shallow_color.a, 1.0, depth_factor);
	ROUGHNESS = mix(roughness, roughness * 0.5, foam_mask);  // Foam is rougher
	METALLIC = metallic;
	SPECULAR = specular_intensity * fresnel;

	// Subsurface for translucency through thin water
	SSS_STRENGTH = sss_strength * (1.0 - depth_factor);
}
