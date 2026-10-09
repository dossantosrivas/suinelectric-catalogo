/* =====================================================================
   ESPECIFICACIONES TÉCNICAS DE LOS PRODUCTOS (una sola fuente)
   ---------------------------------------------------------------------
   Lee de la descripción y de los niveles de categoría los datos que el
   cliente usa para filtrar: amperaje, tensión de bobina, polos, HP,
   tensión de control, color, distancia de detección, etc.

   Lo usan:
     · tienda.html (en el navegador, al cargar): así un producto nuevo o una
       descripción editada entra en los filtros sin hacer nada más.
     · scripts/migrar-catalogo-beta.js y scripts/recalcular-atributos-beta.js
       (base de datos del catálogo único, beta).

   Para agregar un dato o un filtro: ATRIBUTOS (nombre, tipo, unidad),
   FILTROS (qué filtros ve cada categoría) y el extractor de su categoría.
   ===================================================================== */
(function (raiz, fabrica){
  const m = fabrica();
  if (typeof module === 'object' && module.exports) module.exports = m;
  else raiz.Especificaciones = m;
})(typeof self !== 'undefined' ? self : this, function (){

const ATRIBUTOS = {
  // (ya existían)
  serie:              ['Serie', 'lista', null],
  potencia_kw:        ['Potencia', 'numero', 'kW'],
  potencia_hp:        ['Potencia', 'numero', 'HP'],
  tension_v:          ['Tensión', 'numero', 'V'],
  fases:              ['Fases de entrada', 'numero', null],
  corriente_a:        ['Corriente nominal', 'numero', 'A'],
  aplicacion:         ['Tipo de uso', 'lista', null],
  corriente_ac3_a:    ['Corriente AC3', 'numero', 'A'],
  bobina:             ['Tensión de bobina', 'lista', null],
  polos:              ['Polos', 'numero', null],
  contactos_aux:      ['Contactos auxiliares', 'lista', null],
  tamano:             ['Tamaño', 'lista', null],
  ajuste_a:           ['Rango de ajuste', 'rango', 'A'],
  clase:              ['Clase de disparo', 'lista', null],
  curva:              ['Curva', 'lista', null],
  poder_corte_ka:     ['Poder de corte', 'numero', 'kA'],
  disparador:         ['Disparador', 'lista', null],
  tipo_sensor:        ['Tipo de sensor', 'lista', null],
  rosca:              ['Rosca', 'lista', null],
  salida:             ['Salida', 'lista', null],
  distancia_mm:       ['Distancia de detección', 'numero', 'mm'],
  conexion:           ['Conexión', 'lista', null],
  deteccion:          ['Modo de detección', 'lista', null],
  // (nuevos)
  tipo_equipo:        ['Tipo', 'lista', null],
  hp_220:             ['Motor a 220 V', 'numero', 'HP'],
  hp_440:             ['Motor a 440-460 V', 'numero', 'HP'],
  tension_control:    ['Tensión de control', 'lista', null],
  alimentacion:       ['Alimentación', 'lista', null],
  contactos:          ['Contactos', 'lista', null],
  color:              ['Color', 'lista', null],
  diametro:           ['Diámetro de montaje', 'lista', null],
  montaje:            ['Montaje', 'lista', null],
  ejecucion:          ['Ejecución', 'lista', null],
  clase_fusible:      ['Clase de fusible', 'lista', null],
  tension_salida_v:   ['Tensión de salida', 'numero', 'V DC'],
  corriente_salida_a: ['Corriente de salida', 'numero', 'A'],
  tension_entrada:    ['Tensión de entrada', 'lista', null],
  pantalla_pulg:      ['Pantalla', 'numero', 'pulg.'],
  resolucion:         ['Resolución', 'lista', null],
  eje_mm:             ['Diámetro del eje', 'numero', 'mm'],
  actuador:           ['Actuador', 'lista', null],
  envolvente:         ['Caja', 'lista', null],
  seccion_mm2:        ['Sección de cable', 'numero', 'mm²'],
  manguera_mm:        ['Manguera (Ø exterior)', 'numero', 'mm'],
  bus:                ['Red / protocolo', 'lista', null],
  magnitud:           ['Variable medida', 'lista', null],
};

// Variadores y Arrancadores Suaves tienen su panel propio en la tienda: aquí solo se guardan los datos.
const FILTROS = {
  'Variadores de Frecuencia':        [['potencia_kw', true], ['potencia_hp'], ['tension_v', true], ['fases'], ['corriente_a'], ['aplicacion'], ['serie']],
  'Arrancadores Suaves':             [['corriente_a', true], ['serie']],
  'Arrancadores de Motor':           [['ajuste_a'], ['tension_control'], ['tipo_equipo'], ['serie']],
  'Contactores':                     [['corriente_ac3_a', true], ['hp_220'], ['hp_440'], ['bobina', true, true], ['polos'], ['contactos_aux'], ['tamano'], ['serie']],
  'Guardamotores':                   [['ajuste_a', true, true], ['hp_220'], ['hp_440'], ['poder_corte_ka'], ['clase'], ['tamano'], ['serie']],
  'Relés de Sobrecarga':             [['ajuste_a', true, true], ['tipo_equipo'], ['montaje'], ['clase'], ['tamano'], ['serie']],
  'Relés de Supervisión y Control':  [['tipo_equipo', true], ['tension_control'], ['contactos'], ['serie']],
  'Breakers Automáticos':            [['corriente_a', true], ['polos', true], ['tipo_equipo'], ['curva'], ['poder_corte_ka'], ['serie']],
  'Breakers en Caja Moldeada':       [['corriente_a', true], ['polos', true], ['poder_corte_ka'], ['disparador'], ['serie']],
  'Breakers en Aire':                [['corriente_a', true], ['polos'], ['poder_corte_ka'], ['ejecucion'], ['serie']],
  'Breakers para Transferencia':     [['corriente_a', true], ['poder_corte_ka'], ['serie']],
  'Seccionadores':                   [['corriente_a', true], ['polos'], ['serie']],
  'Fusibles Ultrarrápidos':          [['tipo_equipo'], ['corriente_a', true], ['clase_fusible'], ['tamano'], ['tension_v'], ['serie']],
  'Sensores de Proximidad':          [['tipo_sensor', true], ['deteccion'], ['rosca'], ['distancia_mm'], ['salida'], ['contactos'], ['alimentacion'], ['conexion'], ['montaje']],
  'Finales de Carrera':              [['tipo_equipo'], ['actuador'], ['contactos'], ['envolvente'], ['serie']],
  'Encoders':                        [['tipo_equipo', true], ['resolucion'], ['eje_mm'], ['alimentacion']],
  'Instrumentación':                 [['magnitud', true], ['tipo_equipo'], ['serie']],
  'Pulsadores y Pilotos':            [['tipo_equipo', true], ['color'], ['contactos'], ['tension_control'], ['diametro'], ['serie']],
  'Balizas Luminosas y Acústicas':   [['tipo_equipo', true], ['color'], ['tension_control'], ['serie']],
  'Fuentes de Alimentación':         [['tension_salida_v', true], ['corriente_salida_a', true], ['tension_entrada'], ['serie']],
  'PLC Básicos':                     [['tipo_equipo', true], ['alimentacion'], ['salida'], ['serie']],
  'PLC Avanzados':                   [['tipo_equipo', true], ['alimentacion'], ['serie']],
  'PLC Allen Bradley':               [['tipo_equipo', true], ['serie']],
  'Periferia Descentralizada':       [['tipo_equipo', true], ['serie']],
  'Paneles HMI':                     [['pantalla_pulg'], ['tipo_equipo'], ['serie']],
  'SIMATIC NET':                     [['bus'], ['tipo_equipo'], ['serie']],
  'SCALANCE':                        [['tipo_equipo'], ['serie']],
  'Bornes de Conexión':              [['tipo_equipo'], ['seccion_mm2'], ['serie']],
  'Cableado y Accesorios para Tableros': [['tipo_equipo'], ['seccion_mm2']],
  'Neumática':                       [['tipo_equipo'], ['manguera_mm'], ['rosca']],
};

/* ---------- Utilidades ---------- */
const num = (s) => { if (s == null) return null; const v = parseFloat(String(s).replace(/\s/g, '').replace(',', '.').replace(/\.$/, '')); return isNaN(v) ? null : v; };
const sinTildes = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '');
const N = '(\\d+(?:[.,]\\d+)?)';

// Clase de tensión: '24 V', '110-127 V', '220-240 V'… con AC, DC o AC/DC
function claseTension(v){
  if (v == null) return null;
  if (v <= 6) return '5 V';
  if (v <= 14) return '12 V';
  if (v <= 30) return '24 V';
  if (v <= 50) return '48 V';
  if (v <= 70) return '60 V';
  if (v <= 140) return '110-127 V';
  if (v <= 260) return '220-240 V';
  if (v <= 500) return '380-480 V';
  return v + ' V';
}
function tipoCorriente(txt){
  const t = String(txt || '');
  if (/AC\s*\/\s*DC|DC\s*\/\s*AC|\bUC\b|VAC\s*\/\s*VDC|VCA\s*\/\s*VCC|\bAC-?DC\b/i.test(t)) return 'AC/DC';
  if (/\bV?DC\b|VCC\b|\bCC\b/i.test(t)) return 'DC';
  if (/\bV?AC\b|VCA\b|\bCA\b/i.test(t)) return 'AC';
  return null;
}
// Tensión "de mando": un valor o un rango; los rangos amplios (ej. 24-240 V) son "Universal"
function etiquetaTension(lo, hi, tipo){
  if (lo == null) return null;
  if (hi != null && hi > lo){
    const a = claseTension(lo), b = claseTension(hi);
    if (a !== b && hi / lo > 2.2) return 'Universal ' + Math.round(lo) + '-' + Math.round(hi) + ' V';
    lo = hi;   // 220-240 → clase de 240
  }
  const c = claseTension(lo);
  return tipo ? c + ' ' + tipo : c;
}
// Busca todas las tensiones en un texto, con su tipo cercano
function tensionesDe(t){
  const out = [];
  const re = new RegExp('(?:(AC|DC|UC)\\s*(?:\\/\\s*(AC|DC))?\\s*)?' + N + '(?:\\s*(?:\\.{2,3}|…|-|a|hasta|\\/)\\s*' + N + ')?\\s*V(AC|DC|CA|CC)?\\b(?:\\s*(AC\\s*\\/\\s*DC|AC|DC|UC))?', 'gi');
  let m;
  while ((m = re.exec(t))){
    const lo = num(m[3]), hi = m[4] ? num(m[4]) : null;
    if (lo == null || lo < 3 || lo > 1000) continue;
    const pre = (m[1] || '') + (m[2] ? '/' + m[2] : '');
    const tipo = tipoCorriente(pre + ' V' + (m[5] || '') + ' ' + (m[6] || ''));
    out.push({ lo, hi: hi && hi > lo ? hi : null, tipo, i: m.index });
  }
  return out;
}
function hpDe(t, s){
  let m;
  // Hyundai: "2 HP/230V, 5 HP/460V"
  const reH = new RegExp(N + '\\s*HP\\s*\\/\\s*(\\d{3})\\s*V', 'gi');
  while ((m = reH.exec(t))){ const v = num(m[1]), vol = +m[2]; if (vol <= 260){ if (s.hp_220 == null) s.hp_220 = v; } else if (s.hp_440 == null) s.hp_440 = v; }
  // Schneider: "Potencia HP 220/440 V: 3/5.5" y "HP 220 V: 7.5. HP 440 V: 15."
  if ((m = t.match(new RegExp('Potencia HP 220\\s*\\/\\s*440\\s*V\\s*:\\s*' + N + '\\s*\\/\\s*' + N, 'i')))){ s.hp_220 = num(m[1]); s.hp_440 = num(m[2]); }
  if ((m = t.match(new RegExp('HP 220 V\\s*:\\s*' + N, 'i')))) s.hp_220 = num(m[1]);
  if ((m = t.match(new RegExp('HP 440 V\\s*:\\s*' + N, 'i')))) s.hp_440 = num(m[1]);
  // Siemens: "4 kW/400 V" → HP a 440 V aproximado
  if (s.hp_440 == null && (m = t.match(new RegExp(N + '\\s*kW\\s*\\/\\s*(380|400|415)\\s*V', 'i')))) s.hp_440 = Math.round(num(m[1]) * 1.341 * 2) / 2;
  if (s.hp_220 != null && !(s.hp_220 > 0)) delete s.hp_220;
  if (s.hp_440 != null && !(s.hp_440 > 0)) delete s.hp_440;
}
function contactosDe(t){
  let m;
  if ((m = t.match(/(\d)\s*N[AO]\s*\+\s*(\d)\s*N[CF]/i))) return m[1] + 'NA+' + m[2] + 'NC';
  if ((m = t.match(/(\d)\s*N[AO]\s*\/\s*(\d)\s*N[CF]/i))) return m[1] + 'NA+' + m[2] + 'NC';
  if (/\bNA\s*\/\s*NC\b|\bNO\s*\/\s*NC\b|\bNO-NC\b/i.test(t)) return '1NA+1NC';
  if ((m = t.match(/(\d)\s*(?:conmutados?|inversores?|CO\b)/i))) return m[1] + ' conmutado' + (m[1] > 1 ? 's' : '');
  if (/\bconmutado\b/i.test(t)) return '1 conmutado';
  if ((m = t.match(/(\d)\s*N[AO]\b/i))) return m[1] + 'NA';
  if ((m = t.match(/(\d)\s*N[CF]\b/i))) return m[1] + 'NC';
  if (/\bNC\b/.test(t) && !/\bN[AO]\b/.test(t)) return '1NC';
  if (/\bN[AO]\b/.test(t)) return '1NA';
  return null;
}
const COLORES = [['rojo', 'Rojo'], ['verde', 'Verde'], ['amarill', 'Amarillo'], ['azul', 'Azul'], ['blanc', 'Blanco'], ['negro', 'Negro'],
  ['naranja', 'Naranja'], ['gris', 'Gris'], ['transparente|incoloro', 'Transparente'],
  ['\\bred\\b', 'Rojo'], ['\\bgreen\\b', 'Verde'], ['\\byellow\\b', 'Amarillo'], ['\\bblue\\b', 'Azul'], ['\\bwhite\\b', 'Blanco'], ['\\bblack\\b', 'Negro']];
function colorDe(t){
  const s = sinTildes(t).toLowerCase();
  const enc = COLORES.map(([re, n]) => { const m = s.match(new RegExp(re)); return m ? [m.index, n] : null; }).filter(Boolean).sort((a, b) => a[0] - b[0]);
  return enc.length ? enc[0][1] : null;
}
const polosDe = (t) => {
  let m = t.match(/(\d)\s*polos?\b/i) || t.match(/polos\s*:?\s*(\d)\b/i) || t.match(/\b(\d)P\b/);
  if (m) return +m[1];
  if (/tetrapolar/i.test(t)) return 4; if (/tripolar/i.test(t)) return 3; if (/bipolar/i.test(t)) return 2; if (/monopolar|unipolar/i.test(t)) return 1;
  return null;
};
const esAccesorio = (resto) => resto.some(s => /\baccesorios?\b/i.test(s));

/* ---------- Extractores por categoría ----------
   p = { modelo, nombre, descripcion }; resto = niveles de categoría debajo de la categoría.
   Devuelve solo lo que encontró. */
function atributosExtra(p, categoria, resto){
  const s = {};
  resto = resto || [];
  const t = [p.modelo, p.nombre && p.nombre !== p.modelo ? p.nombre : '', p.descripcion || ''].join(' ').replace(/\s+/g, ' ');
  const rutaTxt = resto.join(' > ');
  const tt = rutaTxt + ' ' + t;
  const acc = esAccesorio(resto);
  const sub0 = resto.find(x => !/^(siemens|schneider|hyundai|phoenix contact|kinco|festo|datalogic|allen bradley)$/i.test(x)) || '';
  let m;

  switch (categoria){

  case 'Contactores': {
    if (acc) break;
    hpDe(t, s);
    // tensión de bobina cuando la descripción la dice claramente
    if ((m = t.match(new RegExp('(?:Tensi[oó]n de bobina|mando por|bobina)[^.\\d]{0,20}' + N + '(?:\\s*(?:-|\\.{2,3}|…)\\s*' + N + ')?\\s*V\\s*(AC\\s*\\/\\s*DC|AC|DC|UC)?', 'i')))){
      const tipoPre = tipoCorriente(t.slice(Math.max(0, m.index), m.index + m[0].length + 4));
      const lo = num(m[1]), hi = m[2] ? num(m[2]) : null;
      if (lo && lo >= 12) s._bobina = etiquetaBobina(hi || lo, tipoPre || 'AC');
    }
    if (!s._bobina && (m = t.match(/(\d{2,3})\s*-\s*(\d{2,3})\s*V\s*(AC\s*\/\s*DC|UC)/i))) s._bobina = etiquetaBobina(+m[2], 'AC/DC');
    // Schneider: la letra final del código es la bobina (LC1D09M7 = 220 V AC, LC1D09BD = 24 V DC)
    if ((m = String(p.modelo).trim().match(/^(?:LC1|LC2|LP1|CAD|LC1F|LC1DT|LC1K|CA2K)\w*?([BEFMPUQVRN])([7567D])$/))){
      const v = { B: 24, E: 48, F: 110, M: 220, P: 230, U: 240, Q: 380, V: 400, R: 440, N: 415 }[m[1]];
      if (v) s._bobina = etiquetaBobina(v, m[2] === 'D' ? 'DC' : 'AC');
    }
    break;
  }

  case 'Guardamotores': {
    if (acc) break;
    hpDe(t, s);
    if ((m = t.match(new RegExp('Icu\\s*440\\s*V\\s*\\(kA\\)\\s*:\\s*' + N, 'i'))) || (m = t.match(new RegExp(N + '\\s*kA\\s*\\/\\s*4[48]0\\s*V', 'i')))) s.poder_corte_ka = num(m[1]);
    break;
  }

  case 'Relés de Sobrecarga': {
    if (acc) break;
    if (/electr[oó]nic/i.test(tt)) s.tipo_equipo = 'Electrónico';
    else if (/t[eé]rmic|bimet/i.test(tt)) s.tipo_equipo = 'Térmico (bimetálico)';
    if (/instalaci[oó]n independiente|montaje independiente|separad/i.test(t)) s.montaje = 'Independiente';
    else if (/montar en contactor|sobre contactor|para contactor|Montaje sobre contactor/i.test(t)) s.montaje = 'Sobre contactor';
    break;
  }

  case 'Relés de Supervisión y Control': {
    const r = sinTildes(rutaTxt + ' ' + t.slice(0, 90)).toLowerCase();
    if (/^\S*\s*(zocalo|base enchufable|base para|socket)/.test(sinTildes(String(p.descripcion || '')).toLowerCase().trim())) s.tipo_equipo = 'Zócalo / base';
    else if (/temporizador|retardad|on-delay|off-delay/.test(r)) s.tipo_equipo = 'Temporizador';
    else if (/estado solido|\bssr\b|estatico|3rf/.test(r)) s.tipo_equipo = 'Estado sólido (SSR)';
    else if (/seguridad|3tk/.test(r)) s.tipo_equipo = 'Relé de seguridad';
    else if (/supervision|3ug|vigilancia|nivel|secuencia de fases|asimetria/.test(r)) s.tipo_equipo = 'Supervisión (tensión, fases, nivel)';
    else if (/acoplador|interfaz|enchufable|lzx|lzs|clavija|bornera|pines/.test(r)) s.tipo_equipo = 'Relé de interfaz / enchufable';
    else if (/control|hgr|contactor auxiliar/.test(r)) s.tipo_equipo = 'Relé de control';
    else if (/convertidor/.test(r)) s.tipo_equipo = 'Convertidor de señal';
    if (s.tipo_equipo !== 'Zócalo / base' && !/^Supervisi/.test(s.tipo_equipo || '')){
      const ts = tensionesDe(t).filter(x => !(x.lo >= 380 && /carga|ppal|principal/i.test(t.slice(Math.max(0, x.i - 25), x.i))));
      const tc = ts.find(x => /cnt|control|mando|alimentaci|bobina|US:/i.test(t.slice(Math.max(0, x.i - 25), x.i))) || ts[0];
      if (tc){
        const ampl = ts.length > 1 && ts.some(x => claseTension(x.hi || x.lo) !== claseTension(tc.hi || tc.lo)) && /universal|multi/i.test(t);
        s.tension_control = ampl ? 'Universal / multitensión' : etiquetaTension(tc.lo, tc.hi, tc.tipo || tipoCorriente(t));
      }
      const c = contactosDe(t); if (c) s.contactos = c;
    }
    break;
  }

  case 'Breakers Automáticos': {
    if (acc) break;
    if (/diferencial|RCBO|RCCB|\bmA\b/i.test(tt)) s.tipo_equipo = 'Diferencial';
    else if (/magnetot[eé]rmic|autom[aá]tico|curva/i.test(tt)) s.tipo_equipo = 'Termomagnético';
    if ((m = t.match(/\b([BCD])\s?(\d{1,3})\b(?!\s*(?:kA|mm))/)) && !s.corriente_a){ /* lo toma el extractor base */ }
    break;
  }

  case 'Breakers en Aire': {
    if (acc) break;
    if ((m = t.match(/In\s*=\s*(\d+)\s*A/i))) s.corriente_a = +m[1];
    else if ((m = t.match(/Amperaje:\s*(\d+)\s*-\s*(\d+)\s*A/i))){ s.corriente_a = +m[2]; s.ajuste_a_min = +m[1]; s.ajuste_a_max = +m[2]; }
    const pol = polosDe(t); if (pol) s.polos = pol;
    if ((m = t.match(new RegExp('Icu\\s*=?\\s*' + N + '\\s*kA', 'i'))) || (m = t.match(new RegExp('ruptura:\\s*' + N + '\\s*kA', 'i')))) s.poder_corte_ka = num(m[1]);
    if (/extra[ií]ble/i.test(t)) s.ejecucion = 'Extraíble'; else if (/fij[oa]/i.test(t)) s.ejecucion = 'Fijo';
    break;
  }

  case 'Breakers para Transferencia': {
    if ((m = t.match(/In\s*=\s*(\d+)\s*A/i)) || (m = t.match(/tama[ñn]o\s*(\d{3,4})/i))) s.corriente_a = +m[1];
    const mm = String(p.modelo).match(/3VA27(\d{2})/); if (mm) s.corriente_a = { '10': 1000, '12': 1250, '16': 1600, '80': 800, '63': 630 }[mm[1]] || s.corriente_a;
    if ((m = t.match(new RegExp('Icu\\s*=\\s*' + N + '\\s*kA', 'i')))) s.poder_corte_ka = num(m[1]);
    break;
  }

  case 'Seccionadores': {
    if (acc) break;
    if ((m = t.match(/Iu\s*:?\s*(\d+)\s*A/i)) || (m = t.match(/(\d+)\s*A\b/))) s.corriente_a = +m[1];
    const pol = polosDe(t); if (pol) s.polos = pol;
    break;
  }

  case 'Fusibles Ultrarrápidos': {
    if (acc) break;
    s.tipo_equipo = /seccionador/i.test(t) ? 'Fusible-seccionador' : 'Cartucho fusible';
    if ((m = t.match(/Entrada:\s*(\d+)\s*A/i)) || (m = t.match(/NH\d*\s+(\d+)\s*A\b/i)) || (m = t.match(/(\d+)\s*A\b/))) s.corriente_a = +m[1];
    if ((m = t.match(/\b\d+\s*A\s+(aR|gR|gS|gG|aM)\b/))) s.clase_fusible = m[1];
    else if ((m = rutaTxt.match(/SITOR\s+(aR|gR|gS)/))) s.clase_fusible = m[1];
    if ((m = t.match(/\bNH\s?(000|00|0|1|2|3|4)\b/i))) s.tamano = 'NH' + m[1];
    if ((m = t.match(/Un AC:\s*(\d+)\s*V/i))) s.tension_v = +m[1];
    break;
  }

  case 'Sensores de Proximidad': {
    if (acc || /^conector/i.test(resto[0] || '')) break;
    // Los niveles del proveedor ya dicen alimentación, conexión y salida: "Alimentación VAC / VDC", "PNP - NO/NC"
    const r = rutaTxt + ' | ' + t;
    if (/Alimentaci[oó]n\s*VAC\s*\/?\s*VDC|VAC\s*\/\s*VDC|AC\s*\/\s*DC|VAC\/VDC/i.test(r)) s.alimentacion = 'AC/DC (universal)';
    else if (/Alimentaci[oó]n\s*VAC\b/i.test(rutaTxt)) s.alimentacion = 'AC';
    else if (/Alimentaci[oó]n\s*VDC\b/i.test(rutaTxt)) s.alimentacion = 'DC (10-30 V)';
    else {
      const ts = tensionesDe(t);
      if (ts.length){ const tipo = ts[0].tipo || tipoCorriente(t); s.alimentacion = tipo === 'AC/DC' ? 'AC/DC (universal)' : tipo === 'AC' ? 'AC' : 'DC (10-30 V)'; }
    }
    if (/no\s+rasante|no\s+enrasado|non\s*flush/i.test(t)) s.montaje = 'No rasante';
    else if (/rasante|enrasado|\bflush/i.test(t)) s.montaje = 'Rasante';
    if (/N[AO]\s*\/\s*NC|NO-NC|N[AO]\s*\+\s*NC/i.test(r)) s.contactos = 'NA/NC (programable)';
    else if (/REL[EÉ]/i.test(rutaTxt)) s.contactos = 'Relé (conmutado)';
    else if (/-\s*NC\b/.test(rutaTxt) || (/\bNC\b/.test(t) && !/\bN[AO]\b/.test(t))) s.contactos = 'NC';
    else if (/\bN[AO]\b/.test(r)) s.contactos = 'NA';
    if (/2\s*hilos/i.test(r) && !s.salida) s.salida = '2 hilos';
    if (/[oó]ptic/i.test(resto[0] || '')){
      const d = resto.find(x => /reflex|proximidad|barrera|contraste|fibra|horquilla|difus|color|laser/i.test(x)) || (/fibra/i.test(t) ? 'Fibra óptica' : '');
      if (d) s.deteccion = /polariz/i.test(d) ? 'Reflex polarizado' : /reflex/i.test(d) ? 'Reflex (con reflector)' : /barrera/i.test(d) ? 'Barrera (emisor + receptor)'
        : /proximidad|difus/i.test(d) ? 'Difuso (por proximidad)' : /contraste/i.test(d) ? 'Contraste / marcas' : /fibra/i.test(d) ? 'Fibra óptica' : /horquilla/i.test(d) ? 'Horquilla' : d;
    }
    break;
  }

  case 'Finales de Carrera': {
    const r = sinTildes(t).toLowerCase();
    if (acc || /^cabeza|cabeza de accionamiento|cabezal/.test(r)) s.tipo_equipo = 'Cabeza / actuador suelto';
    else if (/elemento de contacto/.test(r)) s.tipo_equipo = 'Bloque de contactos';
    else if (/seguridad|bisagra|lengueta|cerradura/.test(sinTildes(rutaTxt + ' ' + t).toLowerCase())) s.tipo_equipo = 'Interruptor de seguridad';
    else s.tipo_equipo = 'Interruptor de posición completo';
    if (/rodillo/.test(r)) s.actuador = /palanca/.test(r) ? 'Palanca con rodillo' : 'Vástago con rodillo';
    else if (/varilla|muelle|resorte/.test(r)) s.actuador = 'Varilla elástica';
    else if (/palanca/.test(r)) s.actuador = 'Palanca';
    else if (/vastago|embolo|piston/.test(r)) s.actuador = 'Vástago / émbolo';
    else if (/fraccion de vuelta|giratori/.test(r)) s.actuador = 'Giratorio';
    else if (/bisagra/.test(r)) s.actuador = 'Bisagra';
    else if (/lengueta/.test(r)) s.actuador = 'Lengüeta (llave)';
    const c = contactosDe(t); if (c) s.contactos = c;
    if (/metal/i.test(tt)) s.envolvente = 'Metálica'; else if (/pl[aá]stic|aislante/i.test(tt)) s.envolvente = 'Plástica';
    break;
  }

  case 'Encoders': {
    if (acc || /acoplador|conector/i.test(t)) { s.tipo_equipo = 'Accesorio'; break; }
    s.tipo_equipo = /absolut/i.test(tt) ? 'Absoluto' : 'Incremental';
    if ((m = t.match(/(\d{2,5})\s*(?:imp\.?|I\/V|ppr|pulsos)/i))) s.resolucion = (+m[1]) + ' pulsos/vuelta';
    else if ((m = t.match(/(\d{1,2})\s*Bit\s*=\s*(\d+)/i))) s.resolucion = m[1] + ' bit (' + m[2] + ' pasos)';
    if ((m = t.match(/eje\s*(\d{1,2})\s*mm/i))) s.eje_mm = +m[1];
    const ts = tensionesDe(t); if (ts.length) s.alimentacion = Math.round(ts[0].lo) + '-' + Math.round(ts[0].hi || ts[0].lo) + ' V DC';
    break;
  }

  case 'Instrumentación': {
    const r = sinTildes(rutaTxt + ' ' + t).toLowerCase();
    const mag = (resto[0] || '').trim();
    if (/caudal|flujo/.test(sinTildes(mag).toLowerCase()) || (!mag && /caudal|flujo|mag\s?\d/.test(r))) s.magnitud = 'Caudal';
    else if (/nivel/.test(sinTildes(mag).toLowerCase()) || (!mag && /nivel/.test(r))) s.magnitud = 'Nivel';
    else if (/presion/.test(sinTildes(mag).toLowerCase()) || (!mag && /presion|manometro/.test(r))) s.magnitud = 'Presión';
    else if (/temperatura/.test(sinTildes(mag).toLowerCase()) || (!mag && /temperatura|pt100|termocupla/.test(r))) s.magnitud = 'Temperatura';
    else if (/posicionador/.test(sinTildes(mag).toLowerCase())) s.magnitud = 'Posición (válvulas)';
    else if (mag) s.magnitud = mag;
    const sub = (resto[1] || '').trim();
    if (acc) s.tipo_equipo = 'Accesorio';
    else if (/transmisor|continuo/i.test(sub + ' ' + t.slice(0, 60))) s.tipo_equipo = 'Transmisor (señal continua)';
    else if (/interruptor|switch/i.test(sub + ' ' + t.slice(0, 60))) s.tipo_equipo = 'Interruptor (punto fijo)';
    else if (/convertidor/i.test(sub + ' ' + t.slice(0, 60))) s.tipo_equipo = 'Convertidor de señal';
    else if (/control/i.test(sub)) s.tipo_equipo = 'Controlador';
    else if (/elemento|pt100|termocupla/i.test(sub)) s.tipo_equipo = 'Elemento sensor';
    else if (/medidor/i.test(sub)) s.tipo_equipo = 'Medidor';
    break;
  }

  case 'Pulsadores y Pilotos': {
    const r = sinTildes(t).toLowerCase();
    const head = sinTildes(String(p.descripcion || p.nombre || '')).toLowerCase().trim().slice(0, 70);
    if (/^lampara de senalizacion|^piloto/.test(head)) s.tipo_equipo = 'Piloto / lámpara de señalización';
    else if (/^(lampara|bombillo|led)/.test(head)) s.tipo_equipo = 'Lámpara / bombillo';
    else if (/^(caja|estacion)/.test(head)) s.tipo_equipo = 'Caja / estación de mando';
    else if (/^(tapon|portalampara|soporte|contacto|bloque|elemento|placa|etiqueta|capuchon|cabezal|cuerpo|accionamiento|protector|collar)/.test(head) && !/completo/.test(head)) s.tipo_equipo = 'Accesorio / repuesto';
    else if (/hongo|emergencia|seta|parada de emerg/.test(r)) s.tipo_equipo = 'Parada de emergencia (hongo)';
    else if (/selector|muletilla|manija|llave/.test(r)) s.tipo_equipo = 'Selector';
    else if (/doble/.test(r) && /pulsador/.test(r)) s.tipo_equipo = 'Pulsador doble';
    else if (/pulsador luminoso/.test(r)) s.tipo_equipo = 'Pulsador luminoso';
    else if (/piloto|lampara de senalizacion|senalizacion|indicador/.test(r)) s.tipo_equipo = 'Piloto / lámpara de señalización';
    else if (/pulsador|boton/.test(r)) s.tipo_equipo = 'Pulsador';
    else if (/^lampara|bombillo|ba ?9s/.test(r) || /lampara/i.test(rutaTxt)) s.tipo_equipo = 'Lámpara / bombillo';
    else if (acc) s.tipo_equipo = 'Accesorio / repuesto';
    const col = colorDe(t); if (col) s.color = col;
    const c = contactosDe(t); if (c && !/lampara|piloto/i.test(s.tipo_equipo || '')) s.contactos = c;
    if (/luminos|piloto|lampara|senalizacion|led/.test(r)){
      const ts = tensionesDe(t); if (ts.length) s.tension_control = etiquetaTension(ts[0].lo, ts[0].hi, ts[0].tipo || tipoCorriente(t));
    }
    if ((m = t.match(/(?:ø|Ø|diam(?:etro)?\.?\s*|\b)(22|30|16)\s*mm/i))) s.diametro = m[1] + ' mm';
    break;
  }

  case 'Balizas Luminosas y Acústicas': {
    const r = sinTildes(t).toLowerCase();
    const head = sinTildes(String(p.descripcion || '')).toLowerCase().trim().slice(0, 60);
    if (/^(escuadra|soporte|tubo|pata|tapa|base|adaptador)|elementos de conexion/.test(head)) s.tipo_equipo = 'Accesorio de montaje';
    else if (/^(led zocalo|led |lampara incand|bombillo|lampara led)/.test(head) || /lampara/i.test(rutaTxt)) s.tipo_equipo = 'Lámpara de repuesto';
    else if (/giratori|rotativ/.test(r)) s.tipo_equipo = 'Baliza giratoria';
    else if (/sirena|acustic|\d+\s*db\b|multitono|(?<!sin )zumbador/.test(r) && !/luz|luminos/.test(head)) s.tipo_equipo = 'Sirena / acústico';
    else if (/intermitente|destell|flash/.test(r)) s.tipo_equipo = 'Luz intermitente';
    else if (/columna|elemento|luz permanente|baliza|luminos|omnidir/.test(r)) s.tipo_equipo = 'Luz permanente / columna';
    else if (acc) s.tipo_equipo = 'Accesorio de montaje';
    const col = colorDe(t); if (col) s.color = col;
    const ts = tensionesDe(t); if (ts.length) s.tension_control = etiquetaTension(ts[0].lo, ts[0].hi, ts[0].tipo || tipoCorriente(t));
    break;
  }

  case 'Fuentes de Alimentación': {
    if ((m = t.match(new RegExp('salida:\\s*DC\\s*' + N + '(?:\\s*-\\s*' + N + ')?\\s*V\\s*\\/\\s*' + N + '\\s*A', 'i'))) || (m = t.match(new RegExp(N + '\\s*V\\s*\\/\\s*()' + N + '\\s*A', 'i')))){
      s.tension_salida_v = num(m[2] || m[1]); s.corriente_salida_a = num(m[3]);
      if (m[2]) s.tension_salida_v = 'ajustable';
    }
    if (s.tension_salida_v === 'ajustable') delete s.tension_salida_v;
    if ((m = t.match(/entrada:\s*([^s]*?)salida/i))){
      const e = m[1];
      const ts = tensionesDe(e).map(x => x.hi || x.lo);
      const max = Math.max(...ts.concat([0]));
      s.tension_entrada = max > 300 ? 'Trifásica / amplio (hasta ' + Math.round(max) + ' V)' : (/DC/i.test(e) ? 'AC 100-240 V o DC' : 'AC 120/230 V');
    }
    break;
  }

  case 'PLC Básicos': case 'PLC Avanzados': case 'PLC Allen Bradley': case 'Periferia Descentralizada': {
    // Primero los niveles del proveedor (CPU, Expansiones Digitales > Salidas, Memorias…); si no dicen, la descripción.
    const niv = sinTildes(resto.join(' > ')).toLowerCase();
    const head = sinTildes(String(p.descripcion || p.nombre || '').slice(0, 80)).toLowerCase();
    const T_ = (x) => { s.tipo_equipo = x; };
    const ES = (txt) => /analogic/.test(txt) ? 'E/S analógicas'
      : /entradas\s*\/\s*salidas|e\/s/.test(txt) ? 'E/S digitales'
      : /entradas/.test(txt) ? 'Entradas digitales' : /salidas/.test(txt) ? 'Salidas digitales' : 'E/S digitales';
    if (/kit de aprendizaje/.test(niv)) T_('Kit de aprendizaje');
    else if (/software/.test(niv)) T_('Software');
    else if (/memoria/.test(niv)) T_('Memoria');
    else if (/bateria/.test(niv)) T_('Accesorio');
    else if (/\bcpu\b|controllogix/.test(niv)) T_('CPU / controlador');
    else if (/comunicacion/.test(niv)) T_('Comunicación / interfaz');
    else if (/fuente/.test(niv)) T_('Fuente de alimentación');
    else if (/panel/.test(niv)) T_('Panel de operador');
    else if (/tarjetas especiales/.test(niv)) T_('Módulo especial (pesaje, posicionamiento)');
    else if (/expansion|entradas|salidas/.test(niv)) T_(/expansion/.test(niv) && !/digital|analogic|entradas|salidas/.test(niv) ? 'E/S digitales' : ES(niv));
    else if (/accesorio|cable|base|perfil|conector|ampliacion/.test(niv)) T_('Accesorio');
    // sin nivel que lo diga: por la descripción
    else if (/software|licencia|step ?7|tia.?portal|soft comfort/.test(head)) T_('Software');
    else if (/\bcpu\b|modulo logico|mod\. logico|modulo central|procesador/.test(head)) T_('CPU / controlador');
    else if (/memoria|memory|cartucho/.test(head)) T_('Memoria');
    else if (/fuente|power supply|\bps ?\d/.test(head)) T_('Fuente de alimentación');
    else if (/interfa|\bcp ?\d|\bim ?\d|profibus|profinet|ethernet|comunicac/.test(head)) T_('Comunicación / interfaz');
    else if (/analogic|\bai ?\d|\baq ?\d|\bao ?\d|termopar|\b(ie|oe)\d/.test(head + ' ' + sinTildes(p.modelo).toLowerCase())) T_('E/S analógicas');
    else if (/entradas digitales|\bdi ?\d|-ib\d/.test(head + ' ' + sinTildes(p.modelo).toLowerCase())) T_('Entradas digitales');
    else if (/salidas digitales|\bdq ?\d|\bdo\b|-o[bmw]\d/.test(head + ' ' + sinTildes(p.modelo).toLowerCase())) T_('Salidas digitales');
    else if (/digital|\bdm ?\d|e\/s/.test(head)) T_('E/S digitales');
    else if (/base|bastidor|perfil|riel|conector|cable|terminal|-tb\d/.test(head + ' ' + sinTildes(p.modelo).toLowerCase())) T_('Accesorio');

    if (categoria !== 'Periferia Descentralizada' && /CPU|E\/S|Entradas|Salidas|Fuente/i.test(s.tipo_equipo || '')){
      const ali = /alimentacion 24 vdc/.test(niv) ? '24 V DC' : /alimentacion 85/.test(niv) ? 'AC 115/230 V'
                : /alimentaci[oó]n:\s*AC|AC\/DC\/rel|\b230\s*RC|\bAC 85-264|110\/220 VAC|entrada: AC/i.test(t) ? 'AC 115/230 V'
                : /12\s*\/\s*24\s*R|12\/24/i.test(t) ? '12/24 V DC'
                : /DC\s*24\s*V|24\s*V\s*DC|24 ?VDC|\b24 ?R?C?E?O?\b.*LOGO|24 V\/24 V/i.test(t) ? '24 V DC' : null;
      if (ali && !/^Entradas|^E\/S anal/.test(s.tipo_equipo)) s.alimentacion = ali;
      if (/CPU|E\/S digitales|Salidas digitales/.test(s.tipo_equipo)){
        if (/rel[eé]|\/R\b|\dR\b|RCE?O?\b|\brele\b/i.test(t)) s.salida = 'Relé';
        else if (/transistor|trans\.|DC\/DC\/DC|\bDQ\b|DC\s*24V\/0?5A/i.test(t)) s.salida = 'Transistor';
      }
    }
    break;
  }

  case 'Paneles HMI': {
    const niv = sinTildes(rutaTxt).toLowerCase(), ini = t.slice(0, 90);
    if (/memoria/.test(niv)) s.tipo_equipo = 'Memoria';
    else if (/software/.test(niv)) s.tipo_equipo = 'Software';
    else if (/lamina/.test(niv) || /l[aá]mina/i.test(ini)) s.tipo_equipo = 'Lámina protectora';
    else if (/PLC con HMI|controlador programable|controlador .{0,20}panel de operador/i.test(t)) s.tipo_equipo = 'PLC + HMI integrado';
    else if (/panel|pantalla HMI|touchpanel|\b(K?TP|KP|MP|OP)\s?\d{2,4}/i.test(ini)){
      s.tipo_equipo = /t[aá]ctil|touch|sensible al tacto|\bK?TP\s?\d|\bMP\s?\d/i.test(t) ? 'Pantalla táctil' : 'Con teclado';
      if ((m = t.match(/(\d{1,2}(?:[.,]\d)?)\s*(?:"|''|”|pulg)/))) s.pantalla_pulg = num(m[1]);
      if (s.pantalla_pulg > 24) s.pantalla_pulg = s.pantalla_pulg / 10;   // "57\"" en la lista = 5,7"
    }
    else if (/memoria|tarjeta/i.test(ini)) s.tipo_equipo = 'Memoria';
    else if (/software|wincc|licencia/i.test(ini)) s.tipo_equipo = 'Software';
    break;
  }

  case 'SIMATIC NET': case 'SCALANCE': {
    const r = (rutaTxt + ' ' + t).toUpperCase();
    if (/PROFIBUS PA/.test(r)) s.bus = 'PROFIBUS PA';
    else if (/PROFIBUS|\bDP\b/.test(r)) s.bus = 'PROFIBUS DP';
    else if (/PROFINET|ETHERNET|SCALANCE|RJ45/.test(r)) s.bus = 'PROFINET / Ethernet';
    else if (/AS-?I/.test(r)) s.bus = 'AS-i';
    const sub = sinTildes(resto[1] || resto[0] || '').toLowerCase(), r2 = sinTildes(t).toLowerCase();
    if (/conector|splitconnect|terminador/.test(sub + ' ' + r2.slice(0, 60))) s.tipo_equipo = 'Conector';
    else if (/cable/.test(sub + ' ' + r2.slice(0, 60))) s.tipo_equipo = 'Cable';
    else if (/switch|scalance x/.test(r2)) s.tipo_equipo = 'Switch';
    else if (/fibra|olm|optic/.test(sub + ' ' + r2)) s.tipo_equipo = 'Fibra óptica';
    else if (/fuente/.test(sub)) s.tipo_equipo = 'Fuente';
    else if (/repetidor|repeater/.test(r2)) s.tipo_equipo = 'Repetidor';
    break;
  }

  case 'Bornes de Conexión': {
    const r = sinTildes(rutaTxt + ' ' + t).toLowerCase();
    if (/puente/.test(r)) s.tipo_equipo = 'Puente';
    else if (/numero|marcac|identific|rotul/.test(r)) s.tipo_equipo = 'Marcación';
    else if (/tapa|placa final|tope|soporte/.test(r)) s.tipo_equipo = 'Tapa / tope';
    else if (/fusible/.test(r)) s.tipo_equipo = 'Borne / cartucho fusible';
    else if (/tierra|\bpe\b|verde-amarillo/.test(r)) s.tipo_equipo = 'Borne de tierra';
    else if (/cortocircuit|seccionab/.test(r)) s.tipo_equipo = 'Seccionable / cortocircuitable';
    else if (/multiple|doble nivel|2 niveles|3 niveles/.test(r)) s.tipo_equipo = 'Varios niveles';
    else if (/borne/.test(r)) s.tipo_equipo = 'Borne de paso';
    if (/borne/i.test(s.tipo_equipo || '') || /puente/.test(r)){
      if ((m = t.match(/tam(?:a[ñn]o)?\.?\s*(\d+(?:[.,]\d+)?)\b/i)) || (m = t.match(/(\d+(?:[.,]\d+)?)\s*mm\s*2/i)) || (m = String(p.modelo).match(/^(?:UT|ST|PT|UK)\s?(\d+(?:[.,]\d+)?)/i))) s.seccion_mm2 = num(m[1]);
    }
    break;
  }

  case 'Cableado y Accesorios para Tableros': {
    const sub = (resto[0] || '').trim();
    if (sub) s.tipo_equipo = sub.replace(/\s*\/\s*/g, ' / ');
    if ((m = t.match(/(\d+(?:[.,]\d+)?)\s*mm\s*2\b/i)) || (m = t.match(/(\d+(?:[.,]\d+)?)\s*mm²/)) || (/cable/i.test(sub) && (m = t.match(/\b\d+\s*X\s*(\d+(?:[.,]\d+)?)\s*mm\b/i)))) s.seccion_mm2 = num(m[1]);
    if (s.seccion_mm2 != null && /^0\d+$/.test(String(m && m[1]))) s.seccion_mm2 = num('0.' + String(m[1]).slice(1));   // "4X034" = 0,34 mm²
    if (s.seccion_mm2 != null && (s.seccion_mm2 > 400 || s.seccion_mm2 <= 0)) delete s.seccion_mm2;
    break;
  }

  case 'Neumática': {
    const r = sinTildes(rutaTxt + ' ' + t).toLowerCase();
    if (/regulador/.test(r)) s.tipo_equipo = 'Regulador de caudal';
    else if (/conector rapido|racor|union|giratorio/.test(r)) s.tipo_equipo = 'Conector / racor';
    else if (/valvula|cpv/.test(r)) s.tipo_equipo = 'Válvulas (Festo CPV)';
    if ((m = t.match(/(\d{1,2})\s*mm\s*OD/i)) || (m = t.match(/manguera\s*(\d{1,2})\s*\/\s*\d/i))) s.manguera_mm = +m[1];
    if ((m = t.match(/(1\/8|1\/4|3\/8|1\/2)"?\s*BSPP?/i))) s.rosca = m[1] + '" BSPP';
    break;
  }

  case 'Arrancadores de Motor': {
    if ((m = t.match(new RegExp('intensidad\\s*' + N + '\\s*-\\s*' + N + '\\s*A', 'i')))){ s.ajuste_a_min = num(m[1]); s.ajuste_a_max = num(m[2]); }
    if ((m = t.match(/tensi[oó]n de mando\s*(\d+)\s*V\s*(AC|DC)?/i))) s.tension_control = etiquetaTension(+m[1], null, (m[2] || 'AC').toUpperCase());
    if (/SIMOCODE/i.test(tt)) s.tipo_equipo = 'Gestión de motores (SIMOCODE)';
    else if (/arrancador directo/i.test(t)) s.tipo_equipo = 'Arrancador directo en caja';
    else if (/caja/i.test(t)) s.tipo_equipo = 'Caja para arrancador';
    break;
  }
  }

  for (const k of Object.keys(s)) if (s[k] == null || s[k] === '' || Number.isNaN(s[k])) delete s[k];
  return s;
}

// Mismo formato que bobinaNorm() de migrar-catalogo-beta.js
function etiquetaBobina(v, tipo){
  v = Number(v); tipo = /AC\/DC|UC/i.test(tipo || '') ? 'AC/DC' : /dc|cc/i.test(tipo || '') ? 'DC' : 'AC';
  if (tipo === 'AC/DC'){
    if (v <= 33) return '24 VAC/VDC';
    if (v >= 100 && v <= 127) return '110-127 VAC/VDC';
    if (v >= 200 && v <= 277) return '220-240 VAC/VDC';
    if (v >= 380 && v <= 500) return '380-480 VAC/VDC';
    return v + ' VAC/VDC';
  }
  if (tipo === 'DC') return (v >= 100 && v <= 127 ? '110' : v >= 200 && v <= 250 ? '220' : v) + ' VDC';
  if (v <= 26) return '24 VAC';
  if (v >= 42 && v <= 48) return '48 VAC';
  if (v >= 100 && v <= 132) return '110-120 VAC';
  if (v >= 200 && v <= 240) return '220-240 VAC';
  if (v >= 380 && v <= 480) return '380-440 VAC';
  return v + ' VAC';
}

/* Une lo que ya había con lo nuevo.
   · Lo que define variantes (bobina de los HGC) no se pisa.
   · La bobina leída con frase clara ("Tensión de bobina", "mando por") corrige la vieja. */
function unirSpecs(viejo, extra){
  const s = Object.assign({}, viejo || {});
  for (const [k, v] of Object.entries(extra)){
    if (k === '_bobina'){ if (!s.bobina || /^(33|264) VAC$/.test(s.bobina)) s.bobina = v; continue; }
    if (k === 'corriente_a' && s.corriente_a != null) continue;
    if (k === 'polos' && s.polos != null) continue;
    if (k === 'rosca' && s.rosca) continue;
    s[k] = v;
  }
  return s;
}


/* ---------- Base (los atributos que ya leía la migración) ---------- */
const numBase = (s) => { if (s == null) return null; const v = parseFloat(String(s).replace(/\s/g, '').replace(',', '.')); return isNaN(v) ? null : v; };
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
function serieDe(categoria, resto, aux){
  if (/sensores de proximidad|finales de carrera|encoders/i.test(categoria)) return null;
  for (const s of resto){
    if ((aux && aux.NODOS_MARCA && aux.NODOS_MARCA.has(s)) || /^accesorios?$/i.test(s) || /^otros/i.test(s)) continue;
    if (/^(tama[ñn]o|bobina|di[aá]metro|\d|[123] fases?|capacidad)/i.test(s)) continue;
    const m = s.match(/\bSerie\s+([A-Z0-9][\w\/-]*)/);
    const r = (m ? m[1] : s.split(' - ')[0].split(' (')[0]).trim();
    if (r && r.length <= 40) return r;
  }
  return null;
}

/* ---------- 5. Atributos técnicos ---------- */
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
  for (const re of pats){ const m = t.match(re); if (m){ const a = numBase(m[1]), b = numBase(m[2]); if (a != null && b != null && a < b) return [a, b]; } }
  return null;
};
const polosBase = (t) => {
  let m = t.match(/(\d)\s*polos?\b/i) || t.match(/polos\s*(\d)\b/i);
  if (m) return +m[1];
  if (/tetrapolar/i.test(t)) return 4; if (/tripolar/i.test(t)) return 3; if (/bipolar/i.test(t)) return 2; if (/monopolar|unipolar/i.test(t)) return 1;
  return null;
};

function atributosBase(p, categoria, sub, resto, serie, aux){
  const s = {};
  if (serie) s.serie = serie;
  if (sub === 'Accesorios') return s;
  const t = [p.modelo, p.nombre !== p.modelo ? p.nombre : '', p.descripcion || ''].join(' ').replace(/\s+/g, ' ');
  const rutaTxt = resto.join(' > ');
  let m;
  if (categoria === 'Variadores de Frecuencia'){
    const v = (aux && aux.extraerSpecsVfd ? aux.extraerSpecsVfd(p) : null);
    if (v){ if (v.kw) s.potencia_kw = v.kw; if (v.hp) s.potencia_hp = v.hp; if (v.v) s.tension_v = v.v; if (v.fase) s.fases = v.fase === 13 ? 1 : v.fase; if (v.a) s.corriente_a = v.a; if (v.uso != null) s.aplicacion = (aux && aux.VFD_USOS ? aux.VFD_USOS[v.uso] : null); }
  } else if (categoria === 'Arrancadores Suaves'){
    const v = (aux && aux.extraerSpecsArr ? aux.extraerSpecsArr(p) : null);
    if (v && v.a) s.corriente_a = v.a;
  } else if (categoria === 'Contactores'){
    if ((m = t.match(/(\d+(?:[.,]\d+)?)\s*A\s*\(AC-?3\)/i)) || (m = t.match(/AC-?3\)?\s*(?:\(A\))?\s*:?\s*(\d+(?:[.,]\d+)?)\s*A?\b/i)) ||
        (m = String(p.modelo).match(/^HGC(\d+)(?:11|22)NS/)) || (m = t.match(/(\d+)\s*amperios/i)) || (m = rutaTxt.match(/(\d+(?:[.,]\d+)?)\s*Amp\b/i)))
      s.corriente_ac3_a = numBase(m[1]);
    if ((m = t.match(/(\d{2,3})\s*V\s*(AC|DC)\b/i)) || (m = t.match(/\b(AC|DC)\s*(\d{2,3})\s*V\b/i))){
      const v = /\d/.test(m[1]) ? m[1] : m[2], tipo = /\d/.test(m[1]) ? m[2] : m[1];
      s.bobina = bobinaNorm(v, tipo);
    }
    const pol = polosBase(t); if (pol) s.polos = pol; else if (sub === 'De potencia' && /tripolar|contactor de potencia/i.test(t)) s.polos = 3;
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
    const pol = polosBase(t); if (pol) s.polos = pol;
    if ((m = t.match(/(\d+(?:[.,]\d+)?)\s*kA/i))) s.poder_corte_ka = numBase(m[1]);
  } else if (categoria === 'Breakers en Caja Moldeada'){
    if ((m = t.match(/\bIn\s*(?:\(A\))?\s*[:=]\s*(\d+(?:[.,]\d+)?)/i))) s.corriente_a = numBase(m[1]);
    else if ((m = t.match(/(\d+)\s*-\s*(\d+)\s*A(?:mp)?\b/i))) s.corriente_a = +m[2];   // regulable: se toma el máximo
    const pol = polosBase(t); if (pol) s.polos = pol;
    if ((m = t.match(/Icu\s*=?\s*(\d+(?:[.,]\d+)?)\s*kA/i)) || (m = t.match(/Icu[^:]{0,30}\(kA\)\s*:\s*(\d+(?:[.,]\d+)?)/i)) || (m = t.match(/(\d+(?:[.,]\d+)?)\s*kA/i))) s.poder_corte_ka = numBase(m[1]);
    if (/electr[oó]nic/i.test(t)) s.disparador = 'Electrónico'; else if (/termomagn|TM-?D|\bTM\d/i.test(t)) s.disparador = 'Termomagnético'; else if (/magn[eé]tico/i.test(t)) s.disparador = 'Magnético';
  } else if (categoria === 'Sensores de Proximidad'){
    const tt = rutaTxt + ' ' + t;
    if ((m = tt.match(/inductiv|capacitiv|[oó]ptic|ultras[oó]nic|magn[eé]tic/i))){
      const k = m[0].toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
      s.tipo_sensor = { inductiv: 'Inductivo', capacitiv: 'Capacitivo', optic: 'Óptico', ultrasonic: 'Ultrasónico', magnetic: 'Magnético' }[k];
    }
    if ((m = tt.match(/Di[aá]metro\s*(8|12|18|30)\s*mm/i)) || (m = tt.match(/\bM(8|12|18|30)\b(?!\s*\/)/))) s.rosca = 'M' + m[1];
    if (/NPN\s*\/\s*PNP|PNP\s*\/\s*NPN/i.test(tt)) s.salida = 'PNP/NPN'; else if (/PNP/.test(tt)) s.salida = 'PNP'; else if (/NPN/.test(tt)) s.salida = 'NPN'; else if (/REL[EÉ]/i.test(tt)) s.salida = 'Relé';
    if ((m = t.match(/Sn:\s*(\d+(?:[.,]\d+)?)\s*(mm|mts?|m)\b/i))){ const v = numBase(m[1]); s.distancia_mm = /mm/i.test(m[2]) ? v : Math.round(v * 1000); }
    if ((m = tt.match(/conector\s*(M8|M12)/i))) s.conexion = 'Conector ' + m[1].toUpperCase(); else if (/cable/i.test(tt)) s.conexion = 'Cable';
  }
  for (const k of Object.keys(s)) if (s[k] == null || s[k] === '' || Number.isNaN(s[k])) delete s[k];
  return s;
}


/* ---------- Todo junto: especificaciones de un producto ----------
   p = { modelo, nombre, descripcion, marca }; ruta = [familia, categoría, subcategorías…]
   aux = { extraerSpecsVfd, extraerSpecsArr, VFD_USOS, NODOS_MARCA } (de la tienda) */
function especificacionesDe(p, ruta, aux){
  const categoria = ruta[1] || 'General', resto = ruta.slice(2);
  const sub = subcategoria(categoria, resto);
  const serie = serieDe(categoria, resto, aux);
  return unirSpecs(atributosBase(p, categoria, sub, resto, serie, aux), atributosExtra(p, categoria, resto));
}

/* ---------- Qué filtros ve cada categoría ----------
   rutas = lista de rutas de categoría (arreglos de nombres); slug = función de la tienda.
   Devuelve { 'familia/categoria': [{clave, nombre, tipo, unidad, variante}], … }.
   Dentro de Contactores, las subcategorías de auxiliares y de estado sólido llevan los suyos. */
function filtrosPorRuta(rutas, slug){
  const def = (clave, variante) => { const a = ATRIBUTOS[clave]; return { clave, nombre: a[0], tipo: a[1], unidad: a[2], variante: !!variante }; };
  const out = {};
  for (const r of rutas){
    const cat = r[1];
    if (cat && FILTROS[cat]){
      const k = slug(r[0]) + '/' + slug(cat);
      if (!out[k]) out[k] = FILTROS[cat].map(x => def(x[0], x[2]));
    }
    if (cat === 'Contactores'){
      for (let n = 3; n <= r.length; n++){
        const nom = r[n - 1];
        if (/accesorio/i.test(nom) || !/auxiliar|estado s[oó]lido/i.test(nom)) continue;
        const k = r.slice(0, n).map(slug).join('/');
        if (!out[k]) out[k] = (/auxiliar/i.test(nom) ? [['contactos_aux'], ['bobina'], ['tamano'], ['serie']] : [['bobina'], ['serie']]).map(x => def(x[0]));
      }
    }
  }
  return out;
}

return { ATRIBUTOS, FILTROS, especificacionesDe, filtrosPorRuta, atributosExtra, atributosBase, subcategoria, serieDe, unirSpecs, etiquetaBobina };
});
