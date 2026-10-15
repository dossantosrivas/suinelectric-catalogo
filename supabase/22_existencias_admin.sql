-- =====================================================================
--  SUINELECTRIC · Existencias por inventario para los administradores
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--  Requiere 15_inventario_web.sql.
--
--  · inventario_web_cant gana dos columnas: manuel y papa (lo de cada uno).
--  · publicar_inventario_web acepta, además de "cantidad", "manuel" y "papa".
--    Si Gestión no los manda (versión vieja), quedan vacíos y todo sigue igual.
--  · inventario_detalle_admin() → {"MODELO": {"t": total, "m": manuel, "p": papa}}
--    solo para administradores. La tienda lo usa en la ficha de cada producto.
-- =====================================================================

alter table public.inventario_web_cant add column if not exists manuel integer;
alter table public.inventario_web_cant add column if not exists papa   integer;

create or replace function public.publicar_inventario_web(datos jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.adm_es_admin() then raise exception 'Sin permiso'; end if;
  if jsonb_typeof(datos) <> 'array' then raise exception 'Formato inválido'; end if;

  create temp table _inv on commit drop as
  select distinct on (lower(trim(x->>'modelo')))
         left(trim(x->>'modelo'), 80)                                   as modelo,
         nullif(left(upper(trim(coalesce(x->>'marca', ''))), 80), '')    as marca,
         nullif(left(trim(coalesce(x->>'nombre', '')), 200), '')         as nombre,
         nullif(left(trim(coalesce(x->>'descripcion', '')), 4000), '')   as descripcion,
         nullif(left(trim(coalesce(x->>'categoria', '')), 120), '')      as categoria,
         case when jsonb_typeof(x->'precio') = 'number' and (x->>'precio')::numeric > 0
              then (x->>'precio')::numeric end                           as precio,
         greatest(0, round((x->>'cantidad')::numeric))::int              as cantidad,
         case when jsonb_typeof(x->'manuel') = 'number'
              then greatest(0, round((x->>'manuel')::numeric))::int end  as manuel,
         case when jsonb_typeof(x->'papa') = 'number'
              then greatest(0, round((x->>'papa')::numeric))::int end    as papa
  from jsonb_array_elements(datos) x
  where coalesce(trim(x->>'modelo'), '') <> ''
    and jsonb_typeof(x->'cantidad') = 'number'
    and (x->>'cantidad')::numeric >= 0;

  delete from public.inventario_web w where not exists (select 1 from _inv i where i.modelo = w.modelo);

  insert into public.inventario_web as w (modelo, marca, nombre, descripcion, categoria, precio, stock, actualizado)
  select modelo, marca, nombre, descripcion, categoria, precio,
         case when cantidad > 10 then '+10' when cantidad >= 1 then 'pocas' else 'pedido' end, now()
  from _inv
  on conflict (modelo) do update set
    marca = excluded.marca, nombre = excluded.nombre, descripcion = excluded.descripcion,
    categoria = excluded.categoria, precio = excluded.precio, stock = excluded.stock,
    actualizado = case when (w.marca, w.nombre, w.descripcion, w.categoria, w.precio, w.stock)
                         is distinct from
                        (excluded.marca, excluded.nombre, excluded.descripcion, excluded.categoria, excluded.precio, excluded.stock)
                       then now() else w.actualizado end;

  insert into public.inventario_web_cant (modelo, cantidad, manuel, papa)
  select modelo, cantidad, manuel, papa from _inv
  on conflict (modelo) do update set cantidad = excluded.cantidad, manuel = excluded.manuel, papa = excluded.papa;

  select count(*) into n from _inv;
  return n;
end $$;
revoke all on function public.publicar_inventario_web(jsonb) from public, anon;
grant execute on function public.publicar_inventario_web(jsonb) to authenticated;

-- Solo administradores: lo de cada inventario, para la ficha de la tienda.
create or replace function public.inventario_detalle_admin() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.adm_es_admin() then return null; end if;
  return (select coalesce(jsonb_object_agg(modelo, jsonb_build_object('t', cantidad, 'm', manuel, 'p', papa)), '{}'::jsonb)
          from public.inventario_web_cant);
end $$;
revoke all on function public.inventario_detalle_admin() from public, anon;
grant execute on function public.inventario_detalle_admin() to authenticated;
