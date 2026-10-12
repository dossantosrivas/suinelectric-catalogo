// Visita la página oficial de cada producto y guarda la foto más grande que carga.
const { chromium } = require('playwright');
const fs = require('fs');
const LISTA = require('./fotos-extra-lista.json');
(async () => {
  const nav = await chromium.launch({ channel: 'chrome', headless: false, args: ['--disable-blink-features=AutomationControlled'] });
  const ctx = await nav.newContext({ locale: 'en-US', viewport: { width: 1400, height: 1000 } });
  await ctx.addInitScript(() => Object.defineProperty(navigator, 'webdriver', { get: () => undefined }));
  fs.mkdirSync('salida/extra', { recursive: true });
  const res = [];
  for (const { id, url } of LISTA) {
    const p = await ctx.newPage();
    const imgs = new Map();
    p.on('response', async (r) => {
      try {
        const ct = r.headers()['content-type'] || '';
        if (!/image\/(jpe?g|png|webp)/.test(ct)) return;
        const b = await r.body(); if (b.length > 8000) imgs.set(r.url(), b);
      } catch {}
    });
    const fila = { id, url, fin: null, titulo: null, og: null, guardadas: [] };
    try {
      await p.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
      await p.waitForTimeout(9000);
      for (const t of ['Accept All', 'Accept all', 'Aceptar todo', 'Accept']) { const b = p.getByRole('button', { name: t }); if (await b.count().catch(() => 0)) { await b.first().click().catch(() => {}); await p.waitForTimeout(2500); break; } }
      await p.mouse.wheel(0, 500).catch(() => {}); await p.waitForTimeout(3000);
      fila.fin = p.url(); fila.titulo = (await p.title()).slice(0, 150);
      fila.og = await p.$eval('meta[property="og:image"]', (e) => e.content).catch(() => null);
      fila.vistas = await p.$$eval('img', (a) => a.map((e) => [e.currentSrc || e.src, e.naturalWidth, e.naturalHeight, (e.alt || '').slice(0, 60)]).filter((x) => x[1] >= 200)).catch(() => []);
      if (fila.og && !imgs.has(fila.og)) { const r = await ctx.request.get(fila.og).catch(() => null); if (r && r.ok()) imgs.set(fila.og, await r.body()); }
      const orden = [...imgs.entries()].sort((a, b) => b[1].length - a[1].length).slice(0, 6);
      orden.forEach(([u, b], i) => { const f = `salida/extra/${id.replace(/[^A-Za-z0-9-]/g, '_')}-${i + 1}.img`; fs.writeFileSync(f, b); fila.guardadas.push({ f, u: u.slice(0, 300), bytes: b.length }); });
      await p.screenshot({ path: `salida/extra/${id.replace(/[^A-Za-z0-9-]/g, '_')}-pantalla.jpg`, type: 'jpeg', quality: 50 });
    } catch (e) { fila.error = e.message.slice(0, 200); }
    res.push(fila); console.log(id, fila.guardadas.length, fila.titulo);
    await p.close();
  }
  fs.writeFileSync('salida/extra/resultado.json', JSON.stringify(res, null, 1));
  await nav.close();
})();
