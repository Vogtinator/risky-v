#version 310 es

precision mediump float;
precision highp int;
precision highp uimage2D;

#define SCREEN_WIDTH 640
#define SCREEN_HEIGHT 480

#define CONSOLE_WIDTH 40u
#define CONSOLE_HEIGHT 25u

#define MEMORY_STRIDE 1024u
#define MEMORY_CONSOLE_OFFSET 0u
uniform layout(r32ui) uimage2D memory;

#define FONT_TEX_WIDTH 3072
#define FONT_TEX_HEIGHT 18
// 307 characters in a row
#define CHAR_WIDTH uint(3072/307)
#define CHAR_HEIGHT FONT_TEX_HEIGHT
uvec2 char_size = uvec2(CHAR_WIDTH, CHAR_HEIGHT);
layout(binding = 0) uniform sampler2D font;

layout(location = 0) out vec4 fragColor;

uint readByte(uint addr)
{
    uint offset = addr / 4u;
    ivec2 mem_off = ivec2(offset / MEMORY_STRIDE, offset % MEMORY_STRIDE);
    uint byte = addr - (offset * 4u);
    return imageLoad(memory, mem_off).x >> (8u * byte);
}

void main()
{
    // Flip Y
    vec2 pixelcoord = vec2(gl_FragCoord.x, float(SCREEN_HEIGHT - 1) - gl_FragCoord.y);

    // Which position in the letter grid
    uvec2 char_pos = uvec2(pixelcoord) / char_size;
    if (char_pos.x >= CONSOLE_WIDTH || char_pos.y >= CONSOLE_HEIGHT) {
        fragColor = vec4(0.1, 0.8, 0.1, 1);
        return;
    }

    // Offset of the pixel within the letter
    vec2 char_off = pixelcoord - vec2(char_pos * char_size);

    // Load the character value from the console memory
    uint char_idx = char_pos.x + char_pos.y * CONSOLE_WIDTH;
    uint char_val = readByte(char_idx);
    char_val = char_idx;

    fragColor = texture(font, (vec2(float(char_val * CHAR_WIDTH), 0.0) + char_off) / vec2(FONT_TEX_WIDTH, FONT_TEX_HEIGHT));
    fragColor *= vec4(vec3(0.8), 1);
}
