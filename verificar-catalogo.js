/* =====================================================================
   VERIFICAR EL CATÁLOGO ANTES DE PUBLICARLO
   ---------------------------------------------------------------------
   Corre justo después del scraper. Compara el productos.json nuevo con
   el que está publicado (el último guardado en git) y FRENA la
   publicación si algo se ve raro, por ejemplo porque grupo-electricos.com
   cambió su página o estaba caído:

     · el scraper no terminó o quedó en modo prueba
     · llegaron muchos menos productos que ayer
     · muchos productos quedaron sin precio
     · muchos precios cambiaron de golpe (más del % configurado)
     · las existencias totales se desplomaron

   Si frena: deja la tienda con los datos de ayer, avisa por SuinBot con
   el detalle y termina con error para que no corra nada más.
   Si todo está bien pero hay cambios de precio grandes en pocos
   productos, publica igual y manda un aviso con la lista para revisar.

   Para publicar de todas formas (cuando sabes que el cambio es real):
   GitHub → Actions → "Actualizar catálogo diario" → Run workflow →
   marcar "Publicar aunque la verificación falle".

   Uso local:  node verificar-catalogo.js [anterior.json] [nuevo.json]
   ===================================================================== */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

// ---- Límites (se pueden cambiar con variables de entorno) -------------
const num = (v, d) => (v === undefined || v === '' || isNaN(Number(v)) ? d : Number(v));
const L = {
  MIN_PRODUCTOS:      num(process.env.VERIF_MIN_PRODUCTOS, 1500), // mínimo absoluto
  MAX_CAIDA_PRODUCTOS: num(process.env.VERIF_MAX_CAIDA_PRODUCTOS, 10), // % menos que ayer
  MIN_COMPLETADO:     num(process.env.VERIF_MIN_COMPLETADO, 95),  // % de lo que el scraper esperaba
  MAX_SIN_PRECIO:     num(process.env.VERIF_MAX_SIN_PRECIO, 5),   // % de productos sin precio (nuevos)
  SALTO_PRECIO:       num(process.env.VERIF_SALTO_PRECIO, 40),    // % de cambio que cuenta como "salto"
  MAX_SALTOS:         num(process.env.VERIF_MAX_SALTOS, 3),       // % de productos con salto → frena
  MAX_CAIDA_EXISTENCIAS: num(process.env.VERIF_MAX_CAIDA_EXISTENCIAS, 50), // % menos unidades totales
};
const FORZAR = /^(1|true|si|sí|yes)$/i.test(process.env.VERIF_FORZAR || '');

// ---- Leer archivos ------------------------------------------------------
const RAIZ = __dirname;
function leerAnterior(arg){
  if (arg) return JSON.parse(fs.readFileSync(arg, 'utf8'));
  try {
    const txt = execFileSync('git', ['show', 'HEAD:productos.json'], { cwd: RAIZ, maxBuffer: 512 * 1024 * 1024 }).toString('utf8');
    return JSON.parse(txt);
  } catch (e) { return null; }
}
const anterior = leerAnterior(process.argv[2]);
let nuevo;
try { nuevo = JSON.parse(fs.readFileSync(process.argv[3] || path.join(RAIZ, 'productos.json'), 'utf8')); }
catch (e) { nuevo = null; }

// ---- Utilidades ---------------------------------------------------------
const porModelo = (d) => {
  const m = new Map();
  for (const p of (d && d.productos) || []) if (p && p.modelo && !m.has(p.modelo)) m.set(p.modelo, p);
  return m;
};
const precioDe = (p) => { const n = Number(p && p.precio); return p && p.precio != null && n > 0 ? n : null; };
const existDe = (p) => { const n = Number(p && p.existencias); return p && p.existencias != null && !isNaN(n) ? Math.max(0, n) : 0; };
const pct = (a, b) => (b ? (a / b) * 100 : 0);
const f1 = (n) => (Math.round(n * 10) / 10).toLocaleString('es-VE');
const usd = (n) => '$' + Number(n).toLocaleString('es-VE', { maximumFractionDigits: 2 });

