shader_type canvas_item;

uniform vec4 core_color : source_color = vec4(0.05, 0.04, 0.08, 0.85);
uniform vec4 rim_color : source_color = vec4(0.40, 0.32, 0.20, 0.9);
uniform vec4 glow_color : source_color = vec4(0.85, 0.20, 0.22, 0.6);
uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform float select_amount : hint_range(0.0, 1.0) = 0.0;
uniform float radius_px = 36.0;

void fragment() {
	vec2 center = vec2(0.5);
	vec2 p = (UV - center) * (radius_px * 2.5);
	float r = length(p);
	float angle = atan(p.y, p.x);
	
	// Органическое дыхание капли/сферы с фиксированной фазой
	float wave_raw = sin(angle * 3.0 + TIME * 1.4) * 1.0 + cos(angle * 4.0 - TIME * 1.1) * 0.6;
	float wave_amp = 0.8 + hover_amount * 0.3 + select_amount * 0.2;
	float target_r = radius_px + wave_raw * wave_amp;
	
	float dist = r - target_r;
	
	// Внутреннее наполнение: глубокая жидкость с радиальным свечением
	float norm_r = clamp(r / radius_px, 0.0, 1.0);
	vec4 col = core_color;
	
	// Акцентное свечение из центра
	float core_glow = 1.0 - norm_r;
	col.rgb += glow_color.rgb * (core_glow * core_glow) * (0.4 + hover_amount * 0.3 + select_amount * 0.5);
	
	// Ободок сферы
	float border_width = 2.0;
	float border_mask = smoothstep(-border_width, -border_width + 1.2, dist);
	vec4 active_rim = mix(rim_color, glow_color, 0.4 + hover_amount * 0.3 + select_amount * 0.3);
	col = mix(col, active_rim, border_mask);
	
	// Верхний водяной/линзовый блик (specular reflection)
	vec2 spec_pos = UV - vec2(0.38, 0.35);
	float spec_dist = length(spec_pos * (radius_px * 2.5));
	float spec = smoothstep(12.0, 0.0, spec_dist);
	col.rgb += vec3(1.0, 0.95, 0.9) * spec * (0.25 + hover_amount * 0.2);
	
	// Прозрачность за пределами органического круга
	float alpha = 1.0 - smoothstep(0.0, 1.5, dist);
	col.a *= alpha;
	
	COLOR = col;
}
