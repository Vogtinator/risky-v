#version 310 es

precision mediump float;
precision highp int;
precision highp uimage2D;

// Width of the memory texture
#define MEMORY_STRIDE 2048u
// Size of the memory texture contents
#define MEMORY_SIZE_BYTES (MEMORY_STRIDE*2048u*4u)
// Offset of various structures within the memory texture
#define MEMORY_CPU_OFFSET 0u
#define MEMORY_CONSOLE_OFFSET 0x400u
#define MEMORY_RAM_OFFSET 0x1000u
#define MEMORY_RAM_SIZE (MEMORY_SIZE_BYTES-MEMORY_RAM_OFFSET)
uniform layout(r32ui) uimage2D memory;

#define CONSOLE_WIDTH 40u

// Read and write words in the memory image. Address in bytes, must be word aligned.
uint readRawWord(uint addr)
{
    uint offset = addr / 4u;
    ivec2 mem_off = ivec2(offset % MEMORY_STRIDE, offset / MEMORY_STRIDE);
    return imageLoad(memory, mem_off).x;
}

void writeRawWord(uint addr, uint value)
{
    uint offset = addr / 4u;
    ivec2 mem_off = ivec2(offset % MEMORY_STRIDE, offset / MEMORY_STRIDE);
    imageStore(memory, mem_off, uvec4(value, 0, 0, 0));
}

// RMW functions for non word sized accesses.
uint readRawHalf(uint addr)
{
    uint part = (addr % 4u) / 2u;
    uint word = readRawWord(addr - part*2u);
    return (word >> (16u * part)) & 0xFFFFu;
}

uint readRawByte(uint addr)
{
    uint byte = addr % 4u;
    uint word = readRawWord(addr - byte);
    return (word >> (8u * byte)) & 0xFFu;
}

void writeRawHalf(uint addr, uint value)
{
    uint part = (addr % 4u) / 2u;
    uint word = readRawWord(addr - part*2u);
    word &= ~(0xFFFFu << (part * 16u));
    word |= (value & 0xFFFFu) << (part * 16u);
    writeRawWord(addr - part*2u, word);
}

void writeRawByte(uint addr, uint value)
{
    uint byte = addr % 4u;
    uint word = readRawWord(addr - byte);
    word &= ~(0xFFu << (byte * 8u));
    word |= (value & 0xFFu) << (byte * 8u);
    writeRawWord(addr - byte, word);
}

// Print the hex value of val to the memory image at the given addr.
void dumpHex(uint addr, uint val)
{
    for(uint pos = 0u; pos < 8u; ++pos) {
        uint nibble = val >> 28u;
        uint letter = (nibble < 10u) ? (nibble + 0x30u) : (nibble + 0x61u - 10u);
        writeRawByte(addr + pos, letter);
        val <<= 4u;
    }
}

// If set, returns false from doInstruction.
bool stop = false;

// Print "E: code value" below the register view.
void errorVal(uint code, uint value)
{
    uint linestart = MEMORY_CONSOLE_OFFSET + 17u * CONSOLE_WIDTH;
    writeRawByte(linestart++, 0x45u);
    writeRawByte(linestart++, 0x20u);
    dumpHex(linestart, code);
    linestart += 9u;
    dumpHex(linestart, value);
    stop = true;
}

#define CSR_MIP 0u
#define CSR_MIE 1u
#define CSR_MSCRATCH 2u
#define CSR_MTVEC 3u
#define CSR_MSTATUS 4u
#define CSR_MEPC 5u
#define CSR_MTVAL 6u
#define CSR_MCAUSE 7u
#define CSR_COUNT 8u

#define BIT_MIE_TIE (1u << 7u)
#define BIT_MSTATUS_MIE (1u << 3u)
#define BIT_MSTATUS_MPIE (1u << 7u)
#define SHIFT_MSTATUS_MPP 11u

#define SMH_LINE_OFFSET 0u
#define CLINT_TIMER_VALL 1u
#define CLINT_TIMER_VALH 2u
#define CLINT_TIMER_CMPL 3u
#define CLINT_TIMER_CMPH 4u
#define HW_REGS_COUNT 5u

struct {
    uint pc;
    uint regs[32];
    uint csrs[CSR_COUNT];
    uint hwstate[HW_REGS_COUNT];
} cpu;

