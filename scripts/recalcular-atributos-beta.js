/* =====================================================================
   RECALCULAR ATRIBUTOS DEL CATÁLOGO ÚNICO (beta)
   ---------------------------------------------------------------------
   Vuelve a leer los atributos técnicos de cada SKU con
   scripts/atributos-catalogo.js, sin rehacer toda la migración.
   Parte de catalogo-beta.json (lo que exporta la base) y escribe
   datos-beta/atributos.json con:
     · atributos  → catalogo.atributos
     · filtros    → catalogo.atributos_categoria (qué filtros ve cada categoría)
     · parches    → lo nuevo de catalogo.skus.specs, agrupado por cambio
   La base lo aplica con catalogo.cargar_atributos(json)
   (supabase/19_atributos_todas_las_categorias.sql).

   Uso: node scripts/recalcular-atributos-beta.js
   ===================================================================== */
const fs = require('fs');
const path = require('path');
const { ATRIBUTOS, FILTROS, atributosExtra, unirSpecs } = require('./atributos-catalogo');

const REPO = path.join(__dirname, '..');
const beta = JSON.parse(fs.readFileSync(path.join(REPO, 'catalogo-beta.json'), 'utf8'));
const slug = (s) => String(s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

// ruta (familia/categoría) de cada categoría, tal como está en la base
const rutaCat = new Map();
for (const p of beta.productos) if (p.ruta && p.ruta[1] && !rutaCat.has(p.ruta[1])) rutaCat.set(p.ruta[1], slug(p.ruta[0]) + '/' + slug(p.ruta[1]));

// Solo lo que cambia, agrupado: [{clave: valor…}, [códigos que llevan ese cambio]]
const grupos = new Map();
let nSku = 0;
for (const p of beta.productos){
  const categoria = p.ruta[1], resto = p.ruta.slice(2);
  const viejo = p.specs || {};
  const nuevo = unirSpecs(viejo, atributosExtra({ modelo: p.codigo, nombre: p.nombre, descripcion: p.desc || '' }, categoria, resto));
  const cambio = {};
  for (const [k, v] of Object.entries(nuevo)) if (JSON.stringify(viejo[k]) !== JSON.stringify(v)) cambio[k] = v;
  if (!Object.keys(cambio).length) continue;
  nSku++;
  const clave = JSON.stringify(cambio);
  if (!grupos.has(clave)) grupos.set(clave, [cambio, []]);
  grupos.get(clave)[1].push(p.codigo);
}
const parches = [...grupos.values()];

const filtros = [];
for (const [cat, lista] of Object.entries(FILTROS)){
  const ruta = rutaCat.get(cat);
  if (!ruta){ console.warn('Sin productos en la categoría', cat); continue; }
  lista.forEach(([clave, ob, dv], i) => filtros.push({ categoria: ruta, clave, orden: i, obligatorio: !!ob, define_variante: !!dv }));
}

const salida = {
  generado: new Date().toISOString(),
  atributos: Object.entries(ATRIBUTOS).map(([clave, [nombre, tipo, unidad]]) => ({ clave, nombre, tipo, unidad })),
  filtros,
  parches,
};
fs.writeFileSync(path.join(REPO, 'datos-beta', 'atributos.json'), JSON.stringify(salida));
console.log('Atributos:', salida.atributos.length, '· filtros:', filtros.length, '· SKU con datos nuevos:', nSku, 'de', beta.productos.length, '· grupos:', parches.length);

/* --aplicar: deja catalogo-beta.json igual a lo que exportaría la base después de
   cargar_atributos() (los mismos parches y los filtros nuevos), para no tener que
   volver a exportar el catálogo completo. */
if (process.argv.includes('--aplicar')){
  const porCodigo = new Map();
  for (const [cambio, codigos] of parches) for (const c of codigos) porCodigo.set(c, Object.assign(porCodigo.get(c) || {}, cambio));
  for (const p of beta.productos){ const c = porCodigo.get(p.codigo); if (c) p.specs = Object.assign({}, p.specs || {}, c); }
  const nombres = Object.fromEntries(salida.atributos.map(a => [a.clave, a]));
  const nuevos = {};
  for (const f of filtros){
    const a = nombres[f.clave];
    (nuevos[f.categoria] = nuevos[f.categoria] || []).push({ tipo: a.tipo, clave: a.clave, nombre: a.nombre, unidad: a.unidad, variante: f.define_variante });
  }
  beta.filtros = Object.assign({}, beta.filtros || {}, nuevos);   // las subcategorías con filtros propios se quedan
  // los nombres de atributos que cambiaron también en las definiciones que ya estaban
  for (const defs of Object.values(beta.filtros)) for (const d of defs) if (nombres[d.clave]){ d.nombre = nombres[d.clave].nombre; d.unidad = nombres[d.clave].unidad; d.tipo = nombres[d.clave].tipo; }
  beta.generado = new Date().toISOString();
  fs.writeFileSync(path.join(REPO, 'catalogo-beta.json'), JSON.stringify(beta));
  console.log('catalogo-beta.json actualizado');
}
