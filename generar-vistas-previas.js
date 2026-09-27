/* =====================================================================
   PÁGINAS PÚBLICAS (Google + vistas previas de WhatsApp y redes)
   ---------------------------------------------------------------------
   La tienda (tienda.html) es una sola página que arma todo con JavaScript,
   así que Google casi no la puede leer y WhatsApp siempre muestra la misma
   vista previa. Este script crea una página liviana y real por producto y
   por categoría, con su título, descripción, foto, precio y datos para
   Google (schema.org), y botones para cotizar o abrir la tienda:

     /p/3rt1023-1an20                                  → producto
     /c/variadores-y-arrancadores/arrancadores-suaves  → categoría

   También crea sitemap.xml (la lista de páginas que se le entrega a Google).

   Se corre solo cada día (después del scraper) desde GitHub Actions.
   Para correrlo a mano:  node generar-vistas-previas.js
   ===================================================================== */
const fs = require('fs');
const path = require('path');

const RAIZ = __dirname;
const DOMINIO = 'https://suinelectric.com';          // dirección principal de la tienda
const IMAGEN_GENERAL = DOMINIO + '/imagenes/og-suinelectric.jpg';
const DESCUENTO_GENERAL = 60;                          // % que ven los visitantes (igual que en Supabase)
const MOSTRAR_PRECIO = true;                           // false = no poner precio en las páginas
const MAX_EN_CATEGORIA = 120;                          // más de esto: se muestran subcategorías + una muestra

/* ---------- Cargar la organización de categorías desde tienda.html ----------
   Así hay una sola fuente: si cambias las familias en tienda.html, las páginas
   cambian también. */
const html = fs.readFileSync(path.join(RAIZ, 'tienda.html'), 'utf8');
const ini = html.indexOf('ORGANIZACIÓN DE CATEGORÍAS');
const fin = html.indexOf('/* ---------- Dirección (URL) de cada pantalla');
if (ini < 0 || fin < 0) throw new Error('No encontré el bloque de categorías en tienda.html');
const codigo = html.slice(html.lastIndexOf('/*', ini), fin);
const T = new Function(codigo + '\nreturn { rutaDe, rutaNavDe, slugDe, compararHermanos, MAX_NIVELES, FAMILIAS };')();

// Datos de contacto y condiciones: se leen de tienda.html para no repetirlos.
const WA = (html.match(/const WHATSAPP_PRIORITARIO = "(\d+)"/) || [])[1] || '584124111319';
const WA_TXT = '0' + WA.slice(2, 5) + '-' + WA.slice(5, 8) + ' ' + WA.slice(8);
let CONDICIONES = ['6 meses de garantía contra defecto de fábrica.', 'T. Entrega 1-2 días hábiles después del pago.'];
try { const m = html.match(/const CONDICIONES_VENTA = (\[[\s\S]*?\]);/); if (m) CONDICIONES = new Function('return ' + m[1])(); } catch (e) {}

/* ---------- Productos (manuales primero, como en la tienda) ---------- */
const leer = (f) => { try { return JSON.parse(fs.readFileSync(path.join(RAIZ, f), 'utf8')); } catch (e) { return null; } };
// Se usa catalogo-tienda.json (fotos propias, sin datos del proveedor). Si no existe, los originales.
const catalogo = leer('catalogo-tienda.json');
const fuenteManuales = catalogo ? { productos: catalogo.manuales } : (leer('productos_manuales.json') || { productos: [] });
const fuenteScraper = catalogo || leer('productos.json') || { productos: [] };
const manuales = (fuenteManuales.productos || []).filter(p => p.modelo && p.modelo !== 'EJEMPLO-BORRAR');
manuales.forEach(p => { p._manual = true; });
const setMan = new Set(manuales.map(p => p.modelo));
const productos = manuales.concat((fuenteScraper.productos || []).filter(p => p.modelo && !setMan.has(p.modelo)));
const FECHA = (fuenteScraper.generado || new Date().toISOString()).slice(0, 10);

