#!/usr/bin/env node
// 시안의 장면을 브라우저 없이 모은다 — index.html 의 <script src> 를 적힌 순서대로(../ 공유 파일 포함) node vm 에서
// 실행하고, 장면마다 render() 결과에서 data-go 대상을 뽑는다. 문자열 검색이 아니라 실제 실행이라
// render 안에서 계산되는 값(상태별 버튼 등)도 잡힌다. NB.start() 는 부르지 않는다(DOM 이 없다).
// 사용: node collect_scenes.js <시안 폴더>  →  표준출력 JSON {scenes:[{id,group,name,frame,gos,error}], loaded, notLoaded}
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

function scriptSources(html) {
  const live = html.replace(/<!--[\s\S]*?-->/g, ""); // 주석 처리된 태그는 로드되지 않는다
  return [...live.matchAll(/<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>/gi)].map((m) => m[1]);
}

function loadAll(root, sources) {
  const sandbox = { window: {}, console };
  sandbox.window.window = sandbox.window;
  vm.createContext(sandbox);
  for (const src of sources) {
    if (/^(https?:)?\/\//i.test(src)) continue; // 외부 스크립트는 장면을 등록하지 않는다
    const file = path.resolve(root, src);
    const code = fs.readFileSync(file, "utf8");
    vm.runInContext(`with (window) {${code}\n}`, sandbox, { filename: src });
  }
  return sandbox.window.NB;
}

function describe(NB, screen) {
  const frame = screen.frame || (NB.config && NB.config.frame) || "phone";
  const base = { id: screen.id, group: screen.group, name: screen.name, frame, gos: [], error: null };
  try {
    const out = String(screen.render());
    base.gos = [...new Set([...out.matchAll(/data-go\s*=\s*["']([^"']+)["']/g)].map((m) => m[1]))];
  } catch (err) {
    base.error = String(err && err.message ? err.message : err);
  }
  return base;
}

function main() {
  const root = path.resolve(process.argv[2] || ".");
  const sources = scriptSources(fs.readFileSync(path.join(root, "index.html"), "utf8"));
  const loaded = sources.map((s) => path.relative(root, path.resolve(root, s)).split(path.sep).join("/"));
  const scriptsDir = path.join(root, "scripts");
  const onDisk = fs.existsSync(scriptsDir)
    ? fs.readdirSync(scriptsDir).filter((f) => /^screens-.*\.js$/.test(f)).map((f) => `scripts/${f}`)
    : [];
  let NB;
  try {
    NB = loadAll(root, sources);
  } catch (err) {
    process.stderr.write(`시안 스크립트를 불러오다 멈춤: ${err.stack || err}\n`);
    process.exit(2);
  }
  if (!NB || typeof NB.list !== "function") {
    process.stderr.write("NB.list 가 없음 — registry.js 가 로드 순서에 있는지 확인하십시오\n");
    process.exit(2);
  }
  const scenes = NB.list().map((s) => describe(NB, s));
  const notLoaded = onDisk.filter((f) => !loaded.includes(f));
  process.stdout.write(JSON.stringify({ scenes, loaded, notLoaded }, null, 2) + "\n");
}

main();
