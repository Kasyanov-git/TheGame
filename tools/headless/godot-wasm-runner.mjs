// godot-wasm-runner — запуск Godot-проекта ГОЛОВЫМ-БЕЗ-ОКНА через
// Node.js + wasm-сборку движка (@ringozz/godot-web-wasm32, обычный
// web-рантайм Godot 4.x c emnapi). Придумано как CI-верификатор логики
// (физика/скрипты/сцены) там, где нет GPU/дисплея и нельзя скачать
// нативный редактор.
//
// Подготовка проекта (см. ../run_smoke.sh): копию проекта «затащивают»
// в /tmp-директорию с двумя правками:
//   1) run/main_scene -> тестовая сцена (tests/smoke.tscn);
//   2) sed-strip типов пользовательских class_name (у рантайм-сборки без
//      редактора нет global_script_class_cache — cross-file типы не резолвятся).
// В самом репозитории код остаётся типизированным и нормальным.
//
//Env: GODOT_PROJECT=dir  NPM_ROOT=dir(with node_modules)  FRAMES=number
//Exit: 0 когда 'SMOKE: PASS', иначе 1.

process.on('uncaughtException', (e) => { console.log('UNCAUGHT:', String(e && e.stack || e).slice(0, 400)); process.exit(9); });
process.on('unhandledRejection', (e) => { console.log('UNHANDLED:', String(e && e.message || e).slice(0, 300)); });

// ── browser shims (wasm-рантайм Godot думает, что он в браузере) ──
const canvasStub = {
  id: 'canvas', width: 1280, height: 720, clientWidth: 1280, clientHeight: 720,
  style: {}, tabOrder: 0,
  getContext: () => globalThis.GLUniversal,
  addEventListener() {}, removeEventListener() {}, setAttribute() {}, getAttribute() { return null; },
  appendChild() {}, focus() {}, blur() {},
  getBoundingClientRect: () => ({ left: 0, top: 0, width: 1280, height: 720 }),
  requestPointerLock() {}, remove() {},
  parentElement: { appendChild() {}, style: {} }, parentNode: { appendChild() {}, style: {} },
  offsetParent: null, tabIndex: 0, isContentEditable: false,
};
class Universal {
  static target; // noop
}
globalThis.GLUniversal = new Proxy(function () {}, {
  apply: () => globalThis.GLUniversal,
  construct: () => globalThis.GLUniversal,
  get: (t, p) => {
    if (p === 'getExtension') return () => globalThis.GLUniversal;
    if (p === 'getParameter') return () => 4096;
    if (p === 'getProgramParameter' || p === 'getShaderParameter') return () => true;
    if (p === 'getProgramInfoLog' || p === 'getShaderInfoLog') return () => '';
    if (p === 'getShaderSource' || p === 'getActiveUniform' || p === 'getSync') return () => null;
    if (p === 'canvas') return canvasStub;
    if (p === 'drawingBufferWidth') return 1280;
    if (p === 'drawingBufferHeight') return 720;
    if (p === 'valueOf' || p === Symbol.toPrimitive) return () => 0;
    if (p === 'toString') return () => '0';
    if (typeof p === 'symbol') return undefined;
    return globalThis.GLUniversal;
  },
  set: () => true,
  has: () => true,
});
class FakeAudioCtx {
  constructor() { this.destination = {}; this.state = 'running'; this.currentTime = 0; this.sampleRate = 48000; this.listener = {}; this.audioWorklet = { addModule: () => Promise.resolve() }; }
  resume() {} suspend() { return Promise.resolve(); } close() {}
  createBuffer() { return { getChannelData: () => new Float32Array(64) }; }
  createBufferSource() { return { connect() {}, start() {}, stop() {}, buffer: null, onended: null, playbackRate: { value: 1 } }; }
  createGain() { return { connect() {}, disconnect() {}, gain: { value: 1 } }; }
}
globalThis.AudioContext = FakeAudioCtx; globalThis.webkitAudioContext = FakeAudioCtx;
globalThis.AudioWorkletNode = class { constructor() { this.port = { onmessage: null, postMessage() {} }; } connect() {} disconnect() {} };
globalThis.BaseAudioContext = class {};
globalThis.alert = (m) => console.log('ALERT:', String(m).slice(0, 200));
globalThis.document = {
  head: { appendChild() {}, style: {} }, title: '',
  getElementById: (id) => (id === 'canvas' ? canvasStub : null),
  createElement: (t) => (t === 'canvas' ? Object.create(canvasStub) : { style: {}, addEventListener() {}, setAttribute() {}, appendChild() {}, getContext: () => globalThis.GLUniversal }),
  createElementNS: (ns, t) => globalThis.document.createElement(t),
  createTextNode: () => ({}), createEvent: () => ({ initEvent() {} }),
  querySelector: (q) => (q && q.includes('canvas') ? canvasStub : null), querySelectorAll: () => [],
  getElementsByTagName: (t) => (t === 'head' ? [{ appendChild() {} }] : []),
  addEventListener() {}, removeEventListener() {},
  documentElement: { style: {} }, body: { appendChild() {}, style: {}, addEventListener() {} },
  visibilityState: 'visible', hidden: false, pointerLockElement: null, exitPointerLock() {},
  locale: 'en-US', fullscreenElement: null, exitFullscreen() {}, activeElement: null,
  fonts: { ready: Promise.resolve(), load: () => Promise.resolve(), add() {} },
};
globalThis.window = globalThis; globalThis.self = globalThis;
globalThis.matchMedia = () => ({ matches: false, media: '', addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {} });
globalThis.getComputedStyle = () => ({ getPropertyValue: () => '' });
globalThis.addEventListener = () => {}; globalThis.removeEventListener = () => {};
globalThis.innerWidth = 1280; globalThis.innerHeight = 720; globalThis.devicePixelRatio = 1;
globalThis.HTMLElement = class {}; globalThis.HTMLCanvasElement = class {};
globalThis.Image = class { addEventListener() {} removeEventListener() {} };
globalThis.ResizeObserver = class { observe() {} unobserve() {} disconnect() {} };
for (const ev of ['PointerEvent', 'KeyboardEvent', 'MouseEvent', 'WheelEvent', 'FocusEvent', 'TouchEvent', 'GamepadEvent', 'InputEvent', 'PointerLockError'])
  globalThis[ev] = class {};

