/* =====================================================================
   PRODUCTOS DE DISTRIBUIDORES PARA LA TIENDA (distribuidores-tienda.json)
   ---------------------------------------------------------------------
   Las listas de existencias que tienes en Gestión → Listas de existencias
   (Automatroni, EMI, MOTASI, IMO, Sirius Control…) traen muchos modelos que
   no están en el catálogo de la tienda. Este script arma con ellos un archivo
   aparte que la tienda usa SOLO al buscar ("Bajo pedido · 2-5 días") y que
   alimenta las páginas /d/<modelo> (functions/d/[modelo].js).

   Reglas:
     · Solo modelos con existencia en la lista (cantidad > 0).
     · Se saltan los que ya están en la tienda (catalogo-tienda.json).
     · Listas con más de DIAS_LISTA días sin actualizar no se usan.
     · Precio estimado = costo × (1 + MARGEN). Costo = precio de la lista
       menos el descuento de esa lista. Si el precio tiene más de
       DIAS_PRECIO días o no hay precio → "Precio a consultar" (pe = null).
     · Si varias listas traen el mismo modelo, gana el precio más bajo.
     · No se publica el nombre del distribuidor, ni sus enlaces, ni la
       cantidad: las fotos de Automatroni pasan por /fd/<archivo>
       (functions/fd/[archivo].js) para no mostrar su dirección.

   Se corre cada día desde GitHub Actions (después de generar-catalogo-tienda.js).
   A mano:  node generar-distribuidores-tienda.js
            node generar-distribuidores-tienda.js --desde listas.json   (copia local de las listas)
   ===================================================================== */
const fs = require('fs');
const path = require('path');

const RAIZ = __dirname;
const SALIDA = path.join(RAIZ, 'distribuidores-tienda.json');
const MARGEN = 0.20;          // 20 % de utilidad sobre el costo
const DIAS_PRECIO = 45;       // precio más viejo que esto → "a consultar"
const DIAS_LISTA = 60;        // lista más vieja que esto → no se usa
const ENTREGA = '2-5 días';

