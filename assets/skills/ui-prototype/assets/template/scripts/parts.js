// 공통 부품 HTML 함수 — 상단 바·하단 탭·줄 목록·시트·사진/지도 자리·"예시" 표기.
// 시안마다 필요한 부품을 여기에 더한다. 화면 파일은 HTML 을 직접 반복하지 말고 이 함수를 부른다.
window.NB = window.NB || {};

(function (NB) {
  // 아이콘은 24 격자 선 그림. 크기는 components.css 가 svg 마다 정한다 (크기 미지정 svg 는 화면을 덮는다)
  const ICONS = {
    back: '<path d="M15 5l-7 7 7 7" />',
    close: '<path d="M6 6l12 12M18 6L6 18" />',
    next: '<path d="M9 5l7 7-7 7" />',
    home: '<path d="M4 11l8-7 8 7v9H4z" />',
    list: '<path d="M8 6h12M8 12h12M8 18h12M4 6h.5M4 12h.5M4 18h.5" />',
    user: '<circle cx="12" cy="8" r="4" /><path d="M4 21c1-4 4-6 8-6s7 2 8 6" />',
  };
  NB.icon = (name) =>
    `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ""}</svg>`;

  NB.parts = {
    // 문서에 없는 값 옆에 붙이는 표기 — 확정된 값처럼 보이지 않게
    exTag: () => `<span class="ex-tag">예시</span>`,

    topbar(title, backTo) {
      return `<header class="topbar">
        ${backTo ? `<button class="icon-btn" type="button" aria-label="뒤로" data-go="${backTo}">${NB.icon("back")}</button>` : ""}
        <span class="topbar-title">${title}</span>
      </header>`;
    },

    // tabs: [[아이콘, 라벨, 이동할 화면 번호], ...], active: 켤 탭의 라벨 (두 탭이 같은 화면을 가리켜도 하나만 켜진다)
    tabbar(tabs, active) {
      return `<nav class="tabbar" aria-label="하단 탭">${tabs.map(([icon, label, to]) => `
        <button class="tab" type="button" data-go="${to}"${label === active ? ' aria-current="page"' : ""}>${NB.icon(icon)}<span>${label}</span></button>`).join("")}
      </nav>`;
    },

    // 줄 목록 한 줄 — 왼쪽 글, 오른쪽 값, to 가 있으면 누르면 이동
    rowLink(title, sub, right, to) {
      return `<button class="row-link" type="button"${to ? ` data-go="${to}"` : ""}>
        <span class="stack-xs"><strong>${title}</strong>${sub ? `<span class="muted small">${sub}</span>` : ""}</span>
        <span class="row-right">${right || ""}${to ? NB.icon("next") : ""}</span></button>`;
    },

    // 다른 장면을 배경으로 깔고 그 위에 아래 시트를 겹친다 — 시트를 독립 장면으로 둘 때
    overSheet(bgId, sheetHtml, closeTo, label) {
      return `<div class="over-sheet">${NB.renderOf(bgId)}
        <div class="scrim" data-go="${closeTo}"></div>
        <section class="sheet" role="dialog" aria-label="${label}">${sheetHtml}</section></div>`;
    },

    photo: (caption) => `<div class="photo" role="img" aria-label="${caption} 사진 자리">${caption}</div>`,
    map: (caption) => `<div class="photo is-map" role="img" aria-label="${caption} 지도 자리">${caption}</div>`,
  };
})(window.NB);
