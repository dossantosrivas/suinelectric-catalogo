// Diagnóstico: recorre la web oficial de HD Hyundai Electric buscando las páginas
// de productos de baja tensión y sus fotos.
const { chromium } = require('playwright');
const fs = require('fs');
const INICIOS = ['https://www.hd-hyundaielectric.com/', 'https://www.hd-hyundaielectric.com/en/', 'https://www.hyundai-elec.com/', 'https://www.hyundai-electric.com/'];
const CLAVE = /low|lv|breaker|contactor|product|prod|mccb|acb|mcb|relay|starter|switch|hgm|hgc|hgn|hgd|mms|hgt|저압|차단기|개폐기/i;
(async () => {
  const nav = await chromium.launch({ channel: 'chrome', headless: false });
  const ctx = await nav.newContext({ locale: 'en-US', viewport: { width: 1366, height: 900 } });
  const p = await ctx.newPage();
  const vistos = new Set(), cola = [...INICIOS], out = [];
  while (cola.length && out.length < 120) {
    const url = cola.shift();
    if (vistos.has(url)) continue; vistos.add(url);
    try {
      const r = await p.goto(url, { waitUntil: 'domcontentloaded', timeout: 40000 });
      await p.waitForTimeout(3500);
      const fin = p.url(); const host = new URL(fin).host;
      const links = await p.$$eval('a[href]', (a) => a.map((e) => [e.href, (e.innerText || '').trim().slice(0, 60)]));
      const imgs = await p.$$eval('img', (a) => a.map((e) => [e.currentSrc || e.src, e.naturalWidth, e.naturalHeight, e.alt]).filter((x) => x[1] >= 150));
      out.push({ url, fin, status: r && r.status(), titulo: await p.title(), imgs: imgs.slice(0, 40), links: links.filter(([h, t]) => CLAVE.test(h + ' ' + t)).slice(0, 80) });
      for (const [h] of links) {
        try { const u = new URL(h); if (u.host === host && CLAVE.test(h) && !vistos.has(h) && !/\.(pdf|zip|jpg|png)$/i.test(h)) cola.push(h.split('#')[0]); } catch {}
      }
    } catch (e) { out.push({ url, error: e.message.slice(0, 150) }); }
  }
  fs.mkdirSync('salida', { recursive: true });
  fs.writeFileSync('salida/hyundai-explorar.json', JSON.stringify(out, null, 1));
  await nav.close();
})();
