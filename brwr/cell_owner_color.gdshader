shader_type canvas_item;

uniform vec4 owner_color : source_color = vec4(1.0);

void fragment() {
	vec4 art = texture(TEXTURE, UV);
	// The shared Cell artwork encodes only its mage symbol in magenta.
	// Limit recoloring to the upper parchment, preserving the identical interior.
	if (UV.x > 0.44 && UV.x < 0.56 && UV.y > 0.10 && UV.y < 0.19) {
		float mask = max(min(art.r, art.b) - art.g, 0.0);
		art.rgb += (owner_color.rgb - vec3(1.0, 0.0, 1.0)) * mask;
	}
	COLOR = art;
}