// ── load ──
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const npmRoot = process.env.NPM_ROOT || process.cwd();
const { default: createModule } = await import(path.join(npmRoot, 'node_modules/@ringozz/godot-web-wasm32/gen/godot.web.template_release.wasm32.nothreads.js'));
const { getDefaultContext } = await import(path.join(npmRoot, 'node_modules/@emnapi/runtime/dist/emnapi.mjs'));
const projectDir = process.env.GODOT_PROJECT || path.join(npmRoot, 'proj');
const genDir = path.join(npmRoot, 'node_modules/@ringozz/godot-web-wasm32/gen/');

let rafCb = null;
const Module = await createModule({
  locateFile: (p) => genDir + p,
  wasmBinary: fs.readFileSync(genDir + 'godot.web.template_release.wasm32.nothreads.wasm'),
  noInitialRun: true,
  requestAnimationFrame: (cb) => { rafCb = cb; return 1; },
  cancelAnimationFrame: () => {},
  print: (s) => console.log('[godot]', String(s)),
  printErr: (s) => console.error('[godot!]', String(s)),
});

// staging: res:// корень = FS '/' их сборки
if (!fs.existsSync(path.join(projectDir, 'project.godot'))) { console.log('NO project.godot in', projectDir); process.exit(4); }
let staged = 0;
(function walkd(dir, rel) {
  for (const f of fs.readdirSync(dir)) {
    const fp = path.join(dir, f);
    if (fs.statSync(fp).isDirectory()) walkd(fp, path.join(rel, f));
    else { Module.copyToFS(path.posix.join('/', rel, f), new Uint8Array(fs.readFileSync(fp))); staged++; }
  }
})(projectDir, '');
console.log('STAGED', staged, 'files');

Module.initConfig({ canvas: canvasStub, args: ['--headless'], canvasResizePolicy: 0 });
const ctx = getDefaultContext();
const mod = Module.emnapiInit({ context: ctx });
const _C = mod._C;
const got = mod.getGodot();
try { if (!_C(got, 8337)) _C(got, 13829); } catch (e) { console.log('start note:', String(e).slice(0, 120)); }
try { ctx.openScope?.(); } catch {}

// ── frame pump: GodotInstance.iteration() = napi id 8470 (см. gen/classes/GodotInstance.ts) ──
const FRAMES = Number(process.env.FRAMES || 4000);
let t = 0, smokePass = false;
const iv = setInterval(() => {
  t++;
  try {
    if (rafCb) { const cb = rafCb; rafCb = null; cb(Number(process.hrtime.bigint() / 1000000n)); }
    const quitting = _C(got, 8470);
    if (quitting) { console.log('ENGINE-QUIT at frame', t); clearInterval(iv); process.exit(smokePass ? 0 : 1); }
  } catch (e) { console.log('FRAME-ERR:', String(e && e.stack || e).slice(0, 300)); clearInterval(iv); process.exit(3); }
  if (t > FRAMES) {
    console.log('FRAME-LIMIT', t);
    clearInterval(iv);
    process.exit(smokePass ? 0 : 2);
  }
}, 8);

// exit-код по «SMOKE: PASS» в выводе
const origLog = console.log;
console.log = (...a) => { if (a.join(' ').includes('SMOKE: PASS')) smokePass = true; origLog(...a); };
