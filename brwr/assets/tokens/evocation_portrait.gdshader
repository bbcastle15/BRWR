shader_type canvas_item;
uniform vec4 portrait_region = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	vec4 portrait = texture(TEXTURE, UV);
	vec2 portrait_uv = (UV - portrait_region.xy) / portrait_region.zw;
	float radius = length(portrait_uv - vec2(0.5));
	float edge = max(fwidth(radius), 0.001);
	portrait.a *= 1.0 - smoothstep(0.5 - edge, 0.5, radius);
	COLOR = portrait;
}
