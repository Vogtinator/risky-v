#version 310 es

precision mediump float;
precision highp int;
precision highp uimage2D;

#define MEMORY_STRIDE 1024u
#define MEMORY_CONSOLE_OFFSET 0u
uniform layout(r32ui) uimage2D memory;

uint readRaw(uint addr)
{
    uint offset = addr / 4u;
    ivec2 mem_off = ivec2(offset % MEMORY_STRIDE, offset / MEMORY_STRIDE);
    return imageLoad(memory, mem_off).x;
}

uint readRawByte(uint addr)
{
    uint byte = addr % 4u;
    uint word = readRaw(addr - byte);
    return (word >> (8u * byte)) & 0xFFu;
}

void writeRaw(uint addr, uint value)
{
    uint offset = addr / 4u;
    ivec2 mem_off = ivec2(offset % MEMORY_STRIDE, offset / MEMORY_STRIDE);
    imageStore(memory, mem_off, uvec4(value, 0, 0, 0));
}

void main()
{
    writeRaw(1u, readRaw(0u));
    writeRaw(0u, 0x33323130u);
}
