// 예시 출처: Nbbang-Run previews/2026-10-22-receipt-ticket/js/cloth.js (2026-10-22 사용자 반응 "와 대박대박"). 보통 스크립트 + window.TK 이름공간 — file:// 로 열어도 돈다
// 천 물리 — 번호표 한 장을 Verlet 격자로 둔다. 본권 격자와 반쪽권 격자는 따로 있고 절취선 칸마다 "절취 고리"로 묶인다.
// 고리가 늘어나 문턱을 넘으면 그 칸이 찢어지고(다시 붙지 않음), 모든 칸이 찢기면 반쪽권은 떨어진 조각이 된다.
// 모든 점은 쉬는 자리(뒤집기 각도만큼 세로축으로 돈 자리)로 당기는 약한 스프링을 가져, 놓으면 출렁이다 평평하게 돌아온다.
(() => {
  const TK = (window.TK = window.TK || {});
  const ITERATIONS = 12;          // 제약 풀이 반복 — 적으면 끌 때 종이가 고무처럼 늘어난다
  const DAMPING = 0.965;          // 속도 감쇠 — 1 에 가까울수록 놓은 뒤 오래 출렁인다
  const BEND_STIFF = 0.12;        // 접힘 저항 — 낮을수록 영상처럼 크게 꼬인다
  const TEAR_RATIO = 0.3;         // 절취 고리가 칸 폭의 30% 넘게 벌어지면 찢어진다
  const TAIL_COLS = 2, TAIL_DRIFT = 0.25; // 끝 2칸만 남았을 때 반쪽권 윗줄이 폭의 25% 넘게 돌아가면 마저 찢긴다(검증: 92% 에서 마지막 칸이 경첩으로 남음)
  const PERF_STIFF = 0.25;       // 절취 고리 굳기 — 다른 제약보다 물러야 당긴 힘이 절취선에 모인다(같으면 격자 전체로 흩어져 안 찢어짐, 1차 검증 0%)

  TK.createCloth = ({ w, h, seam, cols = 12 }) => {
    const cell = w / cols, nx = cols + 1;
    const rowsMain = Math.max(4, Math.round(seam / cell));
    const rowsStub = Math.max(3, Math.round((h - seam) / cell));
    const nMain = nx * (rowsMain + 1), n = nMain + nx * (rowsStub + 1);
    const pos = new Float32Array(n * 3), prev = new Float32Array(n * 3), rest = new Float32Array(n * 3);
    const uv = new Float32Array(n * 2), nor = new Float32Array(n * 3), piece = new Uint8Array(n);
    const id = (p, r, c) => (p === 0 ? 0 : nMain) + r * nx + c;
    const rowsOf = (p) => (p === 0 ? rowsMain : rowsStub);
    const yOf = (p, r) => (p === 0 ? -h / 2 + (seam * r) / rowsMain : -h / 2 + seam + ((h - seam) * r) / rowsStub);

    for (const p of [0, 1]) for (let r = 0; r <= rowsOf(p); r++) for (let c = 0; c < nx; c++) {
      const i = id(p, r, c), x = -w / 2 + cell * c, y = yOf(p, r);
      const z = Math.sin(i * 12.9898) * 0.3;   // 아주 작은 들뜸 — 완전 평면이면 접힘이 화면 밖으로 안 나온다
      rest.set([x, y, 0], i * 3); pos.set([x, y, z], i * 3); prev.set([x, y, z], i * 3);
      uv.set([c / cols, (y + h / 2) / h], i * 2); piece[i] = p;
    }

    // 제약: [i, j, 쉬는 길이, 굳기, 절취선 칸(-1 = 보통)]
    const links = [];
    const dist = (i, j) => Math.hypot(rest[i * 3] - rest[j * 3], rest[i * 3 + 1] - rest[j * 3 + 1]);
    const link = (i, j, k, col = -1) => links.push({ i, j, len: dist(i, j), k, col, alive: true });
    for (const p of [0, 1]) for (let r = 0; r <= rowsOf(p); r++) for (let c = 0; c < nx; c++) {
      const i = id(p, r, c), R = rowsOf(p);
      if (c < cols) link(i, id(p, r, c + 1), 1);
      if (r < R) link(i, id(p, r + 1, c), 1);
      if (c < cols && r < R) { link(i, id(p, r + 1, c + 1), 1); link(id(p, r, c + 1), id(p, r + 1, c), 1); }
      if (c < cols - 1) link(i, id(p, r, c + 2), BEND_STIFF);
      if (r < R - 1) link(i, id(p, r + 2, c), BEND_STIFF);
    }
    for (let c = 0; c < nx; c++) {
      link(id(0, rowsMain, c), id(1, 0, c), PERF_STIFF, c);         // 절취 고리 (쉬는 길이 0)
      link(id(0, rowsMain - 1, c), id(1, 1, c), BEND_STIFF, c);     // 절취선을 사이에 둔 접힘 저항
    }

    const tris = (p) => {
      const out = [];
      for (let r = 0; r < rowsOf(p); r++) for (let c = 0; c < cols; c++) {
        const a = id(p, r, c), b = id(p, r, c + 1), d = id(p, r + 1, c), e = id(p, r + 1, c + 1);
        out.push(a, d, b, b, d, e);
      }
      return new Uint16Array(out);
    };

    const torn = new Uint8Array(nx);
    let grab = -1, gx = 0, gy = 0, gz = 0, tornCount = 0;

    const solve = (L) => {
      const { i, j } = L, a = i * 3, b = j * 3;
      const dx = pos[b] - pos[a], dy = pos[b + 1] - pos[a + 1], dz = pos[b + 2] - pos[a + 2];
      const d = Math.hypot(dx, dy, dz);
      if (d < 1e-6) return;
      const wi = i === grab ? 0 : 1, wj = j === grab ? 0 : 1;
      if (wi + wj === 0) return;
      const f = ((d - L.len) / d) * L.k / (wi + wj);
      pos[a] += dx * f * wi; pos[a + 1] += dy * f * wi; pos[a + 2] += dz * f * wi;
      pos[b] -= dx * f * wj; pos[b + 1] -= dy * f * wj; pos[b + 2] -= dz * f * wj;
    };

    // 한 걸음(1/60초). anchor: 조각별 쉬는 자리 스프링 세기, flip: 세로축 회전(라디안), fall: 떨어진 반쪽권 중력, tear: 찢김 허용
    // bow: 뒤집는 동안 아래쪽이 뒤처지며 휘는 정도(px) — 0 이면 판처럼 돈다
    const step = ({ anchorMain, anchorStub, flip, fall, tear, bow = 0 }) => {
      const cf = Math.cos(flip), sf = Math.sin(flip), detached = tornCount === nx;
      for (let i = 0; i < n; i++) {
        const a = i * 3;
        if (i === grab) { prev.set(pos.subarray(a, a + 3), a); pos[a] = gx; pos[a + 1] = gy; pos[a + 2] = gz; continue; }
        for (let k = 0; k < 3; k++) { const v = (pos[a + k] - prev[a + k]) * DAMPING; prev[a + k] = pos[a + k]; pos[a + k] += v; }
        const s = piece[i] === 0 ? anchorMain : detached ? 0 : anchorStub;
        if (s > 0) {
          pos[a] += (rest[a] * cf - pos[a]) * s;
          pos[a + 1] += (rest[a + 1] - pos[a + 1]) * s;
          const lag = ((rest[a + 1] + h / 2) / h) ** 2 * bow;   // 위는 그대로, 아래로 갈수록 뒤로 처진다
          pos[a + 2] += (-rest[a] * sf + lag - pos[a + 2]) * s;
        }
        if (piece[i] === 1 && detached) pos[a + 1] += fall;
      }
      for (let it = 0; it < ITERATIONS; it++) for (const L of links) if (L.alive) solve(L);
      if (!tear) return;
      const swung = grab >= 0 && tornCount >= nx - TAIL_COLS && seamDrift() > w * TAIL_DRIFT;
      for (const L of links) {
        if (L.col < 0 || !L.alive || L.len > 0) continue;
        const a = L.i * 3, b = L.j * 3;
        const gap = Math.hypot(pos[b] - pos[a], pos[b + 1] - pos[a + 1], pos[b + 2] - pos[a + 2]);
        if (gap > cell * TEAR_RATIO || swung) {
          links.forEach((M) => { if (M.col === L.col) M.alive = false; });
          torn[L.col] = 1; tornCount++;
        }
      }
    };
    // 마지막 칸들은 경첩처럼 돌기만 해 고리가 안 늘어난다 — 반쪽권 윗줄 가운데가 본권 아랫줄 가운데에서 벗어난 거리로 "돌아가 버림"을 잰다
    const seamDrift = () => {
      let dx = 0, dy = 0, dz = 0;
      for (let c = 0; c < nx; c++) {
        const a = id(0, rowsMain, c) * 3, b = id(1, 0, c) * 3;
        dx += pos[b] - pos[a]; dy += pos[b + 1] - pos[a + 1]; dz += pos[b + 2] - pos[a + 2];
      }
      return Math.hypot(dx, dy, dz) / nx;
    };

    // 면 방향(빛 계산용): 같은 조각 격자의 좌우·위아래 이웃으로. 카메라 쪽(-z)이 앞면
    const normals = () => {
      for (const p of [0, 1]) for (let r = 0; r <= rowsOf(p); r++) for (let c = 0; c < nx; c++) {
        const R = rowsOf(p), P = (rr, cc) => id(p, rr, cc) * 3;
        const L = P(r, Math.max(0, c - 1)), Rt = P(r, Math.min(cols, c + 1)), U = P(Math.max(0, r - 1), c), D = P(Math.min(R, r + 1), c);
        const ax = pos[Rt] - pos[L], ay = pos[Rt + 1] - pos[L + 1], az = pos[Rt + 2] - pos[L + 2];
        const bx = pos[D] - pos[U], by = pos[D + 1] - pos[U + 1], bz = pos[D + 2] - pos[U + 2];
        let x = -(ay * bz - az * by), y = -(az * bx - ax * bz), z = -(ax * by - ay * bx);
        const m = Math.hypot(x, y, z) || 1;
        nor.set([x / m, y / m, z / m], id(p, r, c) * 3);
      }
    };

    return {
      n, pos, uv, nor, piece, cell, mainTris: tris(0), stubTris: tris(1),
      step, normals,
      // 동작 줄이기: 출렁임 없이 쉬는 자리(뒤집기 각도 반영)로 바로 옮긴다. 떨어진 반쪽권은 건드리지 않는다
      snap: (flip) => {
        const cf = Math.cos(flip), sf = Math.sin(flip), detached = tornCount === nx;
        for (let i = 0; i < n; i++) {
          if (piece[i] === 1 && detached) continue;
          const a = i * 3, t = [rest[a] * cf, rest[a + 1], -rest[a] * sf];
          pos.set(t, a); prev.set(t, a);
        }
      },
      grab: (i, x, y, z) => { grab = i; gx = x; gy = y; gz = z; },
      move: (x, y, z) => { gx = x; gy = y; gz = z; },
      release: () => { grab = -1; },
      grabbed: () => grab,
      tornRatio: () => tornCount / nx,
      detached: () => tornCount === nx,
      // 반쪽권 아래 오른쪽 끝 점 — "떼기 시연"이 잡는 자리(영상에서 손이 잡은 곳)
      stubCorner: () => id(1, rowsStub, cols),
    };
  };
})();
