// Busca la foto oficial de cada modelo Schneider en se.com y la descarga en
// imagenes/schneider/oficial/<MODELO>.jpg. Deja un registro en
// scripts/fotos-schneider-resultado.json. Lo corre el workflow fotos-schneider.yml.
const fs = require('fs');
const path = require('path');

const LISTA = require('./fotos-schneider-lista.json');
const DESTINO = path.join(__dirname, '..', 'imagenes', 'schneider', 'oficial');
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36';
const PAGINAS = (m) => [
  `https://www.se.com/ww/en/product/${m}/`,
  `https://www.se.com/us/en/product/${m}/`,
  `https://www.se.com/mx/es/product/${m}/`,
];

const pausa = (ms) => new Promise((r) => setTimeout(r, ms));

async function traer(url, binario) {
  const r = await fetch(url, { headers: { 'User-Agent': UA, 'Accept-Language': 'es,en;q=0.8' }, redirect: 'follow' });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return binario ? Buffer.from(await r.arrayBuffer()) : await r.text();
}

function urlsDeImagen(html) {
  const set = new Set();
  const re = /https?:\/\/download\.schneider-electric\.com\/files\?[^"'\s<>)]+/g;
  for (const m of html.matchAll(re)) set.add(m[0].replace(/&amp;/g, '&').replace(/\\u0026/g, '&'));
  const og = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)/i);
  if (og) set.add(og[1].replace(/&amp;/g, '&'));
  // Solo imágenes (no PDFs ni CAD)
  return [...set].filter((u) => /p_File_Type=rendition|\.jpe?g|\.png|\.webp/i.test(u) && !/pdf|dwg|stp/i.test(u));
}

// Pide la versión más grande que ofrezca el servidor de Schneider.
function grande(u) {
  if (/p_File_Type=rendition_\d+_(jpg|png)/.test(u)) return u.replace(/rendition_\d+_(jpg|png)/, 'rendition_1500_jpg');
  return u;
}

(async () => {
  fs.mkdirSync(DESTINO, { recursive: true });
  const res = [];
  for (const { familia, modelo } of LISTA) {
    const fila = { familia, modelo, pagina: null, imagenes: [], archivo: null, error: null };
    for (const pag of PAGINAS(modelo)) {
      try {
        const html = await traer(pag);
        const urls = urlsDeImagen(html);
        if (urls.length) { fila.pagina = pag; fila.imagenes = urls; break; }
        fila.error = 'sin imágenes en ' + pag;
      } catch (e) { fila.error = `${pag}: ${e.message}`; }
      await pausa(800);
    }
    // Descarga la primera imagen de producto (la principal) y hasta 2 vistas extra.
    const doc = [...new Set(fila.imagenes.map(grande))];
    let n = 0;
    for (const u of doc) {
      if (n >= 3) break;
      try {
        const buf = await traer(u, true);
        if (buf.length < 4000) continue; // íconos
        const nombre = `${modelo}${n ? '-' + (n + 1) : ''}.jpg`;
        fs.writeFileSync(path.join(DESTINO, nombre), buf);
        if (!n) fila.archivo = nombre; else (fila.extra ||= []).push(nombre);
        n++;
      } catch (e) {
        try { // si no hay versión 1500, intenta la original
          const buf = await traer(u.replace('rendition_1500_jpg', 'rendition_1500_png'), true);
          if (buf.length >= 4000) { const nombre = `${modelo}${n ? '-' + (n + 1) : ''}.png`; fs.writeFileSync(path.join(DESTINO, nombre), buf); if (!n) fila.archivo = nombre; n++; }
        } catch {}
      }
    }
    if (n) fila.error = null;
    console.log(modelo, fila.archivo || 'SIN FOTO', fila.error || '');
    res.push(fila);
    await pausa(600);
  }
  fs.writeFileSync(path.join(__dirname, 'fotos-schneider-resultado.json'), JSON.stringify(res, null, 1));
})();
