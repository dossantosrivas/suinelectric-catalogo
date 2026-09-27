/* =====================================================================
   CATÁLOGO PARA LA TIENDA (catalogo-tienda.json) + IMÁGENES PROPIAS
   ---------------------------------------------------------------------
   productos.json (lo que genera el scraper) trae muchísima información que
   la tienda no usa: enlaces al proveedor, sus categorías con URL, productos
   relacionados, etc. Pesa ~13 MB y deja ver de dónde sale el catálogo.

   Este script crea catalogo-tienda.json, que es lo ÚNICO que carga la tienda:
     · solo los campos que la tienda muestra (≈2 MB en vez de 13 MB)
     · sin URLs ni nombre del proveedor
     · con las fotos servidas desde tu propio dominio (imagenes/productos/)
     · productos del scraper y manuales en un solo archivo (1 descarga)

   productos.json y productos_manuales.json NO se tocan: el cotizador y el
   scraper siguen usándolos igual.

   Las fotos se descargan una sola vez (se guardan con un nombre fijo) y se
   reducen a máx. 800 px. Las siguientes corridas solo bajan las nuevas.
   Si una foto no se puede bajar, ese día se deja el enlace original (para
   que la tienda no se quede sin foto) y se reintenta en la próxima corrida.

   Se corre solo cada día desde GitHub Actions, después del scraper.
   A mano:  node generar-catalogo-tienda.js
            node generar-catalogo-tienda.js --sin-descargas   (solo el JSON)
   ===================================================================== */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const RAIZ = __dirname;
const SALIDA = path.join(RAIZ, 'catalogo-tienda.json');
const CARPETA_IMG = 'imagenes/productos';            // relativa a la raíz del sitio
const REPO_PROPIO = 'dossantosrivas/suinelectric-catalogo';
const LADO_MAX = 800;                                 // px, lado más largo
const SIMULTANEAS = 6;                                // descargas a la vez
const SIN_DESCARGAS = process.argv.includes('--sin-descargas');

// Fotos de portada de cada familia en Inicio (IMAGENES_FAMILIA en tienda.html).
// Se descargan una vez a imagenes/familias/<nombre>.jpg. Para cambiar una foto,
// cambia el enlace aquí y borra el .jpg viejo de esa carpeta.
const FOTOS_FAMILIA = {
  'variadores-y-arrancadores': 'https://image.makewebeasy.net/makeweb/m_1920x0/IyLW6tgjN/GD200A/IMG_2296.png',
  'control-de-motores': 'https://grupo-electricos.com/wp-content/uploads/2023/07/3RT103X.jpg',
  'automatizacion-y-plc': 'https://cdn.myshoptet.com/usr/eshop.sampli.cz/user/shop/big/450_plc-ridici-modul-6ed1052-1md08-0ba3-siemens-logo-12-24rce.png?69ee3449',
  'sensores-e-instrumentacion': 'https://grupo-electricos.com/wp-content/uploads/2023/07/3SE5112-0CH50.jpg',
  'mando-y-senalizacion': 'https://grupo-electricos.com/wp-content/uploads/2023/07/3sb36XX-0BA40.jpg',
};

let sharp = null;
try { sharp = require('sharp'); } catch (e) { console.log('(sharp no instalado: las fotos se guardan sin reducir)'); }

/* ---------- Qué campos llegan a la tienda ---------- */
const CAMPOS = [
  'modelo', 'nombre', 'marca', 'sku',
  'precio', 'precio_lista', 'disponible',
  'descripcion', 'imagen', 'imagenes',
  'categoria', 'categoria_principal', 'categorias', 'subcategoria', 'subcategorias',
];
const vacio = (v) => v === null || v === undefined || v === '' || (Array.isArray(v) && v.length === 0);
// Las cantidades exactas NO se publican. La tienda solo recibe un rango:
//   "+10"   → más de 10 unidades        → "+10 disponibles"
//   "pocas" → de 1 a LIMITE_POCAS        → "Últimas unidades"
// Las cantidades reales van a Supabase (subir-existencias.js) y solo las ven
// los administradores y los clientes a quienes les des permiso en el panel.
const LIMITE_POCAS = 10;
function rangoStock(p){
  const n = Number(p.existencias);
  if (p.existencias == null || isNaN(n) || p.disponible === false || n <= 0) return null;
  return n > LIMITE_POCAS ? '+10' : 'pocas';
}
function reducir(p){
  const r = {};
  for (const k of CAMPOS) if (!vacio(p[k])) r[k] = p[k];
  const stock = rangoStock(p);
  if (stock) r.stock = stock;
  return r;
}

