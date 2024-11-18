#version 310 es

precision mediump float;
precision highp int;
precision highp uimage2D;

#define CONSOLE_WIDTH 80u
#define CONSOLE_HEIGHT 25u

#define MEMORY_STRIDE 1024u
#define MEMORY_CONSOLE_OFFSET 0u
uniform layout(r32ui) uimage2D memory;

// 256 characters, each 8 * 10px
#define CHAR_WIDTH 8
#define CHAR_HEIGHT 10
uvec2 char_size = uvec2(CHAR_WIDTH, CHAR_HEIGHT);
uniform sampler2D font;

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
    // Which position in the letter grid
    uvec2 char_pos = uvec2(gl_FragCoord.xy) / char_size;
    if (char_pos.x >= CONSOLE_WIDTH || char_pos.y >= CONSOLE_HEIGHT) {
        fragColor = vec4(1, 1, 1, 1);
        return;
    }

    // Offset of the pixel within the letter
    vec2 char_off = gl_FragCoord.xy - vec2(char_pos * char_size);

    // Load the character value from the console memory
    uint char_idx = char_pos.x + char_pos.y * CONSOLE_WIDTH;
    uint char_val = readByte(char_idx);

    uvec2 font_pos = uvec2(char_val / 16u, char_val % 16u);
    fragColor = texture(font, vec2(font_pos * char_size) + char_off);
}
