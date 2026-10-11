// Diagnóstico 2: la página de "중저압 차단기" (baja/media tensión) y a dónde lleva.
const { chromium } = require('playwright');
const fs = require('fs');
const INICIOS = ['https://www.hd-hyundaielectric.com/elect/ko/product/product8.jsp',
  'https://www.hd-hyundaielectric.com/elect/ko/product/product8.jsp?anchor=loca11',
  'https://www.hd-hyundaielectric.com/elect/en/product/product8.jsp',
  'https://www.hd-hyundaielectric.com/elect/en/index.jsp'];
(async () => {
  const nav = await chromium.launch({ channel: 'chrome', headless: false });
  const ctx = await nav.newContext({ locale: 'en-US', viewport: { width: 1366, height: 900 } });
  const p = await ctx.newPage();
  const out = [];
  const cola = [...INICIOS], vistos = new Set();
  while (cola.length && out.length < 40) {
    const url = cola.shift(); if (vistos.has(url)) continue; vistos.add(url);
    const navs = [];
    p.on('framenavigated', (f) => { if (f === p.mainFrame()) navs.push(f.url()); });
    try {
      await p.goto(url, { waitUntil: 'commit', timeout: 40000 }).catch((e) => navs.push('ERR ' + e.message.slice(0, 80)));
      await p.waitForTimeout(7000);
      await p.mouse.wheel(0, 3000).catch(() => {}); await p.waitForTimeout(2000);
      const links = await p.$$eval('a[href]', (a) => a.map((e) => [e.href, (e.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 60)])).catch(() => []);
      const imgs = await p.$$eval('img', (a) => a.map((e) => [e.currentSrc || e.src, e.naturalWidth, e.naturalHeight, e.alt])).catch(() => []);
      const bg = await p.$$eval('*', (a) => a.map((e) => getComputedStyle(e).backgroundImage).filter((b) => b && b !== 'none' && /url/.test(b))).catch(() => []);
      out.push({ url, fin: p.url(), navs, titulo: await p.title().catch(() => ''), texto: (await p.innerText('body').catch(() => '')).replace(/\s+/g, ' ').slice(0, 1500), imgs, bg: [...new Set(bg)].slice(0, 40), links });
      const host = new URL(p.url()).host;
      for (const [h, t] of links) {
        try { const u = new URL(h); if ((u.host === host || /hyundai/.test(u.host)) && /차단기|개폐|breaker|contactor|lv|저압|hgm|hgc|hgn|mccb|acb|mcb|product|prod/i.test(h + t) && !/\.(pdf|zip)$/i.test(h)) cola.push(h); } catch {}
      }
    } catch (e) { out.push({ url, error: e.message.slice(0, 150), navs }); }
    p.removeAllListeners('framenavigated');
  }
  fs.mkdirSync('salida', { recursive: true });
  fs.writeFileSync('salida/hyundai-explorar.json', JSON.stringify(out, null, 1));
  await nav.close();
})();
