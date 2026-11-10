/* Páginas públicas /p/… y /c/…: registro de visitas (rastreo.js) y clics en
   "Cotizar por WhatsApp" (panel → Estadísticas y panel → Visitantes).
   Si el cliente tiene la sesión de la tienda abierta en este navegador, rastreo.js
   envía su sesión para que quede en su actividad (panel → Clientes). */
(function(){
  var r = null;
  function titulo(){ var h = document.querySelector('h1'); return h ? h.textContent.trim() : document.title; }
  function arrancar(){
    r = window.suinRastreo;
    if (!r) return;
    r.iniciar();
    var a = document.querySelector('.producto a[data-modelo]');
    if (/^\/p\//.test(location.pathname) && a) r.evento('ver_producto', { modelo: String(a.getAttribute('data-modelo')).slice(0, 80), origen: 'pagina' });
    r.tarjetas({
      selector: 'a.tarjeta',
      modelo: function(el){ var s = el.querySelector('strong'); return s ? s.textContent : ''; },
      contexto: function(){ return (/^\/p\//.test(location.pathname) ? 'Página del producto ' : 'Página ') + titulo(); },
    });
  }
  window.SUIN_RASTREO_MANUAL = true;
  var s = document.createElement('script');
  s.src = '/rastreo.js?v=5';
  s.async = true;
  s.onload = arrancar;
  document.head.appendChild(s);

  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a[data-modelo]') : null;
    if (!a || !r) return;
    r.evento('cotizar_whatsapp', { modelo: String(a.getAttribute('data-modelo')).slice(0, 80), origen: 'pagina' });
  }, true);
})();
/* Buscador de la cabecera: abre la búsqueda dentro de la tienda (#/buscar?q=…). */
(function(){
  var f = document.querySelector('form.buscador');
  if (!f) return;
  f.addEventListener('submit', function(e){
    var q = (f.q.value || '').trim();
    e.preventDefault();
    location.href = '/tienda' + (q ? '#/buscar?q=' + encodeURIComponent(q) : '');
  });
})();
/* Precios del cliente: las páginas /p/ y /c/ traen el precio de visitante.
   Si en este navegador hay una sesión abierta de la tienda, se cargan sus reglas
   de descuento desde Supabase y se recalculan los precios con la misma lógica
   que tienda.html (precioMostrado / reglaPara). Los visitantes no cargan nada. */
(function(){
  var URL_SB = 'https://yqnlxhbjassrkudnhvpr.supabase.co';
  var CLAVE = 'sb_publishable_LOYjM5sqvQbBLIkH4KJTKQ_UfxrpTeC';
  var LLAVE = 'sb-yqnlxhbjassrkudnhvpr-auth-token';
  var DESCUENTO_GENERAL = 60;
  var hay = null;
  try { hay = localStorage.getItem(LLAVE); } catch (e) {}
  if (!hay || !document.querySelector('.precio-cli')) return;

  // que: 0 modelo · 1 marca+categoría · 2 categoría · 3 marca · 4 todo   quien: 0 cliente · 1 tipo · 2 todos
  function rango(que, quien){ return que === 0 ? 1 + quien : 4 + quien * 4 + (que - 1); }
  function may(s){ return String(s || '').toUpperCase().trim(); }
  function clave(s){ return String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]/g, ''); }
  function enCat(p, cat){ var k = clave(cat); return (p.cats || []).some(function(x){ return clave(x) === k; }); }
  function reglaPara(p, reglas, email, tipo){
    var mejor = null, mejorRango = 99;
    for (var i = 0; i < reglas.length; i++){
      var r = reglas[i], quien, que;
      if (r.cliente_email){ if (!email || r.cliente_email !== email) continue; quien = 0; }
      else if (r.tipo_id){ if (!tipo || r.tipo_id !== tipo) continue; quien = 1; }
      else quien = 2;
      if (r.modelo){ if (may(r.modelo) !== may(p.modelo)) continue; que = 0; }
      else {
        if (r.marca && may(r.marca) !== may(p.marca)) continue;
        if (r.categoria && !enCat(p, r.categoria)) continue;
        que = r.marca && r.categoria ? 1 : r.categoria ? 2 : r.marca ? 3 : 4;
      }
      if (p.manual && que === 4) continue;   // los manuales solo usan reglas de marca, categoría o modelo
      var k = rango(que, quien);
      if (k < mejorRango){ mejor = r; mejorRango = k; }
    }
    return mejor;
  }
  function precioPara(p, r, general){
    if (r && r.precio_fijo != null) return Number(r.precio_fijo);
    if (p.lista == null) return null;
    if (r && r.descuento_pct != null){
      var esGeneral = !r.cliente_email && !r.tipo_id && !r.marca && !r.modelo && !r.categoria;
      return p.lista * (1 - (esGeneral ? general : Number(r.descuento_pct)) / 100);
    }
    return p.manual ? p.lista : p.lista * (1 - general / 100);
  }
  function dinero(n){ return '$' + Math.ceil(n).toLocaleString('en-US'); }

  function aplicar(reglas, email, tipo){
    var g = null;
    reglas.forEach(function(r){ if (!g && !r.cliente_email && !r.tipo_id && !r.marca && !r.modelo && !r.categoria && r.descuento_pct != null) g = r; });
    var general = g ? Number(g.descuento_pct) : DESCUENTO_GENERAL;
    var els = document.querySelectorAll('.precio-cli');
    for (var i = 0; i < els.length; i++){
      var el = els[i];
      var l = el.getAttribute('data-lista');
      var p = { lista: (l === '' || l == null || isNaN(Number(l))) ? null : Number(l),
                marca: el.getAttribute('data-marca'), modelo: el.getAttribute('data-modelo'),
                manual: el.getAttribute('data-manual') === '1',
                cats: String(el.getAttribute('data-cat') || '').split('|').filter(Boolean) };
      var r = reglaPara(p, reglas, email, tipo);
      var final = precioPara(p, r, general);
      if (final == null || isNaN(final)) continue;
      var grande = el.classList.contains('p-precio');
      var propio = !!(r && (r.cliente_email || r.tipo_id));
      var fijo = !!(r && r.precio_fijo != null);
      var badge = '';
      if ((propio || fijo) && p.lista > 0 && final < p.lista){
        var pct = Math.round((1 - final / p.lista) * 1000) / 10;
        badge = '<span class="dto-badge" title="' + (fijo ? 'Precio especial para ti' : 'Tu descuento de cliente') + '">-' +
                String(pct).replace('.', ',') + '%' + (fijo ? ' · especial' : '') + '</span>';
      }
      el.innerHTML = dinero(final) + (grande ? ' <small>USD</small>' : '') + badge;
      if (grande && (propio || fijo)){
        var nota = el.parentNode.querySelector('.p-nota-cli');
        if (!nota){ nota = document.createElement('div'); nota.className = 'p-nota-cli'; el.parentNode.insertBefore(nota, el.nextSibling); }
        nota.textContent = fijo ? 'Precio especial de tu cuenta' : 'Precio con tu descuento de cliente';
      }
    }
  }

  var s = document.createElement('script');
  s.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
  s.async = true;
  s.onload = function(){
    var sb;
    try {
      sb = window.supabase.createClient(URL_SB, CLAVE, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false, flowType: 'implicit' } });
    } catch (e) { return; }
    sb.auth.getSession().then(function(res){
      var ses = res && res.data && res.data.session;
      var email = ses && ses.user ? String(ses.user.email || '').toLowerCase() : null;
      if (!email) return;
      return Promise.all([
        sb.from('clientes').select('tipo_id,activo').eq('email', email).maybeSingle(),
        sb.from('reglas_descuento').select('*').eq('activo', true),
      ]).then(function(r){
        var cli = r[0] && r[0].data;
        if (cli && cli.activo === false) return;
        var reglas = (r[1] && !r[1].error && r[1].data) || [];
        if (!reglas.length) return;
        aplicar(reglas, email, cli ? cli.tipo_id : null);
      });
    }).catch(function(e){ console.warn('No se pudieron cargar los precios del cliente', e); });
  };
  document.head.appendChild(s);
})();
/* Chat con un asesor en las páginas /p/ y /c/.
   Estas páginas no traen la burbuja de chat de la tienda. Este mini chat aparece
   solo cuando hay una conversación: si un asesor le escribió primero desde el panel
   (En vivo → Escribirle, 30_chat_iniciar.sql) o si el visitante ya venía chateando
   en la tienda. Usa la misma conversación que la tienda (misma llave en este
   navegador), así que al pasar de una página a la otra sigue el mismo chat. */
