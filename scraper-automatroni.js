/**
 * scraper-automatroni.js — Lista de precios y existencias de automatroni.com
 * ---------------------------------------------------------------------------
 * Recorre el catálogo público (sin iniciar sesión) igual que la propia página:
 * POST https://automatroni.com/ajax/catalogo.php  page=1..N  (12 productos por página).
 * Va con calma: una página cada ~1,5 s, así no molesta al sitio.
 *
 * De cada producto guarda:
 *   ref, nombre, marca, precio (USD sin IVA), existencias por almacén
 *   (Maracay, reservado, Caracas, por llegar) y disponible (lo que su web deja comprar),
 *   promo ("-15% a partir de 100pz"), ficha técnica, foto y enlace.
 *
 * Genera distribuidores/automatroni.json. Si algo sale raro (muchas menos
 * páginas o productos que la vez anterior) NO pisa el archivo y termina con error.
 *
 * Uso:
 *   node scraper-automatroni.js               catálogo completo
 *   node scraper-automatroni.js --paginas 3   prueba con 3 páginas (no guarda encima)
 */
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const cheerio = require('cheerio');

const BASE = 'https://automatroni.com/';
const SALIDA = path.join(__dirname, 'distribuidores', 'automatroni.json');
const PAUSA_MS = 1500;
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

const args = process.argv.slice(2);
const LIMITE = args.includes('--paginas') ? parseInt(args[args.indexOf('--paginas') + 1], 10) : null;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const txt = (s) => String(s || '').replace(/\s+/g, ' ').trim();
const entero = (s) => { const n = parseInt(String(s || '').replace(/[^\d-]/g, ''), 10); return isNaN(n) ? 0 : n; };
// "$USD 10.182,06" → 10182.06
const precioVE = (s) => { const m = String(s || '').match(/[\d.]+,\d+|[\d.]+/); if (!m) return null; const n = parseFloat(m[0].replace(/\./g, '').replace(',', '.')); return isNaN(n) ? null : n; };

let cookie = '';
const http = axios.create({ timeout: 30000, headers: { 'User-Agent': UA, 'Accept-Language': 'es-VE,es;q=0.9' }, validateStatus: () => true });

async function conReintentos(fn, que) {
  for (let i = 0; i < 4; i++) {
    try { const r = await fn(); if (r) return r; } catch (e) { console.log(`  ${que}: ${e.message}`); }
    await sleep(PAUSA_MS * (i + 2) * 2);
  }
  throw new Error(`No se pudo leer ${que} después de 4 intentos`);
}

async function inicio() {
  const r = await http.get(BASE + 'productos');
  if (process.env.DEPURAR) console.log('  [depurar] inicio', r.status, String(r.data).length, String(r.data).slice(0, 300), JSON.stringify(r.headers).slice(0, 200));
  if (r.status !== 200) return null;
  cookie = (r.headers['set-cookie'] || []).map((c) => c.split(';')[0]).join('; ');
  const $ = cheerio.load(r.data);
  const total = entero($('a.filtros[data-cantidad]').first().attr('data-cantidad'));
  return total > 0 ? { total } : null;
}

