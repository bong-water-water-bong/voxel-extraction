shader_type canvas_item;

// Post-processing — color grading, vignette, film grain.
// Gives the voxel world a gritty, cinematic feel.

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// Color grading
group_uniforms grading;
uniform float contrast : hint_range(0.5, 2.0) = 1.1;
uniform float saturation : hint_range(0.0, 2.0) = 1.05;
uniform float brightness : hint_range(0.5, 2.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 0.98, 0.95, 1.0);
uniform float temperature : hint_range(-1.0, 1.0) = 0.0;

// Vignette
group_uniforms vignette;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.5;

// Film grain
group_uniforms grain;
uniform float grain_amount : hint_range(0.0, 0.5) = 0.04;
uniform float grain_speed : hint_range(0.0, 20.0) = 8.0;

// Chromatic aberration
group_uniforms aberration;
uniform float chromatic_amount : hint_range(0.0, 10.0) = 0.5;

float random(vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 adjust_temperature(vec3 color, float temp) {
	color.r += temp * 0.1;
	color.b -= temp * 0.1;
	return color;
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Chromatic aberration
	vec2 ca_offset = (uv - 0.5) * chromatic_amount * 0.001;
	float r = texture(SCREEN_TEXTURE, uv + ca_offset).r;
	float g = texture(SCREEN_TEXTURE, uv).g;
	float b = texture(SCREEN_TEXTURE, uv - ca_offset).b;
	vec3 color = vec3(r, g, b);

	// Brightness
	color *= brightness;

	// Contrast
	color = mix(vec3(0.5), color, contrast);

	// Saturation
	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luminance), color, saturation);

	// Temperature
	color = adjust_temperature(color, temperature);

	// Tint
	color *= tint.rgb;

	// Vignette
	vec2 vig_uv = uv * (1.0 - uv);
	float vig = vig_uv.x * vig_uv.y * 15.0;
	vig = pow(vig, vignette_softness);
	color *= mix(1.0 - vignette_intensity, 1.0, vig);

	// Film grain
	float grain = random(uv * TIME * grain_speed) - 0.5;
	color += grain * grain_amount;

	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
