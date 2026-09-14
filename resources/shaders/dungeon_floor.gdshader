shader_type canvas_item;
render_mode blend_mix;

// Non-repeating Procedural Flagstone Floor Shader
// Органические каменные плиты неправильной формы (Voronoi), непрерывный FBM-шум
// крупных пятен износа и влаги по мировым координатам (без монотонного повторения).

uniform vec4 stone_base : source_color = vec4(0.18, 0.18, 0.23, 1.0);
uniform vec4 stone_warm : source_color = vec4(0.24, 0.23, 0.28, 1.0);
uniform vec4 stone_dark : source_color = vec4(0.12, 0.12, 0.16, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.08, 0.08, 0.11, 1.0);
uniform float slab_scale = 0.012;

varying vec2 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash1(i);
	float b = hash1(i + vec2(1.0, 0.0));
	float c = hash1(i + vec2(0.0, 1.0));
	float d = hash1(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float val = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		val += noise(p) * amp;
		p = p * 2.05 + vec2(1.7, 4.3);
		amp *= 0.5;
	}
	return val;
}

// Вороной с вычислением расстояния до границы (шва) плиты
vec3 voronoi_slabs(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);

	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(n + g) * 0.65;
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}

	// Расстояние до швов между плитами
	float md_edge = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 o = hash2(n + g) * 0.65;
			vec2 r = g + o - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md_edge = min(md_edge, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}

	float slab_id = hash1(n + mg);
	return vec3(sqrt(md), md_edge, slab_id);
}

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	if (tex_color.a * COLOR.a < 0.05) {
		discard;
	}

	vec2 p = v_world_pos * slab_scale;

	// Вычисляем органические плиты
	vec3 slab_data = voronoi_slabs(p);
	float dist_to_seam = slab_data.y;
	float slab_id = slab_data.z;

	// Макро-шум: широкие градиенты цвета на всю комнату (300-400px), разбивающие повторение
	float macro_noise = fbm(v_world_pos * 0.0035);
	float damp_noise = fbm(v_world_pos * 0.012 + vec2(8.5, 3.1));

	// Базовый цвет камня с макро-вариацией и индивидуальным оттенком каждой плиты
	vec3 col = mix(stone_base.rgb, stone_warm.rgb, macro_noise * 0.6);
	col = mix(col, stone_dark.rgb, damp_noise * 0.4);
	col += (slab_id - 0.5) * 0.06;

	// Тонкие аккуратные швы раствора
	float seam = 1.0 - smoothstep(0.015, 0.05, dist_to_seam);

	// Мягкая фаска только у самого края шва
	float edge_bevel = smoothstep(0.015, 0.08, dist_to_seam) * (1.0 - smoothstep(0.08, 0.16, dist_to_seam));
	col += vec3(edge_bevel * 0.035);

	// Затемнение шва
	col = mix(col, mortar_color.rgb, seam * 0.85);

	// Тончайшая зернистость камня
	float grit = (hash1(v_world_pos * 0.35) - 0.5) * 0.025;
	col += grit;

	COLOR = vec4(col, tex_color.a);
}
