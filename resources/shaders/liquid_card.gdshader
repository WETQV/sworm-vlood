shader_type canvas_item;

uniform vec4 bg_color : source_color = vec4(0.07, 0.05, 0.10, 0.96);
uniform vec4 border_color : source_color = vec4(0.32, 0.25, 0.16, 0.85);
uniform vec4 hover_border_color : source_color = vec4(0.86, 0.68, 0.32, 1.0);
uniform vec4 select_border_color : source_color = vec4(1.0, 0.88, 0.46, 1.0);
uniform vec4 accent_color : source_color = vec4(0.85, 0.20, 0.22, 1.0);

uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform float select_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 card_size = vec2(220.0, 340.0);
uniform float corner_radius_px = 16.0;
uniform float border_width_px = 2.5;

float rounded_box(vec2 pos, vec2 b, float r) {
	vec2 d = abs(pos) - b + vec2(r);
	return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

void fragment() {
	vec2 half_size = card_size * 0.5;
	vec2 p = (UV - 0.5) * card_size;
	
	// Плавное, спокойное органическое дыхание контура с фиксированной фазой
	// (НИКАКИХ прыжков частоты от TIME!)
	float angle = atan(p.y, p.x);
	float wave_raw = sin(angle * 3.0 + TIME * 1.3) * 0.7 + cos(angle * 4.0 - TIME * 1.0) * 0.5;
	float wave_amplitude = 0.7 + hover_amount * 0.3 + select_amount * 0.2;
	float wave = wave_raw * wave_amplitude;
	
	float dist = rounded_box(p, half_size - vec2(4.0), corner_radius_px) + wave;
	
	// Внутренний глубокий фон вязкой жидкости
	vec4 fluid_col = bg_color;
	
	// Медленное, медитативное свечение акцентным цветом из глубины
	float center_dist = length(p / half_size);
	float radial_glow = clamp(1.0 - center_dist, 0.0, 1.0);
	float inner_intensity = 0.08 + hover_amount * 0.14 + select_amount * 0.28;
	fluid_col.rgb += accent_color.rgb * (radial_glow * radial_glow) * inner_intensity;
	
	// Мягкая виньетка по краям
	fluid_col.rgb *= clamp(1.1 - center_dist * 0.3, 0.75, 1.15);
	
	// Цвет жидкого ободка: плавный переход от бронзы к золоту/акценту
	float pulse = 0.90 + 0.10 * sin(TIME * 2.8);
	vec4 active_border = mix(border_color, hover_border_color, hover_amount);
	active_border = mix(active_border, select_border_color * pulse, select_amount);
	
	// Отрисовка границы с чистым сглаживанием
	float border_mask = smoothstep(-border_width_px, -border_width_px + 1.3, dist);
	vec4 col = mix(fluid_col, active_border, border_mask);
	
	// Внутренний мениск натяжения жидкости (спокойный, чистый ободок)
	float meniscus = smoothstep(-border_width_px * 3.5, -border_width_px, dist) 
	               * (1.0 - smoothstep(-border_width_px, -border_width_px + 1.0, dist));
	col.rgb += mix(active_border.rgb, accent_color.rgb, 0.35) * meniscus * (0.35 + hover_amount * 0.35 + select_amount * 0.55 * pulse);
	
	// Внешняя прозрачность (анти-алиасинг)
	float outer_alpha = 1.0 - smoothstep(0.0, 1.4, dist);
	col.a *= outer_alpha;
	
	COLOR = col;
}
