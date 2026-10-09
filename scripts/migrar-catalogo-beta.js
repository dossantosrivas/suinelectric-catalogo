/* =====================================================================
   MIGRAR AL CATÁLOGO ÚNICO (fase 2 y 3 del plan, versión beta)
   ---------------------------------------------------------------------
   Arma el catálogo exactamente como lo arma hoy la tienda (mismo código de
   tienda.html: categorías, inventario, productos del panel, ocultos) y lo
   convierte al esquema "catalogo" (supabase/16_catalogo_unico.sql):
     · árbol de 3 niveles (familia · categoría · subcategoría por función)
     · series + SKU (los HGC de Hyundai pasan a series con variantes de bobina)
     · atributos técnicos leídos de la descripción y de los niveles del proveedor
     · ofertas por proveedor y existencias por almacén

   Uso:
     node scripts/migrar-catalogo-beta.js <foto_produccion.json> <salida_privada.json>

   <foto_produccion.json> = productos_web, productos_ocultos, inventario_web y la
   colección productos de Gestión, tal como están en Supabase.
   Escribe:
     datos-beta/carga.json      → lo público (lo mismo que ya muestra la tienda)
     <salida_privada.json>      → existencias y costos de tu inventario (NO va al repo)
   ===================================================================== */
const fs = require('fs');
const path = require('path');

const REPO = path.join(__dirname, '..');
const [, , FOTO, PRIVADO] = process.argv;
if (!FOTO || !PRIVADO) { console.error('Uso: node scripts/migrar-catalogo-beta.js foto.json privado.json'); process.exit(1); }

/* ---------- 1. El código de la tienda (una sola fuente de verdad) ---------- */
const html = fs.readFileSync(path.join(REPO, 'tienda.html'), 'utf8');
const cortar = (a, b) => { const i = html.indexOf(a), j = html.indexOf(b, i); if (i < 0 || j < 0) throw new Error('No encontré ' + a + ' en tienda.html'); return html.slice(i, j); };
const ini = html.indexOf('ORGANIZACIÓN DE CATEGORÍAS');
const T = new Function(
  html.slice(html.lastIndexOf('/*', ini), html.indexOf('/* ---------- Dirección (URL) de cada pantalla')) +
  cortar('function normalizarBusqueda(', 'function textoBuscableDe(') +
  cortar('const VFD_USOS =', 'function specsVfd(') +
  cortar('const ARR_TENSIONES =', 'function specsArr(') +
  cortar('function formaTiendaDePanel(', 'let catalogoEnProgreso') +
  '\nreturn { rutaDe, FAMILIAS, NODOS_MARCA, VFD_USOS, formaTiendaDePanel, unirInventario, claveModelo, extraerSpecsVfd, extraerSpecsArr };')();

const foto = JSON.parse(fs.readFileSync(FOTO, 'utf8'));
const cat = JSON.parse(fs.readFileSync(path.join(REPO, 'catalogo-tienda.json'), 'utf8'));

/* ---------- 2. La lista final, igual que cargar() en la tienda ---------- */
const ocultos = new Set(foto.ocultos);
const delPanel = foto.web.map(T.formaTiendaDePanel);
const setPanel = new Set(delPanel.map(p => p.modelo));
const manuales = delPanel.concat((cat.manuales || []).filter(p => p.modelo !== 'EJEMPLO-BORRAR' && !setPanel.has(p.modelo))).filter(p => !ocultos.has(p.modelo));
manuales.forEach(p => { p._manual = true; });
const setMan = new Set(manuales.map(p => p.modelo));
const delScraper = (cat.productos || []).filter(p => !ocultos.has(p.modelo) && !setMan.has(p.modelo));
delScraper.forEach(p => { p._manual = false; });
const productos = T.unirInventario(manuales.concat(delScraper), foto.inventario, ocultos);

