-- Descuentos de clientes por categoría (ej. variadores o arrancadores suaves de Schneider).
-- Ya aplicado en Supabase el 2026-10-22. Se puede volver a correr sin problema.
-- categoria = familia o categoría de la tienda ("Variadores de Frecuencia", "Arrancadores Suaves",
-- "Variadores y Arrancadores"…). Vacío = todas. Se combina con marca, no con modelo.
alter table public.reglas_descuento add column if not exists categoria text;
alter table public.reglas_descuento drop constraint if exists regla_categoria_sin_modelo;
alter table public.reglas_descuento add constraint regla_categoria_sin_modelo check (categoria is null or modelo is null);
