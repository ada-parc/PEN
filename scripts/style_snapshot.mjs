#!/usr/bin/env node
// Computed-style snapshot + diff, the regression oracle for color refactors.
//
//   node scripts/style_snapshot.mjs snap <out.json> [--theme=<name>] [--base=http://localhost:8123]
//   node scripts/style_snapshot.mjs diff <a.json> <b.json>
//   node scripts/style_snapshot.mjs scan [--theme=<name>] [--attrs=k=v,k=v] [--aaa=1] [--base=...]
//   node scripts/style_snapshot.mjs overflow [--base=...]
//
// `overflow` loads every page across theme x text size x spacing x font at
// 320/768/1440px and reports any visible element that extends past the right
// edge of the viewport (body clips sideways scroll, so this finds text that
// is silently cut off, not just a scrollbar).
//
// `scan` sets the theme (and any extra data attributes), then reports every
// text element whose foreground/effective-background contrast is under AA
// (4.5:1, or 3:1 for large text), grouped by color pair.
//
// `snap` drives a headless Chrome over CDP, visits every page in _site/ at
// 320/768/1440px, and records the color-bearing computed properties of every
// element (plus ::before/::after, and :hover / :focus-visible on every
// interactive element). `diff` reports every key whose value changed.
// Needs Node 22+ (global WebSocket/fetch) and a local Chrome. Serve _site/
// first (python3 -m http.server 8123 -d _site).
import { spawn } from 'node:child_process';
import { readdirSync, statSync, writeFileSync, readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const WIDTHS = [320, 768, 1440];
const PROPS = [
  'color', 'background-color', 'background-image',
  'border-top-color', 'border-right-color', 'border-bottom-color', 'border-left-color',
  'border-top-width', 'border-right-width', 'border-bottom-width', 'border-left-width',
  'outline-color', 'outline-style', 'outline-width', 'fill', 'stroke', 'box-shadow',
  'text-decoration-line', 'text-decoration-color', 'font-family', 'font-size',
  'font-weight', 'line-height', 'letter-spacing', 'opacity', 'display',
];
const PROPS_OUT = [...PROPS, 'rect'];

function pages(root) {
  const out = [];
  const walk = (d, rel) => {
    for (const f of readdirSync(d)) {
      const p = join(d, f);
      if (f === 'site_libs' || f === 'videos' || f === 'assets') continue;
      if (statSync(p).isDirectory()) walk(p, rel + f + '/');
      else if (f.endsWith('.html')) out.push(rel + f);
    }
  };
  walk(root, '');
  return out.sort();
}

class CDP {
  constructor(ws) { this.ws = ws; this.id = 0; this.cbs = new Map(); this.sid = null;
    ws.addEventListener('message', (m) => { const d = JSON.parse(m.data);
      if (d.id && this.cbs.has(d.id)) { const { res, rej } = this.cbs.get(d.id); this.cbs.delete(d.id);
        d.error ? rej(new Error(JSON.stringify(d.error))) : res(d.result); } }); }
  send(method, params = {}) { const id = ++this.id;
    return new Promise((res, rej) => { this.cbs.set(id, { res, rej });
      this.ws.send(JSON.stringify({ id, method, params, ...(this.sid ? { sessionId: this.sid } : {}) })); }); }
}

const COLLECT = `(() => {
  const P = ${JSON.stringify(PROPS)};
  const keyOf = (el) => { const parts = []; for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
    const sib = n.parentElement ? [...n.parentElement.children].indexOf(n) : 0;
    parts.unshift(n.tagName.toLowerCase() + (n.id ? '#' + n.id : '') + ':' + sib); } return parts.join('>'); };
  const grab = (cs) => P.map((p) => cs.getPropertyValue(p)).join('|');
  const rectOf = (el) => { const r = el.getBoundingClientRect(); return [r.left, r.top, r.width, r.height].map((v) => Math.round(v)).join(','); };
  const out = {};
  for (const el of document.querySelectorAll('body, body *')) {
    if (el.closest('script,style')) continue;
    const k = keyOf(el);
    out[k] = grab(getComputedStyle(el)) + '|' + rectOf(el);
    for (const ps of ['::before', '::after']) {
      const cs = getComputedStyle(el, ps);
      if (cs.content && cs.content !== 'none' && cs.content !== 'normal') out[k + ps] = grab(cs);
    }
  }
  const html = getComputedStyle(document.documentElement);
  out['html'] = grab(html) + '|0,0,0,0';
  return out;
})()`;


const SCAN = (aaa) => `((root) => {
  const parse = (str) => {
    let m = str.match(/^rgba?\\(([^)]+)\\)$/);
    if (m) { const p = m[1].split(/[ ,\\/]+/).filter(Boolean).map(Number); return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1]; }
    m = str.match(/^color\\(srgb ([^)]+)\\)$/);
    if (m) { const p = m[1].split(/[ \\/]+/).filter(Boolean).map(Number); return [p[0]*255, p[1]*255, p[2]*255, p.length > 3 ? p[3] : 1]; }
    return [0, 0, 0, 0];
  };
  const lum = (c) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]); };
  const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  const over = (top, bot) => { const a = top[3] + bot[3] * (1 - top[3]);
    if (a === 0) return [0, 0, 0, 0];
    return [0,1,2].map((i) => (top[i] * top[3] + bot[i] * bot[3] * (1 - top[3])) / a).concat(a); };
  const hex = (c) => '#' + [0,1,2].map((i) => Math.round(c[i]).toString(16).padStart(2, '0')).join('');
  const bgOf = (el) => {
    const chain = [];
    for (let n = el; n; n = n.parentElement) {
      const cs = getComputedStyle(n);
      if (cs.backgroundImage !== 'none') return { img: true };
      chain.push(parse(cs.backgroundColor));
    }
    let acc = [255, 255, 255, 1];
    for (let i = chain.length - 1; i >= 0; i--) acc = over(chain[i], acc);
    return { c: acc };
  };
  const out = [];
  const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const seen = new Set();
  for (let t; (t = w.nextNode());) {
    if (!t.nodeValue.trim()) continue;
    const el = t.parentElement; if (!el || seen.has(el)) continue; seen.add(el);
    if (el.closest('script,style,noscript,[hidden],.visually-hidden,.sr-only')) continue;
    const r = el.getBoundingClientRect(); if (r.width < 2 || r.height < 2) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none') continue;
    const bg = bgOf(el); if (bg.img) { out.push({ sel: sel(el), note: 'bg-image', text: t.nodeValue.trim().slice(0, 30) }); continue; }
    let fg = parse(cs.color); fg = over([fg[0], fg[1], fg[2], fg[3] * parseFloat(cs.opacity)], bg.c);
    const px = parseFloat(cs.fontSize), bold = parseInt(cs.fontWeight) >= 700;
    const large = px >= 24 || (px >= 18.66 && bold);
    const need = large ? (${aaa} ? 4.5 : 3) : (${aaa} ? 7 : 4.5), rat = ratio(fg, bg.c);
    if (rat < need) out.push({ sel: sel(el), fg: hex(fg), bg: hex(bg.c), ratio: +rat.toFixed(2), need, text: t.nodeValue.trim().slice(0, 30) });
  }
  function sel(el) { let s = el.tagName.toLowerCase(); if (el.id) s += '#' + el.id; if (el.className && typeof el.className === 'string') s += '.' + el.className.trim().split(/\\s+/).slice(0, 2).join('.'); return s; }
  return out;
})`;


const OVERFLOW = `(() => {
  const vw = document.documentElement.clientWidth, out = [];
  const sel = (el) => { let s = el.tagName.toLowerCase(); if (el.id) s += '#' + el.id; if (typeof el.className === 'string' && el.className.trim()) s += '.' + el.className.trim().split(/\\s+/).slice(0, 2).join('.'); return s; };
  for (const el of document.body.querySelectorAll('*')) {
    if (el.closest('.visually-hidden,.sr-only,script,style,[hidden],.pen-display-panel')) continue;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || cs.position === 'fixed') continue;
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2 || r.right <= vw + 1) continue;
    // Skip content inside a scroller that is itself within the viewport (a deliberate scroll area).
    let scroller = false;
    for (let a = el.parentElement; a && a !== document.body; a = a.parentElement) {
      const o = getComputedStyle(a); if (/(auto|scroll)/.test(o.overflowX) && a.getBoundingClientRect().right <= vw + 1) { scroller = true; break; }
    }
    if (scroller) continue;
    out.push({ sel: sel(el), over: Math.round(r.right - vw) });
  }
  return out;
})()`;

const STATE_SEL = 'a, button, summary, input, select, textarea, [tabindex]';

async function snap(outFile, base, theme, rootDir) {
  const root = rootDir || new URL('../_site', import.meta.url).pathname;
  const list = pages(root);
  const dir = mkdtempSync(join(tmpdir(), 'pen-snap-'));
  const port = 9300 + Math.floor(Math.random() * 500);
  const chrome = spawn(CHROME, ['--headless=new', `--remote-debugging-port=${port}`,
    `--user-data-dir=${dir}`, '--no-first-run', '--disable-gpu', 'about:blank'], { stdio: 'ignore' });
  let ver;
  for (let i = 0; i < 60 && !ver; i++) {
    try { ver = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json(); } catch { await new Promise((r) => setTimeout(r, 250)); }
  }
  if (!ver) throw new Error('Chrome did not start');
  const ws = new WebSocket(ver.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r));
  const cdp = new CDP(ws);
  const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
  cdp.sid = (await cdp.send('Target.attachToTarget', { targetId, flatten: true })).sessionId;
  await cdp.send('Page.enable'); await cdp.send('DOM.enable'); await cdp.send('CSS.enable'); await cdp.send('Runtime.enable');
  const ev = async (expr) => (await cdp.send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })).result.value;

  const result = {};
  for (const w of WIDTHS) {
    await cdp.send('Emulation.setDeviceMetricsOverride', { width: w, height: 900, deviceScaleFactor: 1, mobile: false });
    for (const page of list) {
      await cdp.send('Page.navigate', { url: `${base}/${page}` });
      await new Promise((r) => setTimeout(r, 900));
      await ev('document.fonts.ready.then(() => 1)');
      if (!(await ev(`document.querySelector('main') && document.querySelector('nav.navbar') ? 1 : 0`))) throw new Error(`${base}/${page} did not load a PEN page`);
      if (theme) await ev(`document.documentElement.setAttribute('data-pen-theme', ${JSON.stringify(theme)})`);
      const rec = await ev(COLLECT);
      // Forced interactive states.
      const doc = await cdp.send('DOM.getDocument', { depth: 0 });
      const { nodeIds } = await cdp.send('DOM.querySelectorAll', { nodeId: doc.root.nodeId, selector: STATE_SEL });
      for (const nodeId of nodeIds) {
        for (const st of ['hover', 'focus-visible']) {
          try {
            await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: [st] });
            const { object } = await cdp.send('DOM.resolveNode', { nodeId });
            const r = await cdp.send('Runtime.callFunctionOn', { objectId: object.objectId, returnByValue: true,
              functionDeclaration: `function(){ const P=${JSON.stringify(PROPS)}; const cs=getComputedStyle(this);
                const parts=[]; for(let n=this;n&&n.nodeType===1;n=n.parentElement){const s=n.parentElement?[...n.parentElement.children].indexOf(n):0;parts.unshift(n.tagName.toLowerCase()+(n.id?'#'+n.id:'')+':'+s);}
                return [parts.join('>'), P.map(p=>cs.getPropertyValue(p)).join('|') + '|']; }` });
            const [k, v] = r.result.value;
            rec[`${k}:${st}`] = v;
            await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: [] });
          } catch { /* detached node */ }
        }
      }
      result[`${w}/${page}`] = rec;
    }
    process.stderr.write(`width ${w} done (${list.length} pages)\n`);
  }
  writeFileSync(outFile, JSON.stringify({ props: PROPS_OUT, pages: result }));
  ws.close(); chrome.kill();
  process.stderr.write(`wrote ${outFile}\n`);
}


