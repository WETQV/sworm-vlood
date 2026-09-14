shader_type canvas_item;
render_mode blend_mix;

// Portal Swirl Shader — Космический пространственный разлом с закручивающимся вихрем,
// пульсирующим горизонтом событий, бездонным ядром и эфирными плавающими гранями.

uniform vec4 void_color : source_color = vec4(0.12, 0.03, 0.24, 1.0);
uniform vec4 rune_color : source_color = vec4(0.75, 0.25, 0.98, 1.0);
uniform vec4 rim_glow_color : source_color = vec4(0.92, 0.70, 1.0, 1.0);
uniform float swirl_speed : hint_range(0.5, 6.0) = 2.4;
uniform float wave_intensity : hint_range(0.0, 0.1) = 0.025;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float r = length(uv);
	float a = atan(uv.y, uv.x);

	// 1. Плавающие грани горизонта событий (эфирная воронка)
	float rim_wave = sin(a * 5.0 + TIME * 3.2) * wave_intensity + cos(a * 3.0 - TIME * 2.1) * (wave_intensity * 0.6);
	float max_radius = 0.46 + rim_wave;

	float alpha = 1.0 - smoothstep(max_radius - 0.03, max_radius + 0.01, r);
	if (alpha <= 0.001) {
		discard;
	}

	// 2. Закручивающийся пространственный вихрь (Archimedean log spiral)
	float twist = a + (1.25 / (r + 0.18)) - TIME * swirl_speed;
	float arm1 = sin(twist * 4.0 + sin(r * 16.0 - TIME * 3.0));
	float arm2 = cos(twist * 6.0 - cos(r * 10.0 + TIME * 2.5));
	float energy = clamp((arm1 * 0.5 + 0.5) * (arm2 * 0.5 + 0.5) * 1.6, 0.0, 1.0);

	// 3. Бездонное ядро в центре портала (The Abyss)
	float core_depth = smoothstep(0.04, 0.24, r);

	// 4. Светящийся внешний обод (Event Horizon Ring)
	float rim_ring = smoothstep(max_radius - 0.12, max_radius - 0.03, r) * (1.0 - smoothstep(max_radius - 0.03, max_radius, r));
	rim_ring *= 2.8;

	// 5. Пульсирующие светящиеся волны от центра к краям
	float pulse = sin(r * 22.0 - TIME * 5.0) * 0.5 + 0.5;

	// Композиция цветов
	vec3 col = void_color.rgb;
	col = mix(col, rune_color.rgb, energy * core_depth);
	col += rune_color.rgb * (pulse * 0.25 * core_depth);
	col += rim_glow_color.rgb * rim_ring;

	// Центр уходит в темную бездну
	col *= mix(0.15, 1.0, core_depth);

	COLOR = vec4(col, alpha * 0.92);
}