/* ---------- Utilidades ---------- */
const leer = (f) => JSON.parse(fs.readFileSync(path.join(RAIZ, f), 'utf8'));
const slug = (s) => String(s || 'producto').normalize('NFD').replace(/[̀-ͯ]/g, '')
  .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60) || 'producto';
const corto = (s) => crypto.createHash('sha1').update(s).digest('hex').slice(0, 8);
const esExterna = (u) => typeof u === 'string' && /^https?:\/\//i.test(u);

// Fotos que ya viven en este mismo repo (raw.githubusercontent.com/…/main/imagenes/x.jpg)
// se sirven directo desde el sitio: imagenes/x.jpg
function rutaDelRepo(u){
  const m = String(u).match(/^https?:\/\/raw\.githubusercontent\.com\/([^/]+\/[^/]+)\/[^/]+\/(.+)$/i);
  if (!m || m[1].toLowerCase() !== REPO_PROPIO.toLowerCase()) return null;
  const rel = decodeURIComponent(m[2].split('?')[0]);
  return fs.existsSync(path.join(RAIZ, rel)) ? rel : null;
}

/* ---------- Mapa URL original → archivo propio (se guarda entre corridas) ---------- */
const ARCHIVO_MAPA = path.join(RAIZ, CARPETA_IMG, '_mapa.json');
fs.mkdirSync(path.join(RAIZ, CARPETA_IMG), { recursive: true });
let mapa = {};
try { mapa = JSON.parse(fs.readFileSync(ARCHIVO_MAPA, 'utf8')); } catch (e) {}
const guardarMapa = () => fs.writeFileSync(ARCHIVO_MAPA, JSON.stringify(mapa, null, 0));

function nombreArchivo(url, modelo){
  return CARPETA_IMG + '/' + slug(modelo) + '-' + corto(url) + '.jpg';
}

async function descargar(url, destinoRel){
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 30000);
  try {
    const resp = await fetch(url, {
      signal: ctrl.signal,
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; SuinelectricCatalogo/1.0)' },
    });
    if (!resp.ok) throw new Error('HTTP ' + resp.status);
    const buf = Buffer.from(await resp.arrayBuffer());
    if (buf.length < 100) throw new Error('archivo vacío');
    let salida = buf;
    if (sharp){
      salida = await sharp(buf)
        .rotate()
        .resize({ width: LADO_MAX, height: LADO_MAX, fit: 'inside', withoutEnlargement: true })
        .flatten({ background: '#ffffff' })
        .jpeg({ quality: 82, mozjpeg: true })
        .toBuffer();
    }
    fs.writeFileSync(path.join(RAIZ, destinoRel), salida);
  } finally {
    clearTimeout(t);
  }
}

async function enParalelo(tareas, n){
  let i = 0;
  const trabajador = async () => { while (i < tareas.length){ const t = tareas[i++]; await t(); } };
  await Promise.all(Array.from({ length: n }, trabajador));
}

