-- =====================================================================
--  21 · GESTIÓN: ROLES (ADMINISTRADOR / VENDEDOR), HISTORIAL DE CAMBIOS
--       Y AVISOS DE OFERTAS SIN RESPUESTA
-- ---------------------------------------------------------------------
--  · adm_usuarios.rol      'admin' (ve todo) o 'vendedor'.
--    El vendedor NO lee la tabla adm_registros directo: lee y guarda con
--    adm_leer() / adm_guardar(), que le quitan costos, descuentos de
--    distribuidor, compras, ajustes y comisiones, y al guardar conservan
--    los costos que ya tenía cada documento. No puede eliminar.
--  · adm_historial         quién cambió qué y cuándo (lo llena un trigger).
--    Solo lo ven los administradores. Se guarda 180 días.
--  · adm_avisos_ofertas    qué avisos de SuinBot ya se mandaron por oferta.
--
--  Seguro de correr varias veces.
-- =====================================================================

-- ---------- Roles ----------
alter table public.adm_usuarios add column if not exists rol text not null default 'admin';
alter table public.adm_usuarios add column if not exists nombre text;
alter table public.adm_usuarios add column if not exists creado timestamptz not null default now();
do $$ begin
  alter table public.adm_usuarios add constraint adm_usuarios_rol_ck check (rol in ('admin', 'vendedor'));
exception when duplicate_object then null; end $$;
create unique index if not exists adm_usuarios_email_u on public.adm_usuarios (lower(email));

-- Rol de quien está conectado: 'admin', 'vendedor' o null (sin acceso a Gestión).
create or replace function public.adm_mi_rol()
returns text language sql stable security definer set search_path = public as $$
  select case
    when coalesce(public.es_admin(), false) then 'admin'
    else (select u.rol from public.adm_usuarios u where lower(u.email) = lower(auth.jwt() ->> 'email') limit 1)
  end;
$$;

-- Administrador de Gestión = administrador de la tienda o usuario con rol admin.
create or replace function public.adm_es_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select public.adm_mi_rol() = 'admin';
$$;

create or replace function public.adm_es_vendedor()
returns boolean language sql stable security definer set search_path = public as $$
  select public.adm_mi_rol() = 'vendedor';
$$;

grant execute on function public.adm_mi_rol(), public.adm_es_admin(), public.adm_es_vendedor() to authenticated;

-- Los administradores manejan la lista de usuarios; cada quien ve su propia fila.
drop policy if exists adm_usuarios_admin on public.adm_usuarios;
create policy adm_usuarios_admin on public.adm_usuarios for all to authenticated
  using (public.adm_es_admin()) with check (public.adm_es_admin());

-- ---------- Lo que el vendedor puede ver ----------
-- Quita costos y datos internos de un registro. Devuelve null si no debe verlo.
create or replace function public.adm_limpiar_vendedor(p_col text, p_data jsonb)
returns jsonb language plpgsql immutable as $$
declare d jsonb := p_data; its jsonb; inv jsonb; k text;
begin
  if p_col = 'docs' then
    if coalesce(d->>'tipo', '') in ('compra', 'ajuste') then return null; end if;
    d := d - 'fixCostos';
    if jsonb_typeof(d->'items') = 'array' then
      select coalesce(jsonb_agg(case when jsonb_typeof(it) = 'object' then it - 'costo' - 'dtoDist' - 'recargo' else it end), '[]'::jsonb)
        into its from jsonb_array_elements(d->'items') it;
      d := jsonb_set(d, '{items}', its);
    end if;
  elsif p_col = 'productos' then
    if jsonb_typeof(d->'inv') = 'object' then
      inv := d->'inv';
      for k in select jsonb_object_keys(d->'inv') loop
        if jsonb_typeof(inv->k) = 'object' then inv := jsonb_set(inv, array[k], (inv->k) - 'costo'); end if;
      end loop;
      d := jsonb_set(d, '{inv}', inv);
    end if;
  elsif p_col = 'proveedores' then d := d - 'descuento' - 'reglas';
  elsif p_col = 'config' then d := d - 'descCostoDist';
  elsif p_col = 'empleados' then d := d - 'comision';
  end if;
  return d;
end $$;