uint readMemWord(uint addr)
{
    if (addr < MEMORY_RAM_SIZE)
        return readRawWord(addr + MEMORY_RAM_OFFSET);
    else if (addr == 0xF000BFF8u)
        return cpu.hwstate[CLINT_TIMER_VALL];
    else if (addr == 0xF000BFFCu)
        return cpu.hwstate[CLINT_TIMER_VALH];
    else {
        errorVal(14u, addr);
        return 0u;
    }
}

uint readMemHalf(uint addr)
{
    if (addr < MEMORY_RAM_SIZE)
        return readRawHalf(addr + MEMORY_RAM_OFFSET);
    else {
        errorVal(15u, addr);
        return 0u;
    }
}

uint readMemByte(uint addr)
{
    if (addr < MEMORY_RAM_SIZE)
        return readRawByte(addr + MEMORY_RAM_OFFSET);
    else {
        errorVal(16u, addr);
        return 0u;
    }
}

void writeMemWord(uint addr, uint value)
{
    if (addr < MEMORY_RAM_SIZE)
        writeRawWord(addr + MEMORY_RAM_OFFSET, value);
    else if (addr == 0xF0004000u)
        cpu.hwstate[CLINT_TIMER_CMPL] = value;
    else if (addr == 0xF0004004u)
        cpu.hwstate[CLINT_TIMER_CMPH] = value;
    else
        errorVal(17u, addr);
}

void writeMemHalf(uint addr, uint value)
{
    if (addr < MEMORY_RAM_SIZE)
        writeRawHalf(addr + MEMORY_RAM_OFFSET, value);
    else
        errorVal(18u, addr);
}

void writeMemByte(uint addr, uint value)
{
    if (addr < MEMORY_RAM_SIZE)
        writeRawByte(addr + MEMORY_RAM_OFFSET, value);
    else
        errorVal(19u, addr);
}

uint getReg(uint r)
{
    return cpu.regs[r];
}

void setReg(uint r, uint val)
{
    if (r != 0u)
        cpu.regs[r] = val;
}

uint getPC()
{
    return cpu.pc;
}

void setPC(uint pc)
{
    cpu.pc = pc;
}

void dumpCPUState()
{
    for(uint r = 0u; r < 32u; r++)
    {
        uint linestart = MEMORY_CONSOLE_OFFSET + (r/2u) * CONSOLE_WIDTH;
        if(r == 0u) {
            // "PC: "
            writeRawByte(linestart++, 0x50u);
            writeRawByte(linestart++, 0x43u);
            writeRawByte(linestart++, 0x3Du);
            writeRawByte(linestart++, 0x20u);
            dumpHex(linestart, cpu.pc);
        } else {
            // "Rnr:"
            writeRawByte(linestart++, 0x52u);
            writeRawByte(linestart++, 0x30u + (r / 10u));
            writeRawByte(linestart++, 0x30u + (r % 10u));
            writeRawByte(linestart++, 0x3Du);
            dumpHex(linestart, cpu.regs[r]);
        }
        linestart += 10u;
        r++;

        writeRawByte(linestart++, 0x52u);
        writeRawByte(linestart++, 0x30u + (r / 10u));
        writeRawByte(linestart++, 0x30u + (r % 10u));
        writeRawByte(linestart++, 0x3Du);
        dumpHex(linestart, cpu.regs[r]);
    }
}

uint getCSR(uint csr)
{
    switch(csr)
    {
        case 0x300u:
            return cpu.csrs[CSR_MSTATUS];
        case 0x304u:
            return cpu.csrs[CSR_MIE];
        case 0x340u:
            return cpu.csrs[CSR_MSCRATCH];
        case 0x341u:
            return cpu.csrs[CSR_MEPC];
        case 0x342u:
            return cpu.csrs[CSR_MCAUSE];
        case 0x343u:
            return cpu.csrs[CSR_MTVAL];
        case 0xF11u: // mvendorid
        case 0xF12u: // marchid
        case 0xF13u: // mimpid
            return 0u;
        case 0xF14u: // mhartid
            return 0u;
        default:
            errorVal(3u, csr);
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
        case 0x341u:
            cpu.csrs[CSR_MEPC] = value;
            return;
        case 0x342u:
            cpu.csrs[CSR_MCAUSE] = value;
            return;
        case 0x343u:
            cpu.csrs[CSR_MTVAL] = value;
            return;
        case 0x344u:
            cpu.csrs[CSR_MIP] = value;
            return;
        case 0x3A0u: // pmpcfg0
            return;
        case 0x3B0u: // pmpaddr0
            return;
        case 0xF11u: // mvendorid
        case 0xF12u: // marchid
        case 0xF13u: // mimpid
            return;
        case 0xF14u: // mhartid
            return;
        default:
            errorVal(4u, csr);
            return;
    }
}

