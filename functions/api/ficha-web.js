/* =====================================================================
   DATOS DEL PRODUCTO DESDE LA WEB  (Cloudflare Pages Function: /api/ficha-web)
   ---------------------------------------------------------------------
   Lo usa Gestión → ficha de producto → "Buscar en la web" (y el escáner
   cuando un código no está en tu inventario ni en el catálogo del distribuidor).
   Le pide a Gemini que busque en Google el modelo o el código de barras,
   prefiriendo la web oficial del fabricante, y devuelve los datos para
   rellenar la ficha. Nada se guarda solo: tú revisas y guardas.
   Solo responde a usuarios de Gestión (misma sesión de Supabase).

   GET /api/ficha-web?q=GD20-2R2G-4&marca=INVT
     q      modelo o código de barras (EAN/UPC)
     marca  opcional, ayuda a acertar

   Usa la misma clave que el asistente del chat:
     GEMINI_API_KEY   clave de aistudio.google.com (gratis)
     GEMINI_MODEL     opcional
   ===================================================================== */

const SUPA = 'https://yqnlxhbjassrkudnhvpr.supabase.co';
// los mismos del asistente del chat (ya probados con tu clave) y, de respaldo, los 2.5, que traen búsqueda en Google gratis
const MODELOS = ['gemini-3.5-flash', 'gemini-flash-latest', 'gemini-3.5-flash-lite', 'gemini-3.1-flash-lite', 'gemini-flash-lite-latest', 'gemini-2.5-flash', 'gemini-2.5-flash-lite'];
const json = (obj, status = 200) => new Response(JSON.stringify(obj), {
  status,
  headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' },
});

/* ---------- solo usuarios de Gestión (administrador o vendedor) ---------- */
async function esUsuario(request, env){
  const auth = request.headers.get('Authorization') || '';
  const apikey = request.headers.get('apikey') || '';
  if (!/^Bearer\s+\S+/.test(auth) || !apikey) return false;
  const url = (env.SUPABASE_URL || SUPA).replace(/\/+$/, '');
  for (const fn of ['adm_es_admin', 'adm_es_vendedor', 'es_admin']){
    try {
      const r = await fetch(url + '/rest/v1/rpc/' + fn, { method: 'POST', headers: { 'Content-Type': 'application/json', apikey, Authorization: auth }, body: '{}' });
      if (r.ok && (await r.json()) === true) return true;
    } catch (e) { /* probar la siguiente */ }
  }
  return false;
}

const esGtin = (s) => {
  const k = String(s || '').replace(/\D/g, '');
  if (k !== String(s || '').trim() || ![8, 12, 13, 14].includes(k.length)) return false;
  let sum = 0; for (let i = k.length - 2, w = 3; i >= 0; i--, w = w === 3 ? 1 : 3) sum += +k[i] * w;
  return (10 - sum % 10) % 10 === +k[k.length - 1];
};

const INSTRUCCIONES = `Eres un asistente que llena la ficha de productos de Suinelectric, distribuidor de material eléctrico industrial en Venezuela (variadores de frecuencia INVT, Siemens, Schneider Electric, Hyundai Electric, Allen Bradley, Kinco, Phoenix Contact y otras marcas).

Busca en Google el producto que te indiquen y responde SOLO con un objeto JSON, sin texto antes ni después, con esta forma:
{"encontrado": true|false, "modelo": "", "marca": "", "nombre": "", "descripcion": "", "caracteristicas": [""], "tipo": "", "pagina_oficial": "", "manual": "", "confianza": "alta|media|baja", "nota": ""}

Reglas:
- Prefiere SIEMPRE la página oficial del fabricante (por ejemplo siemens.com / sieportal.siemens.com, se.com, invt.com, hyundai-electric.com, rockwellautomation.com, kinco, phoenixcontact.com). Usa tiendas o distribuidores solo para confirmar el modelo.
- Si te dan un código de barras (EAN/UPC), primero averigua a qué modelo exacto corresponde. Si ninguna página relaciona ese código con un modelo concreto, responde "encontrado": false y explica en "nota" que hace falta el modelo. No adivines.
- Nunca inventes datos técnicos. Si un dato no aparece en las fuentes, déjalo vacío.
- "modelo": la referencia exacta del fabricante (por ejemplo 3RV2011-1KA10, GD20-2R2G-4, ATV320U15N4C).
- "marca": en mayúsculas (SIEMENS, INVT, SCHNEIDER ELECTRIC, HYUNDAI…).
- "nombre": en español, corto y claro, máximo 90 caracteres, con lo que lo identifica. Ejemplo: "Variador de frecuencia GD20 2.2 kW 380 V trifásico".
- "descripcion": en español, un párrafo técnico de máximo 400 caracteres con los datos principales (corriente, potencia, tensión, contactos, montaje, etc.).
- "caracteristicas": de 3 a 8 datos técnicos cortos en español, por ejemplo "Tensión de mando: 24 V DC".
- "tipo": qué es el producto en dos o tres palabras (por ejemplo "Guardamotor", "Contactor", "Variador de frecuencia").
- "pagina_oficial" y "manual": URL completas solo si las viste en los resultados; si no, vacías. El manual debe ser un PDF o la página de descarga del fabricante.
- "confianza": alta si la ficha oficial coincide con el modelo exacto; media si solo hay fuentes de tiendas; baja si hay dudas.
- No incluyas precios.`;

