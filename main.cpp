#include "glad.h"

#define GLFW_INCLUDE_NONE 1
#include <GLFW/glfw3.h>
#include <string>
#include <vector>
#include <format>
#include <stdexcept>

auto loadFile(std::string path)
{
    FILE *f = fopen(path.c_str(), "rb");
    if (!f)
        throw std::runtime_error(std::format("Failed to open {}", path));

    fseek(f, 0, SEEK_END);
    std::vector<char> ret(ftell(f) + 1);
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

    gladLoadGLES2Loader((GLADloadproc) glfwGetProcAddress);

    GLint progamConsole = createProgram(loadFile("vertex.glsl"), loadFile("console.glsl"));
    GLint uniformFont = glGetUniformLocation(progamConsole, "font");

    // Create the console font texture
    GLuint textureFont = 0;
    glGenTextures(1, &textureFont);
    checkCall();
    auto textureFontData = loadFile("consolefont.rgba");
    glBindTexture(GL_TEXTURE_2D, textureFont);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 3072, 18, 0, GL_RGBA, GL_UNSIGNED_BYTE, textureFontData.data());
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

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

        // Draw the console
        glUseProgram(progamConsole);
        checkCall();

        glActiveTexture(GL_TEXTURE0);
        //glUniform1i(uniformFont, textureFont);
        checkCall();

        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        checkCall();
        glEnableVertexAttribArray(0);
        checkCall();
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, (GLvoid*)0);
        checkCall();
        const GLuint indices[6] = {0, 1, 2, 2, 3, 0};
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
