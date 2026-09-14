shader_type canvas_item;
render_mode blend_mix;

// Weapon Stylized Shader — Тактильная фаска, бегущий металлический блик (sheen sweep),
// объёмные тени и магическая пульсирующая аура/руны.

uniform vec4 base_color : source_color = vec4(0.75, 0.75, 0.82, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.28, 0.28, 0.35, 1.0);
uniform vec4 aura_color : source_color = vec4(0.4, 0.7, 1.0, 0.0); // Если alpha > 0, светится аура

uniform float bevel_size : hint_range(0.01, 0.35) = 0.12;
uniform float sheen_speed : hint_range(0.0, 5.0) = 1.6;
uniform float sheen_width : hint_range(0.05, 0.5) = 0.18;
uniform float pulse_speed : hint_range(0.0, 10.0) = 3.0;

void fragment() {
	vec2 uv = UV;

	// Базовый цвет
	vec3 col = base_color.rgb;

	// 1. 2.5D тактильная фаска (свет сверху-слева, тень снизу-справа)
	float top_light = smoothstep(bevel_size, 0.0, uv.y);
	float left_light = smoothstep(bevel_size, 0.0, uv.x);
	float bottom_shadow = smoothstep(1.0 - bevel_size, 1.0, uv.y);
	float right_shadow = smoothstep(1.0 - bevel_size, 1.0, uv.x);

	float bevel = (top_light + left_light * 0.7) * 0.35 - (bottom_shadow + right_shadow * 0.6) * 0.4;
	col = mix(col, highlight_color.rgb, clamp(bevel, 0.0, 1.0));
	col = mix(col, shadow_color.rgb, clamp(-bevel, 0.0, 1.0));

	// 2. Бегущий диагональный металлический блик (Sheen Gleam)
	if (sheen_speed > 0.01) {
		float diag = fract(TIME * (sheen_speed * 0.35) - (uv.x * 1.5 + uv.y * 0.8));
		float sheen = smoothstep(sheen_width, 0.0, abs(diag - 0.5));
		col += highlight_color.rgb * (sheen * 0.65);
	}

	// 3. Пульсирующая магическая аура или кристаллический блеск
	if (aura_color.a > 0.01) {
		float pulse = sin(TIME * pulse_speed + uv.x * 6.0) * 0.5 + 0.5;
		col = mix(col, aura_color.rgb, aura_color.a * (0.5 + pulse * 0.5));
		col += aura_color.rgb * (pulse * 0.4);
	}

	COLOR = vec4(col, base_color.a * COLOR.a);
}
