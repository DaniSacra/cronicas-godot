shader_type canvas_item;
// Contorno colorido: a borda de cima e da esquerda pega a luz fria, a de baixo e da direita a luz quente.
uniform vec4 rim_cool : source_color = vec4(0.45, 0.7, 1.0, 1.0);
uniform vec4 rim_warm : source_color = vec4(1.0, 0.55, 0.25, 1.0);
uniform float strength = 0.6;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	float up = texture(TEXTURE, UV + vec2(0.0, -px.y)).a;
	float left = texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
	float down = texture(TEXTURE, UV + vec2(0.0, px.y)).a;
	float right = texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	float cool = 1.0 - min(up, left);
	float warm = 1.0 - min(down, right);
	vec3 rim = (rim_cool.rgb * cool + rim_warm.rgb * warm) / max(cool + warm, 0.001);
	float edge = clamp(cool + warm, 0.0, 1.0) * c.a;
	c.rgb = mix(c.rgb, rim, edge * strength);
	COLOR = c;
}
