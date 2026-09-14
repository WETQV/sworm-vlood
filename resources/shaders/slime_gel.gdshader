shader_type canvas_item;
render_mode blend_mix;

// Slime Gel Shader — Живое объёмное желе с плавающими органическими краями,
// светящимся пульсирующим ядром, внутренними пузырьками и бликом (Game Juice).

instance uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 base_color : source_color = vec4(0.28, 0.82, 0.32, 1.0);
uniform vec4 rim_color : source_color = vec4(0.10, 0.45, 0.16, 1.0);
uniform vec4 core_color : source_color = vec4(0.70, 0.98, 0.58, 1.0);
uniform float wobble_speed : hint_range(0.5, 10.0) = 4.2;
uniform float wobble_intensity : hint_range(0.0, 0.1) = 0.032;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);
	float angle = atan(uv.y, uv.x);

	// 1. Плавающие живые грани (органическая деформация периметра)
	float w1 = sin(angle * 4.0 + TIME * wobble_speed) * wobble_intensity;
	float w2 = cos(angle * 2.0 - TIME * (wobble_speed * 0.6)) * (wobble_intensity * 0.6);
	float w3 = sin(angle * 6.0 + TIME * (wobble_speed * 1.3)) * (wobble_intensity * 0.35);
	float radius = 0.44 + w1 + w2 + w3;

	// Альфа-маска формы капли желе
	float alpha = 1.0 - smoothstep(radius - 0.02, radius + 0.01, dist);
	if (alpha <= 0.001) {
		discard;
	}

	// 2. Внешняя мембрана / темный контур желе
	float rim = smoothstep(radius - 0.09, radius, dist);

	// 3. Плавающее светящееся ядро (nucleus) со смещением от дыхания
	vec2 core_pos = vec2(sin(TIME * 2.2) * 0.04, cos(TIME * 1.8) * 0.035);
	float core_dist = length(uv - core_pos);
	float core = 1.0 - smoothstep(0.0, 0.22, core_dist);

	// 4. Внутренние жидкие пузырьки / преломление
	float bubbles = sin((uv.x + core_pos.x) * 26.0 + TIME * 2.5) * cos((uv.y - core_pos.y) * 26.0 - TIME * 2.0);
	bubbles = clamp(bubbles * 0.5 + 0.5, 0.0, 1.0);

	// 5. Глянцевый блик света сверху-слева (spherical specular)
	float spec = 1.0 - smoothstep(0.0, 0.11, length(uv - vec2(-0.14, -0.15)));

	// Смешивание слоев цвета
	vec3 col = mix(base_color.rgb, rim_color.rgb, rim * 0.75);
	col = mix(col, core_color.rgb, core * 0.65);
	col += (bubbles * 0.12) * base_color.rgb;
	col += spec * 0.60;

	// Эффект вспышки урона (Hit Flash)
	col = mix(col, flash_color.rgb, flash_modifier);

	COLOR = vec4(col, alpha * base_color.a);
}
