-- =====================================================================
--  20 · Correcciones a productos del distribuidor (panel → Productos → Editar)
--  · productos_web.correccion = true → la fila NO es un producto propio:
--    corrige nombre, marca, descripción, categoría y fotos de un producto
--    que viene del distribuidor (mismo modelo). El precio y la existencia
--    siguen llegando del distribuidor cada día (no se guardan aquí).
--  Ya aplicado en Supabase (producción y beta) el 2026-10-09.
-- =====================================================================
alter table public.productos_web add column if not exists correccion boolean not null default false;
comment on column public.productos_web.correccion is 'true = corrige un producto del distribuidor (nombre, descripción, fotos, categoría); el precio y la existencia siguen viniendo del distribuidor';
