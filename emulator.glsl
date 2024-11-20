#version 310 es

precision mediump float;
precision highp int;
precision highp uimage2D;

#define MEMORY_STRIDE 2048u
#define MEMORY_CPU_OFFSET 0u
#define MEMORY_CONSOLE_OFFSET 0x400u
uniform layout(r32ui) uimage2D memory;

#define CONSOLE_WIDTH 40u

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

void writeRawByte(uint addr, uint value)
{
    uint byte = addr % 4u;
    uint word = readRaw(addr - byte);
    word &= ~(0xFFu << (byte * 8u));
    word |= (value & 0xFFu) << (byte * 8u);
    writeRaw(addr - byte, word);
}

struct {
    uint regs[32];
} cpu;

uint readMemWord(uint addr)
{
    return readRaw(addr + 0x1000u);
}

uint getReg(uint r)
{
    if (r == 0u)
        return 0u;
    else
        return cpu.regs[r];
}

void setReg(uint r, uint val)
{
    if (r == 0u)
        return;
    else
        cpu.regs[r] = val;
}

uint getPC()
{
    return cpu.regs[0];
}

void setPC(uint pc)
{
    cpu.regs[0] = pc;
}

void dumpHex(uint addr, uint val)
{
    for(uint pos = 0u; pos < 8u; ++pos) {
        uint nibble = val >> 28u;
        uint letter = (nibble < 10u) ? (nibble + 0x30u) : (nibble + 0x41u - 10u);
        writeRawByte(addr + pos, letter);
        val <<= 4u;
    }
}

void dumpCPUState()
{
    for(uint r = 0u; r < 32u; r++)
    {
        uint linestart = MEMORY_CONSOLE_OFFSET + (r/2u) * CONSOLE_WIDTH;
        writeRawByte(linestart++, 0x52u);
        writeRawByte(linestart++, 0x30u + (r / 10u));
        writeRawByte(linestart++, 0x30u + (r % 10u));
        writeRawByte(linestart++, 0x3Du);
        dumpHex(linestart, cpu.regs[r]);
        linestart += 10u;
        r++;

        writeRawByte(linestart++, 0x52u);
        writeRawByte(linestart++, 0x30u + (r / 10u));
        writeRawByte(linestart++, 0x30u + (r % 10u));
        writeRawByte(linestart++, 0x3Du);
        dumpHex(linestart, cpu.regs[r]);
    }
}

bool doInstruction()
{
    uint inst = readMemWord(getPC());
    if ((inst & 0x3u) != 0x3u) {
        return false;
    }

    cpu.regs[0] += 4u;
    return true;
}

void readCPUState()
{
    for(uint r = 0u; r < 32u; r++)
        cpu.regs[r] = readRaw(MEMORY_CPU_OFFSET + r * 4u);
}

void writeCPUState()
{
    for(uint r = 0u; r < 32u; r++)
        writeRaw(MEMORY_CPU_OFFSET + r * 4u, cpu.regs[r]);
}

void main()
{
    readCPUState();

    for(uint counter = 1u; counter > 0u; --counter)
        if (!doInstruction())
            break;

    dumpCPUState();
    writeCPUState();
}
