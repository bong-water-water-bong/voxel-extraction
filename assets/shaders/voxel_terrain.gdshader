shader_type spatial;

// Voxel terrain mega-shader — auto-textures based on height, slope, biome.
// Tri-planar PBR with height-based blending, moss growth, snow accumulation.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Texture layers
group_uniforms ground;
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float ground_roughness : hint_range(0.0, 1.0) = 0.85;

group_uniforms rock;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float rock_metallic : hint_range(0.0, 1.0) = 0.1;

group_uniforms snow;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float snow_height : hint_range(0.0, 100.0) = 30.0;
uniform float snow_blend : hint_range(0.1, 10.0) = 5.0;
uniform float snow_slope_threshold : hint_range(0.0, 1.0) = 0.7;

group_uniforms moss;
uniform vec4 moss_color : source_color = vec4(0.15, 0.35, 0.1, 1.0);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.3;
uniform float moss_height_min : hint_range(0.0, 50.0) = 5.0;
uniform float moss_height_max : hint_range(0.0, 80.0) = 25.0;

group_uniforms settings;
uniform float texture_scale : hint_range(0.1, 4.0) = 1.0;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

// Damage / destruction darkening
group_uniforms destruction;
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform vec4 scorch_color : source_color = vec4(0.05, 0.03, 0.02, 1.0);

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 blend_weights;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

	vec3 n = abs(world_normal);
	blend_weights = pow(n, vec3(triplanar_sharpness));
	blend_weights /= dot(blend_weights, vec3(1.0));
}

vec4 tri_sample(sampler2D tex, vec3 pos, vec3 blend) {
	return texture(tex, pos.yz * texture_scale) * blend.x
	     + texture(tex, pos.xz * texture_scale) * blend.y
	     + texture(tex, pos.xy * texture_scale) * blend.z;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float height = world_pos.y;
	float slope = world_normal.y;  // 1.0 = flat, 0.0 = vertical

	// Base ground texture
	vec3 ground = tri_sample(ground_albedo, world_pos, blend_weights).rgb;
	vec3 ground_n = tri_sample(ground_normal, world_pos, blend_weights).rgb;
	float rough = ground_roughness;

	// Rock on steep surfaces
	float rock_factor = 1.0 - smoothstep(0.4, 0.7, slope);
	vec3 rock = tri_sample(rock_albedo, world_pos, blend_weights).rgb;
	vec3 rock_n = tri_sample(rock_normal, world_pos, blend_weights).rgb;

	vec3 albedo = mix(ground, rock, rock_factor);
	vec3 normal_map = mix(ground_n, rock_n, rock_factor);
	rough = mix(ground_roughness, rock_roughness, rock_factor);
	float metal = rock_metallic * rock_factor;

	// Moss on shaded, mid-height surfaces
	if (moss_amount > 0.0) {
		float moss_h = smoothstep(moss_height_min, moss_height_min + 3.0, height)
		             * (1.0 - smoothstep(moss_height_max - 3.0, moss_height_max, height));
		float moss_s = smoothstep(0.6, 0.9, slope);  // Flat-ish surfaces
		float noise_val = hash(floor(world_pos.xz * 4.0));
		float moss_mask = moss_h * moss_s * step(0.5, noise_val) * moss_amount;
		albedo = mix(albedo, moss_color.rgb, moss_mask);
		rough = mix(rough, 0.95, moss_mask);
	}

	// Snow accumulation on high, flat surfaces
	float snow_factor = smoothstep(snow_height - snow_blend, snow_height + snow_blend, height);
	snow_factor *= smoothstep(snow_slope_threshold - 0.1, snow_slope_threshold, slope);
	vec3 snow = tri_sample(snow_albedo, world_pos, blend_weights).rgb;
	snow = max(snow, vec3(0.85, 0.88, 0.92));  // Ensure snow is bright
	albedo = mix(albedo, snow, snow_factor);
	rough = mix(rough, 0.6, snow_factor);
	metal = mix(metal, 0.0, snow_factor);

	// Destruction scorching
	if (damage > 0.0) {
		albedo = mix(albedo, scorch_color.rgb, damage * 0.8);
		rough = mix(rough, 1.0, damage);
		metal = 0.0;
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = normal_map;
	NORMAL_MAP_DEPTH = 1.0;
	AO = mix(1.0, 0.6, rock_factor * 0.5);
}
