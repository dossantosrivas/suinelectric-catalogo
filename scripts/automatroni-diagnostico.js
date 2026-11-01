// Diagnóstico temporal (2): JS de paginación y HTML de un producto
const axios = require('axios'); const cheerio = require('cheerio');
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
const get = (u) => axios.get(u, { headers: { 'User-Agent': UA }, timeout: 30000, validateStatus: () => true });
(async () => {
  const js = String((await get('https://automatroni.com/js/automatroni-1.0.js')).data);
  console.log('JS len', js.length);
  const marcas = [/filtros/g, /catalogo/g, /ajax\//g, /page/g];
  const pos = new Set(); marcas.forEach(re => { let m; while ((m = re.exec(js))) pos.add(Math.floor(m.index / 1500)); });
  [...pos].sort((a, b) => a - b).slice(0, 12).forEach(b => console.log('--- bloque', b, '\n', js.slice(b * 1500, b * 1500 + 1700)));
  const html = String((await get('https://automatroni.com/productos')).data); const $ = cheerio.load(html);
  const a = $('a[href^="producto/"]'); console.log('links producto', a.length);
  let p = a.first(); for (let n = 0; n < 8 && !p.is('#catalogo'); n++) { console.log('padre', n, p.prop('tagName'), p.attr('class')); p = p.parent(); }
  const i = html.indexOf('id="catalogo"'); console.log('=== catalogo html\n', html.slice(i, i + 6000));
  console.log('=== inputs hidden'); $('input[type=hidden]').each((k, e) => console.log($(e).attr('name') || $(e).attr('id'), '=', String($(e).attr('value')).slice(0, 80)));
})();
