/* Páginas públicas /p/…: anota cuando alguien toca "Cotizar por WhatsApp"
   (panel → Estadísticas). Clave pública de Supabase: es segura en la página.
   Si el cliente tiene la sesión de la tienda abierta en este navegador, se
   envía su sesión para que el clic quede en su actividad (panel → Clientes). */
(function(){
  var BASE = 'https://yqnlxhbjassrkudnhvpr.supabase.co', URL = BASE + '/rest/v1/eventos', CLAVE = 'sb_publishable_LOYjM5sqvQbBLIkH4KJTKQ_UfxrpTeC';
  function tokenSesion(){
    try {
      var s = JSON.parse(localStorage.getItem('sb-yqnlxhbjassrkudnhvpr-auth-token') || 'null');
      if (s && s.access_token && (!s.expires_at || s.expires_at * 1000 > Date.now() + 30000)) return s.access_token;
    } catch (x) {}
    return null;
  }
  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a[data-modelo]') : null;
    if (!a) return;
    try {
      var h = { 'Content-Type': 'application/json', apikey: CLAVE, Prefer: 'return=minimal' }, t = tokenSesion();
      if (t) h.Authorization = 'Bearer ' + t;
      fetch(URL, { method: 'POST', keepalive: true, headers: h,
        body: JSON.stringify({ tipo: 'cotizar_whatsapp', modelo: String(a.getAttribute('data-modelo')).slice(0, 80), origen: 'pagina' }) });
    } catch (x) {}
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
