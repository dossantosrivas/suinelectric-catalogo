# Aplica a una copia de la tienda (beta) las mejoras de vista y filtros:
#   · íconos en las opciones de filtro (AC/DC, relé, transistor, contactos, colores)
#   · campo "corriente mínima" (como el de variadores) en contactores, breakers, etc.
#   · vista "Ficha": tarjetas más bajas, más descripción y especificaciones a la vista
# Uso: python3 scripts/mejoras-vista-filtros.py tienda-beta.html
import sys

ruta = sys.argv[1]
s = open(ruta, encoding='utf-8').read()

def rep(viejo, nuevo, veces=1):
    global s
    n = s.count(viejo)
    if n != veces:
        raise SystemExit('No encontré (%d veces) en %s:\n%s' % (n, ruta, viejo[:160]))
    s = s.replace(viejo, nuevo)

# ---------------------------------------------------------------- CSS
CSS = r"""
  /* ================= Íconos en filtros y especificaciones ================= */
  .fi{ display:inline-flex; align-items:center; justify-content:center; width:18px; height:18px; flex:none; color:var(--azul-texto); }
  .fi svg{ width:18px; height:18px; }
  .fi-color{ width:14px; height:14px; border-radius:50%; border:1px solid rgba(0,0,0,.18); box-shadow:inset 0 0 0 1.5px #fff; }
  .vfd-chip{ display:inline-flex; align-items:center; gap:6px; }
  .vfd-chip.on .fi{ color:var(--tinta); }
  .fac-min{ display:flex; gap:6px; align-items:center; }
  .fac-min input{ width:120px; }

  /* ================= Vista Ficha: más productos y más datos a la vista ================= */
  #contenido.vista-ficha .grid{ grid-template-columns:repeat(auto-fill, minmax(300px, 1fr)); gap:12px; }
  #contenido.vista-ficha .card{ display:grid; grid-template-columns:104px minmax(0,1fr); align-items:start; }
  #contenido.vista-ficha .card-marca-logo{ position:static; grid-column:1; grid-row:2; height:15px; max-width:78px; margin:0 auto 10px; }
  #contenido.vista-ficha .thumb{ grid-column:1; grid-row:1; width:88px; height:88px; margin:12px 0 8px 12px; padding:6px;
    border:1px solid var(--linea-suave); border-radius:8px; }
  #contenido.vista-ficha .thumb.sin-imagen{ font-size:11px; text-align:center; }
  #contenido.vista-ficha .card:hover .thumb img{ transform:none; }
  #contenido.vista-ficha .card-body{ grid-column:2; grid-row:1 / span 3; padding:12px 14px 12px 12px;
    display:grid; grid-template-columns:minmax(0,1fr) auto; column-gap:10px; align-content:start; }
  #contenido.vista-ficha .card-body > *{ grid-column:1 / -1; }
  #contenido.vista-ficha .modelo{ font-size:17px; }
  #contenido.vista-ficha .desc{ font-size:13px; line-height:1.4; -webkit-line-clamp:4; margin:4px 0 6px; }
  #contenido.vista-ficha .card-body > .estado{ grid-column:1; align-self:center; justify-self:start; font-size:12px; padding:2px 8px 2px 7px; margin:0; }
  #contenido.vista-ficha .card-body > .price-row{ grid-column:2; margin:0; justify-content:flex-end; text-align:right; }
  #contenido.vista-ficha .precio-box{ align-items:flex-end; }
  #contenido.vista-ficha .precio-linea{ justify-content:flex-end; }
  #contenido.vista-ficha .precio{ font-size:20px; }
  #contenido.vista-ficha .precio-nota{ display:none; }
  #contenido.vista-ficha .card-body > .estado{ white-space:normal; line-height:1.25; min-width:0; max-width:100%; }
  #contenido.vista-ficha .precio-registro{ margin-top:4px; padding:3px 7px; align-items:flex-end; text-align:right; }
  #contenido.vista-ficha .precio-registro .pr-monto{ font-size:14px; }
  #contenido.vista-ficha .card-body > .actions{ display:flex; flex-wrap:nowrap; gap:6px; margin-top:8px; }
  #contenido.vista-ficha .qty-selector{ flex:0 0 auto; height:36px; }
  #contenido.vista-ficha .qty-btn{ width:28px; }
  #contenido.vista-ficha .qty-input{ flex:none; width:34px; font-size:14px; }
  #contenido.vista-ficha .btn-cart-add{ flex:1 1 auto; padding:8px 10px; font-size:14px; }
  #contenido.vista-ficha .card-body > .wa-doble{ margin-top:6px; }
  #contenido.vista-ficha .wa-doble .btn{ flex:1 1 50%; padding:5px 8px; font-size:12.5px; border-width:1px; }
  .especs-mini{ display:flex; flex-wrap:wrap; gap:4px; margin:0 0 8px; }
  .especs-mini > span{ display:inline-flex; align-items:center; gap:4px; font-size:12px; font-weight:600; color:var(--tinta);
    background:var(--azul-suave); border-radius:5px; padding:2px 7px; line-height:1.5; }
  .especs-mini .fi, .especs-mini .fi svg{ width:14px; height:14px; }
  .especs-mini .fi-color{ width:10px; height:10px; }
  #contenido.vista-cuadros .especs-mini, #contenido.vista-compacta .especs-mini{ display:none; }
  @media (max-width: 640px){
    #contenido.vista-ficha .grid{ grid-template-columns:1fr; gap:10px; }
    #contenido.vista-ficha .card{ grid-template-columns:86px minmax(0,1fr); }
    #contenido.vista-ficha .thumb{ width:72px; height:72px; margin:10px 0 6px 10px; padding:4px; }
    #contenido.vista-ficha .card-marca-logo{ max-width:64px; height:13px; }
    #contenido.vista-ficha .card-body{ padding:10px 10px 10px 8px; }
    #contenido.vista-ficha .modelo{ font-size:16px; }
    #contenido.vista-ficha .desc{ -webkit-line-clamp:3; }
    #contenido.vista-ficha .card-body > .wa-doble{ flex-wrap:nowrap; gap:6px; }
  }
"""
rep("  /* ---------- Modos de vista del listado (Cuadros / Lista / Compacta) ---------- */",
    CSS + "\n  /* ---------- Modos de vista del listado (Cuadros / Lista / Compacta) ---------- */")

