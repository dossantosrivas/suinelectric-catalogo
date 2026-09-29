/* =====================================================================
   SUBIR CATÁLOGO PARA EL ASISTENTE DEL CHAT (Supabase)
   ---------------------------------------------------------------------
   La IA del chat busca productos en la tabla productos_busqueda de
   Supabase (ver 09_asistente.sql). Este script la llena con
   catalogo-tienda.json: modelo, marca, categoría, descripción,
   disponibilidad y el enlace a la página del producto. SIN precios.

   Se corre solo desde GitHub Actions (mismos secrets que las existencias):
     SUPABASE_URL, SUPABASE_SECRET_KEY
   Si faltan o falla, avisa y termina sin error (la tienda sigue igual).
   ===================================================================== */
const fs = require('fs');
const path = require('path');

const URL_SB = (process.env.SUPABASE_URL || 'https://yqnlxhbjassrkudnhvpr.supabase.co').replace(/\/+$/, '');
const CLAVE = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_KEY || '';
const SITIO = (process.env.SITIO_URL || 'https://suinelectric.com').replace(/\/+$/, '');

if (!CLAVE){
  console.log('⚠ Falta el secret SUPABASE_SECRET_KEY: no se subió el catálogo del asistente.');
  process.exit(0);
}

// Igual que slugDe() de tienda.html (las páginas /p/… se generan con esto).
const slugDe = (s) => String(s).normalize('NFD').replace(/[\u0300-\u036f]/g, '')
  .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'x';
// Texto para buscar: minúsculas, sin acentos, solo letras/números/./,/ separados por espacios.
// (functions/api/asistente.js normaliza igual los términos que busca la IA.)
const normal = (s) => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
  .replace(/[^a-z0-9.,/]+/g, ' ')
  .replace(/([0-9])([a-z])/g, '$1 $2').replace(/([a-z])([0-9])/g, '$1 $2')   // 15hp → 15 hp, gd20 → gd 20
  .replace(/\s+/g, ' ').trim();

let cat;
try { cat = JSON.parse(fs.readFileSync(path.join(__dirname, 'catalogo-tienda.json'), 'utf8')); }
catch (e){ console.log('✗ No pude leer catalogo-tienda.json: ' + e.message); process.exit(0); }

const lista = [].concat(cat.manuales || [], cat.productos || []);   // manuales primero (mandan si se repite)
const vistos = new Set();
const datos = [];
for (const p of lista){
  if (!p || !p.modelo || p.modelo === 'EJEMPLO-BORRAR' || vistos.has(p.modelo)) continue;
  vistos.add(p.modelo);
  const disponible = p.disponible !== false;
  const disponibilidad = !disponible ? 'Agotado'
    : p.stock === '+10' ? '+10 disponibles'
    : p.stock === 'pocas' ? 'Últimas unidades'
    : 'Disponible';
  const categoria = Array.isArray(p.categorias) ? p.categorias.slice(0, -1).join(' > ') || p.categoria : p.categoria;
  datos.push({
    modelo: p.modelo,
    marca: p.marca || null,
    categoria: categoria || null,
    descripcion: String(p.descripcion || '').slice(0, 1200),
    disponible,
    disponibilidad,
    url: SITIO + '/p/' + slugDe(p.modelo),
    // Empieza con el modelo (para reconocer una búsqueda exacta del modelo) y cada palabra va precedida de espacio.
    texto: ' ' + [p.modelo, p.nombre, p.marca, p.categoria, p.descripcion].filter(Boolean).map(normal).join(' | ') + ' ',
  });
}

(async () => {
  const headers = { 'Content-Type': 'application/json', apikey: CLAVE };
  if (!CLAVE.startsWith('sb_')) headers.Authorization = 'Bearer ' + CLAVE;
  const resp = await fetch(URL_SB + '/rest/v1/rpc/cargar_productos_busqueda', {
    method: 'POST', headers, body: JSON.stringify({ datos }),
  });
  const texto = await resp.text();
  if (!resp.ok){
    console.log('✗ No se pudo subir el catálogo del asistente (' + resp.status + '): ' + texto.slice(0, 300));
    if (/cargar_productos_busqueda/.test(texto)) console.log('  ¿Ya corriste 09_asistente.sql en Supabase?');
    process.exit(0);
  }
  console.log('Catálogo del asistente subido a Supabase: ' + texto + ' productos.');
})().catch((e) => { console.log('✗ Error subiendo el catálogo del asistente: ' + e.message); process.exit(0); });
