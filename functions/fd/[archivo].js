/* =====================================================================
   FOTOS DE PRODUCTOS DE DISTRIBUIDORES  (Cloudflare Pages Function: /fd/<archivo>)
   ---------------------------------------------------------------------
   distribuidores-tienda.json guarda las fotos como /fd/gv2mc01.jpg. Esta
   función las trae del distribuidor y las sirve desde suinelectric.com, así
   el cliente no ve de dónde salen y no hace falta guardar miles de fotos en
   el repo. Cloudflare las guarda en caché 30 días.
   Si la foto no existe, devuelve un recuadro gris "Sin imagen".
   ===================================================================== */
const ORIGEN = 'https://automatroni.com/archivos_productos/';
const SIN_IMAGEN = '<svg xmlns="http://www.w3.org/2000/svg" width="300" height="300" viewBox="0 0 300 300"><rect width="300" height="300" fill="#f3f5f7"/><text x="150" y="156" font-family="sans-serif" font-size="18" fill="#9aa6b0" text-anchor="middle">Sin imagen</text></svg>';

export async function onRequestGet({ params, request }){
  const archivo = String(params.archivo || '');
  if (!/^[A-Za-z0-9._-]{1,120}\.(jpe?g|png|webp|gif)$/i.test(archivo)) return vacio(404);
  try {
    const r = await fetch(ORIGEN + encodeURIComponent(archivo), {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; Suinelectric/1.0)' },
      cf: { cacheEverything: true, cacheTtl: 2592000 },
    });
    const tipo = r.headers.get('Content-Type') || '';
    if (!r.ok || !/^image\//i.test(tipo)) return vacio(200);
    return new Response(r.body, { headers: {
      'Content-Type': tipo,
      'Cache-Control': 'public, max-age=2592000',
      'X-Robots-Tag': 'noindex',
    } });
  } catch (e){
    return vacio(200);
  }
}
function vacio(estado){
  return new Response(SIN_IMAGEN, { status: estado, headers: { 'Content-Type': 'image/svg+xml', 'Cache-Control': 'public, max-age=86400' } });
}