// ---- Revisiones ---------------------------------------------------------
const problemas = [];   // frenan la publicación
const avisos = [];      // se publican igual, pero avisan
const resumen = [];

(function revisar(){
  if (!nuevo || !Array.isArray(nuevo.productos)){
    problemas.push('No se pudo leer el productos.json nuevo (el scraper no generó un archivo válido).');
    return;
  }
  if (nuevo.en_progreso) problemas.push('El scraper no terminó (el archivo quedó marcado "en progreso").');
  if (nuevo.modo_prueba) problemas.push('El scraper corrió en modo prueba (con límite de productos).');

  const N = porModelo(nuevo);
  const A = porModelo(anterior);
  const total = N.size;
  resumen.push(`Productos: ${total.toLocaleString('es-VE')}` + (A.size ? ` (ayer ${A.size.toLocaleString('es-VE')})` : ''));

  if (total < L.MIN_PRODUCTOS)
    problemas.push(`Solo llegaron ${total} productos (mínimo esperado: ${L.MIN_PRODUCTOS}).`);

  if (A.size){
    const caida = pct(A.size - total, A.size);
    if (caida > L.MAX_CAIDA_PRODUCTOS)
      problemas.push(`Llegaron ${f1(caida)}% menos productos que ayer (${A.size} → ${total}; límite ${L.MAX_CAIDA_PRODUCTOS}%).`);
  }

  const esperado = Number(nuevo.total_esperado) || 0;
  if (esperado && pct(total, esperado) < L.MIN_COMPLETADO)
    problemas.push(`El scraper solo pudo leer ${total} de ${esperado} productos (${f1(pct(total, esperado))}%).`);

  // Sin precio: solo cuentan los que ayer SÍ tenían precio (algunos nunca lo tienen).
  let perdieronPrecio = 0, conPrecioAyer = 0;
  for (const [m, p] of N){
    const a = A.get(m);
    if (a && precioDe(a) != null){ conPrecioAyer++; if (precioDe(p) == null) perdieronPrecio++; }
  }
  if (!A.size){
    const sinPrecio = [...N.values()].filter((p) => precioDe(p) == null).length;
    if (pct(sinPrecio, total) > 30) problemas.push(`${sinPrecio} productos (${f1(pct(sinPrecio, total))}%) no tienen precio.`);
  } else if (conPrecioAyer && pct(perdieronPrecio, conPrecioAyer) > L.MAX_SIN_PRECIO){
    problemas.push(`${perdieronPrecio} productos que ayer tenían precio ahora no tienen (${f1(pct(perdieronPrecio, conPrecioAyer))}%; límite ${L.MAX_SIN_PRECIO}%).`);
  } else if (perdieronPrecio){
    avisos.push(`${perdieronPrecio} producto(s) quedaron sin precio.`);
  }

  // Saltos de precio entre productos que están en ambos días.
  const saltos = [];
  let comparables = 0, cambiaron = 0;
  for (const [m, p] of N){
    const a = A.get(m); const pa = precioDe(a), pn = precioDe(p);
    if (pa == null || pn == null) continue;
    comparables++;
    if (pa !== pn) cambiaron++;
    const cambio = pct(pn - pa, pa);
    if (Math.abs(cambio) >= L.SALTO_PRECIO) saltos.push({ m, pa, pn, cambio });
  }
  if (comparables){
    resumen.push(`Precios que cambiaron: ${cambiaron} de ${comparables}`);
    const pSaltos = pct(saltos.length, comparables);
    saltos.sort((x, y) => Math.abs(y.cambio) - Math.abs(x.cambio));
    const lista = saltos.slice(0, 8).map((s) => `  • ${s.m}: ${usd(s.pa)} → ${usd(s.pn)} (${s.cambio > 0 ? '+' : ''}${f1(s.cambio)}%)`).join('\n');
    if (pSaltos > L.MAX_SALTOS){
      problemas.push(`${saltos.length} productos (${f1(pSaltos)}%) cambiaron de precio más de ±${L.SALTO_PRECIO}% (límite ${L.MAX_SALTOS}% de los productos). Ejemplos:\n${lista}`);
    } else if (saltos.length){
      avisos.push(`${saltos.length} producto(s) cambiaron de precio más de ±${L.SALTO_PRECIO}%:\n${lista}` +
        (saltos.length > 8 ? `\n  … y ${saltos.length - 8} más` : ''));
    }
  }

  // Existencias totales.
  if (A.size){
    let uA = 0, uN = 0;
    for (const p of A.values()) uA += existDe(p);
    for (const p of N.values()) uN += existDe(p);
    resumen.push(`Unidades en existencia: ${Math.round(uN).toLocaleString('es-VE')} (ayer ${Math.round(uA).toLocaleString('es-VE')})`);
    if (uA > 0 && pct(uA - uN, uA) > L.MAX_CAIDA_EXISTENCIAS)
      problemas.push(`Las existencias totales cayeron ${f1(pct(uA - uN, uA))}% (${Math.round(uA)} → ${Math.round(uN)} unidades; límite ${L.MAX_CAIDA_EXISTENCIAS}%).`);
  }

  // Productos que desaparecieron / aparecieron (informativo).
  if (A.size){
    let fuera = 0, nuevos = 0;
    for (const m of A.keys()) if (!N.has(m)) fuera++;
    for (const m of N.keys()) if (!A.has(m)) nuevos++;
    resumen.push(`Nuevos: ${nuevos} · Ya no aparecen: ${fuera}`);
  }
})();

