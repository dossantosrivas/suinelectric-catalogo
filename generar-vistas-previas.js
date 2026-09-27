/* =====================================================================
   VISTAS PREVIAS PARA WHATSAPP, FACEBOOK, INSTAGRAM, TELEGRAM…
   WhatsApp y las redes no ejecutan el JavaScript de la tienda ni leen lo
   que va después del "#". Por eso, al compartir un link, siempre salía la
   misma vista previa. Este script crea una página pequeña por producto y
   por categoría con su título, descripción e imagen (etiquetas Open Graph),
   que lleva al cliente a la tienda en el lugar correcto:

     /p/3rt1023-1an20                          → ficha del producto
     /c/variadores-y-arrancadores/arrancadores-suaves  → categoría

   Se corre solo cada día (después del scraper) desde GitHub Actions.
   Para correrlo a mano:  node generar-vistas-previas.js
   ===================================================================== */
const fs = require('fs');
const path = require('path');

const RAIZ = __dirname;
const DOMINIO = 'https://suinelectric.com';          // dirección principal de la tienda
const IMAGEN_GENERAL = DOMINIO + '/imagenes/og-suinelectric.jpg';
const DESCUENTO_GENERAL = 60;                          // % que ven los visitantes (igual que en Supabase)
const MOSTRAR_PRECIO = true;                           // false = no poner precio en la vista previa

/* ---------- Cargar la organización de categorías desde tienda.html ----------
   Así hay una sola fuente: si cambias las familias en tienda.html, las vistas
   previas cambian también. */
const html = fs.readFileSync(path.join(RAIZ, 'tienda.html'), 'utf8');
const ini = html.indexOf('ORGANIZACIÓN DE CATEGORÍAS');
const fin = html.indexOf('/* ---------- Dirección (URL) de cada pantalla');
if (ini < 0 || fin < 0) throw new Error('No encontré el bloque de categorías en tienda.html');
const codigo = html.slice(html.lastIndexOf('/*', ini), fin);
const T = new Function(codigo + '\nreturn { rutaDe, rutaNavDe, slugDe, compararHermanos, MAX_NIVELES, FAMILIAS };')();

/* ---------- Productos (manuales primero, como en la tienda) ---------- */
const leer = (f) => { try { return JSON.parse(fs.readFileSync(path.join(RAIZ, f), 'utf8')); } catch (e) { return { productos: [] }; } };
const manuales = (leer('productos_manuales.json').productos || []).filter(p => p.modelo && p.modelo !== 'EJEMPLO-BORRAR');
manuales.forEach(p => { p._manual = true; });
const setMan = new Set(manuales.map(p => p.modelo));
const productos = manuales.concat((leer('productos.json').productos || []).filter(p => p.modelo && !setMan.has(p.modelo)));

