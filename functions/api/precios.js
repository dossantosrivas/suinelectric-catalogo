/* =====================================================================
   BUSCADOR DE PRECIOS INTERNACIONALES  (Cloudflare Pages Function: /api/precios)
   ---------------------------------------------------------------------
   Lo usa Gestión → Precios. Busca un modelo en:
     • eBay (API oficial "Browse", gratis) — precio, envío dentro de EE. UU.
       hasta el código postal de tu courier, condición y vendedor.
     • IAInventory (tienda Shopify) — precio de cada condición (nuevo, usado…).
   Solo responde a administradores (misma sesión de Supabase que Gestión).

   GET /api/precios?q=GD20-2R2G-4&fuentes=ebay,iai&zip=33166&cond=todas
     cond: todas | nuevo | usado

   Variables en Cloudflare (Settings → Variables and Secrets, Production, tipo Secret):
     EBAY_CLIENT_ID      App ID (Client ID) de developer.ebay.com → Production
     EBAY_CLIENT_SECRET  Cert ID (Client Secret) de la misma app
   Sin ellas, eBay responde "sin_clave" y Gestión ofrece el enlace de búsqueda.
   ===================================================================== */

const SUPA = 'https://yqnlxhbjassrkudnhvpr.supabase.co';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36';
const json = (obj, status = 200) => new Response(JSON.stringify(obj), {
  status,
  headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' },
});
const n2 = (v) => { const n = parseFloat(v); return isFinite(n) ? Math.round(n * 100) / 100 : null; };

/* ---------- solo administradores ---------- */
async function esAdmin(request, env){
  const auth = request.headers.get('Authorization') || '';
  const apikey = request.headers.get('apikey') || '';
  if (!/^Bearer\s+\S+/.test(auth) || !apikey) return false;
  const url = (env.SUPABASE_URL || SUPA).replace(/\/+$/, '');
  try {
    const r = await fetch(url + '/rest/v1/rpc/es_admin', {
      method: 'POST', headers: { 'Content-Type': 'application/json', apikey, Authorization: auth }, body: '{}',
    });
    return r.ok && (await r.json()) === true;
  } catch (e) { return false; }
}

/* ---------- eBay (Browse API) ---------- */
let tokenEbay = null; // { valor, vence }
async function tokenDeEbay(env){
  if (tokenEbay && tokenEbay.vence > Date.now() + 60000) return tokenEbay.valor;
  const r = await fetch('https://api.ebay.com/identity/v1/oauth2/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Authorization: 'Basic ' + btoa(env.EBAY_CLIENT_ID + ':' + env.EBAY_CLIENT_SECRET),
    },
    body: 'grant_type=client_credentials&scope=' + encodeURIComponent('https://api.ebay.com/oauth/api_scope'),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) throw new Error('eBay no aceptó las claves (' + r.status + (j.error_description ? ': ' + j.error_description : '') + ')');
  tokenEbay = { valor: j.access_token, vence: Date.now() + (j.expires_in || 7200) * 1000 };
  return tokenEbay.valor;
}

async function buscarEbay(q, { zip, cond }, env){
  if (!env.EBAY_CLIENT_ID || !env.EBAY_CLIENT_SECRET) return { error: 'sin_clave', items: [] };
  const token = await tokenDeEbay(env);
  const filtros = ['buyingOptions:{FIXED_PRICE|BEST_OFFER}', 'priceCurrency:USD'];
  if (cond === 'nuevo') filtros.push('conditionIds:{1000|1500}');
  if (cond === 'usado') filtros.push('conditionIds:{2000|2500|3000}');
  const u = new URL('https://api.ebay.com/buy/browse/v1/item_summary/search');
  u.searchParams.set('q', q);
  u.searchParams.set('limit', '40');
  u.searchParams.set('filter', filtros.join(','));
  const headers = { Authorization: 'Bearer ' + token, 'X-EBAY-C-MARKETPLACE-ID': 'EBAY_US', 'Accept-Language': 'en-US' };
  if (zip) headers['X-EBAY-C-ENDUSERCTX'] = 'contextualLocation=' + encodeURIComponent('country=US,zip=' + zip);
  const r = await fetch(u, { headers });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error('eBay ' + r.status + ': ' + ((j.errors && j.errors[0] && j.errors[0].message) || 'error'));
  const items = (j.itemSummaries || []).map(it => {
    const env0 = (it.shippingOptions || [])[0];
    const envio = env0 && env0.shippingCost ? n2(env0.shippingCost.value) : null;
    return {
      fuente: 'ebay',
      titulo: it.title || '',
      url: it.itemWebUrl || '',
      img: (it.image && it.image.imageUrl) || (it.thumbnailImages && it.thumbnailImages[0] && it.thumbnailImages[0].imageUrl) || '',
      precio: it.price ? n2(it.price.value) : null,
      moneda: it.price ? it.price.currency : 'USD',
      envio,
      envioTipo: env0 ? env0.shippingCostType || '' : '',
      condicion: it.condition || '',
      vendedor: it.seller ? it.seller.username + (it.seller.feedbackPercentage ? ' (' + it.seller.feedbackPercentage + '%)' : '') : '',
      ubicacion: it.itemLocation ? [it.itemLocation.city, it.itemLocation.stateOrProvince, it.itemLocation.country].filter(Boolean).join(', ') : '',
      pais: it.itemLocation ? it.itemLocation.country || '' : '',
      oferta: (it.buyingOptions || []).includes('BEST_OFFER'),
    };
  }).filter(x => x.precio != null);
  return { total: j.total || items.length, items };
}

