const fs = require('fs');
const path = require('path');

const RAIZ = path.dirname(__dirname);

function migrarTienda() {
  let s = fs.readFileSync(path.join(RAIZ, 'tienda-beta.html'), 'utf8');

  // 1. Quitar noindex
  s = s.replace(/<meta name="robots" content="noindex, nofollow">\r?\n?/, '');

  // 2. Quitar [BETA] del título
  s = s.replace('<title>[BETA] Suinelectric', '<title>Suinelectric');

  // 3. Restaurar rastreo.js oficial v=5
  const idxRastreoInicio = s.indexOf('<!-- beta: sin rastreo.js');
  const idxRastreoFin = s.indexOf('<script src="https://cdn.jsdelivr.net', idxRastreoInicio);
  if (idxRastreoInicio === -1 || idxRastreoFin === -1) {
    throw new Error('No se encontró el bloque de rastreo beta en tienda-beta.html');
  }
  const rastreoNuevo = `<!-- Rastreo de visitantes y estadísticas (sin cookies, no cuenta administradores) -->\n<script src="/rastreo.js?v=5"></script>\n`;
  s = s.slice(0, idxRastreoInicio) + rastreoNuevo + s.slice(idxRastreoFin);

  // 4. Redirección canónica a /tienda
  s = s.replace("return location.origin + '/tienda-beta';", "return location.origin + '/tienda';");

  // 5. Enlaces a apps oficiales
  s = s.replaceAll('href="/admin-beta"', 'href="/admin"');
  s = s.replaceAll('href="/ventas-beta"', 'href="/ventas"');

  // 6. Quitar la carga de catalogo-beta.json en cargar()
  const marcaInicio = "// Catálogo único (beta): si existe catalogo-beta.json";
  const marcaFin = "const [{ data, manuales: manualesJson }, panel, fotosExtra] = await Promise.all([traerCatalogo(silencioso), traerDelPanel(), traerFotosExtra()]);";
  const i = s.indexOf(marcaInicio);
  const j = s.indexOf(marcaFin, i);
  if (i === -1 || j === -1) {
    throw new Error('No se encontró el bloque de catalogo-beta en cargar()');
  }
  const lineaInicio = s.lastIndexOf('\n', i) + 1;
  const lineaFin = s.lastIndexOf('\n', j) + 1;
  s = s.slice(0, lineaInicio) + s.slice(lineaFin);

  // 7. Quitar etiqueta BETA
  const avisoRegex = /<div id="beta-aviso"[^>]*>BETA<\/div>\r?\n?/;
  s = s.replace(avisoRegex, '');

  fs.writeFileSync(path.join(RAIZ, 'tienda.html'), s, 'utf8');
  console.log('✓ tienda.html generada con éxito desde tienda-beta.html');
}

function migrarAdmin() {
  let s = fs.readFileSync(path.join(RAIZ, 'admin-beta.html'), 'utf8');

  s = s.replace('<title>[BETA] Panel web | Suinelectric</title>', '<title>Panel web | Suinelectric</title>');
  s = s.replace("const BASE = '/admin-beta';", "const BASE = '/admin';");
  s = s.replaceAll('/tienda-beta.html', '/tienda.html');
  s = s.replaceAll('/tienda-beta', '/tienda');
  s = s.replaceAll('/ventas-beta', '/ventas');

  const avisoRegex = /<div id="beta-aviso"[^>]*>BETA<\/div>\r?\n?/;
  s = s.replace(avisoRegex, '');

  fs.writeFileSync(path.join(RAIZ, 'admin.html'), s, 'utf8');
  console.log('✓ admin.html generada con éxito desde admin-beta.html');
}

