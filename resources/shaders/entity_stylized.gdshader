shader_type canvas_item;
render_mode blend_mix;

// Entity Stylized Shader — Тактильный 2.5D объёмный жетон персонажа
// с купольным сферическим освещением, бликом (specular), резной металлической окантовкой
// и уникальной классовой эмблемой в центре (Воин, Лучник, Маг, Паладин).

instance uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 base_color : source_color = vec4(0.25, 0.45, 0.90, 1.0);
uniform vec4 aura_color : source_color = vec4(0.85, 0.75, 0.35, 1.0);
uniform float corner_radius : hint_range(0.05, 0.5) = 0.24;
uniform float breath_speed : hint_range(0.5, 5.0) = 2.4;
uniform float breath_amount : hint_range(0.0, 0.05) = 0.015;

// -1 = нет эмблемы, 0 = Воин (мечи), 1 = Рейнджер (стрела), 2 = Маг (руна), 3 = Паладин (крест)
uniform int class_type : hint_range(-1, 3) = -1;

float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void fragment() {
	vec2 p = UV - vec2(0.5);

	// 1. Дыхание формы
	float breath = sin(TIME * breath_speed) * breath_amount;
	vec2 half_size = vec2(0.44 + breath, 0.44 - breath * 0.6);

	float d = rounded_box(p, half_size, corner_radius);

	// Маска жетона
	float alpha = 1.0 - smoothstep(0.0, 0.02, d);
	if (alpha <= 0.001) {
		discard;
	}

	float edge_dist = -d;

	// 2. Купольное 2.5D сферическое освещение с объемом
	vec2 norm_xy = p * 2.2;
	float len_sq = dot(norm_xy, norm_xy);
	float z = sqrt(max(0.0, 1.0 - len_sq));
	vec3 N = normalize(vec3(norm_xy, z * 1.4));
	vec3 L = normalize(vec3(-0.45, -0.65, 0.75));

	float diffuse = clamp(dot(N, L), 0.30, 1.15);
	vec3 col = base_color.rgb * diffuse;

	// Спекулярный блик (глянцевый отблеск сверху-слева)
	vec3 V = vec3(0.0, 0.0, 1.0);
	vec3 R = reflect(-L, N);
	float specular = pow(max(0.0, dot(R, V)), 14.0) * 0.38;
	col += vec3(specular);

	// 3. Тактильная фаска и металлическая окантовка жетона
	float inner_rim = smoothstep(0.0, 0.08, edge_dist);
	float outer_contour = 1.0 - smoothstep(0.0, 0.03, edge_dist);
	col = mix(col, vec3(0.06, 0.06, 0.10), outer_contour * 0.75);

	// Окантовочный золотистый/светлый кант
	float rim_highlight = smoothstep(0.06, 0.0, abs(edge_dist - 0.05)) * (p.y < 0.0 ? 1.0 : 0.4);
	col += aura_color.rgb * rim_highlight * 0.45;

	// 4. Гравированная классовая эмблема в центре
	float len_p = length(p);
	if (class_type >= 0 && len_p < 0.28) {
		float emblem_mask = 0.0;
		vec3 emblem_col = vec3(1.0);

		if (class_type == 0) {
			// Воин: скрещенные стальные клинки
			float sw1 = 1.0 - smoothstep(0.0, 0.024, abs((p.x + p.y) * 0.7071));
			float sw2 = 1.0 - smoothstep(0.0, 0.024, abs((p.x - p.y) * 0.7071));
			emblem_mask = max(sw1, sw2) * step(len_p, 0.19);
			emblem_col = vec3(0.92, 0.95, 1.0);
		} else if (class_type == 1) {
			// Рейнджер: острие стрелы и крылья сокола
			float arrow = 1.0 - smoothstep(0.0, 0.025, abs(abs(p.x) - (p.y + 0.07) * 0.75));
			arrow *= step(-0.15, p.y) * step(p.y, 0.15);
			float tip = 1.0 - smoothstep(0.0, 0.03, length(p - vec2(0.0, -0.12)));
			emblem_mask = max(arrow, tip * 0.7);
			emblem_col = vec3(0.35, 1.0, 0.65);
		} else if (class_type == 2) {
			// Маг: 4-лучевая мистическая звезда и пылающее ядро
			float star = 1.0 - smoothstep(0.0, 0.025, (abs(p.x) + abs(p.y)) - 0.14);
			float core = 1.0 - smoothstep(0.0, 0.055, len_p);
			emblem_mask = max(star, core);
			emblem_col = vec3(0.55, 0.85, 1.0);
		} else if (class_type == 3) {
			// Паладин: лучистый святой крест
			float c_v = (1.0 - smoothstep(0.0, 0.035, abs(p.x))) * step(abs(p.y), 0.18);
			float c_h = (1.0 - smoothstep(0.0, 0.035, abs(p.y))) * step(abs(p.x), 0.14);
			float halo = 1.0 - smoothstep(0.0, 0.065, len_p);
			emblem_mask = max(max(c_v, c_h), halo);
			emblem_col = vec3(1.0, 0.94, 0.45);
		}

		// Легкое свечение эмблемы с пульсацией
		float emblem_pulse = 0.85 + 0.15 * sin(TIME * 3.2);
		col = mix(col, emblem_col * emblem_pulse, emblem_mask * 0.88);
		// Мягкая фаска вокруг эмблемы (вдавленный барельеф)
		col += vec3(emblem_mask * 0.15);
	}

	// 5. Вспышка урона (Hit Flash)
	col = mix(col, flash_color.rgb, flash_modifier);

	COLOR = vec4(col, alpha * base_color.a);
}
