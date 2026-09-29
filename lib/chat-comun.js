/* Utilidades compartidas por las funciones de functions/api (chat de la tienda).
   Vive fuera de functions/ para que no se publique como dirección. */

export const tg = (env, metodo, datos) =>
  fetch('https://api.telegram.org/bot' + env.TELEGRAM_TOKEN + '/' + metodo, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(datos),
  }).then(r => r.json()).catch(e => ({ ok: false, description: String(e) }));

export async function rpc(env, funcion, args){
  const clave = env.SUPABASE_SECRET_KEY || '';
  const headers = { 'Content-Type': 'application/json', apikey: clave };
  if (!clave.startsWith('sb_')) headers.Authorization = 'Bearer ' + clave; // claves antiguas (JWT)
  const url = (env.SUPABASE_URL || 'https://yqnlxhbjassrkudnhvpr.supabase.co').replace(/\/+$/, '');
  const r = await fetch(url + '/rest/v1/rpc/' + funcion, { method: 'POST', headers, body: JSON.stringify(args) });
  const texto = await r.text();
  if (!r.ok) throw new Error('Supabase ' + r.status + ': ' + texto.slice(0, 200));
  return texto ? JSON.parse(texto) : null;
}

export const esc = (t) => String(t == null ? '' : t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// Enlace de WhatsApp a partir de un teléfono venezolano (0412-1234567 → 584121234567).
export function waDe(tel){
  const d = String(tel || '').replace(/\D/g, '');
  if (d.length < 7) return null;
  return 'https://wa.me/' + (d.startsWith('0') ? '58' + d.slice(1) : d);
}
