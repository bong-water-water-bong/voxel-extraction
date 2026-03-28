shader_type spatial;

// Photorealistic stone on voxel geometry.
// Procedural cracks, mineral veins, micro-surface detail.
// No textures needed — 100% procedural, infinite resolution.

render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx, diffuse_burley;

group_uniforms color;
uniform vec4 base_color : source_color = vec4(0.42, 0.40, 0.38, 1.0);
uniform vec4 dark_color : source_color = vec4(0.25, 0.23, 0.22, 1.0);
uniform vec4 vein_color : source_color = vec4(0.55, 0.50, 0.45, 1.0);
uniform float color_variation : hint_range(0.0, 0.3) = 0.08;

group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.82;
uniform float metallic : hint_range(0.0, 1.0) = 0.05;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.6;

group_uniforms detail;
uniform float crack_scale : hint_range(1.0, 20.0) = 6.0;
uniform float crack_sharpness : hint_range(1.0, 20.0) = 8.0;
uniform float vein_scale : hint_range(1.0, 20.0) = 3.0;
uniform float vein_amount : hint_range(0.0, 1.0) = 0.3;
uniform float grain_scale : hint_range(5.0, 50.0) = 25.0;
uniform float grain_amount : hint_range(0.0, 0.3) = 0.1;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 blend_weights;

float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x),
		    mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
		    mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y),
		f.z
	);
}

float voronoi3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float min_dist = 1.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 neighbor = vec3(float(x), float(y), float(z));
				vec3 point = vec3(
					hash(i + neighbor),
					hash((i + neighbor) * 1.3),
					hash((i + neighbor) * 1.7)
				);
				min_dist = min(min_dist, length(neighbor + point - f));
			}
		}
	}
	return min_dist;
}

float fbm3d(vec3 p, int octaves) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		value += amp * noise3d(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return value;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 n = abs(world_normal);
	blend_weights = pow(n, vec3(triplanar_sharpness));
	blend_weights /= dot(blend_weights, vec3(1.0));
}

void fragment() {
	// ── Cracks (voronoi-based, sharp edges) ───────────────────
	float cracks = voronoi3d(world_pos * crack_scale);
	cracks = pow(1.0 - cracks, crack_sharpness);  // Sharp crack lines
	float crack_ao = 1.0 - cracks * 0.4;  // Darkening in cracks

	// ── Mineral veins (flowing noise) ─────────────────────────
	float veins = fbm3d(world_pos * vein_scale + 100.0, 4);
	veins = smoothstep(0.45, 0.55, veins) * vein_amount;

	// ── Fine grain (high frequency noise) ─────────────────────
	float grain = noise3d(world_pos * grain_scale) * grain_amount;

	// ── Color composition ─────────────────────────────────────
	vec3 color = base_color.rgb;

	// Color variation per-block (hash of integer position)
	vec3 block_pos = floor(world_pos + 0.001);
	float block_var = hash(block_pos) * 2.0 - 1.0;
	color += block_var * color_variation;

	// Darken in cracks
	color = mix(color, dark_color.rgb, cracks * 0.6);

	// Veins
	color = mix(color, vein_color.rgb, veins);

	// Grain
	color += grain - grain_amount * 0.5;

	// ── Normal from cracks (procedural bump) ──────────────────
	float eps = 0.02;
	float cx = voronoi3d((world_pos + vec3(eps, 0, 0)) * crack_scale);
	float cy = voronoi3d((world_pos + vec3(0, eps, 0)) * crack_scale);
	float cz = voronoi3d((world_pos + vec3(0, 0, eps)) * crack_scale);
	float c0 = voronoi3d(world_pos * crack_scale);
	vec3 crack_normal = normalize(vec3(c0 - cx, c0 - cy, c0 - cz));

	ALBEDO = color;
	ROUGHNESS = roughness + cracks * 0.1 - veins * 0.05;
	METALLIC = metallic + veins * 0.15;  // Veins slightly metallic
	SPECULAR = 0.5;
	AO = crack_ao * mix(1.0, 0.6, ao_strength);
	AO_LIGHT_AFFECT = 0.4;
	NORMAL_MAP = crack_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.8;
}
