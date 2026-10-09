// Diagnóstico: qué devuelve se.com para algunos modelos.
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const nav = await chromium.launch({ channel: 'chrome', headless: false, args: ['--disable-blink-features=AutomationControlled'] });
  const ctx = await nav.newContext({ locale: 'es-ES', viewport: { width: 1366, height: 900 } });
  await ctx.addInitScript(() => Object.defineProperty(navigator, 'webdriver', { get: () => undefined }));
  const p = await ctx.newPage();
  const out = [];
  for (const m of ['LC1D09BD', 'ATV320U04N4C', 'EZC100H3015', 'XB4BA21'])
    for (const pais of ['ww/en', 'us/en', 've/es', 'mx/es', 'co/es']) {
      const url = `https://www.se.com/${pais}/product/${m}/`;
      try {
        const r = await p.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
        await p.waitForTimeout(5000);
        const og = await p.$eval('meta[property="og:image"]', e => e.content).catch(() => null);
        const imgs = await p.$$eval('img', a => a.map(e => e.currentSrc || e.src).filter(s => /schneider/.test(s)).slice(0, 8)).catch(() => []);
        out.push({ url, status: r && r.status(), final: p.url(), title: await p.title(), og, imgs });
      } catch (e) { out.push({ url, error: e.message.slice(0, 120) }); }
    }
  fs.writeFileSync('scripts/fotos-schneider-diagnostico.json', JSON.stringify(out, null, 1));
  await nav.close();
})();
