#include "glad.h"

#define GLFW_INCLUDE_NONE 1
#include <GLFW/glfw3.h>
#include <string>
#include <deque>
#include <vector>
#include <format>
#include <print>
#include <stdexcept>
#include <cstring>

auto loadFile(std::string path)
{
    FILE *f = fopen(path.c_str(), "rb");
    if (!f)
        throw std::runtime_error(std::format("Failed to open {}", path));

    fseek(f, 0, SEEK_END);
    std::vector<char> ret(ftell(f));
    rewind(f);
    fread(ret.data(), ret.size(), 1, f);
    fclose(f);

    return ret;
}

auto loadShader(GLenum type, std::vector<char> source)
{
    GLint shader = glCreateShader(type);
    const char *sourceptr = source.data();
    const GLint sourcelen = source.size();
    glShaderSource(shader, 1, &sourceptr, &sourcelen);
    glCompileShader(shader);
    GLint compileStatus = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compileStatus);
    if (!compileStatus) {
        std::vector<char> log(512);
        GLsizei actualSize = 0;
        glGetShaderInfoLog(shader, log.size(), &actualSize, log.data());
        throw std::runtime_error(std::format("{}", log.data()));
    }
    return shader;
}

auto createProgram(std::vector<char> vs, std::vector<char> fs)
{
    GLint vShader = loadShader(GL_VERTEX_SHADER, vs);
    GLint fShader = loadShader(GL_FRAGMENT_SHADER, fs);

    GLint program = glCreateProgram();
    glAttachShader(program, vShader);
    glAttachShader(program, fShader);
    glLinkProgram(program);

    GLint linkStatus = 0;
    glGetProgramiv(program, GL_LINK_STATUS, &linkStatus);
    if (!linkStatus) {
        std::vector<char> log(512);
        GLsizei actualSize = 0;
        glGetProgramInfoLog(program, log.size(), &actualSize, log.data());
        throw std::runtime_error(std::format("{}", log.data()));
    }
    
    return program;
}

void checkCall()
{
    const int err = glGetError();
    if (err != GL_NO_ERROR)
        throw std::runtime_error(std::format("Got error {}", err));
}

static bool showFramebuffer = true;
static std::deque<GLint> keyEventQueue;

void keyEventCallback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
    if (action == GLFW_PRESS && key == GLFW_KEY_F11)
        showFramebuffer = !showFramebuffer;
    else if (scancode >= 128)
        ; // not supported
    else if (action == GLFW_PRESS)
        keyEventQueue.push_back(scancode);
    else if (action == GLFW_RELEASE)
        keyEventQueue.push_back(-scancode);
}

