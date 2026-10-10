// Busca las fotos oficiales de cada modelo Schneider en se.com (con un navegador
// real, porque se.com bloquea las descargas directas).
// Guarda cada foto una sola vez, por su referencia de Schneider, en
// salida/fotos/<REF>.jpg (1000 px) y anota qué fotos tiene cada modelo en
// salida/resultado-<PARTE>.json. Lo corre el workflow fotos-schneider.yml.
//   PARTE / PARTES: divide la lista para correr varias copias en paralelo.
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const { chromium } = require('playwright');

const PARTES = +(process.env.PARTES || 1), PARTE = +(process.env.PARTE || 0);
const LISTA = require('./fotos-schneider-lista.json').filter((_, i) => i % PARTES === PARTE);
const SALIDA = path.join(__dirname, '..', 'salida');
const FOTOS = path.join(SALIDA, 'fotos');
const PAISES = ['co/es', 'mx/es', 'us/en', 'es/es', 'ar/es'];

// Planos, íconos de manual, láminas de marketing: no son fotos del producto.
const NO_FOTO = /dimension|_TI\b|_TI-|TIB\d|_MI_|wiring|drawing|schema|curve|logo|Default|-TB$|-TUSP$|-TSUP$|-RO$|_TB$|_TUSP$|_RO$|Technical/i;
// Vistas del mismo producto (frente, lados, atrás…)
const VISTA = /front|rear|back|left|right|top|bottom|45x4|_360|side/i;
const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
const ref = (u) => { const m = u.match(/p_Doc_Ref=([^&]+)/); return m ? decodeURIComponent(m[1]) : null; };
const archivo = (r) => r.replace(/[^A-Za-z0-9._+-]/g, '_') + '.jpg';

(async () => {
  fs.mkdirSync(FOTOS, { recursive: true });
  const nav = await chromium.launch({ channel: 'chrome', headless: true, args: ['--disable-blink-features=AutomationControlled'] });
  const ctx = await nav.newContext({ locale: 'es-ES', viewport: { width: 1366, height: 900 },
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36' });
  await ctx.addInitScript(() => Object.defineProperty(navigator, 'webdriver', { get: () => undefined }));
  const pag = await ctx.newPage();
  const res = {};

  for (const modelo of LISTA) {
    const fila = { titulo: null, pagina: null, refs: [], todas: [], error: null };
    for (const pais of PAISES) {
      const url = `https://www.se.com/${pais}/product/${encodeURIComponent(modelo)}/`;
      try {
        await pag.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
        await pausa(4000);
        if (!decodeURIComponent(pag.url()).toUpperCase().includes(`/PRODUCT/${modelo.toUpperCase()}/`)) { fila.error = 'no existe'; continue; }
        const srcs = await pag.$$eval('img', (a) => a.map((e) => e.currentSrc || e.src || ''));
        const og = await pag.$eval('meta[property="og:image"]', (e) => e.content).catch(() => null);
        const todas = [];
        for (const u of [...srcs, og].filter(Boolean)) {
          if (!/download\.schneider-electric\.com\/files\?/.test(u)) continue;
          const r = ref(u);
          if (r && !todas.includes(r)) todas.push(r);
        }
        fila.titulo = (await pag.title()).replace(/\s*\|\s*Schneider Electric.*$/, '').slice(0, 160);
        fila.todas = todas;
        const fotos = todas.filter((r) => !NO_FOTO.test(r));
        if (!fotos.length) { fila.error = 'sin fotos'; continue; }
        // Principal: la primera; extras: solo vistas del mismo producto.
        fila.refs = [fotos[0], ...fotos.slice(1).filter((r) => VISTA.test(r))].slice(0, 4);
        fila.pagina = pag.url(); fila.error = null;
        break;
      } catch (e) { fila.error = e.message.slice(0, 100); }
    }
    for (const r of fila.refs) {
      const dest = path.join(FOTOS, archivo(r));
      if (fs.existsSync(dest)) continue;
      try {
        const resp = await ctx.request.get(`https://download.schneider-electric.com/files?p_Doc_Ref=${encodeURIComponent(r)}&p_File_Type=rendition_1500_jpg`, { timeout: 30000 });
        if (!resp.ok()) continue;
        const buf = await resp.body();
        if (buf.length < 5000) continue;
        await sharp(buf).flatten({ background: '#ffffff' }).resize(1000, 1000, { fit: 'inside', withoutEnlargement: true })
          .jpeg({ quality: 84, mozjpeg: true }).toFile(dest);
      } catch (e) { console.log('  no se pudo bajar', r, e.message.slice(0, 60)); }
    }
    fila.refs = fila.refs.filter((r) => fs.existsSync(path.join(FOTOS, archivo(r))));
    console.log(modelo, fila.refs.join(' ') || 'SIN FOTO', fila.error || '');
    res[modelo] = fila;
    await pausa(1200);
  }
  await nav.close();
  fs.writeFileSync(path.join(SALIDA, `resultado-${PARTE}.json`), JSON.stringify(res, null, 1));
})();