# ---------------------------------------------------------------- Botón "Ficha" en el selector de vista
rep("""          <button type="button" data-vista-modo="cuadros" title="Ver en cuadros">""",
    """          <button type="button" data-vista-modo="ficha" title="Ficha: más productos y datos a la vista"><svg viewBox="0 0 16 16" aria-hidden="true"><path fill="currentColor" d="M1 1h4v4H1zM6.5 1.5H15V3H6.5zM6.5 3.8H12V5H6.5zM1 9h4v4H1zM6.5 9.5H15V11H6.5zM6.5 11.8H12V13H6.5z"/></svg>Ficha</button>
          <button type="button" data-vista-modo="cuadros" title="Ver en cuadros">""")
# Ficha es la vista por defecto (clave nueva para que todos la vean la primera vez)
rep("""  const CLAVE = 'suin_vista_productos';""", """  const CLAVE = 'suin_vista_productos_v2';""")
rep("""  let pref = { pc:{ modo:'cuadros', cols:'auto' }, movil:{ modo:'cuadros', cols:'2' } };""",
    """  let pref = { pc:{ modo:'ficha', cols:'auto' }, movil:{ modo:'ficha', cols:'2' } };""")

# ---------------------------------------------------------------- Especificaciones en la tarjeta
rep("""        <div class="desc">${p.descripcion || ''}</div>
        <div class="estado ${p.disponible ? 'ok' : 'off'}">${estadoTexto}</div>""",
    """        <div class="desc">${p.descripcion || ''}</div>
        ${especsMiniHTML(p)}
        <div class="estado ${p.disponible ? 'ok' : 'off'}">${estadoTexto}</div>""")