async function withChrome(fn) {
  const dir = mkdtempSync(join(tmpdir(), 'pen-snap-'));
  const port = 9300 + Math.floor(Math.random() * 500);
  const chrome = spawn(CHROME, ['--headless=new', `--remote-debugging-port=${port}`,
    `--user-data-dir=${dir}`, '--no-first-run', '--disable-gpu', 'about:blank'], { stdio: 'ignore' });
  let ver;
  for (let i = 0; i < 60 && !ver; i++) {
    try { ver = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json(); } catch { await new Promise((r) => setTimeout(r, 250)); }
  }
  if (!ver) throw new Error('Chrome did not start');
  const ws = new WebSocket(ver.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r));
  const cdp = new CDP(ws);
  const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
  cdp.sid = (await cdp.send('Target.attachToTarget', { targetId, flatten: true })).sessionId;
  await cdp.send('Page.enable'); await cdp.send('DOM.enable'); await cdp.send('CSS.enable'); await cdp.send('Runtime.enable');
  const ev = async (expr) => { const r = await cdp.send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
    if (r.exceptionDetails) throw new Error('page eval failed: ' + (r.exceptionDetails.exception?.description || r.exceptionDetails.text)); return r.result.value; };
  try { return await fn(cdp, ev); } finally { ws.close(); chrome.kill(); }
}