async function gemini(env, cuerpo){
  const lista = Array.from(new Set((env.GEMINI_MODEL ? [env.GEMINI_MODEL] : []).concat(MODELOS)));
  const errores = []; let soloCupo = true;
  for (const modelo of lista){
    let r;
    try {
      r = await fetch('https://generativelanguage.googleapis.com/v1beta/models/' + modelo + ':generateContent', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': env.GEMINI_API_KEY },
        body: JSON.stringify(cuerpo),
      });
    } catch (e) { errores.push(modelo + ': ' + String(e.message || e).slice(0, 80)); soloCupo = false; continue; }
    if (r.ok) {
      const j = await r.json().catch(() => null);
      const c = j && j.candidates && j.candidates[0];
      if (c && c.content && (c.content.parts || []).some(p => p.text)) return j;
      errores.push(modelo + ': respuesta vacía' + (c && c.finishReason ? ' (' + c.finishReason + ')' : '')); soloCupo = false; continue;
    }
    const txt = (await r.text().catch(() => '')).replace(/\s+/g, ' ');
    const msg = (txt.match(/"message":\s*"([^"]{0,160})/) || [])[1] || txt.slice(0, 160);
    errores.push(modelo + ' ' + r.status + ': ' + msg);
    if (r.status !== 429) soloCupo = false;
    if (r.status === 401) break;   // clave inválida: no tiene sentido seguir
  }
  const e = new Error(errores.join(' | ') || 'Gemini no respondió'); e.cupo = soloCupo && errores.length > 0; throw e;
}

const sacarJson = (txt) => {
  const t = String(txt || '').replace(/```(?:json)?/gi, '');
  const a = t.indexOf('{'), b = t.lastIndexOf('}');
  if (a < 0 || b <= a) return null;
  try { return JSON.parse(t.slice(a, b + 1)); } catch (e) { return null; }
};
const corto = (s, n) => String(s || '').replace(/\s+/g, ' ').trim().slice(0, n);
const url = (s) => { const u = String(s || '').trim(); return /^https?:\/\/[^\s]+$/i.test(u) ? u : ''; };

/* ¿la página existe? (para no guardar enlaces inventados) */
async function existe(u){
  if (!u) return false;
  try {
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 6000);
    const r = await fetch(u, { method: 'GET', redirect: 'follow', signal: ctl.signal, headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130 Safari/537.36' } });
    clearTimeout(t);
    return r.status < 400 || r.status === 403;   // 403: el sitio bloquea robots, pero la página existe
  } catch (e) { return false; }
}

export async function onRequestGet(ctx){
  try { return await buscar(ctx); }
  catch (e) { return json({ error: 'Falló la búsqueda en el servidor.', detalle: String((e && e.stack) || e).slice(0, 600) }, 500); }
}

async function buscar({ request, env }){
  if (!(await esUsuario(request, env))) return json({ error: 'Inicia sesión en Gestión para buscar en la web.' }, 401);
  if (!env.GEMINI_API_KEY) return json({ error: 'Falta GEMINI_API_KEY en Cloudflare (la misma del asistente del chat).' }, 500);
  const q0 = new URL(request.url).searchParams;
  const q = corto(q0.get('q'), 80), marca = corto(q0.get('marca'), 40);
  if (q.length < 3) return json({ error: 'Escribe el modelo o escanea el código.' }, 400);

  const gtin = esGtin(q);
  const pedido = gtin
    ? `Código de barras (EAN/UPC): ${q}${marca ? '. Marca probable: ' + marca : ''}. Encuentra a qué producto corresponde y llena la ficha.`
    : `Modelo / referencia: ${q}${marca ? '. Marca: ' + marca : ''}. Llena la ficha de este producto.`;

  let res;
  try {
    res = await gemini(env, {
      systemInstruction: { parts: [{ text: INSTRUCCIONES }] },
      contents: [{ role: 'user', parts: [{ text: pedido }] }],
      tools: [{ google_search: {} }],
      generationConfig: { temperature: 0.1, maxOutputTokens: 2048 },
    });
  } catch (e) {
    const m = String(e.message || e);
    return json({ error: e.cupo ? 'Se acabó el cupo gratis de búsquedas por ahora. Prueba más tarde o llena la ficha a mano.' : 'No se pudo buscar en la web.', detalle: m.slice(0, 900) }, 502);
  }
  const cand = res.candidates && res.candidates[0];
  const texto = ((cand && cand.content && cand.content.parts) || []).filter(p => p.text && !p.thought).map(p => p.text).join('\n');
  const d = sacarJson(texto);
  const meta = (cand && cand.groundingMetadata) || {};
  const fuentes = (meta.groundingChunks || []).map(c => c.web).filter(Boolean)
    .map(w => ({ titulo: corto(w.title, 80), url: w.uri })).filter((f, i, a) => f.url && a.findIndex(x => x.titulo === f.titulo) === i).slice(0, 6);
  if (!d) return json({ encontrado: false, nota: 'No entendí la respuesta de la búsqueda. Prueba otra vez o con el modelo.', fuentes });

  const out = {
    encontrado: d.encontrado !== false && !!corto(d.modelo, 80),
    consulta: q, porCodigo: gtin,
    modelo: corto(d.modelo, 80), marca: corto(d.marca, 40).toUpperCase(), nombre: corto(d.nombre, 120),
    descripcion: corto(d.descripcion, 600), tipo: corto(d.tipo, 60),
    caracteristicas: (Array.isArray(d.caracteristicas) ? d.caracteristicas : []).map(x => corto(x, 120)).filter(Boolean).slice(0, 8),
    confianza: ['alta', 'media', 'baja'].includes(d.confianza) ? d.confianza : 'baja',
    nota: corto(d.nota, 300), fuentes,
  };
  // enlaces: solo si de verdad abren
  const [pag, man] = await Promise.all([url(d.pagina_oficial), url(d.manual)].map(async u => (await existe(u)) ? u : ''));
  out.pagina_oficial = pag; out.manual = man;
  return json(out);
}
