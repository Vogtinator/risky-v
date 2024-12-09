RISKY-V: RISC-V System Emulator running on your GPU
==

RISKY-V emulates a RISC-V system using OpenGL ES 3.1 the emulator itself is written in GLSL and runs on the GPU as a fragment shader!

What it can do
--

M-mode and U-mode are implemented and by default 32MiB of memory are available to the VM. A 640x480px framebuffer is provided as output and keyboard buttons are passed through as GPIO.

It can boot Linux and run some programs! You do need some patience.

[Booting and logging in to Linux](https://github.com/user-attachments/assets/97839ddf-15c8-4901-8f37-bd4d68c9addd)

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

If using buildroot, run `make uclibc-menuconfig` and set `PTHREADS_STACK_DEFAULT_SIZE` to something like 256k instead of the default 2MiB, otherwise some programs run out of memory.
Several programs like nano and prboom don't set the stack size large enough and corrupt memory:

```diff
diff --git a/package/Makefile.in b/package/Makefile.in
index 82963690..d2783734 100644
--- a/package/Makefile.in
+++ b/package/Makefile.in
@@ -210,7 +210,7 @@ ifeq ($(BR2_riscv),y)
 TARGET_CFLAGS += -fPIC
 endif
 ELF2FLT_FLAGS = $(if $($(PKG)_FLAT_STACKSIZE),\
-       -Wl$(comma)-elf2flt="-r -s$($(PKG)_FLAT_STACKSIZE)",\
+       -Wl$(comma)-elf2flt=-r$(comma)-elf2flt=-s$($(PKG)_FLAT_STACKSIZE),\
         -Wl$(comma)-elf2flt=-r)
 TARGET_CFLAGS += $(ELF2FLT_FLAGS)
 TARGET_CXXFLAGS += $(ELF2FLT_FLAGS)
diff --git a/package/nano/nano.mk b/package/nano/nano.mk
index a1b94c90..105702a4 100644
--- a/package/nano/nano.mk
+++ b/package/nano/nano.mk
@@ -11,6 +11,7 @@ NANO_SOURCE = nano-$(NANO_VERSION).tar.xz
 NANO_LICENSE = GPL-3.0+
 NANO_LICENSE_FILES = COPYING
 NANO_DEPENDENCIES = ncurses
+NANO_FLAT_STACKSIZE=0x100000
 
 ifeq ($(BR2_PACKAGE_NCURSES_WCHAR),y)
 NANO_CONF_ENV += ac_cv_prog_NCURSESW_CONFIG=$(STAGING_DIR)/usr/bin/$(NCURSES_CONFIG_SCRIPTS)
diff --git a/package/prboom/prboom.mk b/package/prboom/prboom.mk
index c1ba05ff..4d074acd 100644
--- a/package/prboom/prboom.mk
+++ b/package/prboom/prboom.mk
@@ -11,6 +11,7 @@ PRBOOM_DEPENDENCIES = sdl sdl_net sdl_mixer
 PRBOOM_LICENSE = GPL-2.0+
 PRBOOM_LICENSE_FILES = COPYING
 PRBOOM_AUTORECONF = YES
+PRBOOM_FLAT_STACKSIZE=0x100000
 
 PRBOOM_CFLAGS = $(TARGET_CFLAGS)
 
```

busybox vi calls openat with filename=NULL and crashes.

The kernel also requires `CONFIG_PAGE_OFFSET=0x00400000`, but for some reason that's hardcoded in Kconfig and needs a patch:

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

There is https://lkml.org/lkml/2024/10/26/482 pending which should fix this by making the kernel fully relocatable instead.

For framebuffer output (e.g. to use SDL), another patch is needed to allow mmap:

```diff
diff --git a/arch/riscv/Kconfig b/arch/riscv/Kconfig
index ff1e353b0d6f..21a98c611605 100644
--- a/arch/riscv/Kconfig
+++ b/arch/riscv/Kconfig
@@ -92,6 +92,7 @@ config RISCV
        select EDAC_SUPPORT
        select FRAME_POINTER if PERF_EVENTS || (FUNCTION_TRACER && !DYNAMIC_FTRACE)
        select FTRACE_MCOUNT_USE_PATCHABLE_FUNCTION_ENTRY if DYNAMIC_FTRACE
+       select FB_PROVIDE_GET_FB_UNMAPPED_AREA if FB && !MMU
        select GENERIC_ARCH_TOPOLOGY
        select GENERIC_ATOMIC64 if !64BIT
        select GENERIC_CLOCKEVENTS_BROADCAST if SMP
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
