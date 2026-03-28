shader_type spatial;

// Voxel glass — transparent voxel blocks with refraction and tint.
// For windows, crystal formations, ice, force fields.

render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 glass_color : source_color = vec4(0.6, 0.8, 1.0, 0.3);
uniform float roughness : hint_range(0.0, 1.0) = 0.05;
uniform float refraction : hint_range(-1.0, 1.0) = 0.05;
uniform float rim_power : hint_range(0.0, 8.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform float thickness : hint_range(0.0, 2.0) = 0.5;

// Procedural scratches / imperfections
uniform float imperfection_scale : hint_range(1.0, 50.0) = 20.0;
uniform float imperfection_amount : hint_range(0.0, 1.0) = 0.1;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	ALBEDO = glass_color.rgb;
	ALPHA = glass_color.a;

	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.8;

	// Rim lighting — glass edges glow
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), rim_power);
	EMISSION = rim_color.rgb * rim * 0.5;

	// Refraction
	vec3 ref_normal = NORMAL;
	ref_normal.xy += imperfection_amount * (noise(world_pos.xz * imperfection_scale) - 0.5);
	BACKLIGHT = thickness;

	// Sub-surface approximation for thick glass
	SSS_STRENGTH = thickness * 0.3;
}