/* ---------- 3. Utilidades ---------- */
const num = (s) => { if (s == null) return null; const v = parseFloat(String(s).replace(/\s/g, '').replace(',', '.')); return isNaN(v) ? null : v; };
const slug = (s) => String(s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const marcaLimpia = (m) => { m = String(m || '').trim().toUpperCase().replace(/^(SIEMENS)+$/, 'SIEMENS'); return m === 'SCHNEIDER ELECTRIC' ? 'SCHNEIDER' : (m || 'SIN MARCA'); };

/* ---------- 4 y 5. Árbol, serie y atributos: viven en /especificaciones.js ---------- */
const E = require('../especificaciones.js');
const { ATRIBUTOS, FILTROS } = E;
const subcategoria = E.subcategoria;
const serieDe = (categoria, resto) => E.serieDe(categoria, resto, T);
const atributosDe = (p, categoria, sub, resto, serie) => E.atributosBase(p, categoria, sub, resto, serie, T);
const atributosExtra = E.atributosExtra, unirSpecs = E.unirSpecs;
// Nombre de bobina para las variantes Hyundai HGC (mismo formato que la base)
function bobinaNorm(v, tipo){
  v = Number(v); tipo = /dc|cc/i.test(tipo || '') ? 'DC' : 'AC';
  if (tipo === 'DC') return v + ' VDC';
  if (v <= 26) return '24 VAC';
  if (v >= 42 && v <= 48) return '48 VAC';
  if (v >= 100 && v <= 127) return '110-120 VAC';
  if (v >= 200 && v <= 240) return '220-240 VAC';
  if (v >= 380 && v <= 480) return '380-440 VAC';
  return v + ' VAC';
}

/* ---------- 6. Variantes: contactores Hyundai HGC con bobina ---------- */
const reHGC = /^HGC(\d+)(11|22)NS([AF])/;
function bobinasDeLista(desc){
  let m = desc.match(/disponible en ([\d,\sy]+)/i);
  if (m) return m[1].split(/[,\sy]+/).map(Number).filter(Boolean);
  m = desc.match(/Bobina Vac\/Vdc:\s*(.+?)\.\s*Rango/i);
  if (m) return [...m[1].matchAll(/(?:^|;\s*)(\d+):/g)].map(x => +x[1]);
  return [];
}
function bobinaDeNombre(modelo){
  if (/S\/B\s*$/i.test(modelo)) return 'sin bobina';
  const m = modelo.match(/(?:\b[AF]0?(24|48|110|220|440)|\b(24|48|110|220|440)\s*V?)\s*$/);
  return m ? +(m[1] || m[2]) : null;
}

/* ---------- 7. Armar series, SKU, ofertas ---------- */
const PROV_LISTA = { SCHNEIDER: 'EMI (lista Schneider)', INVT: 'SAER (lista INVT)' };
const series = new Map();        // clave → serie
const categorias = new Map();    // ruta slug → { nombre, padre, nivel, orden }
const privado = [];              // existencias propias

function addCategoria(nombres){
  let padre = null, ruta = '';
  nombres.forEach((n, i) => {
    ruta = ruta ? ruta + '/' + slug(n) : slug(n);
    if (!categorias.has(ruta)) categorias.set(ruta, { nombre: n, padre, nivel: i + 1, ruta, orden: 0 });
    padre = ruta;
  });
  return ruta;
}
// orden de familias y categorías = el de la tienda
T.FAMILIAS.forEach((f, i) => { addCategoria([f.nombre]); categorias.get(slug(f.nombre)).orden = i; f.categorias.forEach((c, j) => { addCategoria([f.nombre, c]); categorias.get(slug(f.nombre) + '/' + slug(c)).orden = j; }); });

const invPorModelo = new Map(foto.adm.filter(a => a.codigo).map(a => [T.claveModelo(a.codigo), a]));
let nVariantes = 0;

for (const p of productos){
  const ruta = T.rutaDe(p);
  const familia = ruta[0], categoria = ruta[1] || 'General', resto = ruta.slice(2);
  const sub = subcategoria(categoria, resto);
  // Se respetan TODAS las subcategorías originales de la tienda (series, tamaños, marcas…)
  const catRuta = addCategoria(ruta.length >= 2 ? ruta : [familia, categoria]);
  const serie = serieDe(categoria, resto);
  const specs = unirSpecs(atributosDe(p, categoria, sub, resto, serie), atributosExtra(p, categoria, resto));
  const marca = marcaLimpia(p.marca);

  // ¿variante de una serie con bobina?
  const mh = marca === 'HYUNDAI' && categoria === 'Contactores' && String(p.modelo).match(reHGC);
  const codigoSerie = mh ? 'HGC' + mh[1] + mh[2] + 'NS' + mh[3] : String(p.modelo).trim();
  const clave = marca + '|' + codigoSerie;
  let se = series.get(clave);
  if (!se){
    se = { clave, codigo: codigoSerie, marca, categoria: catRuta, nombre: '', descripcion: '', imagenes: [], skus: new Map() };
    series.set(clave, se);
  }
  const nombre = mh ? 'Contactor tripolar Hyundai ' + codigoSerie + (specs.corriente_ac3_a ? ' ' + specs.corriente_ac3_a + ' A' : '') : (p.nombre || p.modelo);
  if (!se.nombre || (p._manual && !mh)) se.nombre = nombre;
  if ((p.descripcion || '').length > se.descripcion.length) se.descripcion = p.descripcion || '';
  const imgs = (p.imagenes && p.imagenes.length ? p.imagenes : (p.imagen ? [p.imagen] : []));
  if (!se.imagenes.length && imgs.length) se.imagenes = imgs;

  // precios y ofertas
  const propio = p._manual ? Number(p.precio) || null : null;          // precio tuyo (sin descuento general)
  const delProveedor = !p._manual ? Number(p.precio) || null : (p._adm && p._adm.otro && p._adm.otro.fuente === 'Distribuidor' && !p._adm.otro._manual ? Number(p._adm.otro.precio) || null : null);
  const ofertas = [];
  if (!p._manual || delProveedor) ofertas.push({ proveedor: 'Grupo Eléctricos', precio_publico: delProveedor, disponible: p._inv ? true : p.disponible !== false });
  else if (!p._inv && !p._panel) ofertas.push({ proveedor: PROV_LISTA[marca] || 'Lista de precios ' + marca.charAt(0) + marca.slice(1).toLowerCase(), precio_publico: null, disponible: p.disponible !== false });

  const base = { specs, precio_lista: propio, ofertas, stock: p.stock || null, pedido: p.stock === 'pedido' };
  const inv = p._inv ? invPorModelo.get(T.claveModelo(p.modelo)) : null;

  let skusDe;
  if (mh){
    const deLista = /\(\*+\)|\*+$/.test(String(p.modelo).split(' ')[0]) && !p._inv ? bobinasDeLista(p.descripcion || '') : [];
    const propia = bobinaDeNombre(String(p.modelo));
    if (deLista.length) skusDe = deLista.map(v => ({ bob: v }));
    else skusDe = [{ bob: propia }];
    nVariantes++;
  } else skusDe = [{ bob: undefined }];

  for (const { bob } of skusDe){
    const sp = Object.assign({}, specs);
    let codigo = String(p.modelo).trim();
    if (mh){
      if (bob === 'sin bobina'){ codigo = codigoSerie + '/SB'; sp.bobina = 'Sin bobina'; }
      else if (bob){ codigo = codigoSerie + '/' + bob + 'V'; sp.bobina = bobinaNorm(bob, 'AC'); }
      else { codigo = codigoSerie; delete sp.bobina; }
    }
    const previo = se.skus.get(codigo);
    // si el mismo SKU viene de tu inventario y de la lista, gana tu inventario (precio y existencia)
    if (previo && !p._inv) continue;
    const sku = Object.assign({ codigo }, base, { specs: sp });
    if (previo){ sku.ofertas = previo.ofertas.concat(sku.ofertas); if (!sku.precio_lista) sku.precio_lista = previo.precio_lista; }
    se.skus.set(codigo, sku);
    if (inv && inv.inv) for (const [alm, d] of Object.entries(inv.inv)){
      const cant = Math.max(0, Math.round(Number(d.cant) || 0));
      if (cant > 0) privado.push({ codigo, almacen: alm === 'papa' ? 'Papá' : 'Manuel', cantidad: cant, costo: Number(d.costo) || null });
    }
  }
}

/* ---------- 8. Salida ---------- */
const salida = {
  generado: new Date().toISOString(),
  categorias: [...categorias.values()],
  atributos: Object.entries(ATRIBUTOS).map(([clave, [nombre, tipo, unidad]]) => ({ clave, nombre, tipo, unidad })),
  filtros: Object.entries(FILTROS).flatMap(([c, lista]) => {
    const fam = T.FAMILIAS.find(f => f.categorias.includes(c));
    const ruta = slug(fam.nombre) + '/' + slug(c);
    return lista.map(([clave, ob, dv], i) => ({ categoria: ruta, clave, orden: i, obligatorio: !!ob, define_variante: !!dv }));
  }).concat(
    // Dentro de Contactores, los auxiliares y los de estado sólido no tienen corriente AC3:
    // sus subcategorías originales llevan su propia definición (la más cercana manda).
    [...categorias.values()].filter(c => c.ruta.startsWith('control-de-motores/contactores/') && !/accesorio/i.test(c.ruta) && /auxiliar|estado s[oó]lido/i.test(c.nombre))
      .flatMap(c => (/auxiliar/i.test(c.nombre) ? [['contactos_aux', true], ['bobina', true], ['tamano'], ['serie']] : [['bobina'], ['serie']])
        .map(([clave, ob], i) => ({ categoria: c.ruta, clave, orden: i, obligatorio: !!ob, define_variante: false })))
  ),
  series: [...series.values()].map(s => ({ codigo: s.codigo, marca: s.marca, categoria: s.categoria, nombre: s.nombre, descripcion: s.descripcion, imagenes: s.imagenes, skus: [...s.skus.values()] })),
};
fs.mkdirSync(path.join(REPO, 'datos-beta'), { recursive: true });
fs.writeFileSync(path.join(REPO, 'datos-beta', 'carga.json'), JSON.stringify(salida));
fs.writeFileSync(PRIVADO, JSON.stringify(privado));

/* ---------- 9. Resumen ---------- */
const nSku = salida.series.reduce((n, s) => n + s.skus.length, 0);
console.log('Productos de la tienda:', productos.length);
console.log('Series:', salida.series.length, '· SKU:', nSku, '· series con variantes:', salida.series.filter(s => s.skus.length > 1).length);
console.log('Categorías:', salida.categorias.length, '· filtros definidos:', salida.filtros.length);
console.log('Existencias propias:', privado.length, 'filas');
const cobertura = {};
for (const s of salida.series) for (const k of s.skus){
  const c = s.categoria.split('/').slice(0, 2).join('/');
  if (/(^|\/)[^/]*accesorio/.test(s.categoria)) continue;
  let manda = s.categoria;
  while (manda && !salida.filtros.some(f => f.categoria === manda)) manda = manda.includes('/') ? manda.slice(0, manda.lastIndexOf('/')) : '';
  const defs = salida.filtros.filter(f => f.categoria === manda && f.obligatorio);
  if (!defs.length) continue;
  const ok = defs.every(f => (k.specs[f.clave] != null) || (k.specs[f.clave + '_min'] != null));
  cobertura[c] = cobertura[c] || [0, 0]; cobertura[c][0] += ok ? 1 : 0; cobertura[c][1]++;
}
for (const [c, [a, b]] of Object.entries(cobertura)) console.log('  completos', c.padEnd(52), a + '/' + b, Math.round(100 * a / b) + '%');
