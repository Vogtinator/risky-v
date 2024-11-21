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

#define CSR_MIP 0u
#define CSR_MIE 1u
#define CSR_MSCRATCH 2u
#define CSR_MTVEC 3u
#define CSR_MSTATUS 4u
#define CSR_COUNT 5u

struct {
    uint regs[32];
    uint csrs[CSR_COUNT];
} cpu;

uint readMemWord(uint addr)
{
    return readRaw(addr + 0x1000u);
}

void writeMemWord(uint addr, uint value)
{
    writeRaw(addr + 0x1000u, value);
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

bool stop = false;

void error(uint code)
{
    uint linestart = MEMORY_CONSOLE_OFFSET + 17u * CONSOLE_WIDTH;
    writeRawByte(linestart++, 0x45u);
    writeRawByte(linestart++, 0x20u);
    dumpHex(linestart++, code);
    stop = true;
}

uint getCSR(uint csr)
{
    switch(csr)
    {
        case 0x300u:
            return cpu.csrs[CSR_MSTATUS];
        case 0xF14u: // mhartid
            return 0u;
        default:
            error(3u);
            return 0u;
    }
}

void setCSR(uint csr, uint value)
{
    switch(csr)
    {
        case 0x300u:
            cpu.csrs[CSR_MSTATUS] = value;
            return;
        case 0x304u:
            cpu.csrs[CSR_MIE] = value;
            return;
        case 0x305u:
            cpu.csrs[CSR_MTVEC] = value;
            return;
        case 0x340u:
            cpu.csrs[CSR_MSCRATCH] = value;
            return;
        case 0x344u:
            cpu.csrs[CSR_MIP] = value;
            // TODO: Clear stuff
            return;
        case 0x3A0u: // pmpcfg0
            return;
        case 0x3B0u: // pmpaddr0
            return;
        case 0xF14u: // mhartid
            return;
        default:
            error(4u);
            return;
    }
}

bool doInstruction()
{
    uint inst = readMemWord(getPC());
    uint opc = inst & 0x7Fu;
    if ((inst & 0x3u) != 0x3u) {
        error(0u);
        return false;
    }

    switch(opc)
    {
        case 0x0fu: // fence.i and others
        {
            // TODO
            break;
        }
        case 0x13u: // integer immediate
        {
            uint funct3 = (inst >> 12u) & 7u;
            uint rd = (inst >> 7u) & 31u;
            uint rs1 = (inst >> 15u) & 31u;
            int imm = int(inst) >> 20u;
            switch (funct3)
            {
                case 0x0u:
                {
                    setReg(rd, uint(int(getReg(rs1)) + imm));
                    break;
                }
                default:
                    error(5u);
                    return false;
            }
            break;
        }
        case 0x17u: // auipc
        {
            uint rd = (inst >> 7u) & 0x1Fu;
            setReg(rd, getPC() + (inst & 0xFFFFF000u));
            break;
        }
        case 0x23u: // store
        {
            uint funct3 = (inst >> 12u) & 7u;
            uint rs1 = (inst >> 15u) & 31u;
            uint rs2 = (inst >> 20u) & 31u;
            int imm = ((int(inst) >> 25u) << 5u) | int((inst >> 7u) & 0x1Fu);
            switch (funct3)
            {
                case 2u: // sw
                    writeMemWord(uint(int(getReg(rs1)) + imm), getReg(rs2));
                    break;
                default:
                    error(7u);
                    return false;
            }
            break;
        }
        case 0x37u: // lui
        {
            uint rd = (inst >> 7u) & 0x1Fu;
            setReg(rd, inst & 0xFFFFF000u);
            break;
        }
        case 0x63u: // branch
        {
            uint funct3 = (inst >> 12u) & 7u;
            uint rs1 = (inst >> 15u) & 31u;
            uint rs2 = (inst >> 20u) & 31u;
            int rs1vals = int(getReg(rs1));
            int rs2vals = int(getReg(rs2));
            uint imm12 = inst >> 31u;
            uint imm105 = (inst >> 25u) & 0x3fu;
            uint imm41 = (inst >> 8u) & 0xfu;
            uint imm11 = (inst >> 7u) & 0x1u;
            int imm = int(((imm12 << 12u) | (imm11 << 11u) | (imm105 << 5u) | (imm41 << 1u)) << 19u) >> 19u;
            bool take = false;
            switch (funct3)
            {
                case 5u: // bge
                    take = rs1 >= rs2;
                    break;
                default:
                    error(6u);
                    return false;
            }
            if (take) {
                setPC(uint(int(getPC()) + imm));
                return true;
            }
            break;
        }
        case 0x67u: // jalr
        {
            uint rd = (inst >> 7u) & 0x1Fu;
            uint rs1 = (inst >> 15u) & 31u;
            int imm = int(inst) >> 20u;
            setReg(rd, getPC() + 4u);
            setPC(uint(int(getReg(rs1)) + imm));
            return true;
        }
        case 0x6fu: // jal
        {
            uint rd = (inst >> 7u) & 0x1Fu;
            uint bit20 = inst >> 31u;
            uint bit101 = (inst >> 21u) & 0x3FFu;
            uint bit11 = (inst >> 20u) & 1u;
            uint bit1912 = (inst >> 12u) & 0xFFu;
            int imm = int(((bit20 << 20u) | (bit1912 << 12u) | (bit11 << 11u) | (bit101 << 1u)) << 12u) >> 12u;
            setReg(rd, getPC() + 4u);
            setPC(uint(int(getPC()) + imm));
            return true;
        }
        case 0x73u: // SYSTEM
        {
            uint funct3 = (inst >> 12u) & 0x7u;
            switch(funct3)
            {
                case 1u: // CSRRW
                {
                    uint csr = inst >> 20u;
                    uint rd = (inst >> 7u) & 31u;
                    if (rd != 0u) {
                        setReg(rd, getCSR(csr));
                    }
                    uint rs1 = (inst >> 15u) & 31u;
                    setCSR(csr, getReg(rs1));
                    break;
                }
                case 2u: // CSRRS
                {
                    uint csr = inst >> 20u;
                    uint rd = (inst >> 7u) & 31u;
                    uint rs1 = (inst >> 15u) & 31u;
                    uint csrval = getCSR(csr);
                    uint rs1val = getReg(rs1);
                    setReg(rd, getCSR(csr));
                    setCSR(csr, csrval | rs1val);
                    break;
                }
                case 3u: // CSRRC
                {
                    uint csr = inst >> 20u;
                    uint rd = (inst >> 7u) & 31u;
                    uint rs1 = (inst >> 15u) & 31u;
                    uint csrval = getCSR(csr);
                    uint rs1val = getReg(rs1);
                    setReg(rd, getCSR(csr));
                    setCSR(csr, csrval & ~rs1val);
                    break;
                }
                case 5u: // CSRWI
                {
                    uint csr = inst >> 20u;
                    uint rd = (inst >> 7u) & 31u;
                    if (rd != 0u) {
                        setReg(rd, getCSR(csr));
                    }
                    uint imm = (inst >> 15u) & 31u;
                    setCSR(csr, imm);
                    break;
                }
                default:
                    error(2u);
                    return false;
            }
            break;
        }
        default:
            error(1u);
            return false;
    }

    if (stop)
        return false;

    cpu.regs[0] += 4u;
    return true;
}

void readCPUState()
{
    for(uint r = 0u; r < 32u; r++)
        cpu.regs[r] = readRaw(MEMORY_CPU_OFFSET + r * 4u);

    for(uint r = 0u; r < CSR_COUNT; r++)
        cpu.csrs[r] = readRaw(MEMORY_CPU_OFFSET + (32u * 4u) + r * 4u);
}

void writeCPUState()
{
    for(uint r = 0u; r < 32u; r++)
        writeRaw(MEMORY_CPU_OFFSET + r * 4u, cpu.regs[r]);

    for(uint r = 0u; r < CSR_COUNT; r++)
        writeRaw(MEMORY_CPU_OFFSET + (32u * 4u) + r * 4u, cpu.csrs[r]);
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
