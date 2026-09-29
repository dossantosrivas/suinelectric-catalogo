/* =====================================================================
   DE DÓNDE ENTRAN  (Cloudflare Pages Function: /api/geo)
   ---------------------------------------------------------------------
   Devuelve el país, estado, ciudad y proveedor de internet aproximados
   del visitante, tal como los calcula Cloudflare a partir de la conexión.
   La tienda lo pide una vez por visita y lo guarda en el evento "visita"
   (ver 10_visitantes.sql). No se guarda la dirección IP.
   No necesita variables ni claves.
   ===================================================================== */
export async function onRequestGet({ request }){
  const cf = request.cf || {};
  const txt = (v, n) => (v == null || v === '' ? null : String(v).slice(0, n));
  return new Response(JSON.stringify({
    pais: txt(cf.country, 60),            // código ISO: VE, CO, US…
    region: txt(cf.region, 80),           // estado: Carabobo, Zulia…
    ciudad: txt(cf.city, 80),
    proveedor: txt(cf.asOrganization, 100), // CANTV, Movilnet, Inter, Digitel…
  }), {
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Robots-Tag': 'noindex',
    },
  });
}
