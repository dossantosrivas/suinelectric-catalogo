-- =====================================================================
--  SUINELECTRIC · Existencias reales solo para quien tú elijas
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--
--  · La tienda pública ya NO trae las cantidades exactas: muestra
--    "+10 disponibles", "Últimas unidades" o "Agotado".
--  · Las cantidades reales se guardan aquí (tabla existencias), las sube
--    GitHub cada día, y solo las pueden leer:
--      - los administradores (siempre)
--      - los clientes marcados con "Ver existencias reales"
--      - los clientes de un tipo marcado con "Ver existencias reales"
-- =====================================================================

-- ---------- Permisos (casillas en el panel) ----------
alter table public.clientes      add column if not exists ver_existencias boolean not null default false;
alter table public.tipos_cliente add column if not exists ver_existencias boolean not null default false;

-- Un cliente no puede darse este permiso a sí mismo.
create or replace function public.proteger_cliente() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('anon', 'authenticated') and not public.es_admin() then
    new.email           := old.email;
    new.user_id         := old.user_id;
    new.tipo_id         := old.tipo_id;
    new.es_admin        := old.es_admin;
    new.activo          := old.activo;
    new.creado          := old.creado;
    new.ver_existencias := old.ver_existencias;
  end if;
  return new;
end $$;

-- ¿Quien está viendo puede ver las cantidades reales?
create or replace function public.puede_ver_existencias() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.clientes c
    left join public.tipos_cliente t on t.id = c.tipo_id
    where c.email = public.mi_email()
      and c.activo
      and (c.es_admin or c.ver_existencias or coalesce(t.ver_existencias, false))
  )
$$;

-- ---------- Cantidades reales ----------
create table if not exists public.existencias (
  modelo      text primary key,
  cantidad    integer not null,
  actualizado timestamptz not null default now()
);
alter table public.existencias enable row level security;
-- Sin políticas: nadie lee ni escribe la tabla directo desde la web.
-- Se usa solo a través de las funciones de abajo.
revoke all on public.existencias from anon, authenticated;

-- La tienda la llama al entrar: devuelve {"MODELO": cantidad, …} o null si no tiene permiso.
create or replace function public.existencias_reales() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.puede_ver_existencias() then return null; end if;
  return (select coalesce(jsonb_object_agg(modelo, cantidad), '{}'::jsonb) from public.existencias);
end $$;
revoke all on function public.existencias_reales() from public, anon;
grant execute on function public.existencias_reales() to authenticated;

-- Para el panel: cuántos modelos hay y cuándo se actualizaron.
create or replace function public.estado_existencias() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.es_admin() then return null; end if;
  return (select jsonb_build_object('modelos', count(*), 'actualizado', max(actualizado)) from public.existencias);
end $$;
revoke all on function public.estado_existencias() from public, anon;
grant execute on function public.estado_existencias() to authenticated;

-- La llama GitHub cada día (con la clave secreta). Reemplaza todo.
create or replace function public.cargar_existencias(datos jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  delete from public.existencias where true;
  insert into public.existencias (modelo, cantidad)
  select key, greatest(0, round((value)::text::numeric))::int
  from jsonb_each(datos)
  where jsonb_typeof(value) = 'number';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.cargar_existencias(jsonb) from public, anon, authenticated;
grant execute on function public.cargar_existencias(jsonb) to service_role;
