shader_type spatial;

// Flowing water shader — for rivers, waterfalls, streams in voxel world.
// Directional flow with speed control. Foam at obstacles.
// Pairs with water_realistic for still water.

render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.12, 0.35, 0.45, 0.75);
uniform vec4 foam_color : source_color = vec4(0.85, 0.92, 1.0, 0.9);

group_uniforms flow;
uniform vec2 flow_direction = vec2(1.0, 0.0);
uniform float flow_speed : hint_range(0.0, 5.0) = 1.5;
uniform float turbulence : hint_range(0.0, 2.0) = 0.5;

group_uniforms surface;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(0.1, 4.0) = 1.5;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.05;

group_uniforms depth;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float depth_fade : hint_range(0.5, 10.0) = 3.0;
uniform float refraction_strength : hint_range(0.0, 0.05) = 0.015;

group_uniforms foam;
uniform float foam_amount : hint_range(0.0, 2.0) = 0.8;
uniform float foam_scale : hint_range(1.0, 20.0) = 10.0;
uniform float foam_edge_width : hint_range(0.0, 2.0) = 0.4;

varying vec3 world_pos;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Flow-aligned wave displacement
	vec2 flow = normalize(flow_direction) * flow_speed * TIME;
	float wave = sin(dot(world_pos.xz + flow, normalize(flow_direction)) * 4.0) * 0.02;
	wave += sin(dot(world_pos.xz + flow * 0.7, vec2(-flow_direction.y, flow_direction.x)) * 6.0) * 0.01;
	VERTEX.y += wave * turbulence;
}

void fragment() {
	vec2 flow = normalize(flow_direction) * flow_speed;

	// Two-phase flow cycling to avoid texture swimming
	float phase1 = fract(TIME * 0.1);
	float phase2 = fract(TIME * 0.1 + 0.5);
	float blend = abs(phase1 * 2.0 - 1.0);

	vec2 uv1 = world_pos.xz * normal_scale + flow * TIME * 0.3;
	vec2 uv2 = world_pos.xz * normal_scale * 1.2 + flow * (TIME * 0.3 + 0.5);

	vec3 n1 = texture(normal_map, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_map, uv2).rgb * 2.0 - 1.0;
	vec3 combined_normal = normalize(mix(n1, n2, blend));

	// Turbulence distortion
	float turb = fbm(world_pos.xz * 3.0 + flow * TIME * 0.2) * turbulence;
	combined_normal.xy += turb * 0.3;
	combined_normal = normalize(combined_normal);

	NORMAL_MAP = combined_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;

	// Depth
	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 wdp = INV_PROJECTION_MATRIX * ndc;
	wdp /= wdp.w;
	float depth = max(-wdp.z - (-VERTEX.z), 0.0);
	float depth_factor = clamp(depth / depth_fade, 0.0, 1.0);

	// Refraction
	vec2 ref_offset = combined_normal.xy * refraction_strength;
	vec3 refracted = texture(SCREEN_TEXTURE, SCREEN_UV + ref_offset).rgb;

	vec3 color = mix(refracted, water_color.rgb, water_color.a * depth_factor);

	// Edge foam (where water meets voxels)
	float edge_foam = smoothstep(foam_edge_width, 0.0, depth);

	// Flow foam (turbulent white water)
	float flow_foam = fbm((world_pos.xz + flow * TIME * 0.5) * foam_scale);
	flow_foam = smoothstep(0.5, 0.8, flow_foam) * foam_amount;

	float total_foam = max(edge_foam, flow_foam);
	color = mix(color, foam_color.rgb, total_foam * foam_color.a);

	// Fresnel
	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0);

	ALBEDO = color;
	ALPHA = mix(water_color.a, 1.0, depth_factor);
	ROUGHNESS = mix(roughness, 0.4, total_foam);
	SPECULAR = 0.8 * fresnel;
	METALLIC = 0.0;
}
