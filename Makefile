CXXFLAGS := -g -std=c++23 -Wall -Wextra -pedantic $(shell pkg-config --cflags glfw3 gl)
LDFLAGS := $(shell pkg-config --libs glfw3 gl)

main: main.o glad.o
	g++ $^ -o $@ $(LDFLAGS)

clean:
	rm main *.o

.PHONY: clean
