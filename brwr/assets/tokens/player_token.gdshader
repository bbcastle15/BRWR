shader_type canvas_item;
uniform vec4 player_color : source_color = vec4(1.0);
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float high = max(tex.r, max(tex.g, tex.b));
	float low = min(tex.r, min(tex.g, tex.b));
	float purple = smoothstep(0.10, 0.25, high - low);
	vec3 tinted = mix(player_color.rgb * high, vec3(high), 0.12);
	COLOR = vec4(mix(tex.rgb, tinted, purple), tex.a);
}