/* ---------- Utilidades ---------- */
const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const corto = (s, n) => { s = String(s || '').replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n - 1).trimEnd() + '…' : s; };
const dinero = (n) => '$' + Math.ceil(n).toLocaleString('en-US');
function precioVisitante(p){
  if (!MOSTRAR_PRECIO || p.precio == null || isNaN(Number(p.precio))) return null;
  return Math.ceil(p._manual ? Number(p.precio) : Number(p.precio) * (1 - DESCUENTO_GENERAL / 100));
}
function imagenAbsoluta(src){
  if (!src) return IMAGEN_GENERAL;
  if (/^https?:\/\//.test(src)) return src;
  return DOMINIO + '/' + String(src).replace(/^\/+/, '');
}
const imagenLocal = (src) => !src ? '' : /^https?:\/\//.test(src) ? src : '/' + String(src).replace(/^\/+/, '');
function textoStock(p){
  if (p.disponible === false) return 'Agotado';
  let r = p.stock;
  if (!r && p.existencias != null && Number(p.existencias) > 0) r = Number(p.existencias) > 10 ? '+10' : 'pocas';
  return r === '+10' ? '+10 disponibles' : r === 'pocas' ? 'Últimas unidades' : 'Disponible';
}
const urlP = (p) => '/p/' + T.slugDe(p.modelo);
const urlC = (ruta) => '/c/' + ruta.map(T.slugDe).join('/');
const waLink = (texto) => 'https://wa.me/' + WA + '?text=' + encodeURIComponent(texto);
const jsonLD = (o) => '<script type="application/ld+json">' + JSON.stringify(o).replace(/</g, '\\u003c') + '</script>';
const ORG = { '@type': 'Organization', name: 'Suinelectric', url: DOMINIO + '/tienda', logo: IMAGEN_GENERAL };

function escribir(rel, contenido){
  const f = path.join(RAIZ, rel);
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, contenido);
}

/* ---------- Plantilla común ---------- */
function pagina({ titulo, descripcion, imagen, canonica, cuerpo, datos, tipoOg }){
  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(titulo)}</title>
<meta name="description" content="${esc(descripcion)}">
<link rel="canonical" href="${esc(canonica)}">
<meta property="og:type" content="${tipoOg || 'website'}">
<meta property="og:site_name" content="Suinelectric">
<meta property="og:locale" content="es_VE">
<meta property="og:title" content="${esc(titulo)}">
<meta property="og:description" content="${esc(descripcion)}">
<meta property="og:image" content="${esc(imagen)}">
<meta property="og:url" content="${esc(canonica)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(titulo)}">
<meta name="twitter:description" content="${esc(descripcion)}">
<meta name="twitter:image" content="${esc(imagen)}">
<meta name="theme-color" content="#0e2a3b">
<link rel="stylesheet" href="/publico.css">
${(datos || []).map(jsonLD).join('\n')}
</head>
<body>
<header class="barra"><div class="ancho">
  <a class="logo" href="/tienda"><span class="logo-s">S</span>SUINELECTRIC</a>
  <nav><a href="/tienda">Tienda</a><a class="wa" href="https://wa.me/${WA}" rel="noopener">WhatsApp ${esc(WA_TXT)}</a></nav>
</div></header>
<main class="ancho">
${cuerpo}
</main>
<footer class="pie"><div class="ancho">
  <strong>Suinelectric</strong> · Automatización y control eléctrico en Venezuela ·
  <a href="https://wa.me/${WA}" rel="noopener">WhatsApp ${esc(WA_TXT)}</a> · <a href="/tienda">Ver toda la tienda</a>
