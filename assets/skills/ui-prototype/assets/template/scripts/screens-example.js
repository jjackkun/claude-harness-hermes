// 예시 장면 3개 — 틀이 섞인 시안이 어떻게 생기는지 보이는 견본 (spec.md 의 세 행과 같다).
// 실제 시안을 만들 때는 이 파일을 지우고 역할별 화면 파일(screens-<역할>.js)을 만든다.
(function (NB) {
  const P = NB.parts;
  const C = NB.content;
  const TABS = [["home", "홈", "EX-01"], ["user", "내 정보", "EX-01"]];

  NB.register({
    id: "EX-01", group: "사용자", name: "목록", frame: "phone", caption: "앱 첫 화면",
    render: () => `<div class="app">
      ${P.topbar("목록")}
      <main class="screen-body">
        <h1 class="title">화면 제목 자리 ${P.exTag()}</h1>
        <div class="list">${C.items.map((it) => P.rowLink(it.title, it.meta, "", "EX-02")).join("")}</div>
      </main>
      ${P.tabbar(TABS, "홈")}
    </div>`,
  });

  // 같은 화면 안의 변화(시트 열기·닫기)는 새 장면 대신 mount 에서 처리한다
  NB.register({
    id: "EX-02", group: "사용자", name: "상세", frame: "phone",
    render: () => `<div class="app">
      ${P.topbar("상세", "EX-01")}
      <main class="screen-body">
        ${P.photo("대표 사진")}
        <h1 class="title">항목 이름 자리</h1>
        <p class="muted">설명 문단 자리 — 문서에 적힌 설명으로 바꾼다.</p>
      </main>
      <footer class="action-bar"><button class="btn btn-primary" type="button" data-open-sheet>다음 단계</button></footer>
      <div class="scrim" data-close-sheet hidden></div>
      <section class="sheet" role="dialog" aria-label="확인" hidden>
        <h2 class="subtitle">확인 시트 자리</h2>
        <p class="muted">되돌릴 수 없는 행동 앞에서 한 번 더 보여 줄 요약을 둔다.</p>
        <button class="btn btn-primary" type="button" data-go="EX-03">확인하고 웹 화면 보기</button>
        <button class="btn btn-quiet" type="button" data-close-sheet>닫기</button>
      </section>
    </div>`,
    mount(root) {
      const parts = root.querySelectorAll(".sheet, .scrim");
      const toggle = (open) => parts.forEach((el) => { el.hidden = !open; });
      root.querySelector("[data-open-sheet]").addEventListener("click", () => toggle(true));
      root.querySelectorAll("[data-close-sheet]").forEach((el) => el.addEventListener("click", () => toggle(false)));
    },
  });

  NB.register({
    id: "EX-03", group: "관리자", name: "관리 목록", frame: "browser", caption: "웹 틀 예시",
    render: () => `<div class="web">
      <header class="web-top"><strong>관리 화면</strong><button class="btn btn-quiet" type="button" data-go="EX-01">앱 화면으로</button></header>
      <main class="web-body">
        <h1 class="title">표 제목 자리 ${P.exTag()}</h1>
        <div class="table-wrap"><table class="table">
          <thead><tr><th>이름</th><th>상태</th><th>보조 설명</th></tr></thead>
          <tbody>${C.items.map((it) => `<tr><td>${it.title}</td><td><span class="pill">상태 자리</span></td><td>${it.meta}</td></tr>`).join("")}</tbody>
        </table></div>
      </main>
    </div>`,
  });
})(window.NB);
