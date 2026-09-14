shader_type canvas_item;
render_mode blend_mix;

// Arrow Trail Shader — Аэродинамический снаряд лучника с наконечником,
// руническим светящимся древком, оперением и скоростным световым шлейфом.

uniform vec4 shaft_color : source_color = vec4(0.20, 0.88, 0.42, 1.0);
uniform vec4 core_glow : source_color = vec4(0.75, 1.0, 0.85, 1.0);
uniform vec4 tip_color : source_color = vec4(0.95, 0.95, 1.0, 1.0);
uniform vec4 trail_color : source_color = vec4(0.12, 0.65, 0.32, 0.6);
uniform float trail_speed = 10.0;

void fragment() {
	vec2 uv = UV;
	float half_y = abs(uv.y - 0.5);

	// 1. Наконечник стрелы (треугольник на передней кромке: x от 0.75 до 1.0)
	float tip_t = clamp((uv.x - 0.75) / 0.25, 0.0, 1.0);
	float tip_half_w = (1.0 - tip_t) * 0.45;
	bool is_tip = (uv.x >= 0.75 && half_y <= tip_half_w);

	// 2. Древко стрелы (центральная линия: x от 0.2 до 0.8, узкая полоса)
	float shaft_w = 0.10;
	bool is_shaft = (uv.x >= 0.20 && uv.x <= 0.80 && half_y <= shaft_w);

	// 3. Оперение стрелы (на конце: x от 0.15 до 0.35)
	float fletch_t = (uv.x - 0.15) / 0.20;
	float fletch_w = fletch_t * 0.40;
	bool is_fletching = (uv.x >= 0.15 && uv.x <= 0.35 && half_y <= fletch_w && half_y >= 0.08);

	// 4. Скоростной след / энергетический шлейф (x < 0.3)
	float trail_mask = smoothstep(0.40, 0.0, uv.x);
	float trail_lines = sin(half_y * 35.0 + TIME * trail_speed) * 0.5 + 0.5;
	float trail_w = smoothstep(0.35, 0.0, half_y);
	float trail_alpha = trail_mask * trail_w * (0.4 + trail_lines * 0.4);

	vec3 col = shaft_color.rgb;
	float alpha = 0.0;

	if (is_tip) {
		col = mix(shaft_color.rgb, tip_color.rgb, tip_t);
		alpha = 1.0;
	} else if (is_fletching) {
		col = shaft_color.rgb * 0.85;
		alpha = 0.9;
	} else if (is_shaft) {
		// Бегущий рунический импульс по древку
		float pulse = sin(uv.x * 22.0 - TIME * trail_speed) * 0.5 + 0.5;
		col = mix(shaft_color.rgb, core_glow.rgb, pulse * 0.7 + (1.0 - half_y / shaft_w) * 0.5);
		alpha = 1.0;
	}

	// Добавляем свечение шлейфа
	if (alpha < 0.1) {
		col = trail_color.rgb;
		alpha = trail_alpha * trail_color.a;
	} else {
		// Ореол свечения вокруг стрелы
		float halo = smoothstep(0.45, 0.0, half_y) * 0.3;
		col += core_glow.rgb * halo;
	}

	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}
