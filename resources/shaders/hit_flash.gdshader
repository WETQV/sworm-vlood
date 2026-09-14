shader_type canvas_item;
render_mode blend_mix;

// instance uniform allows every entity to share one material with independent flash
instance uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	// In Godot 4 CanvasItem, COLOR already contains vertex color (ColorRect.color)
	// and texture(TEXTURE, UV) * COLOR if textured.
	vec4 base_color = COLOR;
	vec3 mixed_color = mix(base_color.rgb, flash_color.rgb, clamp(flash_modifier, 0.0, 1.0));
	COLOR = vec4(mixed_color, base_color.a);
}