async function scan(base, theme, attrs, aaa) {
  const root = new URL('../_site', import.meta.url).pathname;
  const list = pages(root);
  const groups = new Map();
  await withChrome(async (cdp, ev) => {
    for (const w of [1440, 375]) {
      await cdp.send('Emulation.setDeviceMetricsOverride', { width: w, height: 900, deviceScaleFactor: 1, mobile: false });
      for (const page of list) {
        await cdp.send('Page.navigate', { url: `${base}/${page}` });
        await new Promise((r) => setTimeout(r, 700));
        await ev('document.fonts.ready.then(() => 1)');
        const ok = await ev(`document.querySelector('main') && document.querySelector('nav.navbar') ? 1 : 0`);
        if (!ok) throw new Error(`${base}/${page} did not load a PEN page (404 or missing _site file); refusing to report a clean scan`);
        await ev(`(() => { const st = document.createElement('style'); st.textContent = '*,*::before,*::after{transition:none!important;animation:none!important}'; document.head.appendChild(st); })()`);
        if (theme) await ev(`document.documentElement.setAttribute('data-pen-theme', ${JSON.stringify(theme)})`);
        for (const kv of attrs.filter(Boolean)) { const [k, v] = kv.split('='); await ev(`document.documentElement.setAttribute(${JSON.stringify(k)}, ${JSON.stringify(v)})`); }
        // Open every <details> and reveal the certificate so hidden text is scanned too.
        await ev(`document.querySelectorAll('details').forEach((d) => d.open = true); 1`);
        const res = await ev(`(${SCAN(aaa)})(document.body)`);
        // Hover and focus states: force each, rescan that control's own subtree.
        const doc = await cdp.send('DOM.getDocument', { depth: 0 });
        const { nodeIds } = await cdp.send('DOM.querySelectorAll', { nodeId: doc.root.nodeId, selector: 'main a, main button, main summary, .navbar a, footer a, footer summary' });
        for (const nodeId of nodeIds) {
          for (const st of ['hover', 'focus-visible']) {
            try {
              await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: [st] });
              const { object } = await cdp.send('DOM.resolveNode', { nodeId });
              const r = await cdp.send('Runtime.callFunctionOn', { objectId: object.objectId, returnByValue: true,
                functionDeclaration: `function(){ return (${SCAN(aaa)})(this); }` });
              for (const x of (r.result.value || [])) { x.sel += ':' + st; res.push(x); }
              await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: [] });
            } catch { /* detached */ }
          }
        }
        for (const r of res) {
          const key = r.note ? `bg-image  ${r.sel}` : `${r.fg} on ${r.bg}  ${r.ratio} (need ${r.need})  ${r.sel}`;
          const g = groups.get(key) || { n: 0, ex: new Set() };
          g.n++; if (g.ex.size < 2) g.ex.add(`${page}@${w}: "${r.text}"`); groups.set(key, g);
        }
      }
    }
  });
  const rows = [...groups.entries()].sort((a, b) => b[1].n - a[1].n);
  for (const [k, g] of rows) console.log(`${String(g.n).padStart(4)}  ${k}\n        ${[...g.ex].join('  |  ')}`);
  console.log(`\n${rows.length} distinct failing/unscannable groups`);
}