(function(){
  var RPC = 'https://yqnlxhbjassrkudnhvpr.supabase.co/rest/v1/rpc/';
  var CLAVE = 'sb_publishable_LOYjM5sqvQbBLIkH4KJTKQ_UfxrpTeC';
  var LLAVE = 'suin_chat_v1';
  var WA = '584124111319';
  if (!window.fetch || !window.JSON) return;

  var estado = { token: null, nombre: '', contacto: '', activo: false, visto: 0 };
  function leerEstado(){
    try { var g = JSON.parse(localStorage.getItem(LLAVE)); if (g) for (var k in g) estado[k] = g[k]; } catch (e) {}
  }
  function guardar(){ try { localStorage.setItem(LLAVE, JSON.stringify(estado)); } catch (e) {} }
  leerEstado();

  function rpc(fn, cuerpo){
    return fetch(RPC + fn, { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: CLAVE }, body: JSON.stringify(cuerpo) })
      .then(function(r){
        return r.json().catch(function(){ return null; }).then(function(j){
          if (!r.ok){ var e = new Error((j && j.message) || 'Error ' + r.status); e.status = r.status; throw e; }
          return j;
        });
      });
  }
  function esc(t){ return String(t == null ? '' : t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
  function enlazar(t){ return esc(t).replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener">$1</a>'); }
  function hora(f){
    try {
      var d = new Date(f), hoy = new Date();
      var h = d.toLocaleTimeString('es-VE', { hour: 'numeric', minute: '2-digit' });
      return d.toDateString() === hoy.toDateString() ? h : d.toLocaleDateString('es-VE', { day: '2-digit', month: '2-digit' }) + ' ' + h;
    } catch (e) { return ''; }
  }
  function escritorio(){ return window.matchMedia('(min-width: 641px)').matches; }

  var AUTORES = { asistente: '🤖 Asistente virtual', suinelectric: 'Asesor Suinelectric' };
  var mensajes = [], ultimoId = 0, abierto = false, timer = null, esperando = 0;
  var burbuja = null, panel = null, lista = null, texto = null, btn = null, punto = null, etiqueta = null;

  var CSS =
    '#sc-burbuja{position:fixed;right:24px;bottom:24px;z-index:58;display:flex;align-items:center;gap:10px;height:56px;padding:0 20px 0 16px;' +
      'background:var(--tinta);color:#fff;border:none;border-radius:28px;cursor:pointer;font-family:var(--sans);font-size:15px;font-weight:600;' +
      'box-shadow:0 10px 28px rgba(9,24,34,.32)}' +
    '#sc-burbuja:hover{background:var(--tinta-2)}#sc-burbuja svg{width:24px;height:24px;flex:none}' +
    '#sc-burbuja[hidden]{display:none}' +
    '#sc-punto{position:absolute;top:-4px;right:-2px;min-width:22px;height:22px;padding:0 6px;border-radius:11px;background:var(--amarillo);color:var(--tinta);' +
      'font-size:12.5px;font-weight:700;display:none;align-items:center;justify-content:center;border:2px solid #fff}' +
    '#sc-burbuja.con-nuevos #sc-punto{display:flex}' +
    '#sc-panel{position:fixed;right:24px;bottom:24px;z-index:96;width:380px;max-width:calc(100vw - 24px);height:520px;max-height:calc(100vh - 48px);max-height:calc(100dvh - 48px);' +
      'display:none;flex-direction:column;background:#fff;color:var(--texto);border:1px solid var(--linea);border-radius:10px;overflow:hidden;box-shadow:0 20px 60px rgba(9,24,34,.35)}' +
    '#sc-panel.abierto{display:flex}' +
    '.sc-cab{display:flex;align-items:center;gap:12px;padding:14px 14px 14px 16px;background:var(--tinta);color:#fff;border-bottom:3px solid var(--amarillo)}' +
    '.sc-avatar{width:40px;height:40px;border-radius:50%;background:var(--azul);flex:none;display:flex;align-items:center;justify-content:center;font-family:var(--display);font-weight:700;font-size:19px}' +
    '.sc-cab h4{margin:0;font-family:var(--display);font-size:19px;font-weight:700;line-height:1.15}.sc-cab p{margin:2px 0 0;font-size:12.5px;color:#b9cad6;line-height:1.3}' +
    '.sc-x{margin-left:auto;background:none;border:none;color:#fff;font-size:20px;cursor:pointer;width:36px;height:36px;border-radius:50%;flex:none}.sc-x:hover{background:rgba(255,255,255,.12)}' +
    '#sc-mensajes{flex:1;overflow-y:auto;padding:16px 14px;background:var(--fondo);display:flex;flex-direction:column;gap:8px;overscroll-behavior:contain}' +
    '.sc-msj{max-width:84%;padding:9px 12px;border-radius:12px;font-size:14.5px;line-height:1.45;white-space:pre-wrap;overflow-wrap:anywhere;box-shadow:0 1px 2px rgba(9,24,34,.06)}' +
    '.sc-msj time{display:block;margin-top:3px;font-size:11px;opacity:.65;text-align:right}' +
    '.sc-msj.de-suin{align-self:flex-start;background:#fff;border:1px solid var(--linea-s);border-bottom-left-radius:4px}' +
    '.sc-msj.de-cliente{align-self:flex-end;background:var(--azul-s);border:1px solid #cfe8f0;border-bottom-right-radius:4px}' +
    '.sc-msj.pendiente{opacity:.6}.sc-msj.de-asesor{border-left:3px solid var(--amarillo)}' +
    '.sc-autor{display:block;margin-bottom:3px;font-size:11.5px;font-weight:700;color:var(--azul-t)}.sc-msj.de-asesor .sc-autor{color:var(--tinta)}' +
    '.sc-nota{align-self:center;text-align:center;font-size:12.5px;color:var(--t3);line-height:1.4;padding:4px 10px;max-width:92%}' +
    '#sc-form{border-top:1px solid var(--linea);background:#fff;padding:10px 12px calc(10px + env(safe-area-inset-bottom,0px));margin:0}' +
    '.sc-fila{display:flex;gap:8px;align-items:flex-end}' +
    '#sc-texto{flex:1;min-width:0;resize:none;border:1px solid var(--linea);border-radius:var(--radio);padding:10px 11px;font:inherit;font-size:15px;line-height:1.35;max-height:120px;color:var(--texto)}' +
    '#sc-texto:focus{outline:2px solid var(--azul);outline-offset:-1px;border-color:var(--azul)}' +
    '#sc-enviar{flex:none;height:44px;padding:0 16px;border:none;border-radius:var(--radio);cursor:pointer;background:var(--amarillo);color:var(--tinta);font-weight:700;font-size:14.5px}' +
    '#sc-enviar:hover{background:var(--amarillo-h)}#sc-enviar:disabled{opacity:.55;cursor:default}' +
    '.sc-pie{margin-top:8px;font-size:12.5px;color:var(--t3);text-align:center}.sc-pie a{color:var(--wa);font-weight:600;text-decoration:none}' +
    '@media (max-width:640px){' +
      '#sc-burbuja{right:14px;bottom:calc(88px + env(safe-area-inset-bottom,0px));height:52px;min-width:52px;padding:0 14px;justify-content:center}' +
      '#sc-burbuja:not(.con-nuevos){width:52px;padding:0}#sc-burbuja:not(.con-nuevos) .sc-etiqueta{display:none}' +
      '#sc-panel{top:0;left:0;right:0;bottom:0;width:100%;max-width:none;height:100%;max-height:none;border-radius:0;border:none}' +
      '.sc-cab{padding-top:calc(14px + env(safe-area-inset-top,0px))}#sc-texto{font-size:16px}' +
    '}';

  function crear(){
    if (burbuja) return;
    var st = document.createElement('style');
    st.textContent = CSS;
    document.head.appendChild(st);

    burbuja = document.createElement('button');
    burbuja.type = 'button'; burbuja.id = 'sc-burbuja'; burbuja.setAttribute('aria-label', 'Abrir el chat con un asesor');
    burbuja.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M4 3h16a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H9.4l-4.7 3.8A1 1 0 0 1 3 21V5a2 2 0 0 1 1-2zm1 2v13.9L8.7 16H20V5H5zm3 4h8v2H8V9zm0-3h8v2H8V6zm0 6h5v2H8v-2z"/></svg>' +
      '<span class="sc-etiqueta" id="sc-etiqueta">Chat</span><span id="sc-punto">1</span>';

    panel = document.createElement('section');
    panel.id = 'sc-panel'; panel.setAttribute('role', 'dialog'); panel.setAttribute('aria-modal', 'false'); panel.setAttribute('aria-labelledby', 'sc-titulo');
    panel.innerHTML = '<div class="sc-cab"><div class="sc-avatar" aria-hidden="true">S</div><div><h4 id="sc-titulo">Asesor Suinelectric</h4><p>Te respondemos por aquí</p></div>' +
      '<button type="button" class="sc-x" id="sc-cerrar" aria-label="Cerrar chat">✕</button></div>' +
      '<div id="sc-mensajes" aria-live="polite"></div>' +
      '<form id="sc-form"><div class="sc-fila"><textarea id="sc-texto" rows="1" maxlength="1000" placeholder="Escribe tu mensaje…" aria-label="Mensaje"></textarea>' +
      '<button type="submit" id="sc-enviar">Enviar</button></div>' +
      '<div class="sc-pie">¿Prefieres WhatsApp? <a href="https://wa.me/' + WA + '?text=' + encodeURIComponent('Hola, vengo de la web de Suinelectric.') + '" target="_blank" rel="noopener">Escríbenos al 0412</a></div></form>';

    document.body.appendChild(burbuja);
    document.body.appendChild(panel);
    lista = document.getElementById('sc-mensajes'); texto = document.getElementById('sc-texto'); btn = document.getElementById('sc-enviar');
    punto = document.getElementById('sc-punto'); etiqueta = document.getElementById('sc-etiqueta');

    burbuja.addEventListener('click', abrir);
    document.getElementById('sc-cerrar').addEventListener('click', cerrar);
    document.getElementById('sc-form').addEventListener('submit', function(e){ e.preventDefault(); enviar(); });
    texto.addEventListener('input', ajustarAlto);
    texto.addEventListener('keydown', function(e){ if (e.key === 'Enter' && !e.shiftKey && escritorio()){ e.preventDefault(); enviar(); } });
    document.addEventListener('keydown', function(e){ if (e.key === 'Escape' && abierto) cerrar(); });
  }

  function ajustarAlto(){ texto.style.height = 'auto'; texto.style.height = Math.min(texto.scrollHeight, 120) + 'px'; }

  function pintar(){
    if (!lista) return;
    var html = '';
    for (var i = 0; i < mensajes.length; i++){
      var m = mensajes[i];
      html += '<div class="sc-msj ' + (m.autor === 'cliente' ? 'de-cliente' : 'de-suin' + (m.autor === 'suinelectric' ? ' de-asesor' : '')) + (m.pendiente ? ' pendiente' : '') + '">' +
        (AUTORES[m.autor] ? '<span class="sc-autor">' + AUTORES[m.autor] + '</span>' : '') +
        enlazar(m.texto) + '<time>' + (m.pendiente ? 'enviando…' : hora(m.creado)) + '</time></div>';
    }
    if (esperando > 0) html += '<div class="sc-nota">Escribiendo…</div>';
    else if (!mensajes.length) html += '<div class="sc-nota">Escríbenos tu consulta y un asesor te responde por aquí.</div>';
    lista.innerHTML = html;
    lista.scrollTop = lista.scrollHeight;
  }

  function marcar(){
    if (!burbuja) return;
    var nuevos = 0, asesor = false;
    for (var i = 0; i < mensajes.length; i++) if (mensajes[i].autor !== 'cliente' && mensajes[i].id > (estado.visto || 0)){ nuevos++; if (mensajes[i].autor === 'suinelectric') asesor = true; }
    if (abierto || !nuevos){
      burbuja.classList.remove('con-nuevos');
      etiqueta.textContent = 'Chat';
      if (abierto && ultimoId > (estado.visto || 0)){ estado.visto = ultimoId; guardar(); }
      return;
    }
    punto.textContent = nuevos > 9 ? '9+' : String(nuevos);
    etiqueta.textContent = asesor ? 'Un asesor te escribió' : 'Mensaje nuevo';
    burbuja.classList.add('con-nuevos');
  }

  function traer(){
    if (!estado.token || !estado.activo || document.hidden) return Promise.resolve();
    return rpc('chat_leer', { p_token: estado.token, p_desde: ultimoId }).then(function(data){
      if (!data || !data.length) return;
      var cambio = false;
      for (var i = 0; i < data.length; i++){
        var m = data[i], esta = false;
        ultimoId = Math.max(ultimoId, m.id);
        for (var j = 0; j < mensajes.length; j++) if (mensajes[j].id === m.id) esta = true;
        if (!esta){ mensajes.push(m); cambio = true; }
      }
      mensajes.sort(function(a, b){ return (a.id || Infinity) - (b.id || Infinity); });
      if (cambio && abierto) pintar();
      marcar();
    }).catch(function(){ /* sin conexión: se reintenta en el próximo ciclo */ });
  }

  function programar(){
    clearTimeout(timer);
    if (!estado.activo) return;
    timer = setTimeout(function(){ traer().then(programar); }, abierto ? 4000 : 25000);
  }

  function abrir(){
    crear();
    abierto = true;
    panel.classList.add('abierto');
    burbuja.hidden = true;
    pintar(); marcar();
    traer(); programar();
    if (escritorio()) setTimeout(function(){ texto.focus(); }, 60);
  }
  function cerrar(){
    if (!abierto) return;
    abierto = false;
    panel.classList.remove('abierto');
    burbuja.hidden = false;
    programar();
  }

  // Si la IA sigue encendida en este chat, contesta ella; si ya lo atiende una persona, el servidor no hace nada.
  function pedirIA(){
    esperando++; pintar();
    var fin = function(){ esperando = Math.max(0, esperando - 1); traer().then(function(){ if (abierto) pintar(); }); };
    try {
      fetch('/api/asistente', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: estado.token }), keepalive: true }).then(fin, fin);
    } catch (e) { fin(); }
  }

  function enviar(){
    var t = texto.value.trim();
    if (!t || !estado.token){ texto.focus(); return; }
    var tmp = { id: null, autor: 'cliente', texto: t, pendiente: true };
    mensajes.push(tmp);
    texto.value = ''; ajustarAlto();
    btn.disabled = true;
    pintar();
    rpc('chat_enviar', { p_token: estado.token, p_texto: t, p_nombre: null, p_contacto: null, p_pagina: null }).then(function(data){
      tmp.id = data && data.id; tmp.pendiente = false; tmp.creado = new Date().toISOString();
      estado.activo = true; guardar();
      btn.disabled = false;
      pintar(); programar();
      pedirIA();
    }).catch(function(e){
      mensajes = mensajes.filter(function(m){ return m !== tmp; });
      if (!texto.value) texto.value = t;
      ajustarAlto();
      btn.disabled = false;
      pintar();
      var msj = e && e.message && e.message.length < 90 && !/function|schema|permission|Error \d/i.test(e.message) ? e.message : 'No se pudo enviar. Revisa tu conexión o escríbenos por WhatsApp.';
      lista.insertAdjacentHTML('beforeend', '<div class="sc-nota">' + esc(msj) + '</div>');
      lista.scrollTop = lista.scrollHeight;
    });
  }

  // ¿Un asesor le escribió primero a este navegador? (panel → En vivo → Escribirle)
  var sinAviso = false, fallos = 0;
  function revisarAviso(){
    var vis = window.suinRastreo && window.suinRastreo.visitante;
    if (!vis || sinAviso || document.hidden) return;
    leerEstado();   // por si chateó en la tienda en otra pestaña
    rpc('chat_aviso', { p_visitante: vis, p_token: estado.token || null }).then(function(data){
      fallos = 0;
      if (!data || !data.token || !(data.id > (estado.aviso || 0))) return;
      if (estado.token !== data.token){ estado.token = data.token; mensajes = []; ultimoId = 0; }
      estado.activo = true; estado.aviso = data.id; guardar();
      crear();
      return traer().then(function(){
        if (abierto){ pintar(); marcar(); }
        else if (escritorio()) abrir();
        else marcar();
        programar();
      });
    }).catch(function(){ if (++fallos >= 3) sinAviso = true; });   // p. ej. todavía no se corrió el SQL
  }

  function iniciar(){
    if (estado.activo && estado.token){ crear(); traer(); programar(); }
    setTimeout(revisarAviso, 2500);
    setInterval(revisarAviso, 15000);
    document.addEventListener('visibilitychange', function(){ if (!document.hidden){ revisarAviso(); if (estado.activo){ traer(); programar(); } } });
  }
  if (document.body) iniciar(); else document.addEventListener('DOMContentLoaded', iniciar);
})();
