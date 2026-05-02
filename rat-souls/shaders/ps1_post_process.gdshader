shader_type canvas_item;

uniform sampler2D screen_texture: hint_screen_texture, repeat_disable, filter_nearest;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.22;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.12;
uniform float vignette_softness : hint_range(0.0, 2.0) = 1.2;
uniform float aberration_amount : hint_range(0.0, 0.01) = 0.005;

const float ps1_dither[16] = float[16](
	-4.0, 0.0, -3.0, 1.0,
	2.0, -2.0, 3.0, -1.0,
	-3.0, 1.0, -4.0, 0.0,
	3.0, -1.0, 2.0, -2.0
);

void fragment() {
	// Subtle chromatic aberration for that janky CRT feel
	vec2 uv_center = UV - 0.5;
	float dist_from_center = length(uv_center);
	vec2 aberration_offset = uv_center * aberration_amount * dist_from_center;

	float r = texture(screen_texture, UV + aberration_offset).r;
	float g = texture(screen_texture, UV).g;
	float b = texture(screen_texture, UV - aberration_offset).b;
	vec3 screen_colour = vec3(r, g, b);

	// PS1 colour quantization with ordered dithering
	int x = int(FRAGCOORD.x) % 4;
	int y = int(FRAGCOORD.y) % 4;
	int index = y * 4 + x;

	float dither_offset = (ps1_dither[index] / 8.0);
	vec3 quantized_colour = floor((screen_colour * 255.0) / 8.0 + dither_offset) / 31.0;

	// CRT scanlines — darken every other row slightly
	float scanline = 1.0 - (scanline_intensity * step(0.5, fract(FRAGCOORD.y / 2.0)));
	quantized_colour *= scanline;

	// Subtle vignette — barely-there edge darkening
	float vignette = 1.0 - smoothstep(1.0 - vignette_intensity, 1.0 - vignette_intensity + vignette_softness, dist_from_center * 2.0);
	quantized_colour *= vignette;

	COLOR = vec4(quantized_colour, 1);
}

