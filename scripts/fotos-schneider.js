// Busca la foto oficial de cada modelo Schneider en se.com (con un navegador real,
// porque se.com bloquea las descargas directas) y la guarda en
// imagenes/schneider/oficial/<MODELO>.jpg. Deja un registro en
// scripts/fotos-schneider-resultado.json. Lo corre el workflow fotos-schneider.yml.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

let LISTA = require('./fotos-schneider-lista.json');
if (process.env.LIMITE) LISTA = LISTA.slice(0, +process.env.LIMITE);
const DESTINO = path.join(__dirname, '..', 'imagenes', 'schneider', 'oficial');
const PAGINAS = (m) => ['co/es', 'mx/es', 'us/en', 'es/es', 'ar/es'].map((p) => `https://www.se.com/${p}/product/${m}/`);
// Planos, íconos de manual y similares (no son fotos del producto)
const NO_FOTO = /dimension|_TI\b|_TI-|TIB\d|_MI_|wiring|drawing|schema|curve|logo|Default/i;
const pausa = (ms) => new Promise((r) => setTimeout(r, ms));

function esFoto(u) {
  return /download\.schneider-electric\.com\/files\?/.test(u) && /rendition_\d+_(jpg|png)/i.test(u);
}
function grande(u) { return u.replace(/rendition_\d+_(jpg|png)/i, 'rendition_1500_jpg'); }
function ref(u) { const m = u.match(/p_Doc_Ref=([^&]+)/); return m ? m[1] : u; }

(async () => {
  fs.mkdirSync(DESTINO, { recursive: true });
  const nav = await chromium.launch({ channel: 'chrome', headless: true, args: ['--disable-blink-features=AutomationControlled'] });
  const ctx = await nav.newContext({ locale: 'es-ES', viewport: { width: 1366, height: 900 },
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36' });
  await ctx.addInitScript(() => Object.defineProperty(navigator, 'webdriver', { get: () => undefined }));
  const pag = await ctx.newPage();
  const res = [];

  for (const { familia, modelo } of LISTA) {
    const fila = { familia, modelo, pagina: null, titulo: null, imagenes: [], archivos: [], error: null };
    for (const url of PAGINAS(modelo)) {
      try {
        await pag.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
        await pausa(4500);
        if (!decodeURIComponent(pag.url()).toUpperCase().includes(`/PRODUCT/${modelo.toUpperCase()}/`)) { fila.error = 'no existe en ' + url; continue; }
        const srcs = await pag.$$eval('img', (a) => a.map((e) => e.currentSrc || e.src || ''));
        const og = await pag.$eval('meta[property="og:image"]', (e) => e.content).catch(() => null);
        const refs = [];
        for (const u of [...srcs, og].filter(Boolean)) {
          if (!/download\.schneider-electric\.com\/files\?/.test(u)) continue;
          const r = ref(u);
          if (NO_FOTO.test(r) || refs.includes(r)) continue;
          refs.push(r);
        }
        fila.titulo = (await pag.title()).slice(0, 140);
        if (refs.length) {
          fila.pagina = pag.url(); fila.error = null;
          fila.imagenes = refs.map((r) => `https://download.schneider-electric.com/files?p_Doc_Ref=${r}&p_File_Type=rendition_1500_jpg`);
          break;
        }
        fila.error = 'sin fotos en ' + url;
      } catch (e) { fila.error = `${url}: ${e.message.slice(0, 100)}`; }
    }
    for (const u of fila.imagenes.slice(0, 4)) {
      try {
        const r = await ctx.request.get(u, { timeout: 30000 });
        if (!r.ok()) continue;
        const buf = await r.body();
        if (buf.length < 5000) continue;
        const nombre = `${modelo}-${fila.archivos.length + 1}.jpg`;
        fs.writeFileSync(path.join(DESTINO, nombre), buf);
        fila.archivos.push(nombre);
      } catch {}
    }
    console.log(modelo, fila.archivos.length, fila.error || '', fila.titulo || '');
    res.push(fila);
    await pausa(1500);
  }
  await nav.close();
  fs.writeFileSync(path.join(__dirname, 'fotos-schneider-resultado.json'), JSON.stringify(res, null, 1));
})();
