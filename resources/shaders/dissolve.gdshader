shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D noise_texture : repeat_enable;
instance uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float burn_size : hint_range(0.0, 0.25) = 0.08;
uniform vec4 burn_color : source_color = vec4(1.0, 0.45, 0.1, 1.0);

void fragment() {
	vec4 main_texture = COLOR;

	float noise_val = texture(noise_texture, UV).r;
	if (noise_val == 0.0) {
		// Fallback procedural pseudo-noise if no texture is assigned
		noise_val = fract(sin(dot(UV * 5.0, vec2(12.9898, 78.233))) * 43758.5453);
	}

	if (noise_val < dissolve_amount) {
		discard;
	}

	if (dissolve_amount > 0.01 && noise_val < dissolve_amount + burn_size && main_texture.a > 0.0) {
		COLOR = vec4(burn_color.rgb, main_texture.a);
	} else {
		COLOR = main_texture;
	}
}
