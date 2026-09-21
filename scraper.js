/**
 * scraper.js v4 — Catálogo completo de grupo-electricos.com
 * ---------------------------------------------------------------------------
 * Recorre TODO el catálogo (paginando /shop/) y de cada producto extrae:
 *
 *   - Las categorías EXACTAS que la página lista al final ("Categorías: ...")
 *     con nombre, URL, slug y nivel, y la jerarquía real reconstruida desde
 *     la URL (automatizacion-basica > 1-logo > version-8-x > cpu-version-8-x > ...)
 *   - SKU, modelo, marca, precio público / "Tú Precio", existencias, descripción,
 *     video (YouTube), enlace de información técnica, imágenes, atributos,
 *     productos relacionados, ID interno de WooCommerce.
 *
 * Genera dos archivos:
 *   productos.json   -> todos los productos
 *   categorias.json  -> árbol de categorías del sitio (con conteo de productos)
 *
 * Requisitos:  npm install axios cheerio
 *
 * Uso:
 *   node scraper.js                    catálogo completo
 *   node scraper.js --limite 20        prueba con 20 productos
 *   node scraper.js --url <producto>   un solo producto (imprime el JSON)
 *   node scraper.js --reanudar         continúa donde se quedó (usa productos.json)
 *
 * "Tú Precio" solo aparece con la sesión iniciada. Para capturarlo, copia el
 * header Cookie de tu navegador (DevTools > Network > cualquier request) y:
 *   Linux/Mac:   GE_COOKIE="...." node scraper.js
 *   PowerShell:  $env:GE_COOKIE="...."; node scraper.js
 */

const fs = require("fs");
const path = require("path");
const axios = require("axios");
const cheerio = require("cheerio");

const BASE_URL = "https://grupo-electricos.com";
const OUTPUT_FILE = path.join(__dirname, "productos.json");
const CATEGORIES_FILE = path.join(__dirname, "categorias.json");
const REQUEST_DELAY = 800;        // ms entre solicitudes
const MAX_PAGINAS_TIENDA = 500;
const TIMEOUT_MS = 20000;
const GUARDAR_CADA = 20;          // productos entre cada guardado a disco

// ---- argumentos / entorno ----------------------------------------------------
const args = process.argv.slice(2);
const argVal = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : null; };
const LIMITE = argVal("--limite") ? parseInt(argVal("--limite"), 10) : null;
const URL_UNICA = argVal("--url");
const REANUDAR = args.includes("--reanudar");
const COOKIE = process.env.GE_COOKIE || "";

// Marcas para el respaldo de detección (la marca real suele venir en la ficha).
const MARCAS_CONOCIDAS = [
  "SIEMENS", "ALLEN BRADLEY", "INVT", "SCHNEIDER ELECTRIC", "SCHNEIDER",
  "ABB", "WEG", "CHINT", "LS ELECTRIC", "DELTA", "FESTO", "PHOENIX CONTACT",
  "DANFOSS", "OMRON", "MITSUBISHI", "FUJI", "TECO", "HYUNDAI", "NORDIC",
  "BRADY", "PILZ", "SICK", "BALLUFF", "TURCK", "EATON",
];

const client = axios.create({
  headers: {
    "User-Agent":
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept-Language": "es-VE,es;q=0.9",
    ...(COOKIE ? { Cookie: COOKIE } : {}),
  },
  timeout: TIMEOUT_MS,
  validateStatus: () => true,
});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (m) => console.log(`${new Date().toISOString()} [INFO] ${m}`);
const warn = (m) => console.warn(`${new Date().toISOString()} [WARN] ${m}`);
const errorLog = (m) => console.error(`${new Date().toISOString()} [ERROR] ${m}`);
const quitarAcentos = (s) => (s || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "");
const limpiar = (s) => (s || "").replace(/\s+/g, " ").trim();
const norm = (s) => quitarAcentos(s || "").toUpperCase().replace(/[^A-Z0-9]/g, "");