/* ---------- IAInventory (Shopify) ---------- */
async function buscarIai(q){
  const base = 'https://iainventory.com';
  const r = await fetch(base + '/search?type=product&q=' + encodeURIComponent(q), { headers: { 'User-Agent': UA, Accept: 'text/html' } });
  if (!r.ok) throw new Error('IAInventory ' + r.status);
  const html = await r.text();
  const handles = [];
  for (const m of html.matchAll(/\/products\/([a-z0-9][a-z0-9\-_.%]*)/gi)) {
    const h = m[1].toLowerCase().replace(/\.(js|json)$/, '');
    if (!handles.includes(h)) handles.push(h);
    if (handles.length >= 10) break;
  }
  const prods = await Promise.all(handles.map(h =>
    fetch(base + '/products/' + h + '.js', { headers: { 'User-Agent': UA, Accept: 'application/json' } })
      .then(x => (x.ok ? x.json() : null)).catch(() => null)));
  const items = prods.filter(Boolean).map(p => {
    const variantes = (p.variants || []).map(v => ({ nombre: v.title === 'Default Title' ? '' : v.title, precio: n2(v.price / 100), disponible: !!v.available }));
    const disp = variantes.filter(v => v.disponible);
    const min = (disp.length ? disp : variantes).reduce((a, v) => (v.precio != null && (a == null || v.precio < a) ? v.precio : a), null);
    const img = p.featured_image ? (String(p.featured_image).startsWith('//') ? 'https:' + p.featured_image : p.featured_image) : '';
    return {
      fuente: 'iai',
      titulo: p.title || '',
      url: base + (p.url || '/products/' + p.handle),
      img: img ? img + (img.includes('?') ? '&' : '?') + 'width=200' : '',
      precio: min != null ? min : n2(p.price / 100),
      moneda: 'USD',
      envio: null,
      condicion: variantes.length > 1 ? variantes.map(v => v.nombre).filter(Boolean).join(' / ') : (variantes[0] && variantes[0].nombre) || '',
      variantes,
      vendedor: p.vendor || '',
      ubicacion: '',
      disponible: !!p.available,
    };
  });
  return { total: items.length, items };
}

export async function onRequestGet({ request, env }){
  const u = new URL(request.url);
  const q = (u.searchParams.get('q') || '').trim().slice(0, 120);
  if (q.length < 2) return json({ error: 'Escribe al menos 2 letras.' }, 400);
  if (!(await esAdmin(request, env))) return json({ error: 'Solo administradores. Inicia sesión en Gestión.' }, 401);
  const fuentes = (u.searchParams.get('fuentes') || 'ebay,iai').split(',');
  const zip = (u.searchParams.get('zip') || '').replace(/[^0-9]/g, '').slice(0, 5);
  const cond = u.searchParams.get('cond') || 'todas';

  const tarea = async (nombre, fn) => {
    if (!fuentes.includes(nombre)) return [nombre, null];
    try { return [nombre, await fn()]; }
    catch (e) { return [nombre, { error: String(e.message || e).slice(0, 300), items: [] }]; }
  };
  const res = await Promise.all([
    tarea('ebay', () => buscarEbay(q, { zip, cond }, env)),
    tarea('iai', () => buscarIai(q)),
  ]);
  const out = { q, fecha: new Date().toISOString() };
  res.forEach(([k, v]) => { if (v) out[k] = v; });
  return json(out);
}