int main(int argc, char *argv[])
try {
    GLFWwindow* window;

    /* Initialize the library */
    if (!glfwInit())
        return -1;

    /* Create a windowed mode window and its OpenGL context */
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
    glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);

    window = glfwCreateWindow(640, 480, "RISKY-V", NULL, NULL);
    if (!window)
    {
        glfwTerminate();
        return -1;
    }

    /* Make the window's context current */
    glfwMakeContextCurrent(window);

    glfwSetKeyCallback(window, keyEventCallback);

    gladLoadGLES2Loader((GLADloadproc) glfwGetProcAddress);

    GLint programConsole = createProgram(loadFile("vertex.glsl"), loadFile("console.glsl"));
    GLint uniformFont = glGetUniformLocation(programConsole, "font");
    checkCall();
    GLint uniformConsoleMemory = glGetUniformLocation(programConsole, "memory");
    checkCall();
    GLboolean uniformConsoleShowFramebuffer = glGetUniformLocation(programConsole, "showFramebuffer");
    std::print("Font at {}, memory at {}, showFramebuffer at {}\n", uniformFont, uniformConsoleMemory, uniformConsoleShowFramebuffer);

    GLint programEmulator = createProgram(loadFile("vertex.glsl"), loadFile("emulator.glsl"));
    GLint uniformEmuMemory = glGetUniformLocation(programEmulator, "memory");
    checkCall();
    GLint uniformEmuKeyEvent = glGetUniformLocation(programEmulator, "keyEvent");
    std::print("Emulator memory at {}, keyEvent at {}\n", uniformEmuMemory, uniformEmuKeyEvent);

    // Create the console font texture
    GLuint textureFont = 0;
    glGenTextures(1, &textureFont);
    checkCall();
    {
        auto textureFontData = loadFile("consolefont.rgba");
        glBindTexture(GL_TEXTURE_2D, textureFont);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 3072, 18, 0, GL_RGBA, GL_UNSIGNED_BYTE, textureFontData.data());
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glBindTexture(GL_TEXTURE_2D, 0);
    }

    // Create the memory "texture"
    GLuint textureMemory = 0;
    glGenTextures(1, &textureMemory);
    checkCall();
    const GLint memWidth = 2048, memHeight = 4096;
    {
        auto memContent = loadFile("mem.rgba");
        if (memContent.size() != memWidth * memHeight * sizeof(GLuint))
            throw std::runtime_error(std::format("mem.rgba has wrong size (expected {}, actual {})",
                                                 memWidth * memHeight * sizeof(GLuint),
                                                 memContent.size()));

        uint32_t start_pc = 4 * 1024 * 1024;
        memContent[3] = start_pc >> 24;
        memContent[2] = start_pc >> 16;
        memContent[1] = start_pc >> 8;
        memContent[0] = start_pc >> 0;

        uint32_t dtb_addr = 0x1000;
        memContent[11*4 + 3] = dtb_addr >> 24;
        memContent[11*4 + 2] = dtb_addr >> 16;
        memContent[11*4 + 1] = dtb_addr >> 8;
        memContent[11*4 + 0] = dtb_addr >> 0;

        glBindTexture(GL_TEXTURE_2D, textureMemory);
        glTexStorage2D(GL_TEXTURE_2D, 1, GL_R32UI, memWidth, memHeight);
        checkCall();
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, memWidth, memHeight, GL_RED_INTEGER, GL_UNSIGNED_INT, memContent.data());
        checkCall();
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glBindTexture(GL_TEXTURE_2D, 0);
    }

    // Two triangles to fill the screen
    const GLfloat pos[4*2] = {
        -1, -1,
        1, -1,
        1, 1,
        -1, 1,
    };

    GLuint vbo = 0;
    glGenBuffers(1, &vbo);
    checkCall();
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    checkCall();
    glBufferData(GL_ARRAY_BUFFER, sizeof(pos), &pos, GL_STATIC_DRAW);
    checkCall();
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    checkCall();
    glDisable(GL_CULL_FACE);
    checkCall();
    
    /* Loop until the user closes the window */
    while (!glfwWindowShouldClose(window))
    {
        /* Render here */
        glClear(GL_COLOR_BUFFER_BIT);

        // Prepare a full-screen quad
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        checkCall();
        glEnableVertexAttribArray(0);
        checkCall();
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, (GLvoid*)0);
        checkCall();
        const GLuint indices[6] = {0, 1, 2, 2, 3, 0};

        // Run the emulator
        glUseProgram(programEmulator);
        checkCall();

        if (keyEventQueue.empty())
            glUniform1i(uniformEmuKeyEvent, 0);
        else {
            glUniform1i(uniformEmuKeyEvent, keyEventQueue.front());
            keyEventQueue.pop_front();
        }

        glBindImageTexture(uniformEmuMemory, textureMemory, 0, GL_FALSE, 0, GL_READ_WRITE, GL_R32UI);
        checkCall();

        glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, &indices);
        checkCall();

        // Draw the console
        glUseProgram(programConsole);
        checkCall();

        glActiveTexture(GL_TEXTURE0);
        checkCall();
        glBindTexture(GL_TEXTURE_2D, textureFont);
        checkCall();

        glBindImageTexture(uniformConsoleMemory, textureMemory, 0, GL_FALSE, 0, GL_READ_WRITE, GL_R32UI);
        checkCall();

        glUniform1i(uniformConsoleShowFramebuffer, showFramebuffer);
        checkCall();

        glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, &indices);
        checkCall();

        glBindBuffer(GL_ARRAY_BUFFER, 0);
        checkCall();

        /* Swap front and back buffers */
        glfwSwapBuffers(window);

        /* Poll for and process events */
        glfwPollEvents();
    }

    glfwTerminate();
    return 0;
} catch(const std::exception &e) {
    printf("Error: %s\n", e.what());
    return 1;
}
