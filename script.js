// "Borrowed" from https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/Tutorial/Adding_2D_content_to_a_WebGL_context
function loadShader(gl, type, source) {
  const shader = gl.createShader(type);

  // Send the source to the shader object
  gl.shaderSource(shader, source);

  // Compile the shader program
  gl.compileShader(shader);

  // See if it compiled successfully
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
	throw Error(`Shader compilation failed: ${gl.getShaderInfoLog(shader)} ${source}`);
  }

  return shader;
}

function initShaderProgram(gl, vsSource, fsSource) {
  const vertexShader = loadShader(gl, gl.VERTEX_SHADER, vsSource);
  const fragmentShader = loadShader(gl, gl.COMPUTE_SHADER, fsSource);

  // Create the shader program
  const shaderProgram = gl.createProgram();
  gl.attachShader(shaderProgram, vertexShader);
  gl.attachShader(shaderProgram, fragmentShader);
  gl.linkProgram(shaderProgram);

  // If creating the shader program failed, alert
  if (!gl.getProgramParameter(shaderProgram, gl.LINK_STATUS)) {
	gl.deleteShader(vertexShader);
	gl.deleteShader(fragmentShader);
	throw Error(`Unable to initialize the shader program: ${gl.getProgramInfoLog(shaderProgram)}`);
  }

  return shaderProgram;
}

// Get the WebGL context
let canvas = document.getElementById("canvas");
let gl = canvas.getContext("webgl");

// One-time WebGL initialization

// Clear to black
gl.clearColor(0.0, 0.0, 0.0, 1.0);
gl.clear(gl.COLOR_BUFFER_BIT);

async function startWebGL(gl) {
	let consoleFragGlslReqPromise = fetch("console.glsl");
	let emulatorFragGlslReqPromise = fetch("emulator.glsl");

	let consoleFragGlslReq = await consoleFragGlslReqPromise;
	let emulatorFragGlslReq = await emulatorFragGlslReqPromise;

	let consoleFragGlsl = await consoleFragGlslReq.text();
	let emulatorFragGlsl = await emulatorFragGlslReq.text();

	// Trivial pass-through vertex shader.
	const vertGlsl = `#version 300 es
		in vec2 pos;
		void main() {
			gl_Position = vec4(pos, 0, 0);
		}
	`;

	const consoleShaderProgram = initShaderProgram(gl, vertGlsl, consoleFragGlsl);

	function step()
	{
		// No need to clear, we draw over everything
		window.requestAnimationFrame(step);
	}

	window.requestAnimationFrame(step);
}

startWebGL(gl);
