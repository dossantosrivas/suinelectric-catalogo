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
// Súbelo cada vez que cambies publico.css o publico.js: el navegador los guarda un día
// (ver _headers) y sin esto las páginas nuevas se ven con el estilo viejo.
const VERSION_ESTILOS = 6;

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
// Datos para que publico.js recalcule el precio si el cliente tiene la sesión abierta
// (mismas reglas de descuento que la tienda: por cliente, tipo, marca o modelo).
function datosPrecio(p){
  const lista = (p.precio != null && !isNaN(Number(p.precio))) ? Number(p.precio) : '';
  // familia y categoría de la tienda: para los descuentos de clientes por categoría (publico.js)
  let cat = ''; try { cat = T.rutaDe(p).slice(0, 2).join('|'); } catch (e) {}
  return ' data-lista="' + esc(lista) + '" data-marca="' + esc(p.marca || '') + '" data-modelo="' + esc(p.modelo) + '"' + (cat ? ' data-cat="' + esc(cat) + '"' : '') + (p._manual ? ' data-manual="1"' : '');
}
/* ---------- Imagen para la vista previa (WhatsApp, Facebook, Telegram…) ----------
   WhatsApp no muestra (o muestra diminuta) una foto de menos de 300 px, y la
   carga mejor si la página dice el tamaño. Las fotos chicas se copian centradas
   sobre un fondo blanco de 600×600 en imagenes/og/ (al final del script). */
