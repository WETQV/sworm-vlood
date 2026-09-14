shader_type canvas_item;

uniform vec4 bg_color : source_color = vec4(0.07, 0.06, 0.09, 1.0);
uniform vec4 fog_color : source_color = vec4(0.16, 0.11, 0.22, 1.0);
uniform vec4 blood_accent : source_color = vec4(0.32, 0.06, 0.12, 1.0);
uniform float fog_speed : hint_range(0.01, 0.2) = 0.04;
uniform float vignette_intensity : hint_range(0.0, 2.0) = 0.75;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += noise(p) * amp;
		p = p * 2.0 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 uv = UV;
	float time = TIME * fog_speed;

	// Двухслойный туман подземелья (fbm noise)
	float n1 = fbm(uv * 3.5 + vec2(time * 0.5, time * 0.3));
	float n2 = fbm(uv * 5.0 - vec2(time * 0.4, -time * 0.2));
	float fog = smoothstep(0.2, 0.85, n1 * 0.6 + n2 * 0.4);

	// Пульсация темной багровой дымки
	float pulse = sin(TIME * 0.8) * 0.5 + 0.5;
	vec3 mixed_fog = mix(fog_color.rgb, blood_accent.rgb, pulse * 0.3);

	// Виньетирование по краям экрана
	vec2 dist_from_center = uv - vec2(0.5);
	float vig = clamp(1.1 - length(dist_from_center) * vignette_intensity, 0.0, 1.0);

	vec3 final_rgb = mix(bg_color.rgb, mixed_fog, fog * 0.55) * vig;
	COLOR = vec4(final_rgb, 1.0);
}
