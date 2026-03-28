shader_type spatial;

// Voxel PBR — realistic materials on blocky geometry.
// Tri-planar mapping so textures project correctly on all voxel faces
// without UV seams. PBR with roughness, metallic, AO, emission.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms albedo;
uniform vec4 albedo_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D roughness_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metallic_texture : filter_linear_mipmap_anisotropic, repeat_enable;

group_uniforms normal;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

group_uniforms ao;
uniform sampler2D ao_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;

group_uniforms emission;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;
uniform sampler2D emission_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

group_uniforms triplanar;
uniform float triplanar_scale : hint_range(0.1, 10.0) = 1.0;
uniform float triplanar_sharpness : hint_range(0.5, 16.0) = 4.0;

// Edge detection for voxel grid lines
group_uniforms grid;
uniform bool grid_enabled = false;
uniform vec4 grid_color : source_color = vec4(0.0, 0.0, 0.0, 0.3);
uniform float grid_width : hint_range(0.001, 0.1) = 0.02;

// Wetness / rain effect
group_uniforms weather;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 power_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Tri-planar blend weights
	vec3 n = abs(world_normal);
	power_normal = pow(n, vec3(triplanar_sharpness));
	power_normal /= dot(power_normal, vec3(1.0));
}

vec4 triplanar_sample(sampler2D tex, vec3 pos, vec3 blend) {
	vec4 x = texture(tex, pos.yz * triplanar_scale);
	vec4 y = texture(tex, pos.xz * triplanar_scale);
	vec4 z = texture(tex, pos.xy * triplanar_scale);
	return x * blend.x + y * blend.y + z * blend.z;
}

float voxel_edge(vec3 pos) {
	vec3 f = fract(pos);
	vec3 edge = smoothstep(vec3(0.0), vec3(grid_width), f)
	           * smoothstep(vec3(0.0), vec3(grid_width), vec3(1.0) - f);
	return 1.0 - min(min(edge.x, edge.y), edge.z);
}

void fragment() {
	vec3 blend = power_normal;

	// Albedo with tri-planar mapping
	vec4 albedo_tex = triplanar_sample(albedo_texture, world_pos, blend);
	ALBEDO = albedo_color.rgb * albedo_tex.rgb;

	// PBR maps
	float rough_tex = triplanar_sample(roughness_texture, world_pos, blend).r;
	float metal_tex = triplanar_sample(metallic_texture, world_pos, blend).r;
	ROUGHNESS = roughness * rough_tex;
	METALLIC = metallic * metal_tex;
	SPECULAR = specular;

	// Normal map
	vec3 norm = triplanar_sample(normal_texture, world_pos, blend).rgb;
	NORMAL_MAP = norm;
	NORMAL_MAP_DEPTH = normal_strength;

	// AO
	float ao = triplanar_sample(ao_texture, world_pos, blend).r;
	AO = mix(1.0, ao, ao_strength);
	AO_LIGHT_AFFECT = 0.5;

	// Emission (for glowing voxels — lava, crystals, tech)
	vec3 emit = triplanar_sample(emission_texture, world_pos, blend).rgb;
	EMISSION = emission_color.rgb * emit * emission_energy;

	// Voxel grid overlay
	if (grid_enabled) {
		float edge = voxel_edge(world_pos);
		ALBEDO = mix(ALBEDO, grid_color.rgb, edge * grid_color.a);
	}

	// Wetness — darken albedo, smooth roughness, add reflections
	if (wetness > 0.0) {
		ALBEDO *= mix(1.0, 0.6, wetness);
		ROUGHNESS *= mix(1.0, 0.2, wetness);
		// Puddles on upward-facing surfaces
		if (puddle_amount > 0.0 && world_normal.y > 0.8) {
			float puddle = smoothstep(0.3, 0.7, puddle_amount);
			ROUGHNESS = mix(ROUGHNESS, 0.01, puddle);
			METALLIC = mix(METALLIC, 0.0, puddle);
			SPECULAR = mix(SPECULAR, 1.0, puddle * 0.5);
		}
	}
}