</div></footer>
</body>
</html>
`;
}
function migas(ruta, final){
  const items = [['Tienda', '/tienda']].concat(ruta.map((n, i) => [n, urlC(ruta.slice(0, i + 1))]));
  const html = '<nav class="migas" aria-label="Ruta">' + items.map(([n, u]) => '<a href="' + esc(u) + '">' + esc(n) + '</a>').join('<span>›</span>') +
    (final ? '<span>›</span><b>' + esc(final) + '</b>' : '') + '</nav>';
  const ld = { '@context': 'https://schema.org', '@type': 'BreadcrumbList', itemListElement: items.map(([n, u], i) => ({ '@type': 'ListItem', position: i + 1, name: n, item: DOMINIO + u })) };
  return { html, ld };
}
function tarjeta(p){
  const precio = precioVisitante(p);
  return '<a class="tarjeta" href="' + urlP(p) + '">' +
    '<span class="t-img">' + (p.imagen ? '<img src="' + esc(imagenLocal(p.imagen)) + '" alt="' + esc(p.modelo) + '" loading="lazy">' : '<span class="sin">⚡</span>') + '</span>' +
    '<span class="t-marca">' + esc(p.marca || '') + '</span>' +
    '<strong>' + esc(p.modelo) + '</strong>' +
    '<span class="t-desc">' + esc(corto(p.descripcion || p.nombre, 90)) + '</span>' +
    '<span class="t-pie"><b>' + (precio != null ? dinero(precio) : 'Consultar') + '</b><em class="' + (p.disponible === false ? 'off' : 'ok') + '">' + esc(textoStock(p)) + '</em></span></a>';
}

/* ---------- Limpiar lo generado antes ---------- */
for (const d of ['p', 'c']) fs.rmSync(path.join(RAIZ, d), { recursive: true, force: true });

/* ---------- Árbol de categorías ---------- */
const nodos = new Map(); // clave -> { ruta, total, imagen, hijos:Set, productos:[] }
for (const p of productos){
  const r = T.rutaNavDe(p);
  for (let i = 1; i <= r.length; i++){
    const sub = r.slice(0, i), k = sub.join('|||');
    if (!nodos.has(k)) nodos.set(k, { ruta: sub, total: 0, imagen: null, hijos: new Set(), productos: [] });
    const n = nodos.get(k);
    n.total++; n.productos.push(p);
    if (!n.imagen && p.imagen) n.imagen = p.imagen;
    if (i < r.length) n.hijos.add(r[i]);
  }
}
const urls = [];

/* ---------- Productos ---------- */
let nP = 0;
for (const p of productos){
  const slug = T.slugDe(p.modelo);
  const ruta = T.rutaNavDe(p);
  const precio = precioVisitante(p);
  const marca = p.marca ? String(p.marca).toUpperCase() : '';
  const canonica = DOMINIO + '/p/' + slug;
  const titulo = p.modelo + (marca ? ' ' + marca : '') + (p.descripcion ? ' · ' + corto(p.descripcion, 50) : '') + ' | Suinelectric';
  const partes = [];
  partes.push((precio != null ? dinero(precio) + ' · ' : '') + textoStock(p) + ' en Suinelectric Venezuela');
  if (p.descripcion) partes.push(corto(p.descripcion, 140));
  const descripcion = partes.join('. ') + '. Cotiza por WhatsApp.';
  const m = migas(ruta, p.modelo);
  const hermanos = (nodos.get(ruta.join('|||')) || { productos: [] }).productos.filter(x => x !== p).slice(0, 8);
  const textoWa = 'Hola, quiero cotizar: ' + p.modelo + (marca ? ' (' + marca + ')' : '') + '\n' + canonica;
  const imgs = [...new Set([p.imagen].concat(p.imagenes || []).filter(Boolean))];

  const producto = {
    '@context': 'https://schema.org', '@type': 'Product',
    name: p.modelo + (p.descripcion ? ' - ' + corto(p.descripcion, 100) : ''),
    sku: p.sku || p.modelo, mpn: p.modelo,
    description: corto(p.descripcion || p.nombre || p.modelo, 500),
    image: imgs.length ? imgs.map(imagenAbsoluta) : [IMAGEN_GENERAL],
    category: ruta.join(' > '),
    url: canonica,
  };
  if (marca) producto.brand = { '@type': 'Brand', name: marca };
  if (precio != null) producto.offers = {
    '@type': 'Offer', url: canonica, priceCurrency: 'USD', price: String(precio),
    availability: p.disponible === false ? 'https://schema.org/OutOfStock' : 'https://schema.org/InStock',
    itemCondition: 'https://schema.org/NewCondition', seller: ORG,
  };

  const cuerpo = m.html +
    '<article class="producto">' +
      '<div class="p-galeria">' + (p.imagen ? '<img src="' + esc(imagenLocal(p.imagen)) + '" alt="' + esc(p.modelo + ' ' + marca) + '" width="600" height="600">' : '<div class="sin grande">⚡</div>') + '</div>' +
      '<div class="p-info">' +
        (marca ? '<div class="p-marca">' + esc(marca) + '</div>' : '') +
        '<h1>' + esc(p.modelo) + '</h1>' +
        (p.descripcion ? '<p class="p-desc">' + esc(p.descripcion) + '</p>' : '') +
        '<div class="p-precio">' + (precio != null ? dinero(precio) + ' <small>USD</small>' : 'Consultar precio') + '</div>' +
        '<div class="p-stock ' + (p.disponible === false ? 'off' : 'ok') + '">' + esc(textoStock(p)) + '</div>' +
        '<div class="p-botones">' +
          '<a class="btn wa" href="' + esc(waLink(textoWa)) + '" rel="noopener">Cotizar por WhatsApp</a>' +
          '<a class="btn" href="/tienda#/?p=' + encodeURIComponent(p.modelo) + '">Agregar al pedido en la tienda</a>' +
        '</div>' +
        '<ul class="p-cond">' + CONDICIONES.map(c => '<li>' + esc(c) + '</li>').join('') + '<li>Con nota de entrega.</li></ul>' +
        '<dl class="p-datos">' +
          '<dt>Modelo</dt><dd>' + esc(p.modelo) + '</dd>' +
          (marca ? '<dt>Marca</dt><dd>' + esc(marca) + '</dd>' : '') +
          (p.sku && p.sku !== p.modelo ? '<dt>Código</dt><dd>' + esc(p.sku) + '</dd>' : '') +
          '<dt>Categoría</dt><dd>' + ruta.map((n, i) => '<a href="' + urlC(ruta.slice(0, i + 1)) + '">' + esc(n) + '</a>').join(' › ') + '</dd>' +
        '</dl>' +
      '</div>' +
    '</article>' +
    (hermanos.length ? '<section><h2>También en ' + esc(ruta[ruta.length - 1] || 'esta categoría') + '</h2><div class="rejilla">' + hermanos.map(tarjeta).join('') + '</div></section>' : '');

  escribir('p/' + slug + '.html', pagina({ titulo, descripcion, imagen: imagenAbsoluta(p.imagen), canonica, cuerpo, datos: [producto, m.ld], tipoOg: 'product' }));
  urls.push('/p/' + slug);
  nP++;
}

/* ---------- Categorías (todos los niveles con link) ---------- */
// Imágenes de portada elegidas a mano para las familias (las mismas de Inicio)
const imgFam = {};
const mFam = html.match(/const IMAGENES_FAMILIA = \{([\s\S]*?)\};/);
if (mFam) for (const mm of mFam[1].matchAll(/'([^']+)':\s*'([^']+)'/g)) imgFam[mm[1]] = mm[2];

let nC = 0;
for (const n of nodos.values()){
  const nombre = n.ruta[n.ruta.length - 1];
  const canonica = DOMINIO + urlC(n.ruta);
  const hijos = [...n.hijos].sort((a, b) => T.compararHermanos(n.ruta, a, b));
  const marcas = [...new Set(n.productos.map(p => String(p.marca || '').toUpperCase()).filter(Boolean))].slice(0, 6);
  const titulo = nombre + (n.ruta.length > 1 ? ' · ' + n.ruta[0] : '') + (marcas.length ? ' ' + marcas.slice(0, 2).join(', ') : '') + ' | Suinelectric Venezuela';
  const descripcion = n.total + (n.total === 1 ? ' producto' : ' productos') + ' de ' + nombre +
    (marcas.length ? ' (' + marcas.join(', ') + ')' : '') +
    (hijos.length ? ': ' + corto(hijos.join(', '), 120) : '') + '. Precios en USD y cotización por WhatsApp.';
  const m = migas(n.ruta.slice(0, -1), nombre);
  const muestra = n.total > MAX_EN_CATEGORIA ? n.productos.filter(p => p.imagen).slice(0, 24) : n.productos;
  const lista = {
    '@context': 'https://schema.org', '@type': 'CollectionPage', name: nombre, url: canonica,
    mainEntity: { '@type': 'ItemList', numberOfItems: n.total,
      itemListElement: muestra.slice(0, 60).map((p, i) => ({ '@type': 'ListItem', position: i + 1, url: DOMINIO + urlP(p), name: p.modelo })) },
  };
  const cuerpo = m.html +
    '<div class="c-cab"><h1>' + esc(nombre) + '</h1><p>' + n.total.toLocaleString('es-VE') + (n.total === 1 ? ' producto' : ' productos') +
      (marcas.length ? ' · ' + esc(marcas.join(', ')) : '') + '</p>' +
      '<a class="btn" href="/tienda#' + urlC(n.ruta) + '">Ver en la tienda con filtros</a></div>' +
    (hijos.length ? '<section><h2>Categorías</h2><div class="subcats">' + hijos.map(h => {
        const hn = nodos.get(n.ruta.concat(h).join('|||'));
        return '<a href="' + urlC(n.ruta.concat(h)) + '">' + esc(h) + ' <b>' + (hn ? hn.total : '') + '</b></a>';
      }).join('') + '</div></section>' : '') +
    '<section><h2>' + (muestra.length < n.total ? 'Algunos productos' : 'Productos') + '</h2><div class="rejilla">' + muestra.map(tarjeta).join('') + '</div>' +
      (muestra.length < n.total ? '<p class="mas"><a class="btn" href="/tienda#' + urlC(n.ruta) + '">Ver los ' + n.total.toLocaleString('es-VE') + ' productos en la tienda</a></p>' : '') + '</section>';

  escribir('c/' + n.ruta.map(T.slugDe).join('/') + '.html', pagina({
    titulo, descripcion, canonica, cuerpo, datos: [lista, m.ld],
    imagen: imagenAbsoluta((n.ruta.length === 1 && imgFam[nombre]) || n.imagen),
  }));
  urls.push(urlC(n.ruta));
  nC++;
}

/* ---------- sitemap.xml ---------- */
const lista = ['/tienda'].concat(fs.existsSync(path.join(RAIZ, 'links.html')) ? ['/links'] : [], urls.filter(u => u.startsWith('/c/')), urls.filter(u => u.startsWith('/p/')));
const xml = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
  [...new Set(lista)].map(u => '  <url><loc>' + esc(DOMINIO + u) + '</loc><lastmod>' + FECHA + '</lastmod></url>').join('\n') + '\n</urlset>\n';
fs.writeFileSync(path.join(RAIZ, 'sitemap.xml'), xml);

console.log('Páginas creadas: ' + nP + ' productos y ' + nC + ' categorías · sitemap.xml con ' + new Set(lista).size + ' direcciones.');
