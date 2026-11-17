/* =====================================================================
   PÁGINA DE UN PRODUCTO BAJO PEDIDO  (Cloudflare Pages Function: /d/<modelo>)
   ---------------------------------------------------------------------
   Los modelos de las listas de distribuidores (distribuidores-tienda.json,
   ver generar-distribuidores-tienda.js) no tienen página fija en /p/: son
   miles y no caben en el límite de archivos de Cloudflare. Esta función arma
   la página al vuelo, con el mismo estilo de /p/ (publico.css):
     · "Precio estimado" (costo + 20 %) o "Precio a consultar"
     · Entrega 2-5 días hábiles después del pago
     · Cotizar por WhatsApp y agregar al pedido en la tienda
   Mientras se prueba en tienda-beta las páginas llevan noindex (no salen en Google).
   ===================================================================== */
const INDEXAR = false;                  // true cuando se pase a la tienda oficial
const TIENDA = '/tienda-beta';          // '/tienda' cuando se pase a la oficial
const WA = '584124111319';
const DOMINIO = 'https://suinelectric.com';

let cache = null, cacheHora = 0;
async function catalogo(env, request){
  if (cache && Date.now() - cacheHora < 10 * 60 * 1000) return cache;
  const r = await env.ASSETS.fetch(new Request(new URL('/distribuidores-tienda.json', request.url)));
  if (!r.ok) throw new Error('sin distribuidores-tienda.json');
  const d = await r.json();
  const porSlug = new Map();
  (d.productos || []).forEach(p => porSlug.set(p.s, p));
  cache = { d, porSlug }; cacheHora = Date.now();
  return cache;
}
const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const usd = (n) => '$' + Math.ceil(Number(n)).toLocaleString('en-US');

