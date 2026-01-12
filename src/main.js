const canvas = document.getElementById("glcanvas");
const gl = canvas.getContext("webgl");

if (!gl) {
  alert("WebGL not supported");
}

function resize() {
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
  gl.viewport(0, 0, canvas.width, canvas.height);
}
window.addEventListener("resize", resize);
resize();

const vertexSource = `
attribute vec2 position;
void main() {
  gl_Position = vec4(position, 0.0, 1.0);
}
`;

async function loadShader(url) {
  const res = await fetch(url);
  return await res.text();
}

function compile(type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);

  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    console.error(gl.getShaderInfoLog(shader));
    throw new Error("Shader compile error");
  }
  return shader;
}

async function init() {
  const fragmentSource = await loadShader("shader.glsl");

  const program = gl.createProgram();
  gl.attachShader(program, compile(gl.VERTEX_SHADER, vertexSource));
  gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragmentSource));
  gl.linkProgram(program);

  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    console.error(gl.getProgramInfoLog(program));
    return;
  }

  gl.useProgram(program);

  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(
    gl.ARRAY_BUFFER,
    new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
    gl.STATIC_DRAW,
  );

  const pos = gl.getAttribLocation(program, "position");
  gl.enableVertexAttribArray(pos);
  gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, 0, 0);

  const iResolution = gl.getUniformLocation(program, "iResolution");
  const iTime = gl.getUniformLocation(program, "iTime");
  const iMouse = gl.getUniformLocation(program, "iMouse");

  let mouse = [0, 0, 0, 0];
  canvas.addEventListener("mousemove", (e) => {
    mouse[0] = e.clientX;
    mouse[1] = canvas.height - e.clientY;
  });

  const start = performance.now();
  function render() {
    const t = (performance.now() - start) * 0.001;
    gl.uniform3f(iResolution, canvas.width, canvas.height, 1.0);
    gl.uniform1f(iTime, t);
    gl.uniform4fv(iMouse, mouse);

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    requestAnimationFrame(render);
  }
  render();
}

init();
