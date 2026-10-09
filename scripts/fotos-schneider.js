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
const PAGINAS = (m) => [
  `https://www.se.com/ww/en/product/${m}/`,
  `https://www.se.com/mx/es/product/${m}/`,
];
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
      const vistas = new Set();
      const oir = (r) => { const u = r.url(); if (esFoto(u)) vistas.add(u); };
      pag.on('response', oir);
      try {
        const r = await pag.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
        await pausa(4000);
        await pag.mouse.wheel(0, 600).catch(() => {});
        await pausa(1500);
        const html = await pag.content();
        for (const m of html.matchAll(/https?:\/\/download\.schneider-electric\.com\/files\?[^"'\s<>)]+/g)) {
          const u = m[0].replace(/&amp;/g, '&').replace(/\\u0026/g, '&');
          if (esFoto(u)) vistas.add(u);
        }
        fila.titulo = (await pag.title()).slice(0, 120);
        if (vistas.size) { fila.pagina = url; fila.error = null; }
        else fila.error = `HTTP ${r && r.status()} sin fotos en ${url}`;
      } catch (e) { fila.error = `${url}: ${e.message.slice(0, 100)}`; }
      pag.off('response', oir);
      if (vistas.size) { // ordena manteniendo el orden de aparición, sin repetir documento
        const porRef = new Map();
        for (const u of vistas) if (!porRef.has(ref(u))) porRef.set(ref(u), grande(u));
        fila.imagenes = [...porRef.values()];
        break;
      }
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
