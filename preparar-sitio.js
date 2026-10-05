/* =====================================================================
   PREPARAR SITIO: arma la carpeta "sitio/" con SOLO lo que se publica.
   ---------------------------------------------------------------------
   Hoy Cloudflare publica el repo completo, así que cualquiera puede abrir
   suinelectric.com/productos.json, /scraper.js, /01_esquema.sql, etc.
   Con esto se publican únicamente los archivos de la tienda.

   Configuración en Cloudflare (una sola vez):
     Workers & Pages → tu proyecto → Settings → Build
       Build command:           node preparar-sitio.js
       Build output directory:  sitio
   ===================================================================== */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const RAIZ = __dirname;
const DESTINO = path.join(RAIZ, 'sitio');

// Lo que se publica. Agrega aquí cualquier archivo o carpeta nueva que la web necesite.
const PUBLICAR = [
  'index.html', 'tienda.html', 'admin.html', 'links.html', 'ventas.html',
  'tienda-beta.html', 'admin-beta.html', 'ventas-beta.html',   // versiones beta para pruebas
  '_headers', '_redirects', 'robots.txt', 'sitemap.xml', 'publico.css', 'publico.js', 'rastreo.js',
  'catalogo-tienda.json',
  'imagenes',          // logos, fotos propias, fotos de productos y familias
  'p', 'c',            // vistas previas para WhatsApp/redes
];

// Si todavía no existe catalogo-tienda.json (antes de la primera corrida diaria),
// se genera aquí mismo, sin descargar fotos.
if (!fs.existsSync(path.join(RAIZ, 'catalogo-tienda.json'))){
  console.log('No hay catalogo-tienda.json todavía: lo genero sin descargar fotos.');
  execFileSync(process.execPath, [path.join(RAIZ, 'generar-catalogo-tienda.js'), '--sin-descargas'], { stdio: 'inherit' });
}

fs.rmSync(DESTINO, { recursive: true, force: true });
fs.mkdirSync(DESTINO, { recursive: true });
for (const item of PUBLICAR){
  const origen = path.join(RAIZ, item);
  if (!fs.existsSync(origen)) continue;
  fs.cpSync(origen, path.join(DESTINO, item), { recursive: true });
  console.log('  + ' + item);
}
// El mapa interno de fotos no hace falta publicarlo (tiene las URLs originales).
fs.rmSync(path.join(DESTINO, 'imagenes/productos/_mapa.json'), { force: true });
console.log('Sitio listo en sitio/');
