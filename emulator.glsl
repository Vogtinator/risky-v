#version 310 es

#define MEMORY_CONSOLE_OFFSET 0
uniform sampler1D memory;

void main(out vec4 fragColor, in vec2 fragCoord)
{
    fragColor = vec4(0.1, 0.8, 0.1, 1);
}
