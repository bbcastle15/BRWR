shader_type canvas_item;
render_mode unshaded;
uniform vec4 rim_color : source_color = vec4(0.2, 0.4, 0.9, 1.0);
uniform bool exhausted = false;

void fragment() {
	vec2 uv = vec2((UV.x + (exhausted ? 1.0 : 0.0)) * 0.5, UV.y);
	vec4 face = texture(TEXTURE, uv);
	float sapphire = smoothstep(0.025, 0.14, face.b - face.r);
	float brightness = max(face.r, max(face.g, face.b));
	vec3 rim = brightness * mix(rim_color.rgb, vec3(1.0), 0.12 + 0.55 * pow(brightness, 3.0));
	COLOR = vec4(mix(face.rgb, rim, sapphire), face.a);
}
