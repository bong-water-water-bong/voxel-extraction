shader_type spatial;

// Volumetric fog / atmosphere shader for extraction zones.
// Thick, ominous fog that rolls through the voxel world.
// Gets denser near extraction points and during the final minutes.

render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 fog_color : source_color = vec4(0.05, 0.08, 0.12, 0.4);
uniform vec4 fog_glow : source_color = vec4(0.0, 0.5, 1.0, 1.0);
uniform float density : hint_range(0.0, 2.0) = 0.5;
uniform float speed : hint_range(0.0, 2.0) = 0.3;
uniform float scale : hint_range(0.5, 10.0) = 3.0;
uniform float height_fade : hint_range(0.0, 1.0) = 0.5;
uniform float glow_intensity : hint_range(0.0, 4.0) = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n = mix(
		mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x),
		    mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
		    mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y),
		f.z
	);
	return n;
}

float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise3d(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec3 moving_pos = world_pos * scale + vec3(TIME * speed, 0.0, TIME * speed * 0.7);

	float fog = fbm(moving_pos);
	fog *= density;

	// Height fade — fog thins out higher up
	float height_factor = 1.0 - smoothstep(0.0, 20.0, world_pos.y) * height_fade;
	fog *= height_factor;

	ALBEDO = fog_color.rgb;
	ALPHA = clamp(fog * fog_color.a, 0.0, 0.8);

	// Extraction glow — set glow_intensity > 0 when extraction is active
	if (glow_intensity > 0.0) {
		EMISSION = fog_glow.rgb * glow_intensity * fog;
	}
}
