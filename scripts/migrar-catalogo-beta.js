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

/* ---------- 4. Árbol de 3 niveles ---------- */
function subcategoria(categoria, resto){
  if (resto.some(s => /\baccesorios?\b/i.test(s))) return 'Accesorios';
  if (categoria === 'Contactores'){
    if (resto.some(s => /auxiliar/i.test(s))) return 'Auxiliares';
    if (resto.some(s => /estado s[oó]lido/i.test(s))) return 'Estado sólido';
    return 'De potencia';
  }
  return null;
}
// La serie del fabricante deja de ser categoría y pasa a ser un filtro
function serieDe(categoria, resto){
  if (/sensores de proximidad|finales de carrera|encoders/i.test(categoria)) return null;
  for (const s of resto){
    if (T.NODOS_MARCA.has(s) || /^accesorios?$/i.test(s) || /^otros/i.test(s)) continue;
    if (/^(tama[ñn]o|bobina|di[aá]metro|\d|[123] fases?|capacidad)/i.test(s)) continue;
    const m = s.match(/\bSerie\s+([A-Z0-9][\w\/-]*)/);
    const r = (m ? m[1] : s.split(' - ')[0].split(' (')[0]).trim();
    if (r && r.length <= 40) return r;
  }
  return null;
}

/* ---------- 5. Atributos técnicos ---------- */
const ATRIBUTOS = {   // clave: [nombre, tipo, unidad]
  serie:            ['Serie', 'lista', null],
  potencia_kw:      ['Potencia', 'numero', 'kW'],
  potencia_hp:      ['Potencia', 'numero', 'HP'],
  tension_v:        ['Tensión de alimentación', 'numero', 'V'],
  fases:            ['Fases de entrada', 'numero', null],
  corriente_a:      ['Corriente nominal', 'numero', 'A'],
  aplicacion:       ['Tipo de uso', 'lista', null],
  corriente_ac3_a:  ['Corriente AC3', 'numero', 'A'],
  bobina:           ['Tensión de bobina', 'lista', null],
  polos:            ['Polos', 'numero', null],
  contactos_aux:    ['Contactos auxiliares', 'lista', null],
  tamano:           ['Tamaño', 'lista', null],
  ajuste_a:         ['Rango de ajuste', 'rango', 'A'],
  clase:            ['Clase de disparo', 'lista', null],
  curva:            ['Curva', 'lista', null],
  poder_corte_ka:   ['Poder de corte', 'numero', 'kA'],
  disparador:       ['Disparador', 'lista', null],
  tipo_sensor:      ['Tipo de sensor', 'lista', null],
  rosca:            ['Rosca', 'lista', null],
  salida:           ['Salida', 'lista', null],
  distancia_mm:     ['Distancia de detección', 'numero', 'mm'],
  conexion:         ['Conexión', 'lista', null],
};
// Filtros por categoría, en orden. [clave, obligatorio, define_variante]
// Variadores y Arrancadores ya tienen sus propios filtros en la tienda: aquí solo se guardan los datos.
const FILTROS = {
  'Variadores de Frecuencia':    [['potencia_kw', true], ['potencia_hp'], ['tension_v', true], ['fases'], ['corriente_a'], ['aplicacion'], ['serie']],
  'Arrancadores Suaves':         [['corriente_a', true], ['serie']],
  'Contactores/Auxiliares':      [['contactos_aux', true], ['bobina', true], ['tamano'], ['serie']],
  'Contactores/Estado sólido':   [['bobina'], ['serie']],
  'Contactores':                 [['corriente_ac3_a', true], ['bobina', true, true], ['polos'], ['contactos_aux'], ['tamano'], ['serie']],
  'Guardamotores':               [['ajuste_a', true, true], ['tamano'], ['serie']],
  'Relés de Sobrecarga':         [['ajuste_a', true, true], ['clase'], ['tamano'], ['serie']],
  'Breakers Automáticos':        [['corriente_a', true], ['polos', true], ['curva'], ['poder_corte_ka'], ['serie']],
  'Breakers en Caja Moldeada':   [['corriente_a', true], ['polos', true], ['poder_corte_ka'], ['disparador'], ['serie']],
  'Sensores de Proximidad':      [['tipo_sensor', true], ['rosca'], ['salida'], ['distancia_mm'], ['conexion']],
  'Relés de Supervisión y Control': [['serie']],
  'PLC Básicos': [['serie']], 'PLC Avanzados': [['serie']], 'Paneles HMI': [['serie']],
  'Fuentes de Alimentación': [['serie']], 'Pulsadores y Pilotos': [['serie']],
};

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
const rangoDe = (t) => {
  const pats = [
    /(?:Regulaci[oó]n|Rango(?: de ajuste)?)\s*(?:\(A\))?\s*:?\s*(\d+(?:[.,]\d+)?)\s*(?:-|–|a)\s*(\d+(?:[.,]\d+)?)/i,
    /(\d+(?:[.,]\d+)?)\s*(?:\.{2,3}|…)\s*(\d+(?:[.,]\d+)?)\s*A\b/,
    /(\d+(?:[.,]\d+)?)\s*(?:–|-)\s*(\d+(?:[.,]\d+)?)\s*A\b/,
    /\b(\d+(?:[.,]\d+)?)\s*a\s*(\d+(?:[.,]\d+)?)\s*(?:A|Amp)\b/i,
  ];
  for (const re of pats){ const m = t.match(re); if (m){ const a = num(m[1]), b = num(m[2]); if (a != null && b != null && a < b) return [a, b]; } }
  return null;
};
const polosDe = (t) => {
  let m = t.match(/(\d)\s*polos?\b/i) || t.match(/polos\s*(\d)\b/i);
  if (m) return +m[1];
  if (/tetrapolar/i.test(t)) return 4; if (/tripolar/i.test(t)) return 3; if (/bipolar/i.test(t)) return 2; if (/monopolar|unipolar/i.test(t)) return 1;
  return null;
};