void handleMret()
{
    uint mstatus = cpu.csrs[CSR_MSTATUS];

    // Set mstatus.mie to mstatus.mpie
    if ((mstatus & BIT_MSTATUS_MPIE) != 0u)
        mstatus |= BIT_MSTATUS_MIE;
    else
        mstatus &= ~BIT_MSTATUS_MIE;

    // Go into mstatus.mpp mode
    uint newpriv = (mstatus >> SHIFT_MSTATUS_MPP) & 3u;
    if (newpriv != 3u)
        errorVal(21u, newpriv);

    // Set mstatus.mpp to U
    mstatus &= ~(3u << SHIFT_MSTATUS_MPP);

    cpu.csrs[CSR_MSTATUS] = mstatus;
    setPC(cpu.csrs[CSR_MEPC]);
}

void handleInterrupt(uint cause)
{
    cpu.csrs[CSR_MCAUSE] = cause;
    cpu.csrs[CSR_MEPC] = getPC();
    setPC(cpu.csrs[CSR_MTVEC]);

    uint mstatus = cpu.csrs[CSR_MSTATUS];

    // Set mstatus.mpie to mstatus.mie
    if ((mstatus & BIT_MSTATUS_MIE) != 0u)
        mstatus |= BIT_MSTATUS_MPIE;
    else
        mstatus &= ~BIT_MSTATUS_MPIE;

    // Clear mstatus.mie
    mstatus &= ~BIT_MSTATUS_MIE;

    // Set mstatus.mpp to M
    // TODO: User mode stuff
    mstatus &= ~(3u << SHIFT_MSTATUS_MPP);
    mstatus |= 3u << SHIFT_MSTATUS_MPP;

    cpu.csrs[CSR_MSTATUS] = mstatus;
}