# ---------------------------------------------------------------- Íconos, campo mínimo y especificaciones (JS)
JS = r"""
/* ---------- Íconos de las opciones de filtro ---------- */
const SVG_FI = {
  ac:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M2 12c2.5-6 5.5-6 8 0s5.5 6 8 0 3-4 4-3"/></svg>',
  dc:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 9h18"/><path d="M3 15h4M10 15h4M17 15h4"/></svg>',
  acdc: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M2 8c1.6-4 3.4-4 5 0s3.4 4 5 0"/><path d="M13 15h9"/><path d="M13 19h2M17 19h2M21 19h1"/></svg>',
  rayo: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M13 2 4 14h6l-1 8 9-12h-6z"/></svg>',
  rele: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="6" width="8" height="12" rx="1"/><path d="M3 18 11 6"/><path d="M14 12h3l4-4M21 16"/></svg>',
  trans:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="13" cy="12" r="9"/><path d="M4 12h6M10 7v10M10 9l6-4M10 15l6 4"/><path d="m14 17.5 2 1.5-.4-2.4"/></svg>',
  na:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M2 16h6l8-6M16 16h6"/><circle cx="8" cy="16" r="1.2" fill="currentColor"/><circle cx="16" cy="16" r="1.2" fill="currentColor"/></svg>',
  nc:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M2 14h6l9 4M16 14h6M16 9v5"/><circle cx="8" cy="14" r="1.2" fill="currentColor"/></svg>',
  dos:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 9h18M3 15h18"/></svg>',
  motor:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M8 16V8l4 5 4-5v8"/></svg>',
};
const COLORES_FI = { Rojo:'#d7263d', Verde:'#1e9e48', Amarillo:'#f5c400', Azul:'#1f6fd1', Blanco:'#ffffff', Negro:'#1b1b1b',
  Naranja:'#f28c18', Gris:'#9aa3ab', Transparente:'linear-gradient(135deg,#fff 45%,#cfd8de 55%)' };
const CLAVES_TENSION = ['bobina', 'tension_control', 'alimentacion', 'tension_entrada', 'tension_salida_v'];
function iconoFac(clave, v){
  const t = String(v);
  const i = (k) => '<span class="fi">' + SVG_FI[k] + '</span>';
  if (clave === 'color' && COLORES_FI[t]) return '<span class="fi fi-color" style="background:' + COLORES_FI[t] + '"></span>';
  if (CLAVES_TENSION.includes(clave)){
    if (/AC\s*\/\s*V?DC|universal/i.test(t)) return i('acdc');
    if (/DC|VDC/i.test(t)) return i('dc');
    if (/AC|VAC/i.test(t)) return i('ac');
    return i('rayo');
  }
  if (clave === 'salida'){
    if (/rel[eé]/i.test(t)) return i('rele');
    if (/transistor|PNP|NPN/i.test(t)) return i('trans');
    if (/2 hilos/i.test(t)) return i('dos');
  }
  if (clave === 'contactos' || clave === 'contactos_aux'){
    if (/rel[eé]|conmutad/i.test(t)) return i('rele');
    if (/NC/.test(t) && !/NA/.test(t)) return i('nc');
    return i('na');
  }
  if (clave === 'hp_220' || clave === 'hp_440' || clave === 'potencia_hp' || clave === 'potencia_kw') return i('motor');
  return '';
}

/* ---------- Especificaciones cortas en la tarjeta ---------- */
const FMT_NUM = (n) => Number(n).toLocaleString('es-VE');
function textoCortoEspec(d, v){
  switch (d.clave){
    case 'hp_220': return FMT_NUM(v) + ' HP a 220 V';
    case 'hp_440': return FMT_NUM(v) + ' HP a 440 V';
    case 'polos': return v + (Number(v) === 1 ? ' polo' : ' polos');
    case 'fases': return Number(v) === 1 ? 'Monofásico' : 'Trifásico';
    case 'curva': return 'Curva ' + v;
    case 'tamano': return 'Tamaño ' + v;
    case 'distancia_mm': return 'Sn ' + FMT_NUM(v) + ' mm';
    case 'pantalla_pulg': return FMT_NUM(v) + '"';
    case 'corriente_ac3_a': return FMT_NUM(v) + ' A (AC3)';
  }
  if (typeof v === 'number' || d.tipo === 'numero') return FMT_NUM(v) + (d.unidad ? ' ' + d.unidad : '');
  return String(v);
}
function especsMiniHTML(p){
  if (!catalogoBeta || !p._specs) return '';
  const s = p._specs, defs = defsFacDe(rutaDe(p)) || [], out = [];
  for (const d of defs){
    if (out.length >= 5) break;
    if (d.clave === 'serie' || d.clave === 'marca') continue;
    if (d.tipo === 'rango'){
      const a = s[d.clave + '_min'], b = s[d.clave + '_max'];
      if (a != null && b != null) out.push('<span>' + FMT_NUM(a) + '–' + FMT_NUM(b) + ' ' + escHtml(d.unidad || 'A') + '</span>');
      continue;
    }
    const v = s[d.clave];
    if (v == null || v === '') continue;
    out.push('<span>' + iconoFac(d.clave, v) + escHtml(textoCortoEspec(d, v)) + '</span>');
  }
  return out.length ? '<div class="especs-mini">' + out.join('') + '</div>' : '';
}
// Corrientes en las que conviene "escribe la corriente de tu motor / carga"
const CLAVES_MIN = { corriente_ac3_a: 'Corriente de tu motor (A)', corriente_a: 'Corriente que necesitas (A)', corriente_salida_a: 'Corriente que necesitas (A)' };
"""
rep("/* ---------- Filtros por especificación ----------", JS + "\n/* ---------- Filtros por especificación ----------")