async function overflow(base, only, widths) {
  const root = new URL('../_site', import.meta.url).pathname;
  const list = pages(root);
  const combos = [
    ['default', {}],
    ['size125', { 'data-pen-size': '125' }],
    ['size150', { 'data-pen-size': '150' }],
    ['roomy', { 'data-pen-spacing': 'roomy' }],
    ['easy-font', { 'data-pen-font': 'easy' }],
    ['all-max light', { 'data-pen-size': '150', 'data-pen-spacing': 'roomy', 'data-pen-font': 'easy', 'data-pen-theme': 'light' }],
    ['all-max dark', { 'data-pen-size': '150', 'data-pen-spacing': 'roomy', 'data-pen-font': 'easy', 'data-pen-theme': 'dark' }],
    ['all-max contrast', { 'data-pen-size': '150', 'data-pen-spacing': 'roomy', 'data-pen-font': 'easy', 'data-pen-theme': 'contrast' }],
  ];
  const groups = new Map();
  const use = only.length ? combos.filter(([n]) => only.includes(n)) : combos;
  await withChrome(async (cdp, ev) => {
    for (const w of widths) {
      await cdp.send('Emulation.setDeviceMetricsOverride', { width: w, height: 900, deviceScaleFactor: 1, mobile: false });
      for (const page of list) {
        await cdp.send('Page.navigate', { url: `${base}/${page}` });
        await new Promise((r) => setTimeout(r, 600));
        await ev('document.fonts.ready.then(() => 1)');
        if (!(await ev(`document.querySelector('main') && document.querySelector('nav.navbar') ? 1 : 0`))) throw new Error(`${base}/${page} did not load a PEN page`);
        await ev(`document.querySelectorAll('details').forEach((d) => d.open = true); 1`);
        for (const [name, attrs] of use) {
          for (const [k, v] of Object.entries(attrs)) await ev(`document.documentElement.setAttribute(${JSON.stringify(k)}, ${JSON.stringify(v)})`);
          await new Promise((r) => setTimeout(r, 120));
          for (const r of await ev(OVERFLOW)) {
            const key = `${name} @${w}  ${r.sel}`;
            const g = groups.get(key) || { n: 0, max: 0, pages: new Set() };
            g.n++; g.max = Math.max(g.max, r.over); if (g.pages.size < 3) g.pages.add(page); groups.set(key, g);
          }
          for (const k of Object.keys(attrs)) await ev(`document.documentElement.removeAttribute(${JSON.stringify(k)})`);
          await ev(`window.penDisplay && window.penDisplay.apply(window.penDisplay.read()); 1`);
        }
      }
      process.stderr.write(`width ${w} done\n`);
    }
  });
  const rows = [...groups.entries()].sort((a, b) => b[1].max - a[1].max);
  for (const [k, g] of rows) console.log(`${String(g.max).padStart(5)}px over  x${g.n}  ${k}   [${[...g.pages].join(', ')}]`);
  console.log(`\n${rows.length} overflow groups`);
}

