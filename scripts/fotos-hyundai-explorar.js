// Diagnóstico 3: lista del centro de descargas (catálogos) de HD Hyundai Electric.
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const nav = await chromium.launch({ channel: 'chrome', headless: false });
  const ctx = await nav.newContext({ locale: 'en-US', viewport: { width: 1366, height: 900 }, acceptDownloads: true });
  const p = await ctx.newPage();
  const out = [];
  const urls = [];
  for (let n = 1; n <= 12; n++) {
    urls.push(`https://www.hd-hyundaielectric.com/elect/ko/customer/download.jsp?paging.pageNo=${n}&boardCode=download&code1=E0000&code2=&code3=&searchKey=all&searchValue=`);
  }
  for (const v of ['HGM', 'HGC', 'HGN', 'HGD', 'MMS', 'HGT', 'catalog', 'Catalogue', '저압', 'MCCB', 'ACB', 'contactor'])
    urls.push(`https://www.hd-hyundaielectric.com/elect/ko/customer/download.jsp?paging.pageNo=1&boardCode=download&code1=&code2=&code3=&searchKey=all&searchValue=${encodeURIComponent(v)}`);
  urls.push('https://www.hd-hyundaielectric.com/elect/en/customer/download.jsp');
  for (const url of urls) {
    try {
      await p.goto(url, { waitUntil: 'commit', timeout: 40000 });
      await p.waitForTimeout(5000);
      const html = await p.content();
      const filas = await p.$$eval('table tr, ul li, .board-list li, .list li', (a) => a.map((e) => e.innerText.replace(/\s+/g, ' ').trim()).filter((t) => t.length > 5 && t.length < 300)).catch(() => []);
      const links = await p.$$eval('a', (a) => a.map((e) => [e.getAttribute('href') || '', e.getAttribute('onclick') || '', (e.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 100)])).catch(() => []);
      out.push({ url, fin: p.url(), filas: filas.slice(0, 80), links: links.filter(([h, o, t]) => /down|file|view|detail|javascript|fn|\.pdf/i.test(h + o)).slice(0, 120), formularios: (html.match(/function\s+\w*[Dd]own\w*\s*\([^)]*\)\s*\{[^}]{0,400}/g) || []).slice(0, 5) });
    } catch (e) { out.push({ url, error: e.message.slice(0, 150) }); }
  }
  fs.mkdirSync('salida', { recursive: true });
  fs.writeFileSync('salida/hyundai-explorar.json', JSON.stringify(out, null, 1));
  await nav.close();
})();
