CXXFLAGS := -g -std=c++23 -Wall -Wextra -pedantic $(shell pkg-config --cflags glfw3 gl)
LDFLAGS := $(shell pkg-config --libs glfw3 gl)

all: main mem.rgba consolefont.rgba

main: main.o glad.o
	g++ $^ -o $@ $(LDFLAGS)

%.dtb: %.dts
	dtc -I dts -O dtb -o $@ $<

%.rgba: %.png
	magick $< $@

mem.rgba: Image emulator.dtb
	rm -f $@
	# 2048x2048x32bpp
	dd if=/dev/zero of=$@ bs=$$((2048*4)) count=2048 status=none
	# Kernel at 4MiB
	dd if=Image of=$@ bs=1024 seek=$$((4*1024)) status=none conv=notrunc
	# Device tree at 4KiB
	dd if=emulator.dtb of=$@ bs=1024 seek=4 status=none conv=notrunc

clean:
	rm main *.o *.rgba *.dtb

.PHONY: all clean
