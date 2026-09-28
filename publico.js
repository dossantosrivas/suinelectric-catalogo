/* Páginas públicas /p/…: anota cuando alguien toca "Cotizar por WhatsApp"
   (panel → Estadísticas). Clave pública de Supabase: es segura en la página. */
(function(){
  var URL = 'https://yqnlxhbjassrkudnhvpr.supabase.co/rest/v1/eventos', CLAVE = 'sb_publishable_LOYjM5sqvQbBLIkH4KJTKQ_UfxrpTeC';
  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a[data-modelo]') : null;
    if (!a) return;
    try {
      fetch(URL, { method: 'POST', keepalive: true,
        headers: { 'Content-Type': 'application/json', apikey: CLAVE, Prefer: 'return=minimal' },
        body: JSON.stringify({ tipo: 'cotizar_whatsapp', modelo: String(a.getAttribute('data-modelo')).slice(0, 80), origen: 'pagina' }) });
    } catch (x) {}
  }, true);
})();
