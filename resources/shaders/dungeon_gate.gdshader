shader_type canvas_item;
render_mode blend_mix;

// Dungeon Gate Shader — Кованая железная решетка (portcullis) с массивными прутьями,
// острыми наконечниками, стальными заклепками и пылающими руническими цепями печати.

uniform vec4 iron_base : source_color = vec4(0.22, 0.22, 0.27, 1.0);
uniform vec4 iron_highlight : source_color = vec4(0.65, 0.65, 0.75, 1.0);
uniform vec4 iron_shadow : source_color = vec4(0.08, 0.08, 0.12, 1.0);
uniform vec4 rune_glow : source_color = vec4(1.0, 0.25, 0.15, 1.0);
uniform float bar_count = 10.0;
uniform float seal_pulse_speed = 3.2;

void fragment() {
	vec2 uv = UV;

	// 1. Вертикальные кованые прутья решетки
	float bar_coord = fract(uv.x * bar_count);
	float bar_dist = abs(bar_coord - 0.5) * 2.0; // 0 в центре прута, 1 на границе
	float bar_width = 0.42; // ширина прута
	bool is_vertical_bar = (bar_dist < bar_width);

	// Цилиндрический блик на пруте
	float cyl_highlight = smoothstep(0.35, 0.0, abs(bar_coord - 0.38));
	float cyl_shadow = smoothstep(0.2, 0.5, bar_dist);

	// Острые наконечники прутьев внизу (пики)
	bool is_spike = false;
	if (uv.y > 0.82) {
		float spike_t = (uv.y - 0.82) / 0.18;
		float spike_w = (1.0 - spike_t) * bar_width;
		is_spike = (bar_dist < spike_w);
		is_vertical_bar = is_spike;
	}

	// 2. Горизонтальные железные перекладины с заклепками
	bool is_crossbar_top = (uv.y >= 0.14 && uv.y <= 0.28);
	bool is_crossbar_bot = (uv.y >= 0.66 && uv.y <= 0.80);
	bool is_crossbar = is_crossbar_top || is_crossbar_bot;

	// Заклепки / болты на пересечении прутьев и перекладин
	bool is_rivet = false;
	if (is_crossbar && bar_dist < 0.28) {
		float cy = is_crossbar_top ? 0.21 : 0.73;
		vec2 rivet_diff = vec2((bar_coord - 0.5) * (192.0 / bar_count), (uv.y - cy) * 64.0);
		is_rivet = (length(rivet_diff) < 3.8);
	}

	// Вычисляем металл
	vec3 col = iron_base.rgb;
	float alpha = 0.0;

	if (is_crossbar) {
		float cross_uv_y = is_crossbar_top ? (uv.y - 0.14) / 0.14 : (uv.y - 0.66) / 0.14;
		float h_light = smoothstep(0.2, 0.0, cross_uv_y) * 0.4;
		float h_shadow = smoothstep(0.8, 1.0, cross_uv_y) * 0.45;
		col = mix(col, iron_highlight.rgb, h_light);
		col = mix(col, iron_shadow.rgb, h_shadow);
		alpha = 0.95;
	} else if (is_vertical_bar) {
		col = mix(col, iron_highlight.rgb, cyl_highlight * 0.5);
		col = mix(col, iron_shadow.rgb, cyl_shadow * 0.55);
		alpha = 0.92;
	}

	if (is_rivet) {
		col = iron_highlight.rgb * 1.15;
		alpha = 1.0;
	}

	// 3. Пылающие руны и цепи магического барьера (запечатывающие проход во время боя)
	float pulse = sin(TIME * seal_pulse_speed + uv.x * 12.0) * 0.5 + 0.5;
	float rune_wave = sin(uv.x * 24.0 + uv.y * 14.0 - TIME * 4.0);
	float rune_chain = smoothstep(0.12, 0.0, abs(rune_wave)) * pulse;

	// Пространственный эфирный барьер в просветах между прутьями
	float void_barrier = (1.0 - alpha) * 0.35 * (0.6 + pulse * 0.4);
	if (alpha < 0.1) {
		col = rune_glow.rgb * 0.35;
		alpha = void_barrier;
	}

	// Свечение рун на решетке
	col = mix(col, rune_glow.rgb, rune_chain * 0.75);
	col += rune_glow.rgb * (pulse * 0.25);

	COLOR = vec4(col, alpha);
}
