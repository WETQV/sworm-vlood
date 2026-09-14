shader_type canvas_item;
render_mode blend_mix;

// Fireball Plasma Shader — Процедурный плазменный огненный шар с турбулентными языками пламени,
// раскаленным белым ядром и затухающим огненным хвостом.

uniform vec4 core_color : source_color = vec4(1.0, 0.96, 0.70, 1.0);
uniform vec4 inner_flame : source_color = vec4(1.0, 0.45, 0.06, 1.0);
uniform vec4 outer_flame : source_color = vec4(0.85, 0.10, 0.02, 1.0);
uniform float speed = 9.0;

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

void fragment() {
	vec2 uv = UV;
	vec2 centered = uv - vec2(0.5);

	// Огненный хвост вытягивается назад (влево от центра)
	float tail = max(0.0, -centered.x);
	vec2 warped = centered;
	warped.y *= 1.0 + tail * 0.8;

	float dist = length(warped) * 2.1;

	// Турбулентные конвекционные вихри огня
	float n1 = noise(centered * 7.0 - vec2(TIME * speed, sin(TIME * 4.0) * 0.5));
	float n2 = noise(centered * 14.0 + vec2(TIME * speed * 1.4, 0.0));
	float turb = (n1 * 0.65 + n2 * 0.35 - 0.5) * 0.45;

	float fire_dist = dist + turb;

	// Цветовые зоны пламени
	float core = smoothstep(0.35, 0.05, dist);
	float inner = smoothstep(0.72, 0.15, fire_dist);
	float outer = smoothstep(1.05, 0.35, fire_dist);

	vec3 col = mix(outer_flame.rgb, inner_flame.rgb, inner);
	col = mix(col, core_color.rgb, core);

	// Корона свечения
	float glow = smoothstep(1.1, 0.0, length(centered) * 2.0) * 0.35;
	col += inner_flame.rgb * glow;

	float alpha = clamp(outer + glow * 0.5, 0.0, 1.0);
	COLOR = vec4(col, alpha);
}
