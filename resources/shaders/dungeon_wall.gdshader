shader_type canvas_item;
render_mode blend_mix;

// Stylized Ashlar Dungeon Wall Shader — Благородная тесаная каменная кладка.
// Монолитная поверхность со сглаженными блоками без грубых лоуполи-трещин Voronoi.
// Точные 2.5D карнизы и тени строго по внешнему периметру на основе мировых координат.

uniform vec4 wall_base : source_color = vec4(0.25, 0.25, 0.32, 1.0);
uniform vec4 wall_highlight : source_color = vec4(0.38, 0.39, 0.48, 1.0);
uniform vec4 wall_dark : source_color = vec4(0.13, 0.13, 0.18, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.08, 0.08, 0.12, 1.0);

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
		p = p * 2.08 + vec2(2.3, 4.7);
		amp *= 0.5;
	}
	return val;
}

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	if (tex_color.a < 0.05) {
		discard;
	}

	// Декодируем целочисленную битовую маску из COLOR.r:
	// bit 0 (1): стена сверху (North)
	// bit 1 (2): стена снизу (South)
	// bit 2 (4): стена слева (West)
	// bit 3 (8): стена справа (East)
	// Учитываем нормализацию на базовый цвет текстуры атласа, чтобы модуляция не искажалась
	float raw_r = tex_color.r > 0.05 ? clamp(COLOR.r / tex_color.r, 0.0, 1.0) : COLOR.r;
	int mask = int(round(raw_r * 15.0));
	bool has_n = (mask & 1) != 0;
	bool has_s = (mask & 2) != 0;
	bool has_w = (mask & 4) != 0;
	bool has_e = (mask & 8) != 0;

	// Точные непрерывные координаты пикселя внутри тайла 64×64 (строго 0.0..64.0)
	vec2 px = v_world_pos - floor(v_world_pos / 64.0) * 64.0;

	// --- 1. Благородная тесаная каменная кладка (Ashlar Running Bond) ---
	const float BLOCK_W = 48.0;
	const float BLOCK_H = 24.0;

	vec2 wp = v_world_pos + vec2(fbm(v_world_pos * 0.08) * 1.5, fbm(v_world_pos * 0.08 + 3.0) * 1.5);
	float row_idx = floor(wp.y / BLOCK_H);
	float row_stagger = (mod(row_idx, 2.0) > 0.5) ? (BLOCK_W * 0.5) : 0.0;

	float col_idx = floor((wp.x + row_stagger) / BLOCK_W);
	float u = fract((wp.x + row_stagger) / BLOCK_W) * BLOCK_W;
	float v = fract(wp.y / BLOCK_H) * BLOCK_H;

	float dist_x = min(u, BLOCK_W - u);
	float dist_y = min(v, BLOCK_H - v);
	float dist_seam = min(dist_x, dist_y);

	// Уникальный тон каждого блока
	float block_id = hash1(vec2(col_idx, row_idx));

	// Макро-фактура старения камня
	float macro = fbm(v_world_pos * 0.005);
	float damp = fbm(v_world_pos * 0.012 + vec2(7.3, 2.9));

	vec3 base = mix(wall_base.rgb, wall_highlight.rgb, macro * 0.40);
	base = mix(base, wall_dark.rgb, damp * 0.30);
	base += (block_id - 0.5) * 0.06;

	// Мягкая 2.5D выпуклость (подушкообразность) каждого тесаного блока
	float block_bevel_x = smoothstep(0.0, 6.0, dist_x);
	float block_bevel_y = smoothstep(0.0, 6.0, dist_y);
	float stone_pillow = (block_bevel_x * block_bevel_y);

	// Свет сверху-слева на каждом блоке
	float light_x = smoothstep(0.0, 8.0, u) - smoothstep(BLOCK_W - 8.0, BLOCK_W, u);
	float light_y = smoothstep(0.0, 6.0, v) - smoothstep(BLOCK_H - 6.0, BLOCK_H, v);
	float stone_light = (light_x * 0.5 + light_y * 0.7) * 0.12;

	base += vec3(stone_light);

	// Тонкие аккуратные швы раствора
	float mortar_seam = 1.0 - smoothstep(0.5, 1.8, dist_seam);
	vec3 masonry_col = mix(base, mortar_color.rgb, mortar_seam * 0.75);

	// Нежная естественная зернистость камня
	float grit = (hash1(v_world_pos * 0.4) - 0.5) * 0.025;
	masonry_col += grit;

	vec3 col = masonry_col;

	// Мягкое затенение основания стены у пола (Южная грань) — естественная 2.5D глубина без обводок
	if (!has_s) {
		float bottom_dist = 64.0 - px.y;
		float base_shadow = 1.0 - smoothstep(0.0, 10.0, bottom_dist);
		col = mix(col, wall_dark.rgb, base_shadow * 0.40);
	}

	// Деликатный свет на верхнем срезе стены (Северная грань)
	if (!has_n) {
		float top_rim = 1.0 - smoothstep(0.0, 5.0, px.y);
		col += wall_highlight.rgb * top_rim * 0.22;
	}

	COLOR = vec4(col, 1.0);
}