/* ---------- Utilidades ---------- */
const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const corto = (s, n) => { s = String(s || '').replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n - 1).trimEnd() + '…' : s; };
const dinero = (n) => '$' + Math.ceil(n).toLocaleString('en-US');
function precioVisitante(p){
  if (p.precio == null || isNaN(Number(p.precio))) return null;
  return p._manual ? Number(p.precio) : Number(p.precio) * (1 - DESCUENTO_GENERAL / 100);
}
function imagenAbsoluta(src){
  if (!src) return IMAGEN_GENERAL;
  if (/^https?:\/\//.test(src)) return src;
  return DOMINIO + '/' + String(src).replace(/^\/+/, '');
}
function pagina({ titulo, descripcion, imagen, urlCompartir, destino }){
  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(titulo)}</title>
<meta name="description" content="${esc(descripcion)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Suinelectric">
<meta property="og:locale" content="es_VE">
<meta property="og:title" content="${esc(titulo)}">
<meta property="og:description" content="${esc(descripcion)}">
<meta property="og:image" content="${esc(imagen)}">
<meta property="og:url" content="${esc(urlCompartir)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(titulo)}">
<meta name="twitter:description" content="${esc(descripcion)}">
<meta name="twitter:image" content="${esc(imagen)}">
<meta name="theme-color" content="#0e2a3b">
<meta http-equiv="refresh" content="0; url=${esc(destino)}">
<script>location.replace(${JSON.stringify(destino)});</script>
</head>
<body style="font-family:Arial,sans-serif;text-align:center;padding:40px">
<p>Abriendo <a href="${esc(destino)}">${esc(titulo)}</a>…</p>
</body>
</html>
`;
}
function escribir(rel, contenido){
  const f = path.join(RAIZ, rel);
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, contenido);
}

/* ---------- Limpiar lo generado antes ---------- */
for (const d of ['p', 'c']) fs.rmSync(path.join(RAIZ, d), { recursive: true, force: true });

/* ---------- Productos ---------- */
let nP = 0;
for (const p of productos){
  const slug = T.slugDe(p.modelo);
  const ruta = T.rutaNavDe(p);
  const precio = MOSTRAR_PRECIO ? precioVisitante(p) : null;
  const marca = p.marca ? String(p.marca).toUpperCase() : '';
  const titulo = p.modelo + (marca ? ' · ' + marca : '') + ' | Suinelectric';
  const partes = [];
  if (precio != null) partes.push(dinero(precio) + (p.disponible === false ? ' · Agotado' : ' · Disponible'));
  else partes.push(p.disponible === false ? 'Agotado · Consultar' : 'Disponible · Consultar precio');
  if (p.descripcion) partes.push(corto(p.descripcion, 150));
  partes.push(ruta.slice(1).join(' › ') || ruta.join(' › '));
  escribir('p/' + slug + '.html', pagina({
    titulo,
    descripcion: partes.filter(Boolean).join(' — '),
    imagen: imagenAbsoluta(p.imagen),
    urlCompartir: DOMINIO + '/p/' + slug,
    destino: '/tienda#/?p=' + encodeURIComponent(p.modelo),
  }));
  nP++;
}

/* ---------- Categorías (todos los niveles con link) ---------- */
const nodos = new Map(); // clave -> { ruta, total, imagen, hijos:Set }
for (const p of productos){
  const r = T.rutaNavDe(p);
  for (let i = 1; i <= r.length; i++){
    const sub = r.slice(0, i), k = sub.join('|||');
    if (!nodos.has(k)) nodos.set(k, { ruta: sub, total: 0, imagen: null, hijos: new Set() });
    const n = nodos.get(k);
    n.total++;
    if (!n.imagen && p.imagen) n.imagen = p.imagen;
    if (i < r.length) n.hijos.add(r[i]);
  }
}
// Imágenes de portada elegidas a mano para las familias (las mismas de Inicio)
const imgFam = {};
const mFam = html.match(/const IMAGENES_FAMILIA = \{([\s\S]*?)\};/);
if (mFam) for (const m of mFam[1].matchAll(/'([^']+)':\s*'([^']+)'/g)) imgFam[m[1]] = m[2];

let nC = 0;
for (const n of nodos.values()){
  const slugs = n.ruta.map(T.slugDe);
  const nombre = n.ruta[n.ruta.length - 1];
  const hijos = [...n.hijos].sort((a, b) => T.compararHermanos(n.ruta, a, b));
  const desc = n.total + (n.total === 1 ? ' producto' : ' productos') +
    (hijos.length ? ': ' + corto(hijos.join(', '), 140) : '') +
    (n.ruta.length > 1 ? ' — ' + n.ruta.slice(0, -1).join(' › ') : '') +
    '. Cotiza por WhatsApp con Suinelectric.';
  escribir('c/' + slugs.join('/') + '.html', pagina({
    titulo: nombre + ' | Suinelectric',
    descripcion: desc,
    imagen: imagenAbsoluta((n.ruta.length === 1 && imgFam[nombre]) || n.imagen),
    urlCompartir: DOMINIO + '/c/' + slugs.join('/'),
    destino: '/tienda#/c/' + slugs.join('/'),
  }));
  nC++;
}
console.log('Vistas previas creadas: ' + nP + ' productos y ' + nC + ' categorías.');