async function get(url) {
  for (let intento = 0; intento < 3; intento++) {
    try {
      const resp = await client.get(url);
      await sleep(REQUEST_DELAY);
      if (resp.status === 200) return resp.data;
      if (resp.status === 404) return null;
      warn(`Status ${resp.status} en ${url}`);
    } catch (e) {
      warn(`Error de red en ${url}: ${e.message}`);
    }
    await sleep(REQUEST_DELAY * (intento + 1));
  }
  return null;
}

// ---------------------------------------------------------------------------
// Registro global de categorías (para categorias.json)
// ---------------------------------------------------------------------------
const registro = new Map(); // clave "a/b/c" -> {clave,nombre,slug,url,nivel,padre,productos,es_modelo}

function registrarCategoria(c, contar, modelo) {
  let r = registro.get(c.clave);
  if (!r) {
    r = {
      clave: c.clave,
      nombre: c.nombre,
      slug: c.slugs[c.slugs.length - 1],
      url: c.url,
      nivel: c.slugs.length,
      padre: c.slugs.length > 1 ? c.slugs.slice(0, -1).join("/") : null,
      productos: 0,
      es_modelo: false,
    };
    registro.set(c.clave, r);
  }
  if (c.nombre && (!r.nombre || r.nombre === prettySlug(r.slug))) r.nombre = c.nombre;
  if (contar) r.productos++;
  if (modelo && norm(c.nombre) === norm(modelo)) r.es_modelo = true;
}

function guardarCategorias() {
  const lista = [...registro.values()].sort((a, b) =>
    a.clave.localeCompare(b.clave, "es", { numeric: true })
  );
  const nodos = new Map(lista.map((c) => [c.clave, { ...c, hijos: [] }]));
  const raiz = [];
  for (const n of nodos.values()) {
    const padre = n.padre ? nodos.get(n.padre) : null;
    (padre ? padre.hijos : raiz).push(n);
  }
  fs.writeFileSync(
    CATEGORIES_FILE,
    JSON.stringify(
      { fuente: BASE_URL, generado: new Date().toISOString(), total_categorias: lista.length, arbol: raiz, lista },
      null,
      2
    ),
    "utf-8"
  );
}

function prettySlug(slug) {
  return (slug || "").replace(/-/g, " ").replace(/\b\w/g, (m) => m.toUpperCase());
}

