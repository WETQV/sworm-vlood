shader_type canvas_item;

uniform vec4 vial_bg : source_color = vec4(0.08, 0.06, 0.10, 0.9);
uniform vec4 liquid_color : source_color = vec4(0.85, 0.20, 0.25, 1.0);
uniform vec4 liquid_glow : source_color = vec4(1.0, 0.35, 0.35, 1.0);
uniform vec4 glass_rim : source_color = vec4(0.35, 0.28, 0.20, 0.7);

uniform float progress : hint_range(0.0, 1.0) = 0.75;
uniform vec2 bar_size = vec2(140.0, 16.0);
uniform float corner_radius = 4.0;

float rounded_box(vec2 pos, vec2 b, float r) {
	vec2 d = abs(pos) - b + vec2(r);
	return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

void fragment() {
	vec2 half_size = bar_size * 0.5;
	vec2 p = (UV - 0.5) * bar_size;
	
	float dist = rounded_box(p, half_size - vec2(1.0), corner_radius);
	
	// Вне колбы: прозрачно
	float outer_alpha = 1.0 - smoothstep(0.0, 1.2, dist);
	
	// Внутренний фон колбы (пустая часть пробирки)
	vec4 col = vial_bg;
	
	// Волновой уровень жидкости
	float wave = sin(TIME * 2.5 + UV.y * 8.0) * 0.008;
	float fluid_boundary = progress + wave;
	
	// Жидкость заполнена до progress
	if (UV.x < fluid_boundary) {
		// Градиент жидкости внутри колбы
		float fluid_depth = UV.y;
		vec4 f_col = mix(liquid_color, liquid_glow, (1.0 - fluid_depth) * 0.4);
		
		// Мениск на правом крае столбика жидкости
		float meniscus = smoothstep(fluid_boundary - 0.03, fluid_boundary, UV.x);
		f_col.rgb += liquid_glow.rgb * meniscus * 0.6;
		
		// Внутренний микро-блик
		float core_shine = smoothstep(0.7, 0.2, abs(UV.y - 0.5));
		f_col.rgb += vec3(0.15) * core_shine;
		
		col = f_col;
	}
	
	// Стеклянный блик на верхней кромке колбы (glass highlight)
	float top_shine = smoothstep(0.25, 0.05, UV.y) * 0.25;
	col.rgb += vec3(1.0, 0.95, 0.9) * top_shine;
	
	// Ободок стеклянной капсулы
	float border_mask = smoothstep(-1.5, -0.2, dist);
	col = mix(col, glass_rim, border_mask);
	
	col.a *= outer_alpha;
	COLOR = col;
}