export async function onRequestGet({ params, env, request }){
  const slug = String(params.modelo || '').toLowerCase().replace(/\.html$/, '');
  let c;
  try { c = await catalogo(env, request); } catch (e) { return Response.redirect(new URL(TIENDA, request.url).toString(), 302); }
  const p = c.porSlug.get(slug);
  if (!p) return Response.redirect(new URL(TIENDA + '#/buscar?q=' + encodeURIComponent(slug), request.url).toString(), 302);

  const entrega = c.d.entrega || '2-5 días';
  const url = DOMINIO + '/d/' + p.s;
  const nombre = p.n || p.m;
  const titulo = p.m + (p.mk ? ' ' + p.mk : '') + (p.n ? ' · ' + p.n.slice(0, 70) + (p.n.length > 70 ? '…' : '') : '');
  const precioTxt = p.pe != null ? usd(p.pe) : 'Precio a consultar';
  const desc = (p.pe != null ? 'Precio estimado ' + usd(p.pe) : 'Precio a consultar') + ' · bajo pedido, entrega ' + entrega + ' hábiles en Suinelectric Venezuela. ' + (p.n || '') + ' Cotiza por WhatsApp.';
  const img = p.img ? DOMINIO + p.img : DOMINIO + '/imagenes/og-suinelectric.jpg';
  const wa = 'https://wa.me/' + WA + '?text=' + encodeURIComponent('Hola, quiero cotizar: ' + p.m + (p.mk ? ' (' + p.mk + ')' : '') + '\n' + url);
  const ld = { '@context': 'https://schema.org', '@type': 'Product', name: p.m + (p.n ? ' - ' + p.n : ''), mpn: p.m, description: nombre, url,
    image: p.img ? [img] : undefined, brand: p.mk ? { '@type': 'Brand', name: p.mk } : undefined };
  if (p.pe != null) ld.offers = { '@type': 'Offer', url, priceCurrency: 'USD', price: String(Math.ceil(p.pe)), availability: 'https://schema.org/BackOrder', itemCondition: 'https://schema.org/NewCondition',
    seller: { '@type': 'Organization', name: 'Suinelectric', url: DOMINIO + '/tienda' } };
  const ico = (d) => '<svg aria-hidden="true" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + d + '</svg>';

  const html = `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(titulo)} | Suinelectric</title>
<meta name="description" content="${esc(desc.slice(0, 300))}">
${INDEXAR ? '' : '<meta name="robots" content="noindex">\n'}<link rel="canonical" href="${url}">
<meta property="og:type" content="product">
<meta property="og:site_name" content="Suinelectric">
<meta property="og:locale" content="es_VE">
<meta property="og:title" content="${esc(p.m + (p.mk ? ' · ' + p.mk : '') + ' — ' + precioTxt)}">
<meta property="og:description" content="${esc((p.n ? p.n + ' · ' : '') + 'Bajo pedido · Entrega ' + entrega + ' hábiles')}">
<meta property="og:image" content="${esc(img)}">
<meta property="og:url" content="${url}">
<meta name="theme-color" content="#0e2a3b">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Semi+Condensed:wght@600;700&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap">
<link rel="stylesheet" href="/publico.css?v=7">
<script src="/publico.js?v=7" defer></script>
<script type="application/ld+json">${JSON.stringify(ld).replace(/</g, '\\u003c')}</script>
<style>.p-stock.pedido{ background:#fff4d6; color:#8a5a00; } .p-precio .est{ display:block; font-family:var(--sans); font-size:13.5px; font-weight:600; color:var(--t3); letter-spacing:.02em; text-transform:uppercase; margin-bottom:2px; } .p-nota{ font-size:13px; color:var(--t3); margin:6px 0 0; }</style>
</head>
<body>
<div class="topbar"><div class="ancho">
  <a href="https://wa.me/${WA}" rel="noopener">WhatsApp 0412-411 1319</a>
  <span>Automatización y control eléctrico · Venezuela</span>
</div></div>
<header class="cabecera"><div class="ancho">
  <a class="logo" href="${TIENDA}"><img src="/imagenes/logo-suinelectric.png" alt="" width="52" height="52"><span><strong>SUINELECTRIC</strong><small>Automatización y control</small></span></a>
  <form class="buscador" action="${TIENDA}" method="get" role="search">
    <label for="q" class="oculto">Buscar en la tienda</label>
    <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg>
    <input id="q" type="search" name="q" placeholder="Buscar modelo, marca o descripción" autocomplete="off">
  </form>
  <a class="btn tinta" href="${TIENDA}">Ir a la tienda</a>
</div></header>
<main class="ancho">
<nav class="migas" aria-label="Ruta"><a href="${TIENDA}">Tienda</a><span>›</span><span>Bajo pedido</span><span>›</span><b>${esc(p.m)}</b></nav>
<article class="producto">
<div class="p-galeria">${p.img ? `<img src="${esc(p.img)}" alt="${esc(p.m + ' ' + (p.mk || ''))}" width="600" height="600">` : '<div class="p-sin-img">Sin imagen</div>'}</div>
<div class="p-info">
${p.mk ? `<div class="p-marca">${esc(p.mk)}</div>` : ''}<h1>${esc(p.m)}</h1>
${p.n ? `<p class="p-desc">${esc(p.n)}</p>` : ''}
<div class="p-precio">${p.pe != null ? `<span class="est">Precio estimado</span>${usd(p.pe)} <small>USD</small>` : 'Precio a consultar'}</div>
<p class="p-nota">${p.pe != null ? 'Precio referencial: se confirma al cotizar.' : 'Escríbenos y te damos el precio al momento.'}</p>
<div class="p-stock pedido">Bajo pedido · ${esc(entrega)}</div>
<div class="p-botones"><a class="btn wa" href="${wa}" data-modelo="${esc(p.m)}" rel="noopener">Cotizar por WhatsApp</a><a class="btn amarillo" href="${TIENDA}#/?p=${encodeURIComponent(p.m)}">Agregar al pedido</a></div>
<ul class="p-cond"><li>${ico('<path d="M12 3l8 3v6c0 4.5-3.4 8-8 9-4.6-1-8-4.5-8-9V6z"/><path d="M9 12l2 2 4-4"/>')}<span>6 meses de garantía contra defecto de fábrica.</span></li><li>${ico('<path d="M3 7h11v9H3z"/><path d="M14 10h4l3 3v3h-7"/><circle cx="7" cy="18" r="1.6"/><circle cx="17" cy="18" r="1.6"/>')}<span>T. Entrega ${esc(entrega)} hábiles después del pago.</span></li></ul>
<dl class="p-datos"><dt>Modelo</dt><dd>${esc(p.m)}</dd>${p.mk ? `<dt>Marca</dt><dd>${esc(p.mk)}</dd>` : ''}<dt>Disponibilidad</dt><dd>Bajo pedido</dd></dl>
${p.ficha ? `<div class="p-enlaces"><a href="${esc(p.ficha)}" target="_blank" rel="noopener nofollow">Página oficial${p.mk ? ' ' + esc(p.mk) : ''} ↗</a></div>` : ''}
</div>
</article>
</main>
</body>
</html>`;
  return new Response(html, { headers: {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'public, max-age=3600',
    ...(INDEXAR ? {} : { 'X-Robots-Tag': 'noindex' }),
  } });
}
