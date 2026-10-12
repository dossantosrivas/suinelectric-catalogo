// Descarga las fotos oficiales ya ubicadas (Siemens SiePortal / Schneider se.com).
const { chromium } = require('playwright');
const fs = require('fs');
const LISTA = require('./fotos-extra-lista.json');
(async () => {
  const nav = await chromium.launch({ channel: 'chrome', headless: false });
  const ctx = await nav.newContext();
  const p = await ctx.newPage();
  await p.goto('https://sieportal.siemens.com/en-ww/products-services/detail/6ES7315-6TH13-0AB0', { waitUntil: 'domcontentloaded' }).catch(() => {});
  await p.waitForTimeout(4000);
  fs.mkdirSync('salida/extra2', { recursive: true });
  const res = [];
  for (const { id, url } of LISTA) {
    try { const r = await ctx.request.get(url, { timeout: 60000 }); const b = await r.body(); fs.writeFileSync(`salida/extra2/${id}.jpg`, b); res.push({ id, status: r.status(), bytes: b.length }); }
    catch (e) { res.push({ id, error: e.message.slice(0, 120) }); }
  }
  fs.writeFileSync('salida/extra2/resultado.json', JSON.stringify(res, null, 1));
  await nav.close();
})();
