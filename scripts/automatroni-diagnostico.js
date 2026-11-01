// Diagnóstico temporal (3): manejador de paginación completo y una tarjeta de producto
const axios = require('axios'); const cheerio = require('cheerio');
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
const get = (u) => axios.get(u, { headers: { 'User-Agent': UA }, timeout: 30000, validateStatus: () => true });
(async () => {
  const js = String((await get('https://automatroni.com/js/automatroni-1.0.js')).data);
  const i = js.indexOf("$('.products').on('click submit change', '.filtros'");
  console.log(js.slice(i, i + 7000));
  const html = String((await get('https://automatroni.com/productos')).data); const $ = cheerio.load(html);
  console.log('=== tarjetas', $('.list_products--card').length);
  console.log($.html($('.list_products--card').eq(1)));
  console.log('=== tarjeta con promo'); $('.list_products--card').each((k, e) => { if (/a partir de/i.test($(e).text())) { console.log($.html(e)); return false; } });
})();
