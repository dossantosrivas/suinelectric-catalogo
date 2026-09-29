/* =====================================================================
   REGISTRO DE VISITAS  (panel → Visitantes y panel → Estadísticas)
   ---------------------------------------------------------------------
   Lo usan la tienda (/tienda) y las páginas públicas (/p/…, /c/…).
   Anota en Supabase (tabla eventos, ver 04_estadisticas.sql y
   10_visitantes.sql):
     · visita         al entrar: lugar (Cloudflare, /api/geo), equipo,
                      navegador, de dónde vino y la página de entrada
     · ver_tarjetas   las tarjetas de producto que estuvieron en pantalla
                      (al menos la mitad visible durante casi un segundo)
     · y lo que le pase la página (búsquedas, fichas, carrito, WhatsApp)
   Cada navegador lleva un código aleatorio (visitante). Una visita se
   cierra tras 30 minutos sin actividad. No se guardan nombres ni la IP.
   No se anota a los administradores (ni en este navegador después de
   que un administrador entró), ni a robots como Google.
   Clave pública de Supabase: es segura en la página.
   ===================================================================== */
(function(){
  if (window.suinRastreo) return;
  var BASE = 'https://yqnlxhbjassrkudnhvpr.supabase.co';
  var CLAVE = 'sb_publishable_LOYjM5sqvQbBLIkH4KJTKQ_UfxrpTeC';
  var URL_EV = BASE + '/rest/v1/eventos';
  var FIN_VISITA = 30 * 60 * 1000;
  var NUEVOS = ['visitante', 'visita', 'pais', 'region', 'ciudad', 'proveedor', 'dispositivo', 'navegador', 'sistema', 'referencia', 'pagina', 'modelos'];
  var ua = navigator.userAgent || '';
  var ES_ROBOT = !!navigator.webdriver ||
    /bot\b|bot\/|crawl|spider|slurp|headless|lighthouse|pagespeed|facebookexternalhit|whatsapp|telegram|preview|curl|wget|python|axios|node-fetch/i.test(ua);

  function ls(k, v){
    try {
      if (v === undefined) return localStorage.getItem(k);
      localStorage.setItem(k, v);
    } catch (e) {}
    return null;
  }
  function uuid(){
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c){
      var r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
    });
  }
  function noContar(){ return ES_ROBOT || ls('suin_no_contar') === '1'; }

  var visitante = ls('suin_visitante');
  if (!visitante || visitante.length > 40){ visitante = uuid(); ls('suin_visitante', visitante); }

  // Visita actual (compartida entre pestañas). Se renueva tras 30 min sin actividad.
  var visMem = null;
  function visitaActual(){
    var v = null;
    try { v = JSON.parse(ls('suin_visita') || 'null'); } catch (e) {}
    if (!v || !v.id) v = visMem;
    var ahora = Date.now();
    if (!v || !v.id || !(ahora - (v.u || 0) <= FIN_VISITA)) v = { id: uuid(), u: ahora, a: 0 };
    v.u = ahora;
    visMem = v;
    ls('suin_visita', JSON.stringify(v));
    return v;
  }

  // Sesión de la tienda (si el cliente entró con su cuenta, el evento queda a su nombre).
  function token(){
    try {
      var s = JSON.parse(localStorage.getItem('sb-yqnlxhbjassrkudnhvpr-auth-token') || 'null');
      if (s && s.access_token && (!s.expires_at || s.expires_at * 1000 > Date.now() + 30000)) return s.access_token;
    } catch (e) {}
    return null;
  }

  // Si todavía no se corrió 10_visitantes.sql, se envía solo lo de antes.
  var sinColumnas = false;
  function enviar(fila){
    if (sinColumnas){
      if (fila.tipo === 'visita' || fila.tipo === 'ver_tarjetas') return;
      NUEVOS.forEach(function(k){ delete fila[k]; });
    }
    var t = token();
    var post = function(conSesion){
      var h = { 'Content-Type': 'application/json', apikey: CLAVE, Prefer: 'return=minimal' };
      if (conSesion && t) h.Authorization = 'Bearer ' + t;
      return fetch(URL_EV, { method: 'POST', keepalive: true, headers: h, body: JSON.stringify(fila) });
    };
    try {
      post(true).then(function(r){
        if (r.ok) return;
        if (r.status === 401 && t) return post(false);                 // sesión vencida: como visitante
        if (r.status === 400 && !sinColumnas){
          return r.text().then(function(txt){
            if (/visitante|visita|modelos|pais|column|PGRST204|eventos_tipo_check/i.test(txt)){
              sinColumnas = true;
              if (fila.tipo !== 'visita' && fila.tipo !== 'ver_tarjetas') enviar(fila);
            }
          });
        }
      }).catch(function(){});
    } catch (e) {}
  }

  /* ---------- Equipo, navegador y de dónde vino ---------- */
  function dispositivo(){
    if (/iPad|Tablet|PlayBook|Silk|Kindle/i.test(ua) || (/Android/i.test(ua) && !/Mobile/i.test(ua)) ||
        (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1)) return 'Tablet';
    if (/Mobi|iPhone|iPod|Android|Windows Phone/i.test(ua)) return 'Celular';
    return 'Computadora';
  }
  function navegador(){
    if (/FBAN|FBAV|FB_IAB/i.test(ua)) return 'Facebook (app)';
    if (/Instagram/i.test(ua)) return 'Instagram (app)';
    if (/SamsungBrowser/i.test(ua)) return 'Samsung Internet';
    if (/OPR\/|Opera|OPiOS/i.test(ua)) return 'Opera';
    if (/Edg(e|A|iOS)?\//i.test(ua)) return 'Edge';
    if (/FxiOS|Firefox/i.test(ua)) return 'Firefox';
    if (/CriOS|Chrome\//i.test(ua)) return 'Chrome';
    if (/Safari\//i.test(ua)) return 'Safari';
    return 'Otro';
  }
  function sistema(){
    if (/Windows/i.test(ua)) return 'Windows';
    if (/Android/i.test(ua)) return 'Android';
    if (/iPhone|iPad|iPod/i.test(ua) || (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1)) return 'iOS';
    if (/Mac OS X|Macintosh/i.test(ua)) return 'macOS';
    if (/CrOS/i.test(ua)) return 'ChromeOS';
    if (/Linux/i.test(ua)) return 'Linux';
    return 'Otro';
  }
  var SITIOS = [
    [/(^|\.)google\./, 'Google'], [/(^|\.)bing\.com$/, 'Bing'], [/yahoo\./, 'Yahoo'], [/duckduckgo\./, 'DuckDuckGo'],
    [/(^|\.)(facebook\.com|fb\.com|fb\.me)$/, 'Facebook'], [/instagram\./, 'Instagram'], [/(whatsapp\.|wa\.me)/, 'WhatsApp'],
    [/(^|\.)(t\.co|twitter\.com|x\.com)$/, 'X (Twitter)'], [/linkedin\./, 'LinkedIn'], [/(youtube\.|youtu\.be)/, 'YouTube'],
    [/tiktok\./, 'TikTok'], [/(^|\.)(t\.me|telegram\.)/, 'Telegram'], [/mercadoli[bv]re\./, 'MercadoLibre'],
    [/(chatgpt\.com|openai\.com)/, 'ChatGPT'], [/(perplexity\.ai)/, 'Perplexity'], [/(claude\.ai)/, 'Claude'],
  ];
  function referencia(){
    var q = {};
    try { new URLSearchParams(location.search).forEach(function(v, k){ q[k.toLowerCase()] = v; }); } catch (e) {}
    if (q.gclid || q.gbraid || q.wbraid) return 'Google Ads';
    if (q.utm_source) return ('utm: ' + q.utm_source + (q.utm_campaign ? ' / ' + q.utm_campaign : '')).slice(0, 120);
    if (q.fbclid) return 'Facebook';
    var r = document.referrer || '';
    if (!r) return null;
    var host = '';
    try { host = new URL(r).hostname.toLowerCase(); } catch (e) { return null; }
    if (!host || host === location.hostname) return null;          // vino de la misma tienda
    for (var i = 0; i < SITIOS.length; i++) if (SITIOS[i][0].test(host)) return SITIOS[i][1];
    return host.replace(/^www\./, '').slice(0, 120);
  }
  function pagina(){
    var h = location.hash || '';
    try { h = decodeURIComponent(h); } catch (e) {}
    return (location.pathname.replace(/\.html$/, '') + h).slice(0, 200);
  }
  function origen(){ return /^\/tienda/.test(location.pathname) ? 'tienda' : 'pagina'; }

  // Primera acción de cada visita: la anota con lugar y equipo.
  function anunciar(v){
    if (v.a) return;
    v.a = 1; visMem = v; ls('suin_visita', JSON.stringify(v));
    var fila = { tipo: 'visita', visitante: visitante, visita: v.id, origen: origen(), pagina: pagina(),
                 referencia: referencia(), dispositivo: dispositivo(), navegador: navegador(), sistema: sistema() };
    var hecho = false;
    var listo = function(geo){
      if (hecho) return; hecho = true;
      if (geo) ['pais', 'region', 'ciudad', 'proveedor'].forEach(function(k){ if (geo[k]) fila[k] = String(geo[k]); });
      enviar(fila);
    };
    var ctrl = window.AbortController ? new AbortController() : null;
    setTimeout(function(){ if (ctrl) ctrl.abort(); listo(null); }, 3000);
    try {
      fetch('/api/geo', { cache: 'no-store', signal: ctrl ? ctrl.signal : undefined })
        .then(function(r){ return r.ok ? r.json() : null; })
        .then(listo, function(){ listo(null); });
    } catch (e) { listo(null); }
  }

  var arrancado = false, cola = [];
  function evento(tipo, datos){
    if (!arrancado){ if (cola.length < 50) cola.push([tipo, datos]); return; }
    if (noContar()) return;
    var v = visitaActual();
    anunciar(v);
    var fila = { tipo: tipo, visitante: visitante, visita: v.id, origen: origen() };
    for (var k in (datos || {})) if (datos[k] !== undefined) fila[k] = datos[k];
    enviar(fila);
  }

  /* ---------- Tarjetas de producto que se vieron ---------- */
  var cfg = null, io = null, buffer = [], bufCtx = null, tVaciar = null, vistos = {}, visitaVistos = null;
  function vaciar(){
    clearTimeout(tVaciar); tVaciar = null;
    if (!buffer.length) return;
    var lista = buffer, ctx = bufCtx;
    buffer = []; bufCtx = null;
    evento('ver_tarjetas', { texto: ctx || null, modelos: lista });
  }
  function anotarTarjeta(el){
    if (noContar() || !cfg) return;
    var m = '';
    try { m = String(cfg.modelo(el) || '').trim().slice(0, 80); } catch (e) {}
    if (!m) return;
    var ctx = '';
    try { ctx = String(cfg.contexto ? cfg.contexto() || '' : '').trim().slice(0, 120); } catch (e) {}
    var v = visitaActual();
    if (visitaVistos !== v.id){ vistos = {}; visitaVistos = v.id; }
    var clave = ctx + '|' + m;
    if (vistos[clave]) return;                     // ya contada en esta visita y en esta sección
    vistos[clave] = 1;
    if (bufCtx !== null && bufCtx !== ctx) vaciar();
    bufCtx = ctx;
    buffer.push(m);
    if (buffer.length >= 60) vaciar();
    else if (!tVaciar) tVaciar = setTimeout(vaciar, 15000);
  }
  function observar(el){
    if (el.__suinObs) return;
    el.__suinObs = 1;
    io.observe(el);
  }
  function observarEn(nodo){
    if (!cfg || !io || !nodo || nodo.nodeType !== 1) return;
    if (nodo.matches && nodo.matches(cfg.selector)) observar(nodo);
    if (nodo.querySelectorAll) { var l = nodo.querySelectorAll(cfg.selector); for (var i = 0; i < l.length; i++) observar(l[i]); }
  }
  function vigilarTarjetas(){
    if (!cfg || io || !arrancado || noContar() || !('IntersectionObserver' in window)) return;
    io = new IntersectionObserver(function(ents){
      ents.forEach(function(en){
        var el = en.target;
        if (en.isIntersecting && en.intersectionRatio >= 0.5){
          if (!el.__suinT) el.__suinT = setTimeout(function(){
            el.__suinT = null;
            if (!el.isConnected) return;
            io.unobserve(el);
            anotarTarjeta(el);
          }, 800);
        } else if (el.__suinT){ clearTimeout(el.__suinT); el.__suinT = null; }
      });
    }, { threshold: [0, 0.5] });
    observarEn(document.body);
    new MutationObserver(function(muts){
      for (var i = 0; i < muts.length; i++){
        var add = muts[i].addedNodes;
        for (var j = 0; j < add.length; j++) observarEn(add[j]);
      }
    }).observe(document.body, { childList: true, subtree: true });
  }
  document.addEventListener('visibilitychange', function(){ if (document.visibilityState === 'hidden') vaciar(); });
  window.addEventListener('pagehide', vaciar);

  window.suinRastreo = {
    visitante: visitante,
    // Empieza a anotar (la tienda lo llama cuando ya sabe si es un administrador).
    iniciar: function(){
      if (arrancado) return;
      arrancado = true;
      var pend = cola; cola = [];
      if (noContar()) return;
      anunciar(visitaActual());
      pend.forEach(function(e){ evento(e[0], e[1]); });
      vigilarTarjetas();
    },
    evento: evento,
    // { selector, modelo(el) → texto, contexto() → dónde está (búsqueda, categoría…) }
    tarjetas: function(opciones){ cfg = opciones; vigilarTarjetas(); },
    // Este navegador es de un administrador: no se vuelve a anotar nada.
    noContarMas: function(){ ls('suin_no_contar', '1'); cola = []; buffer = []; },
    vaciar: vaciar,
  };
  if (!window.SUIN_RASTREO_MANUAL) window.suinRastreo.iniciar();
})();
