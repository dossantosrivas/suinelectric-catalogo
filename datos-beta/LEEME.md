# datos-beta

`carga.json` lo genera `scripts/migrar-catalogo-beta.js` a partir del catálogo que ya muestra la tienda
(categorías, productos del panel, inventario publicado, ocultos). La base beta lo descarga con
`catalogo.cargar_catalogo()` (ver supabase/18_catalogo_carga_y_tienda.sql).

No contiene costos ni cantidades de tu inventario: esos se cargan aparte y no se guardan en el repo.
