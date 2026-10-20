// 틀 — 장면마다 phone·tablet·browser·desktop 을 <div class="device" data-frame> 에 적용하고,
// 좁은 화면 판정·축소 맞춤·틀 전환 도구를 맡는다. 크기·테두리는 styles/frames.css.
// 맨 위에서는 DOM 을 건드리지 않는다 — collect_scenes.js 가 브라우저 없이 이 파일을 불러온다.
window.NB = window.NB || {};

(function (NB) {
  const FRAMES = { phone: "앱", tablet: "태블릿", browser: "웹", desktop: "데스크톱" };
  // 좁은 화면에서 가로 스크롤 대신 축소로 맞추는 틀. phone·browser 는 틀 없이 전체 화면이 된다
  const SCALED = ["tablet", "desktop"];
  let override = null; // 틀 전환 도구로 고른 틀 — 이 세션 동안 모든 장면에 덮어쓴다
  let orient = "portrait";
  let current = null;
  let narrowQuery = null;

  function frameOf(screen) {
    const f = override || screen.frame || NB.config.frame;
    return f in FRAMES ? f : "phone";
  }

  // 바깥 상자를 줄인 크기로 잡고 안쪽은 원래 크기 그대로 scale — 클릭 위치가 어긋나지 않는다
  function fit() {
    const device = document.getElementById("device");
    const box = document.getElementById("device-box");
    device.style.transform = "";
    box.style.width = "";
    box.style.height = "";
    delete box.dataset.scaled;
    if (!SCALED.includes(current)) return;
    const scale = Math.min(1, box.parentElement.clientWidth / device.offsetWidth);
    if (scale >= 1) return;
    device.style.transform = `scale(${scale})`;
    box.style.width = `${device.offsetWidth * scale}px`;
    box.style.height = `${device.offsetHeight * scale}px`;
    box.dataset.scaled = "";
  }

  function markNarrow() {
    const narrow = narrowQuery.matches;
    document.documentElement.toggleAttribute("data-narrow", narrow);
    document.getElementById("navi").hidden = narrow;
  }

  function wireTools(onChange) {
    const pick = document.getElementById("frame-pick");
    pick.innerHTML = `<option value="">틀: 장면 기본</option>` +
      Object.entries(FRAMES).map(([key, label]) => `<option value="${key}">틀: ${label}</option>`).join("");
    pick.addEventListener("change", () => { override = pick.value || null; onChange(); });
    document.getElementById("rotate-btn").addEventListener("click", () => {
      orient = orient === "portrait" ? "landscape" : "portrait";
      onChange();
    });
  }

  NB.frame = {
    label: (screen) => FRAMES[frameOf(screen)],
    isNarrow: () => Boolean(narrowQuery && narrowQuery.matches),

    // NB.go() 가 장면을 그리기 전에 부른다
    apply(screen) {
      current = frameOf(screen);
      const device = document.getElementById("device");
      device.dataset.frame = current;
      device.dataset.orient = orient;
      document.getElementById("device-box").dataset.frame = current; // 웹 틀의 주소창 띠는 바깥 상자가 그린다
      document.getElementById("rotate-btn").hidden = current !== "tablet";
      fit();
    },

    // onChange: 틀이 바뀌었을 때 지금 장면을 다시 그리는 함수 (registry.js 가 넘긴다)
    init(onChange) {
      narrowQuery = window.matchMedia(`(max-width: ${NB.config.mobileMax}px)`);
      markNarrow();
      narrowQuery.addEventListener("change", () => { markNarrow(); fit(); });
      window.addEventListener("resize", fit);
      wireTools(onChange);
    },
  };
})(window.NB);