async function pagina(n) {
  const form = new URLSearchParams({ page: String(n), departamento: '0', categoria: '', descripcion: '', referencia: '', orden: '', id_almacen: '', m_schn: '' });
  const r = await http.post(BASE + 'ajax/catalogo.php', form.toString(), {
    headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'X-Requested-With': 'XMLHttpRequest', Referer: BASE + 'productos', Cookie: cookie },
  });
  if (process.env.DEPURAR) console.log('  [depurar] página', n, r.status, String(r.data).length, String(r.data).slice(0, 1500).replace(/\s+/g, ' '));
  if (r.status !== 200) return null;
  const $ = cheerio.load(String(r.data));
  const out = [];
  $('.list_products--card').each((_, el) => {
    const c = $(el);
    const enlace = c.find('a[href^="producto/"]').first().attr('href') || '';
    const id = (enlace.match(/producto\/(\d+)/) || [])[1] || c.find('[data-producto]').first().attr('data-producto') || '';
    const refLi = c.find('li.inforef').first();
    const ref = txt(refLi.text()).replace(/^REF\.?\s*/i, '').replace(/\s*\|.*$/, '').trim();
    const stock = txt(c.find('li.lower').first().text());
    const alm = (et) => { const m = stock.match(new RegExp(et + '\\s*:\\s*(\\d+)', 'i')); return m ? +m[1] : 0; };
    const btn = c.find('button.AddToCart').first();
    const lis = c.find('li.lower').toArray().map((x) => $(x)).filter((x) => !x.hasClass('inforef') && !x.hasClass('mx-1'));
    const precio = parseFloat(btn.attr('data-precio')) || precioVE(c.find('.price').first().text());
    out.push({
      id,
      ref,
      nombre: txt(c.find('.title').first().attr('data-bs-title') || c.find('.title').first().text()),
      marca: lis.length ? txt(lis[0].text()).toUpperCase() : '',
      precio: precio > 0 ? Math.round(precio * 100) / 100 : null,
      maracay: alm('Mcy'), reservado: alm('Reser'), caracas: alm('Ccs'), por_llegar: alm('Por llegar'),
      disponible: btn.length ? entero(btn.attr('data-disponible')) : Math.max(0, alm('Mcy') + alm('Ccs') - alm('Reser')),
      promo: txt(c.find('.badge').first().text()) || undefined,
      ficha: refLi.find('a').attr('href') || undefined,
      img: (() => { const s = c.find('img').first().attr('src'); return s ? (/^https?:/.test(s) ? s : BASE + s) : undefined; })(),
      url: enlace ? BASE + enlace : undefined,
    });
  });
  return out.length ? out : null;
}

(async () => {
  const t0 = Date.now();
  const { total } = await conReintentos(inicio, 'la página de productos');
  const hasta = LIMITE ? Math.min(LIMITE, total) : total;
  console.log(`Automatroni: ${total} páginas en su catálogo; leyendo ${hasta}.`);

  let anterior = null; try { anterior = JSON.parse(fs.readFileSync(SALIDA, 'utf8')); } catch (e) { /* primera vez */ }

  const productos = [], vistos = new Set(); let vacias = 0;
  for (let n = 1; n <= hasta; n++) {
    let xs;
    try { xs = await conReintentos(() => pagina(n), `la página ${n}`); }
    catch (e) { vacias++; console.log('  ✗ ' + e.message); if (vacias > 5) throw new Error('Demasiadas páginas fallidas: se detiene para no guardar una lista incompleta'); continue; }
    xs.forEach((p) => { const k = p.id || p.ref; if (k && !vistos.has(k)) { vistos.add(k); productos.push(p); } });
    if (n % 50 === 0) console.log(`  página ${n}/${hasta} · ${productos.length} productos`);
    await sleep(PAUSA_MS);
  }

  const conRef = productos.filter((p) => p.ref).length;
  console.log(`Leídos ${productos.length} productos (${conRef} con REF, ${productos.filter((p) => p.disponible > 0).length} disponibles) en ${Math.round((Date.now() - t0) / 60000)} min.`);

  if (LIMITE) { console.log(JSON.stringify(productos.slice(0, 3), null, 2)); console.log('(prueba: no se guarda)'); return; }

  // ---- verificación: no publicar algo raro ----
  if (productos.length < total * 12 * 0.8) throw new Error(`Muy pocos productos (${productos.length}) para ${total} páginas: no se guarda.`);
  if (anterior && anterior.total && productos.length < anterior.total * 0.7) throw new Error(`Bajó de ${anterior.total} a ${productos.length} productos (más de 30 %): no se guarda.`);
  if (conRef < productos.length * 0.9) throw new Error(`Solo ${conRef} de ${productos.length} traen REF: puede que cambiaron la página.`);

  productos.sort((a, b) => (parseInt(a.id, 10) || 0) - (parseInt(b.id, 10) || 0));
  fs.mkdirSync(path.dirname(SALIDA), { recursive: true });
  fs.writeFileSync(SALIDA, JSON.stringify({ fuente: 'automatroni.com', generado: new Date().toISOString(), paginas: total, total: productos.length, productos }, null, 0));
  console.log('Guardado ' + path.relative(__dirname, SALIDA));
})().catch((e) => { console.log('✗ ' + e.message); process.exit(1); });
