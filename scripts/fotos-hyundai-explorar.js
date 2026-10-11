// Descarga los catálogos oficiales en inglés (baja tensión) de HD Hyundai Electric.
const { chromium } = require('playwright');
const fs = require('fs');
const BUSCAR = ['영문 카탈로그_HGC', 'HGM', 'HGN', '영문 카탈로그_HGD', 'MCCB', 'ACB', '[MCCB]', '[ACB]'];
const QUIERO = /카탈로그|catalog/i, IDIOMA = /영문|\(E\)|ENG/i, SERIES = /HGC|HGT|HGM|HGN|HGD|HMMS|HRC|UAN|MCCB|ACB/i;
(async () => {
  const nav = await chromium.launch({ channel: 'chrome', headless: false });
  const ctx = await nav.newContext({ locale: 'ko-KR', viewport: { width: 1366, height: 900 }, acceptDownloads: true });
  const p = await ctx.newPage();
  fs.mkdirSync('salida/pdf', { recursive: true });
  const lista = new Map(), log = [];
  for (const v of BUSCAR) for (let n = 1; n <= 3; n++) {
    await p.goto(`https://www.hd-hyundaielectric.com/elect/ko/customer/download.jsp?paging.pageNo=${n}&boardCode=download&code1=&code2=&code3=&searchKey=all&searchValue=${encodeURIComponent(v)}`, { waitUntil: 'commit', timeout: 40000 }).catch(() => {});
    await p.waitForTimeout(4000);
    const filas = await p.$$eval('a[onclick*="goDetail"]', (a) => a.map((e) => [e.getAttribute('onclick'), (e.closest('tr') || e.parentElement).innerText.replace(/\s+/g, ' ').trim()])).catch(() => []);
    for (const [oc, txt] of filas) {
      const m = oc.match(/goDetail\('(\d+)',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)'\)/); if (!m) continue;
      if (QUIERO.test(txt + m[4]) && IDIOMA.test(m[4]) && SERIES.test(m[4])) lista.set(m[1], { oc, nombre: m[4], txt, pagina: p.url() });
    }
  }
  log.push({ encontrados: [...lista.values()].map((x) => x.nombre) });
  const goDetailSrc = await p.evaluate(() => (window.goDetail ? window.goDetail.toString() : null)).catch(() => null);
  log.push({ goDetailSrc });
  for (const [id, x] of lista) {
    try {
      await p.goto(x.pagina, { waitUntil: 'commit' }); await p.waitForTimeout(3000);
      const espera = Promise.race([
        p.waitForEvent('download', { timeout: 90000 }).then((d) => ({ d })),
        ctx.waitForEvent('page', { timeout: 90000 }).then((np) => ({ np })),
      ]);
      await p.evaluate((oc) => eval(oc), x.oc);
      const r = await espera;
      const dest = `salida/pdf/${id}.pdf`;
      if (r.d) await r.d.saveAs(dest);
      else { await r.np.waitForLoadState().catch(() => {}); const u = r.np.url(); const resp = await ctx.request.get(u, { timeout: 120000 }); fs.writeFileSync(dest, await resp.body()); }
      log.push({ id, nombre: x.nombre, bytes: fs.statSync(dest).size });
    } catch (e) { log.push({ id, nombre: x.nombre, error: e.message.slice(0, 200) }); }
  }
  fs.writeFileSync('salida/hyundai-descargas.json', JSON.stringify(log, null, 1));
  await nav.close();
})();
