shader_type spatial;

// Emissive voxels — for lava, crystals, tech blocks, extraction beacons.
// Pulsing glow with heat distortion.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, unshaded;

uniform vec4 base_color : source_color = vec4(1.0, 0.2, 0.0, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.6, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 32.0) = 4.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.3;

// Flowing energy pattern
uniform float flow_speed : hint_range(0.0, 5.0) = 1.0;
uniform float flow_scale : hint_range(1.0, 20.0) = 8.0;
uniform float crack_sharpness : hint_range(1.0, 20.0) = 6.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_dist = 1.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = vec2(hash(i + neighbor), hash(i + neighbor + 42.0));
			vec2 diff = neighbor + point - f;
			min_dist = min(min_dist, length(diff));
		}
	}
	return min_dist;
}

void fragment() {
	// Pulsing glow
	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
	float energy = mix(1.0 - pulse_intensity, 1.0, pulse);

	// Voronoi crack pattern — flowing energy through cracks
	vec2 flow_uv = world_pos.xz * flow_scale + TIME * flow_speed * 0.1;
	float cracks = voronoi(flow_uv);
	cracks = pow(1.0 - cracks, crack_sharpness);

	// Mix base and glow based on crack pattern
	vec3 color = mix(base_color.rgb, glow_color.rgb, cracks);

	ALBEDO = color;
	EMISSION = color * emission_energy * energy;
}
