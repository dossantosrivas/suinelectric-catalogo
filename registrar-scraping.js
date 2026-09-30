/* =====================================================================
   REGISTRAR EL SCRAPING EN SUPABASE (historial de existencias)
   ---------------------------------------------------------------------
   Después de cada scraping manda a Supabase las existencias de los
   productos del scraper (productos.json, NO los manuales). Supabase las
   compara con las de la corrida anterior y guarda qué productos bajaron,
   subieron, aparecieron o desaparecieron (ver 11_historial_scraping.sql).
   Se ve en el panel de administración → Scraping.

   Usa los mismos secrets que subir-existencias.js:
     SUPABASE_URL, SUPABASE_SECRET_KEY
   Si faltan o algo falla, avisa y termina sin error (la tienda sigue igual).
   ===================================================================== */
const fs = require('fs');
const path = require('path');

const URL_SB = (process.env.SUPABASE_URL || 'https://yqnlxhbjassrkudnhvpr.supabase.co').replace(/\/+$/, '');
const CLAVE = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_KEY || '';

if (!CLAVE){
  console.log('⚠ Falta el secret SUPABASE_SECRET_KEY: no se registró el scraping.');
  process.exit(0);
}

let datos;
try { datos = JSON.parse(fs.readFileSync(path.join(__dirname, 'productos.json'), 'utf8')); }
catch (e){ console.log('✗ No se pudo leer productos.json: ' + e.message); process.exit(0); }

if (datos.en_progreso || datos.modo_prueba){
  console.log('⚠ productos.json está incompleto o en modo prueba: no se registra este scraping.');
  process.exit(0);
}

const vistos = new Set();
const productos = [];
for (const p of datos.productos || []){
  if (!p || !p.modelo || vistos.has(p.modelo)) continue;
  const n = Number(p.existencias);
  if (p.existencias == null || isNaN(n)) continue;
  vistos.add(p.modelo);
  const precio = Number(p.precio);
  productos.push({
    modelo: p.modelo,
    cantidad: Math.max(0, Math.round(n)),
    marca: p.marca || null,
    nombre: p.nombre && p.nombre !== p.modelo ? String(p.nombre).slice(0, 200) : null,
    precio: isNaN(precio) || !p.precio ? null : precio,
  });
}

(async () => {
  const headers = { 'Content-Type': 'application/json', apikey: CLAVE };
  if (!CLAVE.startsWith('sb_')) headers.Authorization = 'Bearer ' + CLAVE;
  const resp = await fetch(URL_SB + '/rest/v1/rpc/registrar_scraping', {
    method: 'POST', headers,
    body: JSON.stringify({ p_productos: productos, p_generado: datos.generado || null }),
  });
  const texto = await resp.text();
  if (!resp.ok){
    console.log('✗ No se pudo registrar el scraping (' + resp.status + '): ' + texto.slice(0, 300));
    if (/registrar_scraping/.test(texto)) console.log('  ¿Ya corriste 11_historial_scraping.sql en Supabase?');
    process.exit(0);
  }
  let r = {}; try { r = JSON.parse(texto); } catch (e) {}
  if (r.nota) console.log('⚠ ' + r.nota);
  else if (r.primera) console.log('Primer registro del scraping: ' + r.productos + ' productos guardados como punto de partida.');
  else console.log('Scraping registrado: ' + r.bajaron + ' productos bajaron (' + r.unidades_restadas + ' unidades restadas), ' +
    r.subieron + ' subieron, ' + r.nuevos + ' nuevos, ' + r.desaparecidos + ' desaparecieron.');
})().catch((e) => { console.log('✗ Error registrando el scraping: ' + e.message); process.exit(0); });
