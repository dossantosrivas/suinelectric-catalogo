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
  s.src = '/rastreo.js?v=3';
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

  var RANGO = { '00': 1, '01': 2, '02': 3, '10': 4, '20': 5, '11': 6, '21': 7, '12': 8, '22': 9 };
  function may(s){ return String(s || '').toUpperCase().trim(); }
  function reglaPara(p, reglas, email, tipo){
    var mejor = null, mejorRango = 99;
    for (var i = 0; i < reglas.length; i++){
      var r = reglas[i], quien, que;
      if (r.cliente_email){ if (!email || r.cliente_email !== email) continue; quien = 0; }
      else if (r.tipo_id){ if (!tipo || r.tipo_id !== tipo) continue; quien = 1; }
      else quien = 2;
      if (r.modelo){ if (may(r.modelo) !== may(p.modelo)) continue; que = 0; }
      else if (r.marca){ if (may(r.marca) !== may(p.marca)) continue; que = 1; }
      else que = 2;
      if (p.manual && que === 2) continue;   // los manuales solo usan reglas de marca o modelo
      var rango = RANGO['' + que + quien];
      if (rango < mejorRango){ mejor = r; mejorRango = rango; }
    }
    return mejor;
  }
  function precioPara(p, r, general){
    if (r && r.precio_fijo != null) return Number(r.precio_fijo);
    if (p.lista == null) return null;
    if (r && r.descuento_pct != null){
      var esGeneral = !r.cliente_email && !r.tipo_id && !r.marca && !r.modelo;
      return p.lista * (1 - (esGeneral ? general : Number(r.descuento_pct)) / 100);
    }
    return p.manual ? p.lista : p.lista * (1 - general / 100);
  }
  function dinero(n){ return '$' + Math.ceil(n).toLocaleString('en-US'); }

  function aplicar(reglas, email, tipo){
    var g = null;
    reglas.forEach(function(r){ if (!g && !r.cliente_email && !r.tipo_id && !r.marca && !r.modelo && r.descuento_pct != null) g = r; });
    var general = g ? Number(g.descuento_pct) : DESCUENTO_GENERAL;
    var els = document.querySelectorAll('.precio-cli');
    for (var i = 0; i < els.length; i++){
      var el = els[i];
      var l = el.getAttribute('data-lista');
      var p = { lista: (l === '' || l == null || isNaN(Number(l))) ? null : Number(l),
                marca: el.getAttribute('data-marca'), modelo: el.getAttribute('data-modelo'),
                manual: el.getAttribute('data-manual') === '1' };
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
