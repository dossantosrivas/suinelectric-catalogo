/* =====================================================================
   ENLACES OFICIALES DEL FABRICANTE (una sola fuente)
   ---------------------------------------------------------------------
   Para cada producto devuelve:
     · pagina → página oficial del producto/serie en la web del fabricante
     · manual → manual o guía en PDF (directo)

   Prioridad:
     1. Lo que tenga el propio producto: pagina_oficial / manual_url
        (se pueden poner a mano en productos_manuales.json o en el panel),
        o ficha_tecnica / info_tecnica_url (lo que trae el distribuidor).
     2. Las reglas de abajo por marca y serie.

   Lo usan:
     · generar-catalogo-tienda.js (catalogo-tienda.json)
     · generar-vistas-previas.js (páginas /p/)
     · tienda.html (en el navegador, para productos del panel o del inventario)

   Para agregar una serie: copia una línea de SERIES_INVT con el inicio del
   modelo (prefijo), la página y el manual. Nunca poner enlaces al proveedor.
   ===================================================================== */
(function (raiz, fabrica){
  const m = fabrica();
  if (typeof module === 'object' && module.exports) module.exports = m;
  else raiz.EnlacesOficiales = m;
})(typeof self !== 'undefined' ? self : this, function (){

const INVT = 'https://www.invt.com/es/products/';
const PDF = 'https://www.invt.com/uploads/file1/';

// El orden importa: el prefijo más largo primero (GD20LA antes que GD20).
const SERIES_INVT = [
  { serie: 'GD20LA', pagina: INVT + 'gd20la-vfd-192',                      manual: 'https://www.invt.com/es/uploads/file1/20221025/GD20-LA user manual-spanish _V1.0.pdf' },
  { serie: 'GD200A', pagina: INVT + 'gd200a-series-vfd-drive-21',          manual: PDF + '20200413/Goodrive200A Series Inverter_V2.4.pdf' },
  { serie: 'GD270',  pagina: INVT + 'gd270-vfd-for-fan-pump-196',          manual: PDF + '20250421/Manual GD270-Variador de frecuencia para ventiladores y bombas_V1.2.pdf' },
  { serie: 'GD300L', pagina: INVT + 'gd300l-series-elevator-drive-45',     manual: PDF + '20200413/Goodrive300-LIFT series inverter operation manual_V1.2.pdf' },
  { serie: 'GD310',  pagina: null,                                         manual: PDF + '20200715/GD310-UL Series VFD Manual.pdf' },
  { serie: 'GD350',  pagina: INVT + 'gd350-ul-series-vfd-drives-216',      manual: PDF + '20251231/GD350-UL VFD Manual_V1.5.pdf' },
  { serie: 'GD100',  pagina: INVT + 'gd100-pv-series-solar-pump-inverter-28', manual: PDF + '20260624/GD100-PV_Manual_ES_V1.3.pdf' },
  { serie: 'GD20',   pagina: INVT + 'gd20-series-vfd-drive-14',            manual: PDF + '20200410/Goodrive20 Series Inverter_V1.5.pdf' },
  { serie: 'GD27',   pagina: INVT + 'gd27-series-smart-vfd-199',           manual: PDF + '20240510/Goodrive27 Series Smart VFD Manual_V1.2.pdf' },
  { serie: 'GD28',   pagina: INVT + 'gd28-series-flexible-general-purpose-vfd-228', manual: PDF + '20260721/GD28_Quick_Start_Guide_ES_V1.0.pdf' },
  { serie: 'DBU100', pagina: INVT + 'dbu-energy-consumption-braking-unit-213', manual: null },
  { serie: 'EC-PG',  pagina: INVT + 'pg-series-encoder-interface-card-49', manual: null },
];

const limpiar = (u) => {
  let s = String(u || '').trim().replace(/&amp;/gi, '&').replace(/&;+/g, '&').replace(/[.,;)]+$/, '');
  if (!/^https?:\/\//i.test(s) || /grupo-electricos\.com/i.test(s)) return null;   // nunca al proveedor
  try { s = encodeURI(decodeURI(s)); } catch (e) { s = encodeURI(s); }              // espacios en los PDF
  return s;
};

const urlSiemens = (modelo) => 'https://mall.industry.siemens.com/mall/es/ve/Catalog/Search?searchTerm=' +
  encodeURIComponent(String(modelo).trim()) + '&tab=Product';
const urlSchneider = (ref) => 'https://www.se.com/co/es/product/' + encodeURIComponent(ref) + '/';

function porReglas(p){
  const marca = String(p.marca || '').toUpperCase();
  const modelo = String(p.modelo || '').trim().toUpperCase();
  if (!modelo) return {};
  if (/INVT/.test(marca)){
    const s = SERIES_INVT.find(x => modelo.startsWith(x.serie));
    return s ? { pagina: s.pagina, manual: s.manual } : {};
  }
  if (/SIEMENS/.test(marca) && /^[0-9][A-Z0-9]{2,}([- ][A-Z0-9]+)*$/.test(modelo))
    return { pagina: urlSiemens(p.modelo) };
  if (/SCHNEIDER|TELEMECANIQUE|SQUARE ?D/.test(marca) && /^[A-Z0-9][A-Z0-9-]{3,}$/.test(modelo))
    return { pagina: urlSchneider(modelo) };
  return {};
}

function enlacesDe(p){
  if (!p) return { pagina: null, manual: null };
  const r = porReglas(p);
  return {
    pagina: limpiar(p.pagina_oficial) || limpiar(p.ficha_tecnica) || limpiar(p.info_tecnica_url) || limpiar(r.pagina),
    manual: limpiar(p.manual_url) || limpiar(r.manual),
  };
}

return { enlacesDe, SERIES_INVT };
});