const HOVERPROBE = `function(){ const P=['color','background-color','border-top-color','border-left-color','box-shadow','text-decoration-line','text-underline-offset','text-decoration-thickness','transform','outline-style'];
  const n=this; const cs=getComputedStyle(n); const own = P.map(p=>cs.getPropertyValue(p));
  const eff=(el)=>{ for(let a=el;a;a=a.parentElement){ const c=getComputedStyle(a).backgroundColor; const m=c.match(/[\\d.]+/g); if(m && (m.length<4 || +m[3]>0.5)) return c; } return 'rgb(255,255,255)'; };
  own[1]=eff(n);
  const pse=['::before','::after'].map(q=>{const c=getComputedStyle(n,q); return c.content==='none'?'':[c.backgroundColor,c.color,c.transform].join('~')}).join('|'); own.push(pse);
  const kids=[...n.querySelectorAll('*')].slice(0,8).map(k=>{const c=getComputedStyle(k);return [c.color,c.textDecorationLine,c.backgroundColor,c.transform].join('~')});
  return {own, kids}; }`;
async function hover(base, theme) {
  const root = new URL('../_site', import.meta.url).pathname;
  const list = pages(root);
  const lumOf = (c) => { const m = c.match(/[\d.]+/g); if (!m || m.length < 3) return null; const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(+m[0]) + 0.7152 * f(+m[1]) + 0.0722 * f(+m[2]); };
  const rat = (a, b) => { const x = lumOf(a), y = lumOf(b); if (x == null || y == null) return 99; return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  const groups = new Map();
  await withChrome(async (cdp, ev) => {
    await cdp.send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false });
    for (const page of list) {
      await cdp.send('Page.navigate', { url: `${base}/${page}` });
      await new Promise((r) => setTimeout(r, 600));
      await ev('document.fonts.ready.then(() => 1)');
      await ev(`(() => { const st = document.createElement('style'); st.textContent = '*,*::before,*::after{transition:none!important;animation:none!important}'; document.head.appendChild(st); })()`);
      if (theme) await ev(`document.documentElement.setAttribute('data-pen-theme', ${JSON.stringify(theme)})`);
      await ev(`document.querySelectorAll('.dropdown-menu').forEach((m) => m.classList.add('show')); document.querySelectorAll('details').forEach((d) => d.open = true); 1`);
      const doc = await cdp.send('DOM.getDocument', { depth: 0 });
      const { nodeIds } = await cdp.send('DOM.querySelectorAll', { nodeId: doc.root.nodeId, selector: 'a, button, summary, .pen-display-opt input' });
      for (const nodeId of nodeIds) {
        try {
          const { object } = await cdp.send('DOM.resolveNode', { nodeId });
          const call = async () => (await cdp.send('Runtime.callFunctionOn', { objectId: object.objectId, returnByValue: true, functionDeclaration: HOVERPROBE })).result.value;
          const info = (await cdp.send('Runtime.callFunctionOn', { objectId: object.objectId, returnByValue: true, functionDeclaration: `function(){ const r=this.getBoundingClientRect(); const cs=getComputedStyle(this); let s=this.tagName.toLowerCase(); if(this.id) s+='#'+this.id; if(typeof this.className==='string'&&this.className.trim()) s+='.'+this.className.trim().split(/\\s+/).slice(0,2).join('.'); return {sel:s, vis: r.width>2&&r.height>2&&cs.display!=='none'&&cs.visibility!=='hidden', txt:(this.textContent||'').trim().slice(0,24)}; }` })).result.value;
          if (!info.vis) continue;
          const rest = await call();
          await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: ['hover'] });
          const hov = await call();
          await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: [] });
          const [rc, rbg, rbc, , rsh, rdec, , , rtr] = [rest.own[0], rest.own[1], rest.own[2], 0, rest.own[4], rest.own[5], 0, 0, rest.own[8]];
          const hc = hov.own;
          const cues = [];
          if (rat(rest.own[1], hc[1]) >= 1.3) cues.push('fill');
          if (rat(rest.own[0], hc[0]) >= 1.3) cues.push('text');
          if (rest.own[5] !== hc[5] || rest.own[6] !== hc[6] || rest.own[7] !== hc[7]) cues.push('underline');
          if (rest.own[4] !== hc[4]) cues.push('shadow');
          if (rest.own[8] !== hc[8]) cues.push('move');
          if (rest.own[10] !== hc[10]) cues.push('inner');
          if (rest.own[9] !== hc[9]) cues.push('ring');
          if (rest.own[2] !== hc[2] && rat(rest.own[2], hc[2]) >= 1.3) cues.push('border');
          if (JSON.stringify(rest.kids) !== JSON.stringify(hov.kids)) cues.push('inner');
          const weak = cues.length === 0 || (cues.length === 1 && (cues[0] === 'text' || cues[0] === 'inner' || cues[0] === 'underline'));
          if (weak) { const key = `${cues.join('+') || 'NONE'}  ${info.sel}`; const g = groups.get(key) || { n: 0, ex: new Set() }; g.n++; if (g.ex.size < 2) g.ex.add(`${page}: "${info.txt}"`); groups.set(key, g); }
        } catch { /* detached */ }
      }
    }
  });
  for (const [k, g] of [...groups.entries()].sort((a, b) => b[1].n - a[1].n)) console.log(`${String(g.n).padStart(4)}  ${k}\n        ${[...g.ex].join('  |  ')}`);
  console.log(`\n${groups.size} weak-hover groups`);
}

