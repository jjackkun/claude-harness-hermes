// 화면 등록·이동·화면 목록·테마. 각 화면 파일은 NB.register() 로 자기 장면을 올린다.
// 맨 위에서는 DOM 을 건드리지 않는다 — collect_scenes.js 가 브라우저 없이 이 파일을 불러온다.
window.NB = window.NB || {};

(function (NB) {
  // 주소 #ID 로 바로 열 수 있는 글자만 — assets/spec-table.md 의 번호 규칙과 같다
  const ID_RE = /^[A-Z]{1,4}-[0-9]{2}[a-z]?$/;
  const screens = [];
  let currentId = null;
  NB.state = NB.state || {}; // 장면 사이에 이어지는 값 (예: 결제 후 홈에 진행 중 표시)

  NB.register = function (screen) {
    // screen: { id, group, name, state?, caption?, frame?, render(), mount?(root) }
    if (!ID_RE.test(screen.id)) throw new Error(`화면 번호 글자 규칙 위반: ${screen.id} (예: SD-01, EB-01a)`);
    if (screens.some((s) => s.id === screen.id)) throw new Error(`같은 화면 번호를 두 번 등록: ${screen.id}`);
    screens.push(screen);
  };

  NB.list = () => screens.slice();

  // 다른 장면을 배경으로 깔고 그 위에 시트를 겹칠 때 쓴다 (parts.js 의 overSheet)
  NB.renderOf = function (id) {
    const screen = screens.find((s) => s.id === id);
    return screen ? screen.render() : "";
  };

  NB.go = function (id) {
    const screen = screens.find((s) => s.id === id);
    if (!screen) { console.warn(`등록되지 않은 화면: ${id}`); return; }
    NB.frame.apply(screen);
    const root = document.getElementById("device");
    root.innerHTML = screen.render();
    root.scrollTop = 0;
    currentId = id;
    if (typeof screen.mount === "function") screen.mount(root);
    document.getElementById("stage-caption").textContent =
      `${screen.id} · ${screen.name}${screen.state ? " — " + screen.state : ""}${screen.caption ? " · " + screen.caption : ""}`;
    document.querySelectorAll(".navi-item").forEach((btn) => {
      btn.setAttribute("aria-current", String(btn.dataset.id === id));
    });
    if (NB.frame.isNarrow()) document.getElementById("navi").hidden = true;
    // replaceState 는 hashchange 를 부르지 않는다 — 아래 hashchange 와 맞물려 돌지 않는다
    try { history.replaceState(null, "", "#" + id); } catch (err) { /* 미리보기에서 막혀도 이동에는 영향 없음 */ }
  };

  // 묶음 순서: NB.config.groups 에 적은 순서가 먼저, 나머지는 등록 순서
  function groupOrder() {
    const seen = [...new Set(screens.map((s) => s.group))];
    const fixed = (NB.config.groups || []).filter((g) => seen.includes(g));
    return [...fixed, ...seen.filter((g) => !fixed.includes(g))];
  }

  function renderNavi() {
    const host = document.getElementById("navi-groups");
    host.innerHTML = groupOrder().map((group) => `
      <section class="navi-group">
        <h2>${group}</h2>
        ${screens.filter((s) => s.group === group).map((s) => `
          <button class="navi-item" type="button" data-id="${s.id}">
            <span class="navi-id">${s.id}</span>
            <span class="navi-name">${s.name}${s.state ? " · " + s.state : ""}</span>
            <span class="navi-frame">${NB.frame.label(s)}</span>
          </button>`).join("")}
      </section>`).join("");
    host.querySelectorAll(".navi-item").forEach((btn) => btn.addEventListener("click", () => NB.go(btn.dataset.id)));
  }

  function wireTools() {
    const navi = document.getElementById("navi");
    document.getElementById("navi-toggle").addEventListener("click", () => { navi.hidden = !navi.hidden; });

    // 화면 안 [data-go="ID"] 를 누르면 그 장면으로 — 장면을 다시 그려도 한 번만 걸면 된다
    document.getElementById("device").addEventListener("click", (event) => {
      const link = event.target.closest("[data-go]");
      if (!link) return;
      event.preventDefault();
      NB.go(link.getAttribute("data-go"));
    });

    const themeBtn = document.getElementById("theme-btn");
    const order = ["system", "light", "dark"];
    const labels = { system: "화면 모드: 시스템", light: "화면 모드: 라이트", dark: "화면 모드: 다크" };
    let mode = "system";
    themeBtn.addEventListener("click", () => {
      mode = order[(order.indexOf(mode) + 1) % order.length];
      if (mode === "system") delete document.documentElement.dataset.theme;
      else document.documentElement.dataset.theme = mode;
      themeBtn.textContent = labels[mode];
    });
  }

  function idFromHash() {
    const id = decodeURIComponent(location.hash.slice(1));
    return screens.some((s) => s.id === id) ? id : null;
  }

  NB.start = function () {
    document.getElementById("navi-title").textContent = NB.config.title;
    document.getElementById("navi-note").textContent = NB.content.note;
    renderNavi();
    wireTools();
    NB.frame.init(() => currentId && NB.go(currentId));
    // 주소의 #ID 만 바꿔도 그 장면으로 — 브라우저 점검에서 장면을 바로 여는 길
    window.addEventListener("hashchange", () => { const id = idFromHash(); if (id && id !== currentId) NB.go(id); });
    NB.go(idFromHash() || screens[0].id);
  };
})(window.NB);
