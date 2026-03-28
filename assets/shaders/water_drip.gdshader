shader_type spatial;

// Wet surface / dripping water shader.
// For dungeon walls and ceilings where water seeps through.
// Animated drip trails, wet patches, glistening highlights.
// Apply to voxel surfaces near water sources.

render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx, diffuse_burley;

uniform vec4 base_color : source_color = vec4(0.35, 0.33, 0.30, 1.0);
uniform vec4 wet_tint : source_color = vec4(0.20, 0.22, 0.25, 1.0);

group_uniforms wetness;
uniform float wetness : hint_range(0.0, 1.0) = 0.6;
uniform float drip_speed : hint_range(0.1, 3.0) = 0.8;
uniform float drip_density : hint_range(1.0, 20.0) = 8.0;
uniform float drip_width : hint_range(0.01, 0.2) = 0.05;
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.3;

group_uniforms surface;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.1;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(0.1, 4.0) = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

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

// Animated drip trails flowing down vertical surfaces
float drip_trail(vec2 uv, float time) {
	// Multiple drip columns at random positions
	float drips = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float x_offset = hash(vec2(fi * 7.3, fi * 13.1)) * 2.0 - 1.0;
		float speed_var = 0.7 + hash(vec2(fi * 3.1, fi * 5.7)) * 0.6;
		float width_var = drip_width * (0.5 + hash(vec2(fi, fi * 2.0)));

		float x_dist = abs(uv.x - x_offset);
		float trail = smoothstep(width_var, 0.0, x_dist);

		// Flowing downward
		float flow = fract(-uv.y * drip_density + time * drip_speed * speed_var + fi * 0.3);
		flow = smoothstep(0.0, 0.3, flow) * smoothstep(1.0, 0.5, flow);

		drips += trail * flow;
	}
	return clamp(drips, 0.0, 1.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Tri-planar UV for voxel surfaces
	vec3 n = abs(world_normal);
	vec3 blend = pow(n, vec3(4.0));
	blend /= dot(blend, vec3(1.0));

	// Base normal map
	vec3 norm_xy = texture(base_normal, world_pos.xy * normal_scale).rgb;
	vec3 norm_xz = texture(base_normal, world_pos.xz * normal_scale).rgb;
	vec3 norm_yz = texture(base_normal, world_pos.yz * normal_scale).rgb;
	vec3 blended_normal = norm_yz * blend.x + norm_xz * blend.y + norm_xy * blend.z;

	// Wetness mask — more wet on upper surfaces and near drips
	float wet_mask = wetness;

	// Drip trails on vertical surfaces
	float is_vertical = 1.0 - abs(world_normal.y);
	float drips = 0.0;
	if (is_vertical > 0.3) {
		// Use the dominant horizontal axis for drip UV
		vec2 drip_uv;
		if (abs(world_normal.x) > abs(world_normal.z)) {
			drip_uv = world_pos.zy;
		} else {
			drip_uv = world_pos.xy;
		}
		drips = drip_trail(drip_uv, TIME) * is_vertical * wetness;
	}

	// Puddles on horizontal surfaces
	float puddles = 0.0;
	if (world_normal.y > 0.7) {
		float puddle_noise = noise(world_pos.xz * 3.0);
		puddles = smoothstep(1.0 - puddle_amount, 1.0, puddle_noise) * wetness;
	}

	float total_wet = clamp(wet_mask * 0.3 + drips + puddles, 0.0, 1.0);

	// Color — wet surfaces are darker
	vec3 color = mix(base_color.rgb, wet_tint.rgb, total_wet * 0.7);

	// Roughness — wet = shiny
	float rough = mix(base_roughness, wet_roughness, total_wet);

	// Specular kick on wet surfaces
	float spec = mix(0.5, 0.9, total_wet);

	ALBEDO = color;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = spec;
	NORMAL_MAP = blended_normal;
	NORMAL_MAP_DEPTH = mix(1.0, 0.3, total_wet);  // Wet surfaces have flatter normals

	// Subtle emission on drip trails (glistening)
	float glisten = drips * pow(max(dot(NORMAL, VIEW), 0.0), 8.0) * 0.3;
	EMISSION = vec3(0.5, 0.6, 0.7) * glisten;
}