const OG_MIN = 300, OG_LADO = 600;
const ogPendientes = new Map();   // origen local → destino local
function medidasImagen(rel){
  // Lee ancho y alto de un JPG o PNG sin dependencias (rápido y sincrónico).
  try {
    const b = fs.readFileSync(path.join(RAIZ, rel));
    if (b[0] === 0x89 && b[1] === 0x50) return { w: b.readUInt32BE(16), h: b.readUInt32BE(20), tipo: 'image/png' };
    if (b[0] === 0xFF && b[1] === 0xD8){
      let i = 2;
      while (i < b.length - 9){
        if (b[i] !== 0xFF){ i++; continue; }
        const mk = b[i + 1];
        if (mk >= 0xC0 && mk <= 0xCF && ![0xC4, 0xC8, 0xCC].includes(mk))
          return { h: b.readUInt16BE(i + 5), w: b.readUInt16BE(i + 7), tipo: 'image/jpeg' };
        i += 2 + b.readUInt16BE(i + 2);
      }
    }
  } catch (e) {}
  return null;
}
const MEDIDAS_GENERAL = medidasImagen('imagenes/og-suinelectric.jpg');
function imagenOg(src, alt){
  // Devuelve { url, w, h, tipo, alt } lista para las etiquetas og:image.
  if (src && !/^https?:\/\//.test(src)){
    const rel = String(src).replace(/^\/+/, '');
    const m = medidasImagen(rel);
    if (m && Math.min(m.w, m.h) >= OG_MIN) return { url: DOMINIO + '/' + rel, ...m, alt };
    if (m){
      const destino = 'imagenes/og/' + path.basename(rel).replace(/\.[a-z]+$/i, '') + '.jpg';
      ogPendientes.set(rel, destino);
      return { url: DOMINIO + '/' + destino, w: OG_LADO, h: OG_LADO, tipo: 'image/jpeg', alt };
    }
  }
  if (src) return { url: imagenAbsoluta(src), alt };
  return { url: IMAGEN_GENERAL, ...(MEDIDAS_GENERAL || {}), alt: 'Suinelectric' };
}
// Quita frases repetidas ("Variador serie GD20. Serie GD20. 0.4 kW" → "Variador serie GD20. 0.4 kW").
function sinRepetidos(t){
  const vistos = new Set(), out = [];
  for (const f of String(t || '').replace(/\s+/g, ' ').trim().split(/(?<=\.)\s+/)){
    const k = f.toLowerCase().replace(/[^a-z0-9áéíóúñ]/g, '');
    // Se salta si ya apareció, aunque sea dentro de una frase anterior.
    if (k && (vistos.has(k) || (k.length >= 4 && [...vistos].some(v => v.endsWith(k))))) continue;
    vistos.add(k); out.push(f);
  }
  return out.join(' ');
}
// Recorta sin partir palabras.
function cortoPalabra(s, n){
  s = String(s || '').replace(/\s+/g, ' ').trim();
  if (s.length <= n) return s;
  const c = s.slice(0, n - 1); const e = c.lastIndexOf(' ');
  return (e > n * 0.6 ? c.slice(0, e) : c).replace(/[\s.,;:·-]+$/, '') + '…';
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
/* Separa la descripción en texto y datos técnicos.
   "Contactor tripolar. Corriente AC3 (A): 500. Tensión de bobina: 110 V AC."
   → texto "Contactor tripolar." + filas [["Corriente AC3 (A)","500"], ["Tensión de bobina","110 V AC"]]
   Si salen menos de 2 filas se deja la descripción tal cual. */
function separarDatos(desc){
  const frases = String(desc || '').replace(/\s+/g, ' ').trim().split(/\.\s+(?=[A-ZÁÉÍÓÚÑ0-9¿"])/).map(f => f.replace(/\.$/, '').trim()).filter(Boolean);
  const filas = [], texto = [];
  for (const f of frases){
    const m = f.match(/^([^:]{2,40}?)\s*:\s*(.+)$/);
    if (m && !/:/.test(m[2]) && /[A-Za-zÁÉÍÓÚáéíóúñÑ]/.test(m[1])) filas.push([m[1], m[2]]);
    else texto.push(f);
  }
  if (filas.length < 2) return { texto: String(desc || ''), filas: [] };
  return { texto: texto.length ? texto.join('. ') + '.' : '', filas };
}
// Íconos de las condiciones de venta (garantía, entrega, nota de entrega)
const ICONO_WA = '<svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24"><path fill="currentColor" d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2zm0 18.2a8.2 8.2 0 0 1-4.2-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8-.2-.1-.4-.1-.6.1l-.8 1c-.1.2-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.3-.4.3-.4.7-1.3.1-.2 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2c0 1.3.9 2.5 1.1 2.7.1.2 1.8 2.8 4.4 3.9 1.6.7 2.3.8 3.1.6.5-.1 1.5-.6 1.7-1.2.2-.6.2-1.1.2-1.2-.1-.1-.3-.2-.5-.3z"/></svg>';
function iconoCond(txt){
  const t = String(txt).toLowerCase();
  const d = /garant/.test(t) ? '<path d="M12 3l8 3v6c0 4.5-3.4 8-8 9-4.6-1-8-4.5-8-9V6z"/><path d="M9 12l2 2 4-4"/>'
    : /entrega/.test(t) && !/nota/.test(t) ? '<path d="M3 7h11v9H3z"/><path d="M14 10h4l3 3v3h-7"/><circle cx="7" cy="18" r="1.6"/><circle cx="17" cy="18" r="1.6"/>'
    : '<path d="M6 3h9l3 3v15H6z"/><path d="M9 11h6M9 15h6"/>';
  return '<svg aria-hidden="true" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + d + '</svg>';
}
const urlP = (p) => '/p/' + T.slugDe(p.modelo);
const urlC = (ruta) => '/c/' + ruta.map(T.slugDe).join('/');
const waLink = (texto) => 'https://wa.me/' + WA + '?text=' + encodeURIComponent(texto);
const jsonLD = (o) => '<script type="application/ld+json">' + JSON.stringify(o).replace(/</g, '\\u003c') + '</script>';
const ORG = { '@type': 'Organization', name: 'Suinelectric', url: DOMINIO + '/tienda', logo: IMAGEN_GENERAL };

// Página oficial y manual del fabricante (reglas en enlaces-oficiales.js)
const { enlacesDe } = require('./enlaces-oficiales.js');
function enlacesOficiales(p){
  const e = enlacesDe(p);
  if (!e.pagina && !e.manual) return '';
  return '<div class="p-enlaces">' +
    (e.pagina ? '<a href="' + esc(e.pagina) + '" target="_blank" rel="noopener nofollow">Página oficial' + (p.marca ? ' ' + esc(String(p.marca).toUpperCase()) : '') + ' ↗</a>' : '') +
    (e.manual ? '<a href="' + esc(e.manual) + '" target="_blank" rel="noopener nofollow">' + esc(e.manualTexto || 'Manual (PDF)') + ' ↗</a>' : '') +
    '</div>';
}

function escribir(rel, contenido){
  const f = path.join(RAIZ, rel);
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, contenido);
}

/* ---------- Plantilla común ---------- */
function pagina({ titulo, descripcion, imagen, canonica, cuerpo, datos, tipoOg, ogTitulo, ogDescripcion, og, extraOg }){
  ogTitulo = ogTitulo || titulo; ogDescripcion = ogDescripcion || descripcion;
  og = og || { url: imagen };
  const ogImg = [
    `<meta property="og:image" content="${esc(og.url)}">`,
    `<meta property="og:image:secure_url" content="${esc(og.url)}">`,
    og.tipo ? `<meta property="og:image:type" content="${og.tipo}">` : '',
    og.w ? `<meta property="og:image:width" content="${og.w}">\n<meta property="og:image:height" content="${og.h}">` : '',
    og.alt ? `<meta property="og:image:alt" content="${esc(og.alt)}">` : '',
  ].filter(Boolean).join('\n');
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
<meta property="og:title" content="${esc(ogTitulo)}">
<meta property="og:description" content="${esc(ogDescripcion)}">
${ogImg}
<meta property="og:url" content="${esc(canonica)}">${extraOg ? '\n' + extraOg : ''}
<meta name="twitter:card" content="${og.w && og.w === og.h ? 'summary' : 'summary_large_image'}">
<meta name="twitter:title" content="${esc(ogTitulo)}">
<meta name="twitter:description" content="${esc(ogDescripcion)}">
<meta name="twitter:image" content="${esc(og.url)}">
<meta name="theme-color" content="#0e2a3b">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Semi+Condensed:wght@600;700&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap">
<link rel="stylesheet" href="/publico.css?v=${VERSION_ESTILOS}">
<script src="/publico.js?v=${VERSION_ESTILOS}" defer></script>
${(datos || []).map(jsonLD).join('\n')}
</head>
<body>
<div class="topbar"><div class="ancho">
  <a href="https://wa.me/${WA}" rel="noopener">WhatsApp ${esc(WA_TXT)}</a>
  <span>Automatización y control eléctrico · Venezuela</span>
</div></div>
<header class="cabecera"><div class="ancho">
  <a class="logo" href="/tienda"><img src="/imagenes/logo-suinelectric.png" alt="" width="52" height="52"><span><strong>SUINELECTRIC</strong><small>Automatización y control</small></span></a>
  <form class="buscador" action="/tienda" method="get" role="search">
    <label for="q" class="oculto">Buscar en la tienda</label>
    <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg>
    <input id="q" type="search" name="q" placeholder="Buscar modelo, marca o descripción" autocomplete="off">
  </form>
  <a class="btn tinta" href="/tienda">Ir a la tienda</a>
</div></header>
<main class="ancho">
${cuerpo}
</main>
<footer class="pie"><div class="ancho">
  <div><strong>SUINELECTRIC</strong><p>Automatización y control eléctrico en Venezuela.</p></div>
  <div><h2>Contacto</h2><a href="https://wa.me/${WA}" rel="noopener">WhatsApp ${esc(WA_TXT)}</a><a href="/tienda">Ver toda la tienda</a></div>
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
    '<span class="t-pie"><b class="precio-cli"' + datosPrecio(p) + '>' + (precio != null ? dinero(precio) : 'Consultar') + '</b><em class="' + (p.disponible === false ? 'off' : 'ok') + '">' + esc(textoStock(p)) + '</em></span></a>';
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
  const descLimpia = sinRepetidos(p.descripcion);
  // Para Google (pestaña y resultados): modelo, marca y de qué se trata.
  const titulo = p.modelo + (marca ? ' ' + marca : '') + (descLimpia ? ' · ' + cortoPalabra(descLimpia, 55) : '') + ' | Suinelectric';
  const partes = [];
  partes.push((precio != null ? dinero(precio) + ' · ' : '') + textoStock(p) + ' en Suinelectric Venezuela');
  if (descLimpia) partes.push(cortoPalabra(descLimpia, 140).replace(/\.$/, ''));
  const descripcion = partes.join('. ') + '. Cotiza por WhatsApp.';
  // Para WhatsApp y redes: en el teléfono casi solo se ve el título, así que
  // lleva modelo, marca y precio; la descripción dice qué es y las condiciones.
  const ogTitulo = p.modelo + (marca ? ' · ' + marca : '') + ' — ' + (precio != null ? dinero(precio) + ' USD' : 'Consultar precio');
  const ogDescripcion = [descLimpia ? cortoPalabra(descLimpia, 110).replace(/\.$/, '') : '', textoStock(p),
    'Garantía 6 meses', 'Entrega 1-2 días hábiles'].filter(Boolean).join(' · ');
  const og = imagenOg(p.imagen, p.modelo + (marca ? ' ' + marca : ''));
  const extraOg = [
    precio != null ? `<meta property="product:price:amount" content="${precio}">\n<meta property="product:price:currency" content="USD">` : '',
    `<meta property="product:availability" content="${p.disponible === false ? 'out of stock' : 'in stock'}">`,
    `<meta property="product:condition" content="new">`,
    marca ? `<meta property="product:brand" content="${esc(marca)}">` : '',
    `<meta property="product:retailer_item_id" content="${esc(p.modelo)}">`,
  ].filter(Boolean).join('\n');
  const m = migas(ruta, p.modelo);
  const hermanos = (nodos.get(ruta.join('|||')) || { productos: [] }).productos.filter(x => x !== p).slice(0, 8);
  const textoWa = 'Hola, quiero cotizar: ' + p.modelo + (marca ? ' (' + marca + ')' : '') + '\n' + canonica;
  const sep = separarDatos(p.descripcion);
  const imgs = [...new Set([p.imagen].concat(p.imagenes || []).filter(Boolean))];

  const producto = {
    '@context': 'https://schema.org', '@type': 'Product',
    name: p.modelo + (descLimpia ? ' - ' + cortoPalabra(descLimpia, 100) : ''),
    sku: p.sku || p.modelo, mpn: p.modelo,
    description: corto(descLimpia || p.nombre || p.modelo, 500),
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
        (sep.texto ? '<p class="p-desc">' + esc(sep.texto) + '</p>' : '') +
        '<div class="p-precio precio-cli"' + datosPrecio(p) + '>' + (precio != null ? dinero(precio) + ' <small>USD</small>' : 'Consultar precio') + '</div>' +
        '<div class="p-stock ' + (p.disponible === false ? 'off' : 'ok') + '">' + esc(textoStock(p)) + '</div>' +
        '<div class="p-botones">' +
          '<a class="btn wa" href="' + esc(waLink(textoWa)) + '" data-modelo="' + esc(p.modelo) + '" rel="noopener">Cotizar por WhatsApp</a>' +
          '<a class="btn amarillo" href="/tienda#/?p=' + encodeURIComponent(p.modelo) + '">Agregar al pedido</a>' +
        '</div>' +
        '<ul class="p-cond">' + CONDICIONES.concat(['Con nota de entrega.']).map(c => '<li>' + iconoCond(c) + '<span>' + esc(c) + '</span></li>').join('') + '</ul>' +
        (sep.filas.length ? '<h2 class="p-sub">Especificaciones</h2><table class="p-tabla"><tbody>' +
          sep.filas.map(([k, v]) => '<tr><th scope="row">' + esc(k) + '</th><td>' + esc(v) + '</td></tr>').join('') + '</tbody></table>' : '') +
        '<dl class="p-datos">' +
          '<dt>Modelo</dt><dd>' + esc(p.modelo) + '</dd>' +
          (marca ? '<dt>Marca</dt><dd>' + esc(marca) + '</dd>' : '') +
          (p.sku && p.sku !== p.modelo ? '<dt>Código</dt><dd>' + esc(p.sku) + '</dd>' : '') +
          '<dt>Categoría</dt><dd>' + ruta.map((n, i) => '<a href="' + urlC(ruta.slice(0, i + 1)) + '">' + esc(n) + '</a>').join(' › ') + '</dd>' +
        '</dl>' +
        enlacesOficiales(p) +
        // celular: barra fija abajo con el modelo, el precio y Cotizar
        '<div class="p-barra"><div class="p-barra-txt"><strong>' + esc(p.modelo) + '</strong><span class="precio-cli"' + datosPrecio(p) + '>' + (precio != null ? dinero(precio) : 'Consultar precio') + '</span></div>' +
          '<a class="btn wa" href="' + esc(waLink(textoWa)) + '" data-modelo="' + esc(p.modelo) + '" rel="noopener">' + ICONO_WA + 'Cotizar</a></div>' +
      '</div>' +
    '</article>' +
    (hermanos.length ? '<section><h2>También en ' + esc(ruta[ruta.length - 1] || 'esta categoría') + '</h2><div class="rejilla">' + hermanos.map(tarjeta).join('') + '</div></section>' : '');

  escribir('p/' + slug + '.html', pagina({ titulo, descripcion, ogTitulo, ogDescripcion, og, extraOg, canonica, cuerpo, datos: [producto, m.ld], tipoOg: 'product' }));
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
    og: imagenOg((n.ruta.length === 1 && imgFam[nombre]) || n.imagen, nombre + ' · Suinelectric'),
    ogTitulo: nombre + ' — ' + n.total.toLocaleString('es-VE') + (n.total === 1 ? ' producto' : ' productos') + ' | Suinelectric',
  }));
  urls.push(urlC(n.ruta));
  nC++;
}

/* ---------- sitemap.xml ---------- */
const lista = ['/tienda'].concat(fs.existsSync(path.join(RAIZ, 'links.html')) ? ['/links'] : [], urls.filter(u => u.startsWith('/c/')), urls.filter(u => u.startsWith('/p/')));
const xml = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
  [...new Set(lista)].map(u => '  <url><loc>' + esc(DOMINIO + u) + '</loc><lastmod>' + FECHA + '</lastmod></url>').join('\n') + '\n</urlset>\n';
fs.writeFileSync(path.join(RAIZ, 'sitemap.xml'), xml);

/* ---------- Fotos chicas → versión 600×600 para la vista previa ---------- */
(async () => {
  if (!ogPendientes.size) return;
  let sharp = null;
  try { sharp = require('sharp'); } catch (e) { console.log('(sharp no instalado: no se crean las imágenes de vista previa)'); return; }
  let hechas = 0;
  for (const [origen, destino] of ogPendientes){
    const f = path.join(RAIZ, destino);
    if (fs.existsSync(f)) continue;   // el nombre lleva el de la foto original: si cambia, se crea otra
    try {
      fs.mkdirSync(path.dirname(f), { recursive: true });
      const lado = Math.round(OG_LADO * 0.86);
      const foto = await sharp(path.join(RAIZ, origen)).flatten({ background: '#ffffff' })
        .resize(lado, lado, { fit: 'inside' }).toBuffer();
      await sharp({ create: { width: OG_LADO, height: OG_LADO, channels: 3, background: '#ffffff' } })
        .composite([{ input: foto, gravity: 'center' }]).jpeg({ quality: 82, mozjpeg: true }).toFile(f);
      hechas++;
    } catch (e) { console.log('No se pudo crear ' + destino + ': ' + e.message); }
  }
  console.log('Imágenes de vista previa: ' + ogPendientes.size + ' fotos chicas (' + hechas + ' nuevas en imagenes/og/).');
})();

console.log('Páginas creadas: ' + nP + ' productos y ' + nC + ' categorías · sitemap.xml con ' + new Set(lista).size + ' direcciones.');
