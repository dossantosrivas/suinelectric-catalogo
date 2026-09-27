/* =====================================================================
   SUBIR EXISTENCIAS REALES A SUPABASE
   ---------------------------------------------------------------------
   La tienda pública solo muestra "+10 disponibles" / "Últimas unidades".
   Las cantidades exactas se guardan en Supabase, donde solo las pueden
   leer los administradores y los clientes con permiso (ver 03_existencias.sql).

   Se corre solo cada día desde GitHub Actions. Necesita dos "secrets" del
   repositorio (GitHub → Settings → Secrets and variables → Actions):
     SUPABASE_URL          https://yqnlxhbjassrkudnhvpr.supabase.co
     SUPABASE_SECRET_KEY   la clave secreta (Supabase → Project Settings →
                           API Keys → Secret keys, empieza con sb_secret_)
   Si faltan, el script avisa y termina sin error (la tienda sigue igual).
   ===================================================================== */
const fs = require('fs');
const path = require('path');

const URL_SB = (process.env.SUPABASE_URL || 'https://yqnlxhbjassrkudnhvpr.supabase.co').replace(/\/+$/, '');
const CLAVE = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_KEY || '';

if (!CLAVE){
  console.log('⚠ Falta el secret SUPABASE_SECRET_KEY: no se subieron las existencias reales.');
  process.exit(0);
}

const leer = (f) => { try { return JSON.parse(fs.readFileSync(path.join(__dirname, f), 'utf8')); } catch (e) { return { productos: [] }; } };

// Manuales primero (si un modelo se repite, manda el manual, igual que en la tienda).
const datos = {};
const agregar = (lista, pisar) => {
  for (const p of lista || []){
    if (!p || !p.modelo || p.modelo === 'EJEMPLO-BORRAR') continue;
    const n = Number(p.existencias);
    if (p.existencias == null || isNaN(n)) continue;
    if (!pisar && p.modelo in datos) continue;
    datos[p.modelo] = Math.max(0, Math.round(n));
  }
};
agregar(leer('productos_manuales.json').productos, true);
agregar(leer('productos.json').productos, false);

(async () => {
  const headers = { 'Content-Type': 'application/json', apikey: CLAVE };
  // Las claves antiguas (service_role) son JWT y también van en Authorization.
  if (!CLAVE.startsWith('sb_')) headers.Authorization = 'Bearer ' + CLAVE;
  const resp = await fetch(URL_SB + '/rest/v1/rpc/cargar_existencias', {
    method: 'POST', headers, body: JSON.stringify({ datos }),
  });
  const texto = await resp.text();
  if (!resp.ok){
    console.log('✗ No se pudieron subir las existencias (' + resp.status + '): ' + texto.slice(0, 300));
    if (/cargar_existencias/.test(texto)) console.log('  ¿Ya corriste 03_existencias.sql en Supabase?');
    process.exit(0); // no frena la actualización de la tienda
  }
  console.log('Existencias reales subidas a Supabase: ' + texto + ' modelos.');
})().catch((e) => { console.log('✗ Error subiendo existencias: ' + e.message); process.exit(0); });