function diff(a, b) {
  const A = JSON.parse(readFileSync(a, 'utf8')), B = JSON.parse(readFileSync(b, 'utf8'));
  let changed = 0, missing = 0;
  const byProp = {};
  for (const pg of Object.keys(A.pages)) {
    const pa = A.pages[pg], pb = B.pages[pg] || {};
    for (const k of Object.keys(pa)) {
      if (!(k in pb)) { missing++; if (missing <= 10) console.log(`MISSING in B  ${pg}  ${k}`); continue; }
      if (pa[k] === pb[k]) continue;
      const va = pa[k].split('|'), vb = pb[k].split('|');
      va.forEach((x, i) => { if (x !== vb[i]) { changed++; byProp[A.props[i]] = (byProp[A.props[i]] || 0) + 1;
        if (changed <= 40) console.log(`${pg}  ${k.slice(-90)}  ${A.props[i]}: ${x}  ->  ${vb[i]}`); } });
    }
  }
  console.log(`\nchanged values: ${changed}   missing keys: ${missing}`);
  console.log(byProp);
  process.exit(changed || missing ? 1 : 0);
}

const [cmd, ...rest] = process.argv.slice(2);
const flag = (n, d) => (rest.find((r) => r.startsWith(`--${n}=`)) || `--${n}=${d}`).split('=')[1];
const pos = rest.filter((r) => !r.startsWith('--'));
if (cmd === 'snap') await snap(pos[0], flag('base', 'http://localhost:8123'), flag('theme', ''), flag('root', ''));
else if (cmd === 'diff') diff(pos[0], pos[1]);
else if (cmd === 'hover') await hover(flag('base', 'http://localhost:8123'), flag('theme', ''));
else if (cmd === 'overflow') await overflow(flag('base', 'http://localhost:8123'), flag('only', '').split(',').filter(Boolean), flag('widths', '320,768,1440').split(',').map(Number));
else if (cmd === 'scan') await scan(flag('base', 'http://localhost:8123'), flag('theme', ''), flag('attrs', '').split(','), flag('aaa', '') === '1');
else { console.error('usage: snap <out> | diff <a> <b>'); process.exit(2); }
