// Diagnóstico temporal: cómo pagina automatroni.com/productos (se borra después)
const axios = require('axios'); const cheerio = require('cheerio');
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
const get = (u) => axios.get(u, { headers: { 'User-Agent': UA }, timeout: 30000, validateStatus: () => true });
const primero = (html) => { const $ = cheerio.load(html); const a = $('a[href*="/producto/"]').first(); return a.attr('href'); };
(async () => {
  const r = await get('https://automatroni.com/productos');
  console.log('status', r.status, 'len', r.data.length, 'set-cookie', JSON.stringify(r.headers['set-cookie'] || []).slice(0, 300));
  const html = r.data; const $ = cheerio.load(html);
  console.log('=== scripts src'); $('script[src]').each((i, e) => console.log($(e).attr('src')));
  console.log('=== forms'); $('form').each((i, e) => console.log($.html(e).slice(0, 600).replace(/\s+/g, ' ')));
  console.log('=== alrededor de 686');
  let i = html.indexOf('686'); while (i >= 0 && i < html.length) { console.log('...', html.slice(Math.max(0, i - 700), i + 400).replace(/\s+/g, ' ')); i = html.indexOf('686', i + 1); if (i > 0 && i > 0 && false) break; }
  console.log('=== scripts inline con paginación/ajax');
  $('script:not([src])').each((k, e) => { const t = $(e).html() || ''; if (/pag|ajax|fetch|\$\.(post|get)|load\(/i.test(t)) console.log('--- script', k, t.length, '\n', t.slice(0, 4000)); });
  console.log('=== primer producto (html)');
  const a = $('a[href*="/producto/"]').first(); let p = a; for (let n = 0; n < 6; n++) p = p.parent();
  console.log($.html(p).slice(0, 5000));
  console.log('=== productos en página 1:', new Set($('a[href*="/producto/"]').map((i, e) => $(e).attr('href')).get()).size, 'primero', primero(html));
  for (const u of ['?pagina=2', '?page=2', '?pag=2', '?p=2', '/2', '?pg=2', '?np=2']) {
    const x = await get('https://automatroni.com/productos' + u); console.log('probar', u, x.status, String(x.data).length, primero(String(x.data)));
    await new Promise(s => setTimeout(s, 1500));
  }
})();
