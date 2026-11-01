/* =====================================================================
   SUBIR AUTOMATRONI A GESTIÓN
   ---------------------------------------------------------------------
   Toma distribuidores/automatroni.json (lo genera scraper-automatroni.js)
   y lo deja en Gestión como una LISTA DE EXISTENCIAS del distribuidor
   "Automatroni", igual que las listas de EMI:
     · Gestión → Distribuidores: aparece Automatroni (si no existe, se crea
       una sola vez; lo que edites en su ficha no se toca más).
     · Gestión → Existencias: su lista, con cantidad (Maracay + Caracas −
       reservado) y precio de lista (USD sin IVA) de cada producto.
     · El descuento que le pongas a la lista en Gestión se respeta: este
       script solo cambia productos, cantidades y precios.

   Se guarda en la tabla adm_registros (la misma que sincroniza Gestión).
   Necesita los secrets SUPABASE_URL y SUPABASE_SECRET_KEY.
   Si faltan o algo falla, avisa y termina con error (para el aviso de Telegram).
   ===================================================================== */
const fs = require('fs');
const path = require('path');

const URL_SB = (process.env.SUPABASE_URL || 'https://yqnlxhbjassrkudnhvpr.supabase.co').replace(/\/+$/, '');
const CLAVE = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_KEY || '';
const ARCHIVO = path.join(__dirname, 'distribuidores', 'automatroni.json');
const ID_BASE = 'dist_automatroni';

// mismas reglas que Gestión (ventas.html): normTxt / normKey
const normTxt = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const normKey = (s) => normTxt(s).replace(/[^a-z0-9]/g, '');
const round2 = (n) => Math.round(n * 100) / 100;
const hoyCaracas = () => new Date(Date.now() - 4 * 3600e3).toISOString().slice(0, 10);

if (!CLAVE) { console.log('✗ Falta el secret SUPABASE_SECRET_KEY: no se subió Automatroni.'); process.exit(1); }

const headers = { 'Content-Type': 'application/json', apikey: CLAVE };
if (!CLAVE.startsWith('sb_')) headers.Authorization = 'Bearer ' + CLAVE;

async function leerRegistros(coleccion) {
  const r = await fetch(`${URL_SB}/rest/v1/adm_registros?coleccion=eq.${coleccion}&borrado=eq.false&select=id,data`, { headers });
  if (!r.ok) throw new Error(`leer ${coleccion} (${r.status}): ${(await r.text()).slice(0, 300)}`);
  return r.json();
}
async function guardar(rows) {
  const r = await fetch(`${URL_SB}/rest/v1/adm_registros?on_conflict=coleccion,id`, {
    method: 'POST', headers: Object.assign({ Prefer: 'resolution=merge-duplicates,return=minimal' }, headers),
    body: JSON.stringify(rows),
  });
  if (!r.ok) throw new Error(`guardar (${r.status}): ${(await r.text()).slice(0, 300)}`);
}

(async () => {
  const datos = JSON.parse(fs.readFileSync(ARCHIVO, 'utf8'));
  if (datos.en_progreso || datos.modo_prueba) { console.log('⚠ automatroni.json incompleto o de prueba: no se sube.'); return; }
  const productos = (datos.productos || []).filter(p => p && p.ref);
  if (!productos.length) throw new Error('automatroni.json no trae productos');
  const ahora = new Date().toISOString(), fecha = hoyCaracas();

  // ---- distribuidor: el que ya exista con ese nombre o el nuestro ----
  const provs = await leerRegistros('proveedores');
  let prov = provs.map(x => x.data).find(d => d && (d.id === ID_BASE || /automatroni/.test(normTxt(d.nombre))));
  const filas = [];
  if (!prov) {
    prov = {
      id: ID_BASE, nombre: 'Automatroni', empresa: 'AUTOMATRONI, C.A.', tipo: 'Distribuidor', alcance: 'nacional',
      rif: 'J-29391479-5', telefono: '+58 412-3135985', correo: 'ventasautomatroni@gmail.com',
      direccion: 'Maracay, Aragua', descuento: 0, web: 'https://automatroni.com',
      notas: 'Lista diaria automática desde automatroni.com: precio de lista en USD sin IVA y existencias de Maracay + Caracas (menos lo reservado).',
      surte: { scraping: false, marcas: '' }, reglas: [], logistica: {}, mod: ahora,
    };
    filas.push({ coleccion: 'proveedores', id: prov.id, data: prov, borrado: false });
    console.log('Distribuidor Automatroni creado en Gestión.');
  }

  // ---- lista: se conserva el descuento y lo demás que pongas en Gestión ----
  const idLista = 'lista_' + prov.id + '_general';
  const listas = await leerRegistros('listas');
  const vieja = (listas.find(x => x.id === idLista) || {}).data || null;
  const vistos = new Set(), items = [], precios = {};
  for (const p of productos) {
    const k = normKey(p.ref); if (!k || vistos.has(k)) continue; vistos.add(k);
    const it = { m: p.ref, q: Math.max(0, p.disponible || 0) };
    if (p.marca) it.mk = String(p.marca).toUpperCase();
    if (p.nombre) it.n = String(p.nombre).slice(0, 160);
    if (p.por_llegar) it.ll = p.por_llegar;          // por llegar (Gestión aún no lo muestra)
    items.push(it);
    if (p.precio > 0) precios[k] = { p: round2(p.precio), f: fecha };
  }
  const lista = Object.assign({}, vieja || {}, {
    id: idLista, dist: prov.id, marca: '', items, precios, fecha,
    archivo: 'automatroni.com (automático)', cargado: ahora, por: 'scraper diario', mod: ahora,
  });
  filas.push({ coleccion: 'listas', id: idLista, data: lista, borrado: false });
  await guardar(filas);

  const conQ = items.filter(i => i.q > 0).length;
  console.log(`Automatroni en Gestión: ${items.length} productos (${conQ} con existencia, ${Object.keys(precios).length} con precio)` +
    (vieja && vieja.dto != null && vieja.dto !== '' ? `, descuento de la lista ${vieja.dto}% conservado.` : '.'));
})().catch((e) => { console.log('✗ Error subiendo Automatroni: ' + e.message); process.exit(1); });