function migrarVentas() {
  let s = fs.readFileSync(path.join(RAIZ, 'ventas-beta.html'), 'utf8');

  s = s.replace(/<meta name="robots" content="noindex, nofollow">\r?\n?/, '');
  s = s.replace('<title>[BETA] Gestión | Suinelectric</title>', '<title>Gestión | Suinelectric</title>');
  s = s.replaceAll('/^\\/ventas-beta(?:\\.html)?', '/^\\/ventas(?:\\.html)?');
  s = s.replaceAll("'/ventas-beta/'", "'/ventas/'");
  s = s.replaceAll('href="/tienda-beta"', 'href="/tienda"');
  s = s.replaceAll('href="/admin-beta"', 'href="/admin"');
  s = s.replaceAll('/admin-beta/', '/admin/');

  const avisoRegex = /<div id="beta-aviso"[^>]*>BETA<\/div>\r?\n?/;
  s = s.replace(avisoRegex, '');

  fs.writeFileSync(path.join(RAIZ, 'ventas.html'), s, 'utf8');
  console.log('✓ ventas.html generada con éxito desde ventas-beta.html');
}

function migrarMiCuenta() {
  let s = fs.readFileSync(path.join(RAIZ, 'mi-cuenta-beta.html'), 'utf8');

  s = s.replaceAll('href="/tienda-beta"', 'href="/tienda"');

  const avisoRegex = /<div id="beta-aviso"[^>]*>BETA<\/div>\r?\n?/;
  s = s.replace(avisoRegex, '');

  fs.writeFileSync(path.join(RAIZ, 'mi-cuenta.html'), s, 'utf8');
  console.log('✓ mi-cuenta.html creada con éxito desde mi-cuenta-beta.html');
}

function actualizarPrepararSitio() {
  const p = path.join(RAIZ, 'preparar-sitio.js');
  let s = fs.readFileSync(p, 'utf8');
  if (!s.includes("'mi-cuenta.html'")) {
    s = s.replace(
      "'index.html', 'tienda.html', 'admin.html', 'links.html', 'ventas.html', 'cotizador.html',",
      "'index.html', 'tienda.html', 'admin.html', 'links.html', 'ventas.html', 'cotizador.html', 'mi-cuenta.html',"
    );
    fs.writeFileSync(p, s, 'utf8');
    console.log('✓ preparar-sitio.js actualizado con mi-cuenta.html');
  } else {
    console.log('· preparar-sitio.js ya contiene mi-cuenta.html');
  }
}

function actualizarHeaders() {
  const p = path.join(RAIZ, '_headers');
  let s = fs.readFileSync(p, 'utf8');
  if (!s.includes('/mi-cuenta\n') && !s.includes('/mi-cuenta\r\n')) {
    const nuevo = `/mi-cuenta\n  X-Robots-Tag: noindex\n/mi-cuenta.html\n  X-Robots-Tag: noindex\n`;
    s = s + nuevo;
    fs.writeFileSync(p, s, 'utf8');
    console.log('✓ _headers actualizado con /mi-cuenta');
  } else {
    console.log('· _headers ya contiene /mi-cuenta');
  }
}

function actualizarRedirects() {
  const p = path.join(RAIZ, '_redirects');
  let s = fs.readFileSync(p, 'utf8');
  if (!s.includes('/mi-cuenta/*')) {
    s = s.replace(
      '# Versiones beta (pruebas): misma base de datos, links propios',
      '# Mi cuenta (portal de clientes)\n/mi-cuenta/*    /mi-cuenta    200\n\n# Versiones beta (pruebas): misma base de datos, links propios'
    );
    fs.writeFileSync(p, s, 'utf8');
    console.log('✓ _redirects actualizado con /mi-cuenta/*');
  } else {
    console.log('· _redirects ya contiene /mi-cuenta/*');
  }
}

try {
  migrarTienda();
  migrarAdmin();
  migrarVentas();
  migrarMiCuenta();
  actualizarPrepararSitio();
  actualizarHeaders();
  actualizarRedirects();
  console.log('\n¡Todos los archivos beta fueron pasados a la versión oficial exitosamente!');
} catch (err) {
  console.error('Error durante la migración:', err);
  process.exit(1);
}
