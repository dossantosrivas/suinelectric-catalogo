# datos-beta

`carga.json` lo genera `scripts/migrar-catalogo-beta.js` a partir del catálogo que ya muestra la tienda
(categorías, productos del panel, inventario publicado, ocultos). La base beta lo descarga con
`catalogo.cargar_catalogo()` (ver supabase/18_catalogo_carga_y_tienda.sql).

No contiene costos ni cantidades de tu inventario: esos se cargan aparte y no se guardan en el repo.

Para volver a leer solo los atributos técnicos (filtros) sin rehacer la migración:
`node scripts/recalcular-atributos-beta.js` arma `datos-beta/atributos.json` (atributos, filtros por categoría y
los cambios de cada SKU) desde `catalogo-beta.json`; la base lo aplica con `catalogo.cargar_atributos()`
(supabase/19_atributos_todas_las_categorias.sql). Con `--aplicar` también deja `catalogo-beta.json` al día.
Los extractores están en `scripts/atributos-catalogo.js` (los usa también la migración completa).
