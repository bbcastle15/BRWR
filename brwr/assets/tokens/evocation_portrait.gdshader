shader_type canvas_item;

void fragment() {
	vec4 portrait = texture(TEXTURE, UV);
	float radius = length(UV - vec2(0.5));
	float edge = max(fwidth(radius), 0.001);
	portrait.a *= 1.0 - smoothstep(0.5 - edge, 0.5, radius);
	COLOR = portrait;
}
