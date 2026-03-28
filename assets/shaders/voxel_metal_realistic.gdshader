shader_type spatial;

// Photorealistic metal on voxel geometry.
// Rust, scratches, patina, fingerprints, anisotropic reflections.
// Procedural — no textures needed.

render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx, diffuse_burley;

group_uniforms color;
uniform vec4 metal_color : source_color = vec4(0.58, 0.60, 0.63, 1.0);
uniform vec4 rust_color : source_color = vec4(0.45, 0.22, 0.08, 1.0);
uniform vec4 patina_color : source_color = vec4(0.30, 0.55, 0.45, 1.0);

group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform float metallic : hint_range(0.0, 1.0) = 0.95;

group_uniforms wear;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.2;
uniform float rust_scale : hint_range(1.0, 15.0) = 4.0;
uniform float scratch_amount : hint_range(0.0, 1.0) = 0.3;
uniform float scratch_scale : hint_range(5.0, 30.0) = 15.0;
uniform float patina_amount : hint_range(0.0, 1.0) = 0.0;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.4;
uniform float dent_amount : hint_range(0.0, 1.0) = 0.1;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

varying vec3 world_pos;
varying vec3 world_normal;

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

float fbm3d(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3d(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

// Directional scratches
float scratches(vec3 p, float scale) {
	// Anisotropic noise — stretched along one axis per face
	vec3 stretched = p * vec3(scale, scale * 0.2, scale);
	float s1 = noise3d(stretched);
	float s2 = noise3d(stretched * 1.7 + 33.0);
	float scratch = smoothstep(0.45, 0.5, s1) + smoothstep(0.47, 0.5, s2) * 0.5;
	return clamp(scratch, 0.0, 1.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// ── Rust mask ─────────────────────────────────────────────
	float rust_noise = fbm3d(world_pos * rust_scale);
	float rust = smoothstep(0.5 - rust_amount * 0.5, 0.5 + rust_amount * 0.3, rust_noise);

	// Rust concentrates at edges and lower surfaces
	rust *= mix(1.0, 1.5, 1.0 - world_normal.y);  // More on undersides
	rust = clamp(rust, 0.0, 1.0);

	// ── Scratches ─────────────────────────────────────────────
	float scratch = scratches(world_pos, scratch_scale) * scratch_amount;

	// ── Patina (copper/bronze oxidation) ──────────────────────
	float patina_noise = fbm3d(world_pos * 5.0 + 50.0);
	float patina = smoothstep(0.4, 0.6, patina_noise) * patina_amount;

	// ── Edge wear (brighter metal at voxel edges) ─────────────
	vec3 frac_pos = fract(world_pos);
	float edge_dist = min(min(
		min(frac_pos.x, 1.0 - frac_pos.x),
		min(frac_pos.y, 1.0 - frac_pos.y)
	), min(frac_pos.z, 1.0 - frac_pos.z));
	float edge = smoothstep(0.05, 0.0, edge_dist) * edge_wear;

	// ── Dents ─────────────────────────────────────────────────
	float dents = 0.0;
	if (dent_amount > 0.0) {
		float dent_noise = noise3d(world_pos * 8.0);
		dents = smoothstep(0.7, 0.75, dent_noise) * dent_amount;
	}

	// ── Compose ───────────────────────────────────────────────
	vec3 color = metal_color.rgb;

	// Edge wear reveals brighter base metal
	color = mix(color, color * 1.3, edge);

	// Scratches reveal brighter metal underneath
	color = mix(color, color * 1.2, scratch * 0.5);

	// Rust overtakes metal
	color = mix(color, rust_color.rgb, rust);

	// Patina overtakes metal (but not rust)
	color = mix(color, patina_color.rgb, patina * (1.0 - rust));

	// ── Material properties ───────────────────────────────────
	float r = roughness;
	float m = metallic;

	// Rust is rough and non-metallic
	r = mix(r, 0.9, rust);
	m = mix(m, 0.1, rust);

	// Scratches are smoother (polished by abrasion)
	r = mix(r, max(r - 0.2, 0.05), scratch);

	// Edge wear is smoother
	r = mix(r, max(r - 0.15, 0.1), edge);

	// Patina is medium rough
	r = mix(r, 0.6, patina);
	m = mix(m, 0.2, patina);

	// ── Procedural normal from noise ──────────────────────────
	float eps = 0.01;
	float h0 = fbm3d(world_pos * 10.0);
	float hx = fbm3d((world_pos + vec3(eps, 0, 0)) * 10.0);
	float hz = fbm3d((world_pos + vec3(0, 0, eps)) * 10.0);
	vec3 proc_normal = normalize(vec3(h0 - hx, eps, h0 - hz));

	// Add dent deformation to normal
	if (dents > 0.0) {
		float d0 = noise3d(world_pos * 8.0);
		float dx = noise3d((world_pos + vec3(eps, 0, 0)) * 8.0);
		float dz = noise3d((world_pos + vec3(0, 0, eps)) * 8.0);
		vec3 dent_normal = normalize(vec3(d0 - dx, eps * 0.5, d0 - dz));
		proc_normal = normalize(mix(proc_normal, dent_normal, dents));
	}

	ALBEDO = color;
	ROUGHNESS = r;
	METALLIC = m;
	SPECULAR = 0.6;
	NORMAL_MAP = proc_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	AO = 1.0 - rust * 0.2 - dents * 0.3;
}