-- Lectura para vendedores (incremental: solo lo cambiado después de p_desde).
create or replace function public.adm_leer(p_desde timestamptz default null, p_limite int default 1000, p_desplazar int default 0)
returns table (coleccion text, id text, data jsonb, borrado boolean, actualizado timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if public.adm_mi_rol() is null then raise exception 'Sin permiso para Gestión' using errcode = '42501'; end if;
  if public.adm_es_admin() then
    return query select r.coleccion, r.id, r.data, r.borrado, r.actualizado from public.adm_registros r
      where p_desde is null or r.actualizado > p_desde
      order by r.actualizado, r.coleccion, r.id limit p_limite offset p_desplazar;
  else
    return query select r.coleccion, r.id,
        case when r.borrado then r.data else coalesce(public.adm_limpiar_vendedor(r.coleccion, r.data), jsonb_build_object('id', r.id)) end,
        -- lo que el vendedor no debe ver le llega como "borrado" para que no quede en su equipo
        r.borrado or public.adm_limpiar_vendedor(r.coleccion, r.data) is null,
        r.actualizado
      from public.adm_registros r
      where (p_desde is null or r.actualizado > p_desde)
      order by r.actualizado, r.coleccion, r.id limit p_limite offset p_desplazar;
  end if;
end $$;
grant execute on function public.adm_leer(timestamptz, int, int) to authenticated;

-- Guardado para vendedores. Recibe [{coleccion,id,data,borrado}, …].
-- Conserva los costos guardados; los productos nuevos de tu inventario
-- toman el costo de la ficha del producto.
create or replace function public.adm_guardar(p_filas jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare
  f jsonb; col text; rid text; nueva jsonb; vieja jsonb; borr boolean; n int := 0;
  it jsonb; old_it jsonb; prod jsonb; c jsonb; out_its jsonb;
begin
  if public.adm_es_admin() then
    -- un administrador puede usarla igual que la tabla
    for f in select * from jsonb_array_elements(p_filas) loop
      insert into public.adm_registros (coleccion, id, data, borrado)
        values (f->>'coleccion', f->>'id', f->'data', coalesce((f->>'borrado')::boolean, false))
        on conflict (coleccion, id) do update set data = excluded.data, borrado = excluded.borrado;
      n := n + 1;
    end loop;
    return n;
  end if;
  if not public.adm_es_vendedor() then raise exception 'Sin permiso para Gestión' using errcode = '42501'; end if;

  for f in select * from jsonb_array_elements(p_filas) loop
    col := f->>'coleccion'; rid := f->>'id'; nueva := f->'data'; borr := coalesce((f->>'borrado')::boolean, false);
    vieja := null;
    select r.data into vieja from public.adm_registros r where r.coleccion = col and r.id = rid;

    if col not in ('docs', 'clientes', 'rapidas', 'productos') then
      raise exception 'Un vendedor no puede cambiar %', col using errcode = '42501';
    end if;
    if borr and col <> 'rapidas' then
      raise exception 'Un vendedor no puede eliminar' using errcode = '42501';
    end if;

    if col = 'docs' and not borr then
      if coalesce(nueva->>'tipo', '') in ('compra', 'ajuste') or coalesce(vieja->>'tipo', '') in ('compra', 'ajuste') then
        raise exception 'Un vendedor no puede registrar compras ni ajustes' using errcode = '42501';
      end if;
      nueva := nueva - 'fixCostos';
      if vieja ? 'fixCostos' then nueva := nueva || jsonb_build_object('fixCostos', vieja->'fixCostos'); end if;
      if jsonb_typeof(nueva->'items') = 'array' then
        out_its := '[]'::jsonb;
        for it in select * from jsonb_array_elements(nueva->'items') loop
          if jsonb_typeof(it) = 'object' then
            it := it - 'costo' - 'dtoDist' - 'recargo';
            old_it := null;
            if vieja is not null and jsonb_typeof(vieja->'items') = 'array' then
              select o into old_it from jsonb_array_elements(vieja->'items') o where o->>'id' = it->>'id' limit 1;
            end if;
            if old_it is not null then
              it := it || jsonb_strip_nulls(jsonb_build_object('costo', old_it->'costo', 'dtoDist', old_it->'dtoDist', 'recargo', old_it->'recargo'));
            elsif coalesce(it->>'origen', '') in ('manuel', 'papa') and it->>'productoId' is not null then
              prod := null;
              select p.data into prod from public.adm_registros p where p.coleccion = 'productos' and p.id = it->>'productoId';
              c := prod->'inv'->(it->>'origen')->'costo';
              if c is not null and jsonb_typeof(c) = 'number' then it := it || jsonb_build_object('costo', c); end if;
            end if;
          end if;
          out_its := out_its || jsonb_build_array(it);
        end loop;
        nueva := jsonb_set(nueva, '{items}', out_its);
      end if;
    elsif col = 'productos' and not borr then
      -- el vendedor no toca existencias ni costos de la ficha
      if vieja is not null and vieja ? 'inv' then nueva := jsonb_set(nueva, '{inv}', vieja->'inv');
      else nueva := nueva - 'inv'; end if;
    end if;

    insert into public.adm_registros (coleccion, id, data, borrado)
      values (col, rid, coalesce(nueva, jsonb_build_object('id', rid)), borr)
      on conflict (coleccion, id) do update set data = excluded.data, borrado = excluded.borrado;
    n := n + 1;
  end loop;
  return n;
end $$;
grant execute on function public.adm_guardar(jsonb) to authenticated;

-- ---------- Historial de cambios ----------
create table if not exists public.adm_historial (
  id          bigint generated always as identity primary key,
  cuando      timestamptz not null default now(),
  quien       text,                 -- correo de quien hizo el cambio
  coleccion   text not null,
  reg_id      text not null,
  accion      text not null check (accion in ('crear', 'editar', 'borrar', 'restaurar')),
  antes       jsonb,
  despues     jsonb
);
create index if not exists adm_historial_reg on public.adm_historial (coleccion, reg_id, cuando desc);
create index if not exists adm_historial_cuando on public.adm_historial (cuando desc);
alter table public.adm_historial enable row level security;
drop policy if exists adm_historial_leer on public.adm_historial;
create policy adm_historial_leer on public.adm_historial for select to authenticated using (public.adm_es_admin());

create or replace function public.adm_registrar_historial()
returns trigger language plpgsql security definer set search_path = public as $$
declare a text; quien text := nullif(coalesce(auth.jwt() ->> 'email', ''), '');
begin
  if tg_op = 'UPDATE' and old.data is not distinct from new.data and old.borrado = new.borrado then return new; end if;
  -- los cambios automáticos internos (sin usuario) no se anotan, salvo borrados
  a := case
    when tg_op = 'INSERT' then 'crear'
    when new.borrado and not old.borrado then 'borrar'
    when old.borrado and not new.borrado then 'restaurar'
    else 'editar' end;
  -- "mod" cambia en cada guardado; si es lo único distinto, no vale la pena anotarlo
  if tg_op = 'UPDATE' and a = 'editar' and (old.data - 'mod') is not distinct from (new.data - 'mod') then return new; end if;
  insert into public.adm_historial (quien, coleccion, reg_id, accion, antes, despues)
    values (coalesce(quien, 'sistema'), new.coleccion, new.id, a,
            case when tg_op = 'UPDATE' then old.data end,
            case when new.borrado then null else new.data end);
  return new;
end $$;
drop trigger if exists adm_registros_historial on public.adm_registros;
create trigger adm_registros_historial after insert or update on public.adm_registros
  for each row execute function public.adm_registrar_historial();

-- Limpieza (la corre el aviso diario de ofertas): guarda 180 días.
create or replace function public.adm_historial_limpiar(p_dias int default 180)
returns integer language sql security definer set search_path = public as $$
  with x as (delete from public.adm_historial where cuando < now() - make_interval(days => p_dias) returning 1)
  select count(*)::int from x;
$$;
revoke execute on function public.adm_historial_limpiar(int) from public, anon, authenticated;

-- ---------- Avisos de ofertas sin respuesta ----------
create table if not exists public.adm_avisos_ofertas (
  doc_id   text not null,
  clave    text not null,             -- 'd3', 'd5'…
  enviado  timestamptz not null default now(),
  primary key (doc_id, clave)
);
alter table public.adm_avisos_ofertas enable row level security;   -- solo la clave secreta (GitHub Actions)

-- Ofertas abiertas o enviadas de los últimos 60 días (las lee el aviso diario).
create or replace function public.ofertas_para_seguimiento()
returns table (id text, data jsonb, avisos text[])
language sql stable security definer set search_path = public as $$
  select r.id, r.data, coalesce((select array_agg(a.clave) from public.adm_avisos_ofertas a where a.doc_id = r.id), '{}')
  from public.adm_registros r
  where r.coleccion = 'docs' and not r.borrado
    and r.data->>'tipo' = 'oferta'
    and coalesce(r.data->>'estado', 'abierta') in ('abierta', 'enviada')
    and left(coalesce(r.data->>'enviadaEn', r.data->>'fecha', ''), 10) >= to_char(now() - interval '60 days', 'YYYY-MM-DD');
$$;
revoke execute on function public.ofertas_para_seguimiento() from public, anon, authenticated;
