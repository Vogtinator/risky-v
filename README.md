RISKY-V: RISC-V System Emulator running on your GPU
==

RISKY-V emulates a RISC-V system using OpenGL ES 3.1 the emulator itself is written in GLSL and runs on the GPU as a fragment shader!

What it can do
--

M-mode and U-mode are implemented and by default 32MiB of memory are available to the VM. A 640x480px framebuffer is provided as output and 

What it can't do
--

S-mode and MMU support are not implemented, so many applications and libraries won't be available.

Keyboard input is currently implemented such that the key codes from the windowing system are passed straight to the emulated system, so the mappings are only accurate when using Wayland. With X11, keys will be mixed up.

Build and run it
--

Build a Linux kernel for riscv32 nommu. Important config options:

```
CONFIG_32BIT=y
CONFIG_RISCV_M_MODE=y
CONFIG_SERIAL_EARLYCON_SEMIHOST=y
CONFIG_FB_SIMPLE=y
CONFIG_VT_CONSOLE=y
CONFIG_RISCV_SLOW_UNALIGNED_ACCESS=y
CONFIG_GPIO_GENERIC_PLATFORM=y
CONFIG_KEYBOARD_GPIO_POLLED=y
```

You can build an initramfs of your choice and embed it into the kernel build.

It also requires `CONFIG_PAGE_OFFSET=0x00400000`, but for some reason that's hardcoded in Kconfig and needs a patch:

```diff
diff --git a/arch/riscv/Kconfig b/arch/riscv/Kconfig
index ff1e353b0d6f..7c07151cfed2 100644
--- a/arch/riscv/Kconfig
+++ b/arch/riscv/Kconfig
@@ -285,7 +285,7 @@ config MMU
 
 config PAGE_OFFSET
        hex
-       default 0x80000000 if !MMU && RISCV_M_MODE
+       default 0x00400000 if !MMU && RISCV_M_MODE
        default 0x80200000 if !MMU
        default 0xc0000000 if 32BIT
        default 0xff60000000000000 if 64BIT
```

Build the kernel:

```
make -j8 ARCH=riscv CC="clang -target riscv32" HOSTCC=clang HOSTCXX=clang++ LD=ld
```

Link or copy the resulting `arch/riscv/boot/Image` into the risky-v directory.

Run `make` to generate resource files and build the main executable, then run `./main`.

Press F11 to switch between framebuffer view (default) and console view. The latter shows the content of registers and the last line of the semihosting console.

How it works
--
TODO.

License and External Resources
--

While the RISKY-V code is licensed under the [GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html), some files are from external projects and subject to their individual licenses:

consolefont.png: https://lucide.github.io/Font-Atlas-Generator/ Using Classic Console, 3072x18px, 256 cells per row, 12x18px cells, font size 14pt.

glad.c/glad.h/khrplatform.h: Generated from https://glad.dav1d.de. gles2 3.1 with all available extensions.
