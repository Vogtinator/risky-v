#version 310 es

precision mediump float;
precision highp int;
precision highp uimage2D;

#define SCREEN_WIDTH 640
#define SCREEN_HEIGHT 480

#define CONSOLE_WIDTH 40u
#define CONSOLE_HEIGHT 25u

#define MEMORY_STRIDE 2048u
#define MEMORY_CONSOLE_OFFSET 0x400u
#define MEMORY_RAM_OFFSET 0u
#define MEMORY_FRAMEBUFFER_OFFSET (MEMORY_RAM_OFFSET + 0x4000u)
#define MEMORY_FRAMEBUFFER_Y_START (MEMORY_FRAMEBUFFER_OFFSET/(MEMORY_STRIDE*4u))
uniform layout(r32ui) uimage2D memory;

#define FONT_TEX_WIDTH 3072
#define FONT_TEX_HEIGHT 18
// 256 characters in a row
#define CHAR_WIDTH uint(3072/256)
#define CHAR_HEIGHT FONT_TEX_HEIGHT
uvec2 char_size = uvec2(CHAR_WIDTH, CHAR_HEIGHT);
uniform sampler2D font;

layout(location = 0) out vec4 fragColor;

uint readByteRaw(uint addr)
{
    uint offset = addr / 4u;
    ivec2 mem_off = ivec2(offset % MEMORY_STRIDE, offset / MEMORY_STRIDE);
    uint byte = addr % 4u;
    return (imageLoad(memory, mem_off).x >> (8u * byte)) & 0xFFu;
}

vec3 readFramebufferPixel(ivec2 coord)
{
    uint argbraw = imageLoad(memory, ivec2(coord.x, coord.y + int(MEMORY_FRAMEBUFFER_Y_START))).x;
    uvec3 rgb = (uvec3(argbraw) >> uvec3(16u, 8u, 0u)) & uvec3(0xFFu);
    return vec3(rgb) / vec3(0xFF);
}

void main()
{
    // Flip Y
    vec2 pixelcoord = vec2(gl_FragCoord.x, float(SCREEN_HEIGHT - 1) - gl_FragCoord.y);

    // Which position in the letter grid
    uvec2 char_pos = uvec2(pixelcoord) / char_size;

    if (char_pos.y != 18u) {
        fragColor = vec4(readFramebufferPixel(ivec2(pixelcoord)), 1.0);
        return;
    }

    if (char_pos.x >= CONSOLE_WIDTH || char_pos.y >= CONSOLE_HEIGHT) {
        fragColor = vec4(0.1, 0.8, 0.1, 1);
        return;
    }

    // Offset of the pixel within the letter
    vec2 char_off = pixelcoord - vec2(char_pos * char_size);

    // Load the character value from the console memory
    uint char_idx = char_pos.x + char_pos.y * CONSOLE_WIDTH;
    uint char_val = readByteRaw(MEMORY_CONSOLE_OFFSET + char_idx);

    fragColor = texelFetch(font, ivec2(char_val * CHAR_WIDTH + uint(char_off.x), uint(char_off.y)), 0);
    fragColor *= vec4(vec3(0.8), 1);
}