# filtros numéricos con prefijo (cubre: y min:)
rep("""    if (k.indexOf('cubre:') === 0){
      if (v == null) continue;
      const c = k.slice(6), s = p._specs || {}, a = s[c + '_min'], b = s[c + '_max'];
      if (a == null || b == null || v < a || v > b) return false;
      continue;
    }""",
    """    if (k.indexOf('cubre:') === 0){
      if (v == null) continue;
      const c = k.slice(6), s = p._specs || {}, a = s[c + '_min'], b = s[c + '_max'];
      if (a == null || b == null || v < a || v > b) return false;
      continue;
    }
    if (k.indexOf('min:') === 0){
      if (v == null) continue;
      const pv = p._specs ? p._specs[k.slice(4)] : null;
      if (pv == null || Number(pv) < v) return false;
      continue;
    }""")
rep("""function nActFac(){ return Object.keys(filtrosFac).filter(k => k.indexOf('cubre:') === 0 ? filtrosFac[k] != null : (filtrosFac[k] || []).length).length; }""",
    """const esNumFac = (k) => k.indexOf('cubre:') === 0 || k.indexOf('min:') === 0;
function nActFac(){ return Object.keys(filtrosFac).filter(k => esNumFac(k) ? filtrosFac[k] != null : (filtrosFac[k] || []).length).length; }""")
rep("""  return Object.keys(filtrosFac).filter(k => k.indexOf('cubre:') === 0 ? filtrosFac[k] != null : (filtrosFac[k] || []).length)
    .map(k => k + ':' + (k.indexOf('cubre:') === 0 ? filtrosFac[k] : filtrosFac[k].join('|'))).join(';');""",
    """  return Object.keys(filtrosFac).filter(k => esNumFac(k) ? filtrosFac[k] != null : (filtrosFac[k] || []).length)
    .map(k => k + ':' + (esNumFac(k) ? filtrosFac[k] : filtrosFac[k].join('|'))).join(';');""")
rep("""    if (par.indexOf('cubre:') === 0){ const [, c, v] = par.split(':'); const n = parseFloat(v); if (c && !isNaN(n)) f['cubre:' + c] = n; return; }""",
    """    if (par.indexOf('cubre:') === 0 || par.indexOf('min:') === 0){ const [pre, c, v] = par.split(':'); const n = parseFloat(v); if (c && !isNaN(n)) f[pre + ':' + c] = n; return; }""")

# campo mínimo antes de los chips del atributo
rep("""    const elegidos = (filtrosFac[def.clave] || []).map(String);
    // ¿Muchos valores numéricos distintos?""",
    """    if (CLAVES_MIN[def.clave] && base.some(p => p._specs && p._specs[def.clave] != null)){
      const val = filtrosFac['min:' + def.clave];
      grupos.push('<div class="vfd-grupo"><div class="vfd-tit">' + CLAVES_MIN[def.clave] + '</div>' +
        '<input type="number" min="0" step="0.1" inputmode="decimal" class="fac-cubre" data-pre="min" data-clave="' + def.clave + '" placeholder="Ej. 18" value="' + (val != null ? val : '') + '">' +
        '<div class="vfd-ayuda">Muestra los que soportan esa corriente o más</div></div>');
    }
    const elegidos = (filtrosFac[def.clave] || []).map(String);
    // ¿Muchos valores numéricos distintos?""")