// ---------------------------------------------------------------------------
// Paso 1: descubrir URLs de producto paginando /shop/
// ---------------------------------------------------------------------------
const RE_PRODUCTO = /^https?:\/\/(?:www\.)?grupo-electricos\.com\/shop\/([^/?#]+)\/?$/;

async function descubrirUrls() {
  const urls = [];
  const vistos = new Set();
  for (let pagina = 1; pagina <= MAX_PAGINAS_TIENDA; pagina++) {
    const url = pagina === 1 ? `${BASE_URL}/shop/` : `${BASE_URL}/shop/page/${pagina}/`;
    const html = await get(url);
    if (!html) break;
    const $ = cheerio.load(html);
    const nuevos = [];
    $("a[href*='/shop/']").each((_, el) => {
      let href = ($(el).attr("href") || "").split("#")[0].split("?")[0];
      try { href = new URL(href, BASE_URL).href; } catch { return; }
      const m = href.match(RE_PRODUCTO);
      if (!m || m[1] === "page") return;
      const limpio = `${BASE_URL}/shop/${m[1]}/`;
      if (!vistos.has(limpio)) { vistos.add(limpio); nuevos.push(limpio); }
    });
    if (!nuevos.length) break;
    urls.push(...nuevos);
    log(`/shop/ página ${pagina}: ${nuevos.length} productos (acum. ${urls.length})`);
    if (LIMITE && urls.length >= LIMITE) break;
  }
  return LIMITE ? urls.slice(0, LIMITE) : urls;
}

// ---------------------------------------------------------------------------
// Utilidades de parseo
// ---------------------------------------------------------------------------

/** Texto de un elemento respetando saltos de línea (<br>, <p>, <div>, <li>). */
function textoConSaltos($, el) {
  const $c = $(el).clone();
  $c.find("br").replaceWith("\n");
  $c.find("p, div, li, h1, h2, h3, h4, h5, h6, tr").each((_, e) => { $(e).append("\n"); });
  return $c.text()
    .replace(/[ \t\r\f\v\u00a0]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{2,}/g, "\n")
    .trim();
}

function obtenerResumen($) {
  for (const s of [".summary.entry-summary", ".entry-summary", ".product-details-wrap .summary", "div.summary", ".summary"]) {
    const el = $(s).first();
    if (el.length && el.text().trim().length > 30) return el;
  }
  return null;
}

function parsearPrecio(texto) {
  if (!texto) return null;
  const m = texto.replace(/,/g, "").match(/[\d.]+/);
  if (!m) return null;
  const v = parseFloat(m[0]);
  return isNaN(v) ? null : v;
}

function extraerPrecios($, resumen, texto) {
  const q = (s) => (resumen ? resumen.find(s) : $(s));
  let precio = null, precioLista = null;
  const del = q(".price del .amount, .price del").first().text();
  const ins = q(".price ins .amount, .price ins").first().text();
  if (del) precioLista = parsearPrecio(del);
  if (ins) precio = parsearPrecio(ins);

  const mTu = texto.match(/t[uú]\s*precio[^0-9]{0,6}([\d.,]+)/i);
  if (precio === null && mTu) precio = parsearPrecio(mTu[1]);
  if (precioLista === null) {
    const sinTu = texto.replace(/t[uú]\s*precio[^0-9]{0,6}[\d.,]+/i, "");
    const mP = sinTu.match(/\bprecio\b[^0-9]{0,6}([\d.,]+)/i);
    if (mP) precioLista = parsearPrecio(mP[1]);
  }
  if (precio === null) precio = precioLista;
  if (precio !== null && precio === precioLista) precioLista = null;
  return { precio, precioLista, precioTipo: mTu || ins ? "cliente" : "publico" };
}

function extraerDisponibilidad($, resumen, texto) {
  const mEstado = texto.match(/estado\s*:?\s*(\d+)\s*disponibles?/i);
  if (mEstado) {
    const n = parseInt(mEstado[1], 10);
    return { disponible: n > 0, existencias: n };
  }
  if (/estado\s*:?\s*(agotado|no\s*disponible|sin\s*(stock|existencias))/i.test(texto)) {
    return { disponible: false, existencias: 0 };
  }
  const mGen = texto.match(/(\d+)\s*(in stock|disponibles?)/i);
  if (mGen) { const n = parseInt(mGen[1], 10); return { disponible: n > 0, existencias: n }; }
  if (/agotado|out of stock/i.test(texto)) return { disponible: false, existencias: 0 };
  const q = (s) => (resumen ? resumen.find(s) : $(s));
  return { disponible: q("button[name='add-to-cart'], .single_add_to_cart_button").length > 0, existencias: null };
}

function extraerSku($, resumen, texto) {
  const q = (s) => (resumen ? resumen.find(s) : $(s));
  const t = limpiar(q(".sku").first().text());
  if (t) return t;
  const m = texto.match(/SKU:?\s*([\w-]+)/i);
  return m ? m[1] : null;
}

function extraerProductId($, html) {
  const v = $("button[name='add-to-cart']").attr("value") || $("input[name='add-to-cart']").attr("value");
  if (v) return parseInt(v, 10);
  const m1 = (($("body").attr("class")) || "").match(/postid-(\d+)/);
  if (m1) return parseInt(m1[1], 10);
  const m2 = (($("link[rel='shortlink']").attr("href")) || "").match(/[?&]p=(\d+)/);
  return m2 ? parseInt(m2[1], 10) : null;
}

// ---------------------------------------------------------------------------
// Categorías: EXACTAMENTE las que lista la página
// ---------------------------------------------------------------------------
function parseCategoriaHref(href) {
  let u;
  try { u = new URL(href, BASE_URL); } catch { return null; }
  const m = u.pathname.match(/\/product-category\/(.+?)\/?$/);
  if (!m) return null;
  const slugs = m[1].split("/").filter(Boolean);
  if (!slugs.length) return null;
  return { slugs, clave: slugs.join("/"), url: `${BASE_URL}/product-category/${slugs.join("/")}/` };
}

function extraerCategoriasPagina($) {
  const vistos = new Set();
  const cats = [];
  const agregar = (a) => {
    const info = parseCategoriaHref($(a).attr("href") || "");
    if (!info || vistos.has(info.clave)) return;
    vistos.add(info.clave);
    cats.push({ nombre: limpiar($(a).text()), ...info });
  };

  const $links = $(".product_meta a[href*='/product-category/'], .posted_in a[href*='/product-category/']");
  if ($links.length) {
    $links.each((_, a) => agregar(a));
  } else {
    // Respaldo: buscar el rótulo "Categorías:" y tomar sus enlaces.
    $("span, div, p, li").each((_, el) => {
      const propio = limpiar($(el).clone().children().remove().end().text());
      if (/^categor[ií]as?\s*:/i.test(propio)) {
        $(el).find("a[href*='/product-category/']").each((__, a) => agregar(a));
      }
    });
  }
  return cats;
}

function extraerBreadcrumbCategorias($) {
  const vistos = new Set();
  const out = [];
  $(".woocommerce-breadcrumb a, nav[class*='breadcrumb'] a, [class*='breadcrumb'] a").each((_, a) => {
    const info = parseCategoriaHref($(a).attr("href") || "");
    if (!info || vistos.has(info.clave)) return;
    vistos.add(info.clave);
    out.push({ nombre: limpiar($(a).text()), ...info });
  });
  return out;
}

/** Rutas completas (raíz -> hoja) para cada rama de categorías del producto. */
function construirRutas(cats) {
  const nombres = new Map(cats.map((c) => [c.clave, c.nombre]));
  const claves = cats.map((c) => c.clave);
  const hojas = cats.filter((c) => !claves.some((k) => k !== c.clave && k.startsWith(c.clave + "/")));
  return hojas.map((h) =>
    h.slugs.map((slug, i) => {
      const clave = h.slugs.slice(0, i + 1).join("/");
      const conocido = registro.get(clave);
      return {
        clave,
        nombre: nombres.get(clave) || (conocido && conocido.nombre) || prettySlug(slug),
        url: `${BASE_URL}/product-category/${clave}/`,
      };
    })
  );
}

// ---------------------------------------------------------------------------
// Descripción, enlaces (video / info técnica), marca, imágenes, etc.
// ---------------------------------------------------------------------------
const esVideo = (u) => /(youtube\.com|youtu\.be|vimeo\.com)/i.test(u);

function descartarSiEsMarca(texto, marca, modelo) {
  const t = norm(texto);
  if (!t) return null;
  if (t === norm(marca) || t === norm(modelo)) return null;
  if (MARCAS_CONOCIDAS.some((m) => t === norm(m))) return null;
  return texto;
}

function descripcionPosicional(lineas) {
  const t = lineas.join("\n");
  let inicio = -1;
  const re = /(?:t[uú]\s*)?precio[^0-9\n]{0,6}\n?[\d.,]+\s*\$/gi;
  let m;
  while ((m = re.exec(t))) inicio = m.index + m[0].length;
  if (inicio < 0) return "";
  const resto = t.slice(inicio);
  const fin = resto.search(/\bestado\s*:/i);
  return (fin >= 0 ? resto.slice(0, fin) : resto).trim();
}

const RE_MARCADOR = /m[aá]s\s*informaci[oó]n\s*t[eé]cnica/i;
const RE_CORTE = /\bestado\s*:|a[ñn]adir al carrito|\bsku\s*:/i;

/** Bloque que contiene la descripción, ubicado por el rótulo "MAS INFORMACION TECNICA". */
function bloquePorMarcador($) {
  let hoja = null;
  $("body *").each((_, el) => {
    if (hoja) return;
    if (!RE_MARCADOR.test($(el).text())) return;
    const hijoConMarcador = $(el).children().toArray().some((c) => RE_MARCADOR.test($(c).text()));
    if (!hijoConMarcador) hoja = el;
  });
  if (!hoja) return null;
  // Subir mientras el bloque solo tenga el rótulo/enlace y el padre no incluya stock/carrito/SKU.
  let actual = $(hoja);
  const sustancia = (el) => textoConSaltos($, el)
    .replace(/https?:\/\/\S+/g, "").replace(RE_MARCADOR, "").replace(/[:\s]/g, "").length;
  while (sustancia(actual) < 15) {
    const padre = actual.parent();
    if (!padre.length || padre.is("body") || RE_CORTE.test(padre.text())) break;
    actual = padre;
  }
  return actual;
}

/** Quita URLs y el rótulo "MAS INFORMACION TECNICA EN:" y devuelve solo el texto descriptivo. */
function limpiarDescripcion(bruto, marca, modelo) {
  const d = bruto
    .split("\n")
    .map(limpiar)
    .filter((l) => l && !/^m[aá]s\s*informaci[oó]n\s*t[eé]cnica\s*en\s*:?$/i.test(l))
    .join(" ")
    .replace(/https?:\/\/[^\s<>"']+/g, "")
    .replace(/m[aá]s\s*informaci[oó]n\s*t[eé]cnica\s*en\s*:?/gi, "")
    .replace(/\s+/g, " ")
    .trim();
  return d ? descartarSiEsMarca(d, marca, modelo) : null;
}

/** Un candidato es válido si es texto descriptivo real: no marca, no precio, no un contenedor gigante. */
function candidatoValido(bruto, marca, modelo) {
  if (!bruto || RE_CORTE.test(bruto)) return null;        // incluye stock/carrito/SKU => contenedor demasiado grande
  const d = limpiarDescripcion(bruto, marca, modelo);
  if (!d || d.length < 10) return null;
  if (/^(t[uú]\s*)?precio\b[^a-z]*$/i.test(d)) return null; // solo es una línea de precio
  return d;
}

function extraerDescripcion($, resumen, lineas, modelo, marca, cuerpoLineas) {
  // Candidatos en orden de preferencia; se acepta el primero que dé una descripción válida.
  const candidatos = [];
  const deElemento = (el, m) => () => ({
    bruto: textoConSaltos($, el),
    hrefs: $(el).find("a[href]").map((_, a) => $(a).attr("href")).get(),
    metodo: m,
  });

  $(".woocommerce-product-details__short-description, .product-short-description, .short-description, [itemprop='description']")
    .each((_, el) => { candidatos.push(deElemento(el, "selector")); });
  candidatos.push(() => {
    const bl = bloquePorMarcador($);
    return bl && bl.length ? deElemento(bl, "marcador")() : null;
  });
  candidatos.push(() => ({ bruto: descripcionPosicional(lineas), hrefs: [], metodo: "posicional-resumen" }));
  if (cuerpoLineas) candidatos.push(() => ({ bruto: descripcionPosicional(cuerpoLineas), hrefs: [], metodo: "posicional-cuerpo" }));

  let elegido = null;
  for (const f of candidatos) {
    const c = f();
    if (c && candidatoValido(c.bruto, marca, modelo)) { elegido = c; break; }
  }
  const bruto = elegido ? elegido.bruto : "";
  const hrefs = elegido ? elegido.hrefs : [];
  const metodo = elegido ? elegido.metodo : null;

  // URLs presentes en el texto + enlaces reales
  const urlsTexto = (bruto.match(/https?:\/\/[^\s<>"']+/g) || []).map((u) => u.replace(/[.,;)]+$/, ""));
  const todas = [...new Set([...hrefs.filter(Boolean), ...urlsTexto])];

  const videos = todas.filter(esVideo);
  $("iframe[src*='youtube'], iframe[src*='youtu.be'], iframe[src*='vimeo']").each((_, f) => videos.push($(f).attr("src")));

  const mTec = bruto.match(/informaci[oó]n\s*t[eé]cnica\s*en\s*:?\s*(https?:\/\/[^\s<>"']+)/i);
  let infoTecnica = mTec ? mTec[1].replace(/[.,;)]+$/, "") : null;
  if (!infoTecnica) infoTecnica = todas.find((u) => !esVideo(u)) || null;

  const desc = elegido ? limpiarDescripcion(bruto, marca, modelo) : null;

  // Descripción larga (pestaña), si existe y aporta algo distinto
  let larga = null;
  const tab = $("#tab-description, .woocommerce-Tabs-panel--description").first();
  if (tab.length) {
    larga = textoConSaltos($, tab).replace(/^descripci[oó]n\s*\n?/i, "").trim();
    if (!larga || (desc && limpiar(larga) === desc)) larga = null;
  }

  return {
    descripcion: desc || null,
    descripcion_metodo: metodo,
    descripcion_larga: larga,
    videos: [...new Set(videos.filter(Boolean))],
    info_tecnica_url: infoTecnica,
    enlaces_descripcion: todas.filter((u) => !esVideo(u) && u !== infoTecnica),
  };
}

function extraerMarca($, resumen, lineas, texto, modelo, sku) {
  const q = (s) => (resumen ? resumen.find(s) : $(s));
  // 1) taxonomía de marca, si el tema la usa
  const t1 = limpiar(
    q("a[href*='/brand/'], a[href*='/marca/'], a[href*='product_brand'], .product-brand a, .brand a, .brands a").first().text()
  ) || limpiar(q(".brand img, .product-brand img, .brands img").first().attr("alt"));
  if (t1) return t1.replace(/\.$/, "");

  // 2) la línea que viene justo después de "Estado: N disponibles"
  const i = lineas.findIndex((l) => /^estado\s*:?/i.test(l));
  if (i >= 0) {
    for (let j = i + 1; j <= i + 3 && j < lineas.length; j++) {
      const cand = lineas[j].replace(/\.$/, "").trim();
      if (/disponible|agotado|^\d+$/i.test(cand)) continue;
      if (norm(cand) === norm(modelo) || norm(cand) === norm(sku)) break;
      if (/^[A-Z0-9][A-Z0-9 .&\-]{1,30}$/.test(cand)) return cand;
      break;
    }
  }

  // 3) marcas conocidas, SOLO dentro del resumen del producto (no en menú/footer)
  const plano = quitarAcentos(texto).toUpperCase();
  for (const marca of MARCAS_CONOCIDAS) {
    if (new RegExp(`\\b${marca.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`).test(plano)) return marca;
  }
  return null;
}

function extraerImagenes($) {
  const abs = (u) => { try { return new URL(u, BASE_URL).href; } catch { return null; } };
  const gal = $(".woocommerce-product-gallery, .product-gallery, .images").first();
  const full = new Set();
  let miniatura = null;
  if (gal.length) {
    gal.find("a[href]").each((_, a) => {
      const h = $(a).attr("href") || "";
      if (/\.(jpe?g|png|webp|gif)(\?|$)/i.test(h)) full.add(abs(h));
    });
    gal.find("img").each((_, im) => {
      const $im = $(im);
      const large = $im.attr("data-large_image");
      if (large) full.add(abs(large));
      const src = $im.attr("data-src") || $im.attr("src");
      if (src && !miniatura) miniatura = abs(src);
      if (!large && src && full.size === 0) full.add(abs(src.replace(/-\d+x\d+(?=\.\w+$)/, "")));
    });
  } else {
    const im = $("img.wp-post-image").first();
    const src = im.attr("data-src") || im.attr("src");
    if (src) { miniatura = abs(src); full.add(abs(src.replace(/-\d+x\d+(?=\.\w+$)/, ""))); }
  }
  const imagenes = [...full].filter(Boolean);
  return { imagen: imagenes[0] || miniatura || null, imagen_miniatura: miniatura, imagenes };
}

function extraerAtributos($) {
  const attrs = {};
  $("table.woocommerce-product-attributes tr, #tab-additional_information table tr").each((_, tr) => {
    const k = limpiar($(tr).find("th").first().text());
    const v = limpiar($(tr).find("td").first().text());
    if (k && v) attrs[k] = v;
  });
  return attrs;
}

function extraerRelacionados($) {
  const out = [];
  const vistos = new Set();
  $(".related.products li.product, section.related li.product, .related li.product").each((_, li) => {
    const a = $(li).find("a[href*='/shop/']").first();
    let href = a.attr("href") || "";
    try { href = new URL(href, BASE_URL).href; } catch { return; }
    const m = href.match(RE_PRODUCTO);
    if (!m || vistos.has(m[1])) return;
    vistos.add(m[1]);
    const titulo = limpiar($(li).find(".woocommerce-loop-product__title, h2, h3").first().text());
    out.push({ modelo: titulo || m[1].toUpperCase(), url: `${BASE_URL}/shop/${m[1]}/` });
  });
  return out;
}

// ---------------------------------------------------------------------------
// Producto completo
// ---------------------------------------------------------------------------
function parsearProducto(html, url) {
  const $ = cheerio.load(html);
  const modelo = limpiar($("h1.product_title, h1.entry-title, h1").first().text()) || null;
  if (!modelo) return null;

  const resumen = obtenerResumen($);
  let texto = resumen ? textoConSaltos($, resumen) : "";
  if (!resumen || texto.length < 30) {
    // Respaldo: desde "SKU:" hasta "Productos Relacionados" (evita menú y footer)
    const cuerpo = textoConSaltos($, $("body"));
    const a = cuerpo.search(/SKU:/i);
    const b = cuerpo.search(/productos relacionados/i);
    texto = a >= 0 ? cuerpo.slice(a, b > a ? b : undefined) : cuerpo;
  }
  const lineas = texto.split("\n").map(limpiar).filter(Boolean);

  const sku = extraerSku($, resumen, texto);
  const { precio, precioLista, precioTipo } = extraerPrecios($, resumen, texto);
  const { disponible, existencias } = extraerDisponibilidad($, resumen, texto);
  const marca = extraerMarca($, resumen, lineas, texto, modelo, sku);
  const cuerpo = textoConSaltos($, $("body"));
  const iSku = cuerpo.search(/SKU:/i);
  const iRel = cuerpo.search(/productos relacionados/i);
  const cuerpoLineas = (iSku >= 0 ? cuerpo.slice(iSku, iRel > iSku ? iRel : undefined) : cuerpo)
    .split("\n").map(limpiar).filter(Boolean);
  const desc = extraerDescripcion($, resumen, lineas, modelo, marca, cuerpoLineas);
  if (process.argv.includes("--debug")) {
    console.error("[DEBUG] método descripción:", desc.descripcion_metodo);
    console.error("[DEBUG] líneas del resumen:\n" + lineas.slice(0, 40).map((l, i) => `  ${i}: ${l.slice(0, 120)}`).join("\n"));
  }
  const img = extraerImagenes($);

  // ---- categorías ----
  const categoriasPagina = extraerCategoriasPagina($);
  const breadcrumb = extraerBreadcrumbCategorias($);
  categoriasPagina.forEach((c) => registrarCategoria(c, false, modelo)); // primero nombres
  const rutas = construirRutas(categoriasPagina);

  let principal = null;
  if (breadcrumb.length) {
    const ultima = breadcrumb[breadcrumb.length - 1].clave;
    principal = rutas.find((r) => r[r.length - 1].clave === ultima)
      || breadcrumb.map((b) => ({ clave: b.clave, nombre: b.nombre, url: b.url }));
  } else if (rutas.length) {
    principal = [...rutas].sort((a, b) => b.length - a.length)[0];
  }
  const jerarquia = principal ? principal.map((x) => x.nombre) : [];
  const subcategorias = jerarquia.slice(1).filter((n) => norm(n) !== norm(modelo));

  return {
    modelo,
    nombre: modelo,
    sku: sku || modelo,
    product_id: extraerProductId($, html),
    marca,

    // Categorías tal como las muestra la página ("Categorías: ...")
    categorias_pagina: categoriasPagina.map((c) => ({
      nombre: c.nombre, slug: c.slugs[c.slugs.length - 1], url: c.url, ruta: c.clave, nivel: c.slugs.length,
    })),
    // Jerarquía real (raíz -> hoja) reconstruida desde las URLs
    categoria_principal: jerarquia[0] || null,
    subcategorias,
    subcategoria: subcategorias.join(" > "),
    categorias: jerarquia,
    categoria: jerarquia.join(" > "),
    rutas_categoria: rutas.map((r) => r.map((x) => x.nombre)), // una por rama si hay varias
    categoria_url: principal ? principal[principal.length - 1].url : null,

    precio,
    precio_lista: precioLista,
    precio_tipo: precioTipo, // "cliente" (Tú Precio, con sesión) | "publico"
    moneda: "USD",
    disponible,
    existencias,

    descripcion: desc.descripcion,
    descripcion_metodo: desc.descripcion_metodo,
    descripcion_larga: desc.descripcion_larga,
    videos: desc.videos,
    info_tecnica_url: desc.info_tecnica_url,
    enlaces_descripcion: desc.enlaces_descripcion,
    atributos: extraerAtributos($),

    imagen: img.imagen,
    imagen_miniatura: img.imagen_miniatura,
    imagenes: img.imagenes,
    relacionados: extraerRelacionados($),

    url,
    actualizado: new Date().toISOString(),
  };
}

async function extraerProducto(url) {
  const html = await get(url);
  if (!html) return null;
  return parsearProducto(html, url);
}

function registrarProducto(p) {
  for (const c of p.categorias_pagina || []) {
    registrarCategoria(
      { nombre: c.nombre, slugs: c.ruta.split("/"), clave: c.ruta, url: c.url },
      true,
      p.modelo
    );
  }
}

// ---------------------------------------------------------------------------
// Programa principal
// ---------------------------------------------------------------------------
async function main() {
  log("=== scraper.js v4 (categorías exactas + datos completos) ===");
  if (!COOKIE) warn('Sin GE_COOKIE: solo se captura el precio público ("PRECIO"), no "Tú Precio".');

  if (URL_UNICA) {
    const p = await extraerProducto(URL_UNICA);
    console.log(JSON.stringify(p, null, 2));
    return;
  }

  let productos = [];
  const hechos = new Set();
  if (REANUDAR && fs.existsSync(OUTPUT_FILE)) {
    try {
      productos = JSON.parse(fs.readFileSync(OUTPUT_FILE, "utf-8")).productos || [];
      productos.forEach((p) => { hechos.add(p.url); registrarProducto(p); });
      log(`Reanudando: ${productos.length} productos ya guardados`);
    } catch (e) { warn(`No pude leer ${OUTPUT_FILE}: ${e.message}`); }
  }

  const urls = await descubrirUrls();
  log(`Total de productos a procesar: ${urls.length}`);

  const guardar = (enProgreso) => {
    fs.writeFileSync(
      OUTPUT_FILE,
      JSON.stringify(
        {
          fuente: BASE_URL,
          total_productos: productos.length,
          total_esperado: urls.length,
          en_progreso: Boolean(enProgreso),
          generado: new Date().toISOString(),
          con_sesion: Boolean(COOKIE),
          modo_prueba: Boolean(LIMITE),
          productos,
        },
        null,
        2
      ),
      "utf-8"
    );
    guardarCategorias();
  };
  process.on("SIGINT", () => { log("Interrumpido: guardando..."); guardar(true); process.exit(0); });

  let i = 0;
  for (const url of urls) {
    i++;
    if (hechos.has(url)) continue;
    log(`[${i}/${urls.length}] ${url}`);
    try {
      const p = await extraerProducto(url);
      if (p) {
        productos.push(p);
        registrarProducto(p);
        if (productos.length % GUARDAR_CADA === 0) guardar(true);
      }
    } catch (e) {
      errorLog(`Error procesando ${url}: ${e.message}`);
    }
  }

  guardar(false);
  log(`Listo. ${productos.length} productos en ${OUTPUT_FILE} y ${registro.size} categorías en ${CATEGORIES_FILE}`);
}

module.exports = { parsearProducto };

if (require.main === module) {
  main().catch((e) => { errorLog(e.stack || e.message); process.exit(1); });
}
