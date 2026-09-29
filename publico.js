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
  s.src = '/rastreo.js?v=1';
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