// ---- Telegram -----------------------------------------------------------
async function telegram(texto){
  const token = process.env.TELEGRAM_TOKEN, chat = process.env.TELEGRAM_CHAT_ID;
  if (!token || !chat){ console.log('(Sin secretos de Telegram: no se envía aviso.)'); return false; }
  try {
    const r = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chat, text: texto.slice(0, 4000), disable_web_page_preview: true }),
    });
    if (!r.ok) console.log('No se pudo enviar el aviso de Telegram: ' + r.status);
    return r.ok;
  } catch (e) { console.log('No se pudo enviar el aviso de Telegram: ' + e.message); return false; }
}

(async () => {
  const enlace = process.env.ENLACE ? `\n\nDetalles: ${process.env.ENLACE}` : '';
  console.log(resumen.join('\n'));

  if (problemas.length && !FORZAR){
    console.log('\n✗ VERIFICACIÓN FALLIDA — no se publica:\n- ' + problemas.join('\n- '));
    // Deja los archivos como estaban (los de ayer) por si algo más corre después.
    try { execFileSync('git', ['checkout', '--', 'productos.json', 'categorias.json'], { cwd: RAIZ }); } catch (e) {}
    const ok = await telegram(
      '🛑 Catálogo NO publicado: la verificación encontró algo raro en el scraping de hoy. La tienda sigue con los datos de ayer.\n\n' +
      problemas.map((p) => '• ' + p).join('\n') + '\n\n' + resumen.join('\n') +
      '\n\nSi el cambio es real, corre el flujo a mano con "Publicar aunque la verificación falle".' + enlace
    );
    if (ok && process.env.MARCA_AVISO) fs.writeFileSync(process.env.MARCA_AVISO, '1');
    process.exit(1);
  }

  if (problemas.length && FORZAR){
    console.log('\n⚠ Problemas encontrados, pero se publica porque se marcó "forzar":\n- ' + problemas.join('\n- '));
    await telegram('⚠️ Catálogo publicado a la fuerza (lo pediste a mano) aunque la verificación encontró:\n\n' +
      problemas.map((p) => '• ' + p).join('\n') + '\n\n' + resumen.join('\n') + enlace);
  } else if (avisos.length){
    console.log('\n⚠ Avisos (se publica igual):\n- ' + avisos.join('\n- '));
    await telegram('👀 Catálogo publicado, pero revisa esto:\n\n' + avisos.map((a) => '• ' + a).join('\n') + '\n\n' + resumen.join('\n') + enlace);
  } else {
    console.log('\n✓ Verificación correcta.');
  }
})();
