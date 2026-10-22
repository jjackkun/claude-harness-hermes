// 예시 출처: Nbbang-Run previews/2026-10-22-receipt-ticket/js/render.js (2026-10-22 사용자 반응 "와 대박대박"). 보통 스크립트 + window.TK 이름공간 — file:// 로 열어도 돈다
// WebGL 그리기 — 천 격자를 원근으로 비추고, 앞을 보는 면엔 번호표 그림, 뒤를 보는 면엔 영수증 그림을 입힌다.
// 색은 그림(토큰)에서만 오고, 여기선 접힌 면의 밝기·옅은 반사만 더한다(무지개 포일 없음 — MASTER.md 색 규칙).
(() => {
  const TK = (window.TK = window.TK || {});
  const FOCAL = 900;   // 원근 초점 거리(px) — 작을수록 접힌 면이 과장된다
  const VS = `
    attribute vec3 aPos; attribute vec2 aUV; attribute vec3 aNor;
    uniform vec2 uHalf; uniform vec2 uCenter; uniform float uF;
    varying vec2 vUV; varying vec3 vNor;
    void main() {
      float s = uF / (uF + aPos.z);
      vec2 clip = (uCenter + aPos.xy * s) / uHalf - 1.0;
      gl_Position = vec4(clip.x, -clip.y, aPos.z / 2000.0, 1.0);
      vUV = aUV; vNor = aNor;
    }`;
  const FS = `
    precision mediump float;
    uniform sampler2D uFront; uniform sampler2D uBack; uniform float uAlpha;
    varying vec2 vUV; varying vec3 vNor;
    void main() {
      vec4 c = gl_FrontFacing ? texture2D(uFront, vUV) : texture2D(uBack, vec2(1.0 - vUV.x, vUV.y));
      if (c.a < 0.02) discard;
      vec3 n = normalize(vNor);
      if (!gl_FrontFacing) n = -n;
      vec3 L = normalize(vec3(-0.35, -0.55, -1.0));
      float shade = clamp(0.5 + 0.6 * max(dot(n, L), 0.0), 0.0, 1.04);   // 평평하면 1.0, 빛을 등지면 어두워진다
      float spec = pow(max(dot(n, normalize(L + vec3(0.0, 0.0, -1.0))), 0.0), 60.0) * 0.1;
      gl_FragColor = vec4(c.rgb * shade + spec * c.a, c.a) * uAlpha;
    }`;

  const compile = (gl, type, src) => {
    const s = gl.createShader(type);
    gl.shaderSource(s, src); gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(`셰이더 컴파일 실패: ${gl.getShaderInfoLog(s)}`);
    return s;
  };

  TK.createRenderer = (canvas) => {
    const gl = canvas.getContext('webgl', { antialias: true, premultipliedAlpha: true, alpha: true });
    if (!gl) return null;
    const prog = gl.createProgram();
    gl.attachShader(prog, compile(gl, gl.VERTEX_SHADER, VS));
    gl.attachShader(prog, compile(gl, gl.FRAGMENT_SHADER, FS));
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(`셰이더 연결 실패: ${gl.getProgramInfoLog(prog)}`);
    gl.useProgram(prog);
    const loc = (name) => gl.getUniformLocation(prog, name);
    const u = { half: loc('uHalf'), center: loc('uCenter'), f: loc('uF'), front: loc('uFront'), back: loc('uBack'), alpha: loc('uAlpha') };
    gl.uniform1i(u.front, 0); gl.uniform1i(u.back, 1); gl.uniform1f(u.f, FOCAL);
    gl.enable(gl.DEPTH_TEST); gl.depthFunc(gl.LEQUAL);
    gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);

    const attr = (name, size) => {
      const buf = gl.createBuffer(), at = gl.getAttribLocation(prog, name);
      gl.bindBuffer(gl.ARRAY_BUFFER, buf); gl.enableVertexAttribArray(at); gl.vertexAttribPointer(at, size, gl.FLOAT, false, 0, 0);
      return buf;
    };
    const bPos = attr('aPos', 3), bUV = attr('aUV', 2), bNor = attr('aNor', 3);
    const bMain = gl.createBuffer(), bStub = gl.createBuffer();
    const tex = [gl.createTexture(), gl.createTexture()];
    let mesh = null;

    const setTextures = (front, back) => [front, back].forEach((img, k) => {
      gl.activeTexture(gl.TEXTURE0 + k); gl.bindTexture(gl.TEXTURE_2D, tex[k]);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);
      for (const [p, v] of [[gl.TEXTURE_MIN_FILTER, gl.LINEAR], [gl.TEXTURE_MAG_FILTER, gl.LINEAR], [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]]) gl.texParameteri(gl.TEXTURE_2D, p, v);
    });
    const setMesh = (cloth) => {
      mesh = cloth;
      gl.bindBuffer(gl.ARRAY_BUFFER, bPos); gl.bufferData(gl.ARRAY_BUFFER, cloth.pos, gl.DYNAMIC_DRAW);
      gl.bindBuffer(gl.ARRAY_BUFFER, bNor); gl.bufferData(gl.ARRAY_BUFFER, cloth.nor, gl.DYNAMIC_DRAW);
      gl.bindBuffer(gl.ARRAY_BUFFER, bUV); gl.bufferData(gl.ARRAY_BUFFER, cloth.uv, gl.STATIC_DRAW);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bMain); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, cloth.mainTris, gl.STATIC_DRAW);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bStub); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, cloth.stubTris, gl.STATIC_DRAW);
    };
    // cssW·cssH: 캔버스 화면 크기, cx·cy: 번호표 가운데(캔버스 왼쪽 위 기준 px), stubAlpha: 떨어지는 반쪽권 흐려짐
    const draw = ({ cssW, cssH, cx, cy, stubAlpha }) => {
      if (!mesh) return;
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
      gl.uniform2f(u.half, cssW / 2, cssH / 2); gl.uniform2f(u.center, cx, cy);
      gl.bindBuffer(gl.ARRAY_BUFFER, bPos); gl.bufferSubData(gl.ARRAY_BUFFER, 0, mesh.pos);
      gl.bindBuffer(gl.ARRAY_BUFFER, bNor); gl.bufferSubData(gl.ARRAY_BUFFER, 0, mesh.nor);
      for (const [buf, count, alpha] of [[bMain, mesh.mainTris.length, 1], [bStub, mesh.stubTris.length, stubAlpha]]) {
        if (alpha <= 0) continue;
        gl.uniform1f(u.alpha, alpha);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buf); gl.drawElements(gl.TRIANGLES, count, gl.UNSIGNED_SHORT, 0);
      }
    };
    // 화면 점 → 깊이 z 에서의 격자 좌표 (원근 역변환)
    const unproject = (sx, sy, cx, cy, z) => { const k = (FOCAL + z) / FOCAL; return [(sx - cx) * k, (sy - cy) * k]; };
    const project = (x, y, z, cx, cy) => { const s = FOCAL / (FOCAL + z); return [cx + x * s, cy + y * s]; };
    return { setTextures, setMesh, draw, unproject, project, gl };
  };
})();