const clave = (m) => String(m || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]/g, '');
// Igual que slugDe() de la tienda: /d/<slug>
const slugDe = (s) => String(s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'x';
const dias = (f) => { const t = Date.parse(String(f || '').slice(0, 10) + 'T12:00:00Z'); return isFinite(t) ? (Date.now() - t) / 864e5 : Infinity; };
const leer = (f) => { try { return JSON.parse(fs.readFileSync(path.join(RAIZ, f), 'utf8')); } catch (e) { return null; } };
const limpio = (s) => String(s || '').replace(/automatroni/gi, '').replace(/\s+/g, ' ').trim();
// Marcas que no son marca (o que delatan al distribuidor): se dejan vacías
const marcaValida = (s) => { const t = limpio(s).toUpperCase(); return /^[-.\s]*$|^(N\/?A|S\/?M|SIN MARCA|GENERICO|GENÉRICO)$/.test(t) ? '' : t; };

/* ---------- Listas: de Supabase o de una copia local ----------
   Forma común: [{ id, dist, fecha, marca, dto, filas: [[modelo, nombre, marca, cantidad, precio, fechaPrecio]] }] */
async function traerListas(){
  const i = process.argv.indexOf('--desde');
  if (i > 0) return JSON.parse(fs.readFileSync(process.argv[i + 1], 'utf8'));
  const url = (process.env.SUPABASE_URL || '').replace(/\/+$/, '');
  const key = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_KEY || '';
  if (!url || !key){ console.log('Sin SUPABASE_URL/SUPABASE_SECRET_KEY: no se actualiza distribuidores-tienda.json.'); return null; }
  const h = { apikey: key }; if (!key.startsWith('sb_')) h.Authorization = 'Bearer ' + key;
  const r = await fetch(url + '/rest/v1/adm_registros?select=id,data&coleccion=eq.listas&borrado=eq.false', { headers: h });
  if (!r.ok) throw new Error('adm_registros ' + r.status);
  return (await r.json()).map(({ id, data: l }) => {
    l = l || {}; const pr = l.precios || {};
    return { id, dist: l.dist, fecha: l.fecha, marca: l.marca || '', dto: l.dto,
      filas: (l.items || []).filter(it => Number(it.q) > 0).map(it => { const x = pr[clave(it.m)] || {}; return [it.m, it.n || '', it.mk || '', Number(it.q), x.p, x.f]; }) };
  });
}

(async () => {
  const listas = await traerListas();
  if (!listas) return;

  // Lo que ya está en la tienda no se repite
  const cat = leer('catalogo-tienda.json') || {};
  const enTienda = new Set([].concat(cat.productos || [], cat.manuales || []).map(p => clave(p.modelo)));

  // Fotos y página oficial de Automatroni (del scraper diario)
  const auto = new Map();
  for (const p of ((leer('distribuidores/automatroni.json') || {}).productos || [])){
    const k = clave(p.ref); if (!k) continue;
    const img = (String(p.img || '').match(/\/archivos_productos\/([A-Za-z0-9._-]+\.(?:jpe?g|png|webp|gif))$/i) || [])[1];
    const ficha = /^https?:\/\//i.test(p.ficha || '') && !/automatroni/i.test(p.ficha) ? String(p.ficha).replace(/^http:/i, 'https:') : null;
    auto.set(k, { img: img ? '/fd/' + img : null, ficha });
  }

  const porClave = new Map();
  let usadas = 0;
  for (const l of listas){
    const edad = dias(l.fecha);
    if (edad > DIAS_LISTA){ console.log(`  · ${l.id}: lista de ${l.fecha} (más de ${DIAS_LISTA} días), no se usa`); continue; }
    usadas++;
    const dto = Number(l.dto) > 0 ? Number(l.dto) : 0;
    for (const [m, n, mk, q, p, f] of l.filas || []){
      const k = clave(m); if (!k || !(Number(q) > 0) || enTienda.has(k)) continue;
      const fechaP = f || l.fecha;
      const pe = Number(p) > 0 && dias(fechaP) <= DIAS_PRECIO ? Math.round(Number(p) * (1 - dto / 100) * (1 + MARGEN) * 100) / 100 : null;
      const x = porClave.get(k) || { m: limpio(m), n: '', mk: '', pe: null };
      const nn = limpio(n); if (nn.length > x.n.length) x.n = nn;
      if (!x.mk) x.mk = marcaValida(mk) || marcaValida(l.marca);
      if (pe != null && (x.pe == null || pe < x.pe)) x.pe = pe;
      porClave.set(k, x);
    }
  }

  const slugs = new Set();
  const productos = [];
  for (const [k, x] of porClave){
    const s = slugDe(x.m); if (slugs.has(s)) continue; slugs.add(s);
    const o = { m: x.m, s };
    if (x.n && clave(x.n) !== k) o.n = x.n.slice(0, 220);
    if (x.mk) o.mk = x.mk;
    if (x.pe != null) o.pe = x.pe;
    const a = auto.get(k);
    if (a && a.img) o.img = a.img;
    if (a && a.ficha) o.ficha = a.ficha;
    productos.push(o);
  }
  productos.sort((a, b) => (a.mk || '~').localeCompare(b.mk || '~') || a.m.localeCompare(b.m));

  const salida = { generado: new Date().toISOString(), margen: MARGEN * 100, entrega: ENTREGA, total: productos.length, productos };
  const texto = JSON.stringify(salida);
  fs.writeFileSync(SALIDA, texto);
  // Sitemap aparte para Google (robots.txt lo anuncia)
  const hoy = salida.generado.slice(0, 10);
  fs.writeFileSync(path.join(RAIZ, 'sitemap-bajo-pedido.xml'), '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    productos.map(p => '<url><loc>https://suinelectric.com/d/' + p.s + '</loc><lastmod>' + hoy + '</lastmod></url>').join('\n') + '\n</urlset>\n');
  const conPrecio = productos.filter(p => p.pe != null).length;
  console.log(`distribuidores-tienda.json: ${productos.length} modelos de ${usadas} listas · ${conPrecio} con precio estimado · ` +
    `${productos.length - conPrecio} a consultar · ${(texto.length / 1048576).toFixed(2)} MB`);
  if (/automatroni|grupo-electricos/i.test(texto.replace(/"\/fd\/[^"]*"/g, ''))) console.log('⚠ Quedó una mención de un distribuidor en distribuidores-tienda.json');
})().catch((e) => { console.error(e); process.exit(1); });