rep("""        const n = parseFloat(String(inp.value).replace(',', '.'));
        filtrosFac['cubre:' + inp.dataset.clave] = isNaN(n) ? null : n;
        aplicarFiltros();
        const nuevo = document.querySelector('.fac-cubre[data-clave="' + inp.dataset.clave + '"]');""",
    """        const n = parseFloat(String(inp.value).replace(',', '.'));
        const pre = inp.dataset.pre || 'cubre';
        filtrosFac[pre + ':' + inp.dataset.clave] = isNaN(n) ? null : n;
        aplicarFiltros();
        const nuevo = document.querySelector('.fac-cubre[data-clave="' + inp.dataset.clave + '"][data-pre="' + (inp.dataset.pre || '') + '"]') ||
                      document.querySelector('.fac-cubre[data-clave="' + inp.dataset.clave + '"]:not([data-pre])');""")
rep("""class="fac-cubre" data-clave="' + def.clave + '" placeholder="Ej. 8,5\"""",
    """class="fac-cubre" data-pre="" data-clave="' + def.clave + '" placeholder="Ej. 8,5\"""")

# ícono dentro de cada chip
rep("""        : escHtml(esMarca ? (v === 'SIN MARCA' ? 'Otras marcas' : nombreMarca(v)) : usaTramos ? etiquetaTramoFac(def, v) : etiquetaFac(def, v));""",
    """        : (usaTramos ? '' : iconoFac(def.clave, v)) + escHtml(esMarca ? (v === 'SIN MARCA' ? 'Otras marcas' : nombreMarca(v)) : usaTramos ? etiquetaTramoFac(def, v) : etiquetaFac(def, v));""")
# en el celular se ven menos opciones por grupo antes de "Ver más"
rep("""const FAC_VISIBLES = 14;""", """const FAC_VISIBLES = window.innerWidth <= 640 ? 8 : 14;""")


# Los tramos numéricos (amperios, HP, distancia…) van en una lista desplegable, como "Potencia del motor" en variadores
rep("""    const chips = vals.map((v, i) => {""",
    """    if (usaTramos){
      const sel = elegidos[0] || '';
      grupos.push('<div class="vfd-grupo"><div class="vfd-tit">' + escHtml(def.nombre) + '</div>' +
        '<select class="fac-sel" data-clave="' + escHtml(def.clave) + '" aria-label="' + escHtml(def.nombre) + '"><option value="">Cualquiera</option>' +
        vals.map(v => '<option value="' + escHtml(v) + '"' + (v === sel ? ' selected' : '') + (cuenta.get(v) || v === sel ? '' : ' disabled') + '>' +
          escHtml(etiquetaTramoFac(def, v)) + ' (' + cuenta.get(v) + ')</option>').join('') + '</select></div>');
      continue;
    }
    const chips = vals.map((v, i) => {""")
rep("""  panel.querySelectorAll('.fac-mas').forEach(b => b.addEventListener('click', () => {""",
    """  panel.querySelectorAll('.fac-sel').forEach(sel => sel.addEventListener('change', () => {
    filtrosFac[sel.dataset.clave] = sel.value ? [sel.value] : [];
    aplicarFiltros();
  }));
  panel.querySelectorAll('.fac-mas').forEach(b => b.addEventListener('click', () => {""")

# si un logo de marca no carga, se muestra el nombre
rep("""      const txt = logo ? '<img src="' + logo + '" alt="' + escHtml(v) + '" loading="lazy">'""",
    """      const txt = logo ? '<img src="' + logo + '" alt="' + escHtml(nombreMarca(v)) + '" loading="lazy" onerror="this.replaceWith(document.createTextNode(this.alt))">'""")

open(ruta, 'w', encoding='utf-8').write(s)
print('Mejoras aplicadas a', ruta)