/* ---------- Principal ---------- */
(async () => {
  const scraper = leer('productos.json');
  let manuales = [];
  try { manuales = (leer('productos_manuales.json').productos || []).filter(p => p.modelo && p.modelo !== 'EJEMPLO-BORRAR'); }
  catch (e) { console.log('productos_manuales.json no se pudo leer; sigo sin manuales.'); }

  const listaScraper = (scraper.productos || []).filter(p => p.modelo).map(reducir);
  const listaManuales = manuales.map(reducir);
  const todos = listaManuales.concat(listaScraper);

  // 1) Reunir todas las fotos externas y decidir su archivo propio
  const pendientes = new Map(); // url -> archivo
  for (const p of todos){
    for (const u of [p.imagen].concat(p.imagenes || [])){
      if (!esExterna(u) || mapa[u] || pendientes.has(u)) continue;
      const delRepo = rutaDelRepo(u);
      if (delRepo){ mapa[u] = delRepo; continue; }
      const archivo = nombreArchivo(u, p.modelo);
      if (fs.existsSync(path.join(RAIZ, archivo))){ mapa[u] = archivo; continue; }
      pendientes.set(u, archivo);
    }
  }

  // Fotos de familia que falten
  fs.mkdirSync(path.join(RAIZ, 'imagenes/familias'), { recursive: true });
  for (const [nombre, url] of Object.entries(FOTOS_FAMILIA)){
    const archivo = 'imagenes/familias/' + nombre + '.jpg';
    if (fs.existsSync(path.join(RAIZ, archivo)) || SIN_DESCARGAS) continue;
    try { await descargar(url, archivo); console.log('Foto de familia: ' + archivo); }
    catch (e) { console.log('  ✗ foto de familia ' + nombre + ' (' + e.message + ')'); }
  }

  // 2) Descargar las que faltan
  let ok = 0, fallos = 0;
  if (pendientes.size && !SIN_DESCARGAS){
    console.log('Fotos nuevas por descargar: ' + pendientes.size);
    const tareas = [...pendientes].map(([url, archivo]) => async () => {
      try {
        await descargar(url, archivo);
        mapa[url] = archivo; ok++;
      } catch (e) {
        fallos++;
        if (fallos <= 20) console.log('  ✗ ' + url + ' (' + e.message + ')');
      }
      if ((ok + fallos) % 200 === 0){ console.log('  … ' + (ok + fallos) + '/' + pendientes.size); guardarMapa(); }
    });
    await enParalelo(tareas, SIMULTANEAS);
    guardarMapa();
    console.log('Fotos descargadas: ' + ok + ' · fallaron: ' + fallos);
  } else {
    guardarMapa();
  }

  // 3) Reemplazar las URLs por las propias. Si una foto todavía no se pudo
  //    descargar, se deja la original por ahora (para que la tienda nunca se
  //    quede sin fotos) y se reintenta en la próxima corrida.
  const externasRestantes = new Set();
  const propia = (u) => {
    if (!u) return null;
    if (!esExterna(u) || !mapa[u]) { if (esExterna(u)) externasRestantes.add(u); return u; }
    return mapa[u];
  };
  for (const p of todos){
    const imgs = [...new Set((p.imagenes || []).map(propia).filter(Boolean))];
    const principal = propia(p.imagen) || imgs[0] || null;
    if (principal) p.imagen = principal; else delete p.imagen;
    if (imgs.length) p.imagenes = imgs; else delete p.imagenes;
  }
  const sinFoto = todos.filter(p => !p.imagen).length;

  // 4) Guardar
  const salida = {
    generado: scraper.generado || new Date().toISOString(),
    en_progreso: !!scraper.en_progreso,
    total_esperado: scraper.total_esperado || null,
    total_productos: listaScraper.length,
    total_manuales: listaManuales.length,
    productos: listaScraper,
    manuales: listaManuales,
  };
  const texto = JSON.stringify(salida);
  fs.writeFileSync(SALIDA, texto);
  console.log('catalogo-tienda.json: ' + listaScraper.length + ' del scraper + ' + listaManuales.length +
    ' manuales · ' + (texto.length / 1048576).toFixed(2) + ' MB · productos sin foto: ' + sinFoto);
  if (externasRestantes.size) console.log('⚠ Fotos que siguen con enlace externo (se reintentan mañana): ' + externasRestantes.size);
  const menciones = (texto.match(/grupo-electricos/gi) || []).length;
  if (menciones) console.log('⚠ Menciones del proveedor que quedan en catalogo-tienda.json: ' + menciones);
})().catch((e) => { console.error(e); process.exit(1); });