function atributosDe(p, categoria, sub, resto, serie){
  const s = {};
  if (serie) s.serie = serie;
  if (sub === 'Accesorios') return s;
  const t = [p.modelo, p.nombre !== p.modelo ? p.nombre : '', p.descripcion || ''].join(' ').replace(/\s+/g, ' ');
  const rutaTxt = resto.join(' > ');
  let m;
  if (categoria === 'Variadores de Frecuencia'){
    const v = T.extraerSpecsVfd(p);
    if (v){ if (v.kw) s.potencia_kw = v.kw; if (v.hp) s.potencia_hp = v.hp; if (v.v) s.tension_v = v.v; if (v.fase) s.fases = v.fase === 13 ? 1 : v.fase; if (v.a) s.corriente_a = v.a; if (v.uso != null) s.aplicacion = T.VFD_USOS[v.uso]; }
  } else if (categoria === 'Arrancadores Suaves'){
    const v = T.extraerSpecsArr(p);
    if (v && v.a) s.corriente_a = v.a;
  } else if (categoria === 'Contactores'){
    if ((m = t.match(/(\d+(?:[.,]\d+)?)\s*A\s*\(AC-?3\)/i)) || (m = t.match(/AC-?3\)?\s*(?:\(A\))?\s*:?\s*(\d+(?:[.,]\d+)?)\s*A?\b/i)) ||
        (m = String(p.modelo).match(/^HGC(\d+)(?:11|22)NS/)) || (m = t.match(/(\d+)\s*amperios/i)) || (m = rutaTxt.match(/(\d+(?:[.,]\d+)?)\s*Amp\b/i)))
      s.corriente_ac3_a = num(m[1]);
    if ((m = t.match(/(\d{2,3})\s*V\s*(AC|DC)\b/i)) || (m = t.match(/\b(AC|DC)\s*(\d{2,3})\s*V\b/i))){
      const v = /\d/.test(m[1]) ? m[1] : m[2], tipo = /\d/.test(m[1]) ? m[2] : m[1];
      s.bobina = bobinaNorm(v, tipo);
    }
    const pol = polosDe(t); if (pol) s.polos = pol; else if (sub === 'De potencia' && /tripolar|contactor de potencia/i.test(t)) s.polos = 3;
    if ((m = t.match(/(\d)\s*N[AO]\s*\+\s*(\d)\s*NC/i))) s.contactos_aux = m[1] + 'NA+' + m[2] + 'NC';
    if ((m = (t + ' ' + rutaTxt).match(/tama[ñn]o\s*(S\d{1,2})\b/i))) s.tamano = m[1].toUpperCase();
  } else if (categoria === 'Guardamotores' || categoria === 'Relés de Sobrecarga'){
    const r = rangoDe(t) || rangoDe(rutaTxt);
    if (r){ s.ajuste_a_min = r[0]; s.ajuste_a_max = r[1]; }
    if ((m = t.match(/clase\s*(\d{1,2})\b/i))) s.clase = 'Clase ' + m[1];
    if ((m = (t + ' ' + rutaTxt).match(/tama[ñn]o\s*(S\d{1,2})\b/i))) s.tamano = m[1].toUpperCase();
  } else if (categoria === 'Breakers Automáticos'){
    if ((m = t.match(/\b([BCD])\s?(\d{1,3})\s?A\b/))){ s.curva = m[1]; s.corriente_a = +m[2]; }
    if (!s.curva && (m = t.match(/curva\s*([BCD])\b/i))) s.curva = m[1].toUpperCase();
    if (!s.corriente_a && ((m = t.match(/\bIn\s*(?:\(A\))?\s*[:=]\s*(\d+)/i)) || (m = t.match(/(\d+)\s*amp\b/i)))) s.corriente_a = +m[1];
    const pol = polosDe(t); if (pol) s.polos = pol;
    if ((m = t.match(/(\d+(?:[.,]\d+)?)\s*kA/i))) s.poder_corte_ka = num(m[1]);
  } else if (categoria === 'Breakers en Caja Moldeada'){
    if ((m = t.match(/\bIn\s*(?:\(A\))?\s*[:=]\s*(\d+(?:[.,]\d+)?)/i))) s.corriente_a = num(m[1]);
    else if ((m = t.match(/(\d+)\s*-\s*(\d+)\s*A(?:mp)?\b/i))) s.corriente_a = +m[2];   // regulable: se toma el máximo
    const pol = polosDe(t); if (pol) s.polos = pol;
    if ((m = t.match(/Icu\s*=?\s*(\d+(?:[.,]\d+)?)\s*kA/i)) || (m = t.match(/Icu[^:]{0,30}\(kA\)\s*:\s*(\d+(?:[.,]\d+)?)/i)) || (m = t.match(/(\d+(?:[.,]\d+)?)\s*kA/i))) s.poder_corte_ka = num(m[1]);
    if (/electr[oó]nic/i.test(t)) s.disparador = 'Electrónico'; else if (/termomagn|TM-?D|\bTM\d/i.test(t)) s.disparador = 'Termomagnético'; else if (/magn[eé]tico/i.test(t)) s.disparador = 'Magnético';
  } else if (categoria === 'Sensores de Proximidad'){
    const tt = rutaTxt + ' ' + t;
    if ((m = tt.match(/inductiv|capacitiv|[oó]ptic|ultras[oó]nic|magn[eé]tic/i))){
      const k = m[0].toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
      s.tipo_sensor = { inductiv: 'Inductivo', capacitiv: 'Capacitivo', optic: 'Óptico', ultrasonic: 'Ultrasónico', magnetic: 'Magnético' }[k];
    }
    if ((m = tt.match(/Di[aá]metro\s*(8|12|18|30)\s*mm/i)) || (m = tt.match(/\bM(8|12|18|30)\b(?!\s*\/)/))) s.rosca = 'M' + m[1];
    if (/NPN\s*\/\s*PNP|PNP\s*\/\s*NPN/i.test(tt)) s.salida = 'PNP/NPN'; else if (/PNP/.test(tt)) s.salida = 'PNP'; else if (/NPN/.test(tt)) s.salida = 'NPN'; else if (/REL[EÉ]/i.test(tt)) s.salida = 'Relé';
    if ((m = t.match(/Sn:\s*(\d+(?:[.,]\d+)?)\s*(mm|mts?|m)\b/i))){ const v = num(m[1]); s.distancia_mm = /mm/i.test(m[2]) ? v : Math.round(v * 1000); }
    if ((m = tt.match(/conector\s*(M8|M12)/i))) s.conexion = 'Conector ' + m[1].toUpperCase(); else if (/cable/i.test(tt)) s.conexion = 'Cable';
  }
  for (const k of Object.keys(s)) if (s[k] == null || s[k] === '' || Number.isNaN(s[k])) delete s[k];
  return s;
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
  const catRuta = addCategoria([familia, categoria].concat(sub ? [sub] : []));
  const serie = serieDe(categoria, resto);
  const specs = atributosDe(p, categoria, sub, resto, serie);
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
    const [c2, c3] = c.split('/');
    const fam = T.FAMILIAS.find(f => f.categorias.includes(c2));
    const ruta = slug(fam.nombre) + '/' + slug(c2) + (c3 ? '/' + slug(c3) : '');
    return lista.map(([clave, ob, dv], i) => ({ categoria: ruta, clave, orden: i, obligatorio: !!ob, define_variante: !!dv }));
  }),
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
  const propias = salida.filtros.filter(f => f.categoria === s.categoria);
  const defs = (propias.length ? propias : salida.filtros.filter(f => f.categoria === c)).filter(f => f.obligatorio);
  if (!defs.length || s.categoria.endsWith('/accesorios')) continue;
  const ok = defs.every(f => (k.specs[f.clave] != null) || (k.specs[f.clave + '_min'] != null));
  cobertura[c] = cobertura[c] || [0, 0]; cobertura[c][0] += ok ? 1 : 0; cobertura[c][1]++;
}
for (const [c, [a, b]] of Object.entries(cobertura)) console.log('  completos', c.padEnd(52), a + '/' + b, Math.round(100 * a / b) + '%');