bool doInstruction()
{
    uint inst = readMemWord(getPC());
    uint opc = inst & 0x7Fu;
    if ((inst & 0x3u) != 0x3u) {
        errorVal(0u, inst);
        return false;
    }

    switch(opc)
    {
        case 0x03u: // load
        {
            uint funct3 = (inst >> 12u) & 7u;
            uint rd = (inst >> 7u) & 31u;
            uint rs1 = (inst >> 15u) & 31u;
            int imm = int(inst) >> 20u;
            switch (funct3)
            {
                case 0u: // lh
                    setReg(rd, readMemByte(uint(int(getReg(rs1)) + imm)));
                    break;
                case 1u: // lh
                    setReg(rd, uint(int(readMemHalf(uint(int(getReg(rs1)) + imm)) << 16u) >> 16u));
                    break;
                case 2u: // lw
                    setReg(rd, readMemWord(uint(int(getReg(rs1)) + imm)));
                    break;
                case 4u: // lbu
                    setReg(rd, readMemByte(uint(int(getReg(rs1)) + imm)));
                    break;
                case 5u: // lhu
                    setReg(rd, readMemHalf(uint(int(getReg(rs1)) + imm)));
                    break;
                default:
                    errorVal(8u, funct3);
                    return false;
            }
            break;
        }
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
            uint rawimm = inst >> 20u;
            switch (funct3)
            {
                case 0x0u: // addi
                    setReg(rd, uint(int(getReg(rs1)) + imm));
                    break;
                case 0x1u: // slli
                    if ((rawimm >> 5u) == 0x00u) // slli
                        setReg(rd, getReg(rs1) << (rawimm & 31u));
                    else {
                        errorVal(12u, rawimm);
                        return false;
                    }
                    break;
                case 0x2u: // slti
                    setReg(rd, (int(getReg(rs1)) < imm) ? 1u : 0u);
                    break;
                case 0x3u: // sltiu
                    setReg(rd, (getReg(rs1) < rawimm) ? 1u : 0u);
                    break;
                case 0x4u: // xori
                    setReg(rd, getReg(rs1) ^ uint(imm));
                    break;
                case 0x5u: // sr(l,a)i
                    if ((rawimm >> 5u) == 0x00u) // srli
                        setReg(rd, getReg(rs1) >> (rawimm & 31u));
                    else if ((rawimm >> 5u) == 0x20u) // srai
                        setReg(rd, uint(int(getReg(rs1)) >> (rawimm & 31u)));
                    else {
                        errorVal(11u, rawimm);
                        return false;
                    }
                    break;
                case 0x6u: // ori
                    setReg(rd, getReg(rs1) | uint(imm));
                    break;
                case 0x7u: // andi
                    setReg(rd, getReg(rs1) & uint(imm));
                    break;
                default:
                    errorVal(5u, funct3);
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
                case 0u: // sb
                    writeMemByte(uint(int(getReg(rs1)) + imm), getReg(rs2));
                    break;
                case 1u: // sh
                    writeMemHalf(uint(int(getReg(rs1)) + imm), getReg(rs2));
                    break;
                case 2u: // sw
                    writeMemWord(uint(int(getReg(rs1)) + imm), getReg(rs2));
                    break;
                default:
                    errorVal(7u, funct3);
                    return false;
            }
            break;
        }
        case 0x2fu: // atomic extension
        {
            uint funct3 = (inst >> 12u) & 7u;
            uint rd = (inst >> 7u) & 31u;
            uint rs1 = (inst >> 15u) & 31u;
            uint rs2 = (inst >> 20u) & 31u;
            uint funct7 = inst >> 25u;

            // For atomic, ignore aq and rl bits
            if (funct3 == 2u)
                funct7 &= ~3u;
            
            switch((funct3 << 8u) | funct7)
            {
                case 0x200u: // amoadd
                {
                    uint addr = getReg(rs1);
                    uint val = readMemWord(addr);
                    writeMemWord(addr, val + getReg(rs2));
                    setReg(rd, val);
                    break;
                }
                case 0x204u: // amoswap
                {
                    // TODO: Is this correct? Several docs disagree...
                    uint addr = getReg(rs1);
                    uint val = readMemWord(addr);
                    uint regval = getReg(rs2);
                    writeMemWord(addr, regval);
                    setReg(rd, val);
                    break;
                }
                case 0x208u: // lr
                    if (rs2 != 0u) {
                        errorVal(12u, rs2);
                        return false;
                    }

                    setReg(rd, readMemWord(getReg(rs1)));
                    break;
                case 0x20cu: // sc
                    writeMemWord(getReg(rs1), getReg(rs2));
                    setReg(rd, 0u);
                    break;
                case 0x220u: // amoor
                {
                    uint addr = getReg(rs1);
                    uint val = readMemWord(addr);
                    writeMemWord(addr, val | getReg(rs2));
                    setReg(rd, val);
                    break;
                }
                case 0x230u: // amoand
                {
                    uint addr = getReg(rs1);
                    uint val = readMemWord(addr);
                    writeMemWord(addr, val & getReg(rs2));
                    setReg(rd, val);
                    break;
                }
                default:
                    errorVal(9u, (funct3 << 8u) | (funct7));
                    return false;
            }
            break;
        }
        case 0x33u: // integer register
        {
            uint funct3 = (inst >> 12u) & 7u;
            uint rd = (inst >> 7u) & 31u;
            uint rs1 = (inst >> 15u) & 31u;
            uint rs2 = (inst >> 20u) & 31u;
            uint funct7 = inst >> 25u;

            switch((funct3 << 8u) | funct7)
            {
                case 0x000u: // add
                    setReg(rd, getReg(rs1) + getReg(rs2));
                    break;
                case 0x001u: // mul
                    setReg(rd, getReg(rs1) * getReg(rs2));
                    break;
                case 0x020u: // sub
                    setReg(rd, getReg(rs1) - getReg(rs2));
                    break;
                case 0x100u: // sll
                    setReg(rd, getReg(rs1) << (getReg(rs2) & 31u));
                    break;
                case 0x101u: // mulh
                {
                    // TODO: Correct signedness?
                    int lres, hres;
                    imulExtended(int(getReg(rs1)), int(getReg(rs2)), hres, lres);
                    setReg(rd, uint(hres));
                    break;
                }
                case 0x200u: // slt
                    setReg(rd, (int(getReg(rs1)) < int(getReg(rs2))) ? 1u : 0u);
                    break;
                case 0x300u: // sltu
                    setReg(rd, (getReg(rs1) < getReg(rs2)) ? 1u : 0u);
                    break;
                case 0x301u: // mul(h)u
                {
                    uint lres, hres;
                    umulExtended(getReg(rs1), getReg(rs2), hres, lres);
                    setReg(rd, hres);
                    break;
                }
                case 0x400u: // xor
                    setReg(rd, getReg(rs1) ^ getReg(rs2));
                    break;
                case 0x401u: // div
                    setReg(rd, uint(int(getReg(rs1)) / int(getReg(rs2))));
                    break;
                case 0x500u: // srl
                    setReg(rd, getReg(rs1) >> (getReg(rs2) & 31u));
                    break;
                case 0x501u: // divu
                    setReg(rd, getReg(rs1) / getReg(rs2));
                    break;
                case 0x520u: // sra
                    setReg(rd, uint(int(getReg(rs1)) >> (getReg(rs2) & 31u)));
                    break;
                case 0x600u: // or
                    setReg(rd, getReg(rs1) | getReg(rs2));
                    break;
                case 0x601u: // rem
                    // TODO: Signedness correct?
                    setReg(rd, uint(int(getReg(rs1)) % int(getReg(rs2))));
                    break;
                case 0x700u: // and
                    setReg(rd, getReg(rs1) & getReg(rs2));
                    break;
                case 0x701u: // remu
                    setReg(rd, getReg(rs1) % getReg(rs2));
                    break;
                default:
                    errorVal(10u, (funct3 << 8u) | funct7);
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
            uint rs1valu = getReg(rs1);
            uint rs2valu = getReg(rs2);
            uint imm12 = inst >> 31u;
            uint imm105 = (inst >> 25u) & 0x3fu;
            uint imm41 = (inst >> 8u) & 0xfu;
            uint imm11 = (inst >> 7u) & 0x1u;
            int imm = int(((imm12 << 12u) | (imm11 << 11u) | (imm105 << 5u) | (imm41 << 1u)) << 19u) >> 19u;
            bool take = false;
            switch (funct3)
            {
                case 0u: // beq
                    take = rs1valu == rs2valu;
                    break;
                case 1u: // bne
                    take = rs1valu != rs2valu;
                    break;
                case 4u: // blt
                    take = rs1vals < rs2vals;
                    break;
                case 5u: // bge
                    take = rs1vals >= rs2vals;
                    break;
                case 6u: // bltu
                    take = rs1valu < rs2valu;
                    break;
                case 7u: // bgeu
                    take = rs1valu >= rs2valu;
                    break;
                default:
                    errorVal(6u, funct3);
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

            uint retaddr = getPC() + 4u;
            setPC(uint(int(getReg(rs1)) + imm));
            setReg(rd, retaddr);

            return true;
        }
        case 0x6fu: // jal
        {
            uint rd = (inst >> 7u) & 0x1Fu;
            uint bit20 = inst >> 31u;
            uint bit101 = (inst >> 21u) & 0x3FFu;
            uint bit11 = (inst >> 20u) & 1u;
            uint bit1912 = (inst >> 12u) & 0xFFu;
            int imm = int(((bit20 << 20u) | (bit1912 << 12u) | (bit11 << 11u) | (bit101 << 1u)) << 11u) >> 11u;
            setReg(rd, getPC() + 4u);
            setPC(uint(int(getPC()) + imm));
            return true;
        }
        case 0x73u: // SYSTEM
        {
            uint funct3 = (inst >> 12u) & 0x7u;
            switch(funct3)
            {
                case 0u: // Misc stuff
                {
                    if(inst == 0x00100073u) // EBREAK
                    {
                        uint op = getReg(10u);
                        if (op == 3u) {
                            // smh putc
                            uint char = readMemByte(getReg(11u));
                            if (char == 0x0au)
                                cpu.hwstate[SMH_LINE_OFFSET] = 0u;
                            else
                                writeRawByte(MEMORY_CONSOLE_OFFSET + 18u * CONSOLE_WIDTH + cpu.hwstate[SMH_LINE_OFFSET]++, char);
                        } else {
                            // Kernel BUG/WARN, pass it
                            handleInterrupt(3u);
                            return true;
                        }
                    } else if(inst == 0x10500073u) {
                        // WFI
                        // TODO: Forward until next interrupt?
                        break;
                    } else if(inst == 0x30200073u) {
                        // MRET
                        handleMret();
                        return true;
                    } else {
                        errorVal(14u, inst);
                    }
                    break;
                }
                case 1u: // CSRRW
                {
                    uint csr = inst >> 20u;
                    uint rd = (inst >> 7u) & 31u;
                    uint rs1 = (inst >> 15u) & 31u;
                    uint rs1val = getReg(rs1);
                    if (rd != 0u) {
                        setReg(rd, getCSR(csr));
                    }
                    setCSR(csr, rs1val);
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
                case 6u: // CSRRSI
                {
                    uint csr = inst >> 20u;
                    uint rd = (inst >> 7u) & 31u;
                    uint imm = (inst >> 15u) & 31u;
                    uint csrval = getCSR(csr);
                    setReg(rd, getCSR(csr));
                    setCSR(csr, csrval | imm);
                    break;
                }
                case 7u: // CSRRCI
                {
                    uint csr = inst >> 20u;
                    uint rd = (inst >> 7u) & 31u;
                    uint imm = (inst >> 15u) & 31u;
                    uint csrval = getCSR(csr);
                    setReg(rd, getCSR(csr));
                    setCSR(csr, csrval & ~imm);
                    break;
                }
                default:
                    errorVal(2u, funct3);
                    return false;
            }
            break;
        }
        default:
            errorVal(1u, inst);
            return false;
    }

    if (stop)
        return false;

    cpu.pc += 4u;
    return true;
}

// Dumps struct cpu to MEMORY_CPU_OFFSET.
// cpu.pc is written in place of cpu.regs[0].
void readCPUState()
{
    uint ptr = MEMORY_CPU_OFFSET;

    cpu.pc = readRawWord(ptr);
    ptr += 4u;
    cpu.regs[0] = 0u;

    for(uint r = 1u; r < 32u; r++, ptr += 4u)
        cpu.regs[r] = readRawWord(ptr);

    for(uint r = 0u; r < CSR_COUNT; r++, ptr += 4u)
        cpu.csrs[r] = readRawWord(ptr);

    for(uint r = 0u; r < HW_REGS_COUNT; r++, ptr += 4u)
        cpu.hwstate[r] = readRawWord(ptr);
}

void writeCPUState()
{
    uint ptr = MEMORY_CPU_OFFSET;

    writeRawWord(ptr, cpu.pc);
    ptr += 4u;

    for(uint r = 1u; r < 32u; r++, ptr += 4u)
        writeRawWord(ptr, cpu.regs[r]);

    for(uint r = 0u; r < CSR_COUNT; r++, ptr += 4u)
        writeRawWord(ptr, cpu.csrs[r]);

    for(uint r = 0u; r < HW_REGS_COUNT; r++, ptr += 4u)
        writeRawWord(ptr, cpu.hwstate[r]);
}

void main()
{
    if (gl_FragCoord.xy != vec2(0.5, 0.5))
        return;

    readCPUState();

    for(uint ticks = 128u; ticks > 0u; --ticks)
    {
        // Run 64 instructions in between timer ticks
        for(uint cycles = 64u; cycles > 0u; --cycles)
            if (!doInstruction())
                break;

        // TODO: Handle VALH and CMPH
        cpu.hwstate[CLINT_TIMER_VALL]++;

        // Check for interrupts
        if(cpu.hwstate[CLINT_TIMER_VALL] >= cpu.hwstate[CLINT_TIMER_CMPL])
            cpu.csrs[CSR_MIP] |= BIT_MIE_TIE;

        if((cpu.csrs[CSR_MSTATUS] & BIT_MSTATUS_MIE) != 0u)
        {
            uint ipend = cpu.csrs[CSR_MIP] & cpu.csrs[CSR_MIE];
            if(ipend == BIT_MIE_TIE)
                handleInterrupt(0x80000007u); // IRQ 7
            else if (ipend != 0u) {
                errorVal(20u, ipend);
                break;
            }
        }
    }

    dumpCPUState();
    writeCPUState();
}
