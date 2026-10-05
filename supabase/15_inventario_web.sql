-- =====================================================================
--  SUINELECTRIC · Tu inventario en la tienda
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--  Requiere haber corrido antes 01_esquema.sql, 03_existencias.sql y la
--  tabla de la app de ventas (adm_registros / adm_es_admin).
--
--  · inventario_web       → lo público de cada producto que tienes en
--                           existencia (tuyo + de tu papá): modelo, marca,
--                           nombre, descripción, categoría, precio de venta y
--                           un rango ("+10" o "pocas"). SIN costos ni cantidades.
--  · inventario_web_cant  → las cantidades exactas. Nadie la lee directo:
--                           solo administradores y clientes con permiso de
--                           "Ver existencias reales", a través de una función.
--
--  La app de ventas (ventas.html) las mantiene al día sola cada vez que la
--  abres o guardas una compra, venta o ajuste. La tienda las lee al cargar:
--  tus productos salen primero, con tu precio y tu marca.
-- =====================================================================

create table if not exists public.inventario_web (
  modelo       text primary key check (char_length(modelo) between 1 and 80),
  marca        text check (char_length(marca) <= 80),
  nombre       text check (char_length(nombre) <= 200),
  descripcion  text check (char_length(descripcion) <= 4000),
  categoria    text check (char_length(categoria) <= 120),
  precio       numeric check (precio is null or precio >= 0),
  stock        text not null check (stock in ('+10', 'pocas')),
  actualizado  timestamptz not null default now()
);

create table if not exists public.inventario_web_cant (
  modelo    text primary key references public.inventario_web(modelo) on delete cascade,
  cantidad  integer not null check (cantidad >= 0)
);

alter table public.inventario_web      enable row level security;
alter table public.inventario_web_cant enable row level security;

drop policy if exists inventario_web_leer on public.inventario_web;
create policy inventario_web_leer on public.inventario_web for select to anon, authenticated using (true);
grant select on public.inventario_web to anon, authenticated;
revoke insert, update, delete on public.inventario_web from anon, authenticated;
-- Sin políticas: nadie lee ni escribe las cantidades directo desde la web.
revoke all on public.inventario_web_cant from anon, authenticated;

-- La app de ventas manda la lista completa y reemplaza la anterior.
-- datos = [{ modelo, marca, nombre, descripcion, categoria, precio, cantidad }, …]
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
         greatest(0, round((x->>'cantidad')::numeric))::int              as cantidad
  from jsonb_array_elements(datos) x
  where coalesce(trim(x->>'modelo'), '') <> ''
    and jsonb_typeof(x->'cantidad') = 'number'
    and (x->>'cantidad')::numeric >= 1;

  delete from public.inventario_web w where not exists (select 1 from _inv i where i.modelo = w.modelo);

  insert into public.inventario_web as w (modelo, marca, nombre, descripcion, categoria, precio, stock, actualizado)
  select modelo, marca, nombre, descripcion, categoria, precio,
         case when cantidad > 10 then '+10' else 'pocas' end, now()
  from _inv
  on conflict (modelo) do update set
    marca = excluded.marca, nombre = excluded.nombre, descripcion = excluded.descripcion,
    categoria = excluded.categoria, precio = excluded.precio, stock = excluded.stock,
    actualizado = case when (w.marca, w.nombre, w.descripcion, w.categoria, w.precio, w.stock)
                         is distinct from
                        (excluded.marca, excluded.nombre, excluded.descripcion, excluded.categoria, excluded.precio, excluded.stock)
                       then now() else w.actualizado end;

  insert into public.inventario_web_cant (modelo, cantidad)
  select modelo, cantidad from _inv
  on conflict (modelo) do update set cantidad = excluded.cantidad;

  select count(*) into n from _inv;
  return n;
end $$;
revoke all on function public.publicar_inventario_web(jsonb) from public, anon;
grant execute on function public.publicar_inventario_web(jsonb) to authenticated;

-- La tienda la llama al entrar: {"MODELO": cantidad, …} o null si no tiene permiso.
create or replace function public.inventario_cantidades() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.puede_ver_existencias() then return null; end if;
  return (select coalesce(jsonb_object_agg(modelo, cantidad), '{}'::jsonb) from public.inventario_web_cant);
end $$;
revoke all on function public.inventario_cantidades() from public, anon;
grant execute on function public.inventario_cantidades() to authenticated;
