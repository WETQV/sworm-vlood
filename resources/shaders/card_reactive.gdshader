shader_type canvas_item;

uniform vec4 bg_color : source_color = vec4(0.08, 0.06, 0.11, 0.95);
uniform vec4 border_color : source_color = vec4(0.35, 0.28, 0.18, 0.8);
uniform vec4 hover_border_color : source_color = vec4(0.85, 0.68, 0.35, 1.0);
uniform vec4 select_border_color : source_color = vec4(1.0, 0.88, 0.48, 1.0);
uniform vec4 accent_color : source_color = vec4(0.8, 0.2, 0.2, 1.0);

uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform float select_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 card_size = vec2(210.0, 310.0);
uniform float corner_radius_px = 4.0;
uniform float border_width_px = 2.0;

float rounded_box(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + vec2(r);
	return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

void fragment() {
	vec2 half_size = card_size * 0.5;
	vec2 p = (UV - 0.5) * card_size;
	
	float dist = rounded_box(p, half_size, corner_radius_px);
	
	// Dark obsidian background with subtle class tint
	vec4 base_bg = mix(bg_color, vec4(accent_color.rgb * 0.12, bg_color.a), select_amount * 0.5 + hover_amount * 0.25);
	// Vertical subtle gradient (slightly lighter at top)
	base_bg.rgb += vec3(0.02, 0.015, 0.025) * (0.5 - UV.y);
	
	// Shimmer effect (diagonal glint sweep)
	float speed = 0.35 + hover_amount * 0.25 + select_amount * 0.35;
	float shimmer_pos = fract(TIME * speed);
	float diag = UV.x * 0.65 + UV.y * 0.35;
	float shimmer_dist = abs(diag - shimmer_pos * 1.5 + 0.25);
	float shimmer = smoothstep(0.08, 0.0, shimmer_dist);
	float shimmer_strength = 0.08 + hover_amount * 0.22 + select_amount * 0.32;
	base_bg.rgb += select_border_color.rgb * shimmer * shimmer_strength;
	
	// Border animation & color interpolation
	float pulse = 0.88 + 0.12 * sin(TIME * 3.5);
	vec4 active_border = mix(border_color, hover_border_color, hover_amount);
	active_border = mix(active_border, select_border_color * pulse, select_amount);
	
	// Anti-aliased border mask
	float border_edge = smoothstep(-border_width_px, -border_width_px + 1.2, dist);
	vec4 col = mix(base_bg, active_border, border_edge);
	
	// Soft inner glow when hovered or selected
	float inner_glow = smoothstep(-border_width_px * 6.0, -border_width_px, dist);
	float glow_strength = hover_amount * 0.18 + select_amount * 0.35 * pulse;
	col.rgb += mix(hover_border_color.rgb, accent_color.rgb, 0.35) * inner_glow * glow_strength;
	
	// Anti-aliased outer edge transparency
	float outer_alpha = 1.0 - smoothstep(0.0, 1.2, dist);
	col.a *= outer_alpha;
	
	COLOR = col;
}
