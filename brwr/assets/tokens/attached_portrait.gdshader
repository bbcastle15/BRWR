shader_type canvas_item;
uniform vec4 portrait_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 mage_center = vec2(-0.05, 0.5);
uniform vec4 rim_color : source_color = vec4(0.45, 0.25, 0.6, 1.0);
uniform bool attached = true;
uniform float cut_radius = 0.409;
void fragment() {
	vec2 p = (UV - portrait_region.xy) / portrait_region.zw;
	float outer = length(p - vec2(0.5));
	float inner = length(p - mage_center);
	float aa = max(fwidth(outer), 0.002);
	float coverage = 1.0 - smoothstep(0.5 - aa, 0.5, outer);
	if (attached) coverage *= smoothstep(cut_radius, cut_radius + aa, inner);
	vec4 ink = texture(TEXTURE, UV);
	float rim = smoothstep(0.439, 0.455, outer);
	if (attached) rim = max(rim, 1.0 - smoothstep(cut_radius + 0.012, cut_radius + 0.028, inner));
	ink.rgb = mix(ink.rgb, rim_color.rgb, rim);
	COLOR = vec4(ink.rgb, ink.a * coverage);
}
