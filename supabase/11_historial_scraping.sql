-- =====================================================================
--  SUINELECTRIC · Historial del scraping (qué bajó de existencias)
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--  Requiere haber corrido antes 01_esquema.sql.
--
--  Cada vez que corre el scraper de grupo-electricos.com, GitHub manda
--  las existencias de los productos del scraper (no los manuales) y aquí
--  se comparan con las de la corrida anterior:
--    · scraping_ejecuciones → una fila por cada scraping (fecha y totales)
--    · scraping_movimientos → cada producto que cambió: antes, después y
--                             la diferencia (negativa = se restaron)
--  La primera corrida solo guarda la foto inicial (no hay con qué comparar).
--    · scraping_precios     → cada producto al que le cambió el precio
--                             (antes, después, diferencia y %)
--  Solo los administradores pueden verlo (panel → Scraping).
-- =====================================================================

-- ---------- Tablas ----------
create table if not exists public.scraping_ejecuciones (
  id                bigserial primary key,
  fecha             timestamptz not null default now(),
  generado          timestamptz,          -- cuándo terminó el scraper
  productos         integer not null default 0,
  bajaron           integer not null default 0,
  subieron          integer not null default 0,
  nuevos            integer not null default 0,
  desaparecidos     integer not null default 0,
  agotados          integer not null default 0,  -- llegaron a 0 en esta corrida
  unidades_restadas integer not null default 0,
  unidades_sumadas  integer not null default 0,
  primera           boolean not null default false,
  nota              text
);
alter table public.scraping_ejecuciones add column if not exists precios_subieron integer not null default 0;
alter table public.scraping_ejecuciones add column if not exists precios_bajaron  integer not null default 0;
create index if not exists scraping_ejecuciones_fecha on public.scraping_ejecuciones (fecha desc);

create table if not exists public.scraping_movimientos (
  id           bigserial primary key,
  ejecucion_id bigint not null references public.scraping_ejecuciones(id) on delete cascade,
  fecha        timestamptz not null default now(),
  modelo       text not null,
  marca        text,
  nombre       text,
  precio       numeric,
  antes        integer,
  despues      integer,
  diferencia   integer,      -- despues - antes (null si es nuevo o desapareció)
  tipo         text not null check (tipo in ('bajo', 'subio', 'nuevo', 'desaparecio'))
);
create index if not exists scraping_mov_ejecucion on public.scraping_movimientos (ejecucion_id);
create index if not exists scraping_mov_modelo    on public.scraping_movimientos (modelo, fecha desc);
create index if not exists scraping_mov_fecha     on public.scraping_movimientos (fecha desc);

create table if not exists public.scraping_precios (
  id             bigserial primary key,
  ejecucion_id   bigint not null references public.scraping_ejecuciones(id) on delete cascade,
  fecha          timestamptz not null default now(),
  modelo         text not null,
  marca          text,
  nombre         text,
  precio_antes   numeric not null,
  precio_despues numeric not null,
  diferencia     numeric not null,   -- despues - antes
  porcentaje     numeric             -- % de cambio sobre el precio anterior
);
create index if not exists scraping_precios_ejecucion on public.scraping_precios (ejecucion_id);
create index if not exists scraping_precios_modelo    on public.scraping_precios (modelo, fecha desc);
create index if not exists scraping_precios_fecha     on public.scraping_precios (fecha desc);

-- Última foto de existencias del scraper (para comparar con la siguiente).
create table if not exists public.scraping_ultimo (
  modelo   text primary key,
  cantidad integer not null,
  marca    text,
  nombre   text,
  precio   numeric
);

alter table public.scraping_ejecuciones enable row level security;
alter table public.scraping_movimientos enable row level security;
alter table public.scraping_ultimo      enable row level security;
alter table public.scraping_precios     enable row level security;
-- Sin políticas: nadie lee ni escribe directo desde la web; solo con las funciones de abajo.
revoke all on public.scraping_ejecuciones, public.scraping_movimientos, public.scraping_ultimo, public.scraping_precios from anon, authenticated;

-- ---------- La llama GitHub después de cada scraping (clave secreta) ----------
-- productos: [{"modelo":"X","cantidad":5,"marca":"…","nombre":"…","precio":12.3}, …]
create or replace function public.registrar_scraping(p_productos jsonb, p_generado timestamptz default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  eid       bigint;
  n_nuevo   integer;
  n_antes   integer;
  es_primera boolean;
  r         public.scraping_ejecuciones;
begin
  create temp table if not exists _scr_nuevo (modelo text primary key, cantidad integer, marca text, nombre text, precio numeric) on commit drop;
  truncate _scr_nuevo;
  insert into _scr_nuevo
  select distinct on (x.modelo) x.modelo, greatest(0, x.cantidad), x.marca, x.nombre, x.precio
  from jsonb_to_recordset(coalesce(p_productos, '[]'::jsonb)) as x(modelo text, cantidad integer, marca text, nombre text, precio numeric)
  where x.modelo is not null and x.modelo <> '' and x.cantidad is not null
  order by x.modelo;

  select count(*) into n_nuevo from _scr_nuevo;
  select count(*) into n_antes from public.scraping_ultimo;
  es_primera := n_antes = 0;

  -- Protección: si el scraping trajo muy pocos productos (falló a medias),
  -- no se compara ni se reemplaza la foto, para no registrar bajas falsas.
  if n_nuevo = 0 or (not es_primera and n_nuevo < n_antes * 0.6) then
    insert into public.scraping_ejecuciones (generado, productos, nota)
    values (p_generado, n_nuevo,
            'Omitido: llegaron ' || n_nuevo || ' productos y la corrida anterior tenía ' || n_antes || '. Parece un scraping incompleto.')
    returning * into r;
    return to_jsonb(r);
  end if;

  insert into public.scraping_ejecuciones (generado, productos, primera)
  values (p_generado, n_nuevo, es_primera)
  returning id into eid;

  if not es_primera then
    insert into public.scraping_movimientos (ejecucion_id, modelo, marca, nombre, precio, antes, despues, diferencia, tipo)
    select eid,
           coalesce(n.modelo, u.modelo),
           coalesce(n.marca, u.marca),
           coalesce(n.nombre, u.nombre),
           coalesce(n.precio, u.precio),
           u.cantidad, n.cantidad,
           case when u.modelo is not null and n.modelo is not null then n.cantidad - u.cantidad end,
           case when u.modelo is null then 'nuevo'
                when n.modelo is null then 'desaparecio'
                when n.cantidad < u.cantidad then 'bajo'
                else 'subio' end
    from _scr_nuevo n
    full join public.scraping_ultimo u on u.modelo = n.modelo
    where u.modelo is null or n.modelo is null or n.cantidad <> u.cantidad;

    -- Cambios de precio (solo si hay precio antes y después; se ignoran diferencias de centavos por redondeo).
    insert into public.scraping_precios (ejecucion_id, modelo, marca, nombre, precio_antes, precio_despues, diferencia, porcentaje)
    select eid, n.modelo, coalesce(n.marca, u.marca), coalesce(n.nombre, u.nombre),
           u.precio, n.precio, round(n.precio - u.precio, 2),
           case when u.precio > 0 then round(100 * (n.precio - u.precio) / u.precio, 1) end
    from _scr_nuevo n
    join public.scraping_ultimo u on u.modelo = n.modelo
    where n.precio is not null and u.precio is not null
      and abs(n.precio - u.precio) >= 0.01;
  end if;

  -- Si esta vez un producto vino sin precio, conserva el anterior para la próxima comparación.
  update _scr_nuevo n set precio = u.precio
  from public.scraping_ultimo u
  where u.modelo = n.modelo and n.precio is null;

  -- Reemplaza la foto con la de ahora.
  delete from public.scraping_ultimo where true;
  insert into public.scraping_ultimo (modelo, cantidad, marca, nombre, precio)
  select modelo, cantidad, marca, nombre, precio from _scr_nuevo;

  -- Totales de la corrida.
  update public.scraping_ejecuciones e set
    bajaron           = s.bajaron,
    subieron          = s.subieron,
    nuevos            = s.nuevos,
    desaparecidos     = s.desaparecidos,
    agotados          = s.agotados,
    unidades_restadas = s.restadas,
    unidades_sumadas  = s.sumadas,
    precios_subieron  = (select count(*) from public.scraping_precios where ejecucion_id = eid and diferencia > 0),
    precios_bajaron   = (select count(*) from public.scraping_precios where ejecucion_id = eid and diferencia < 0)
  from (
    select count(*) filter (where tipo = 'bajo')                      as bajaron,
           count(*) filter (where tipo = 'subio')                     as subieron,
           count(*) filter (where tipo = 'nuevo')                     as nuevos,
           count(*) filter (where tipo = 'desaparecio')               as desaparecidos,
           count(*) filter (where tipo = 'bajo' and despues = 0)      as agotados,
           coalesce(-sum(diferencia) filter (where diferencia < 0), 0) as restadas,
           coalesce(sum(diferencia)  filter (where diferencia > 0), 0) as sumadas
    from public.scraping_movimientos where ejecucion_id = eid
  ) s
  where e.id = eid
  returning e.* into r;

  -- Se guarda un año de historial.
  delete from public.scraping_ejecuciones where fecha < now() - interval '400 days';

  return to_jsonb(r);
end $$;
revoke all on function public.registrar_scraping(jsonb, timestamptz) from public, anon, authenticated;
grant execute on function public.registrar_scraping(jsonb, timestamptz) to service_role;

-- ---------- Para el panel (solo administradores) ----------
-- Resumen de los últimos N días: corridas, totales y productos que más se restaron.
create or replace function public.resumen_scraping(dias integer default 30)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 400)));
begin
  if not public.es_admin() then return null; end if;
  return jsonb_build_object(
    'ejecuciones', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.fecha desc)
      from (select * from public.scraping_ejecuciones where fecha >= desde order by fecha desc limit 200) e), '[]'::jsonb),
    'totales', (
      select jsonb_build_object(
        'corridas',          count(*) filter (where nota is null),
        'unidades_restadas', coalesce(sum(unidades_restadas), 0),
        'unidades_sumadas',  coalesce(sum(unidades_sumadas), 0),
        'bajaron',           coalesce(sum(bajaron), 0),
        'agotados',          coalesce(sum(agotados), 0),
        'precios_subieron',  coalesce(sum(precios_subieron), 0),
        'precios_bajaron',   coalesce(sum(precios_bajaron), 0))
      from public.scraping_ejecuciones where fecha >= desde),
    'mas_restados', coalesce((
      select jsonb_agg(t order by t.unidades desc)
      from (
        select modelo, max(marca) as marca, max(nombre) as nombre, max(precio) as precio,
               -sum(diferencia) as unidades, count(*) as veces, max(fecha) as ultima,
               (select u.cantidad from public.scraping_ultimo u where u.modelo = m.modelo) as queda
        from public.scraping_movimientos m
        where fecha >= desde and tipo = 'bajo'
        group by modelo
        order by -sum(diferencia) desc
        limit 50
      ) t), '[]'::jsonb)
  );
end $$;
revoke all on function public.resumen_scraping(integer) from public, anon;
grant execute on function public.resumen_scraping(integer) to authenticated;

-- Movimientos: de una corrida, de un modelo o de los últimos N días.
create or replace function public.movimientos_scraping(
  p_ejecucion bigint  default null,
  p_modelo    text    default null,
  dias        integer default 30,
  p_tipo      text    default null,   -- 'bajo' | 'subio' | 'nuevo' | 'desaparecio' | null = todos
  limite      integer default 1000
)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.es_admin() then return null; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(m) order by m.fecha desc, m.diferencia nulls last)
    from (
      select id, ejecucion_id, fecha, modelo, marca, nombre, precio, antes, despues, diferencia, tipo
      from public.scraping_movimientos
      where (p_ejecucion is null or ejecucion_id = p_ejecucion)
        and (p_modelo is null or modelo = p_modelo)
        and (p_ejecucion is not null or p_modelo is not null
             or fecha >= now() - make_interval(days => greatest(1, least(dias, 400))))
        and (p_tipo is null or tipo = p_tipo)
      order by fecha desc, diferencia nulls last
      limit greatest(1, least(limite, 5000))
    ) m), '[]'::jsonb);
end $$;
revoke all on function public.movimientos_scraping(bigint, text, integer, text, integer) from public, anon;
grant execute on function public.movimientos_scraping(bigint, text, integer, text, integer) to authenticated;

-- Cambios de precio: de una corrida, de un modelo o de los últimos N días.
create or replace function public.precios_scraping(
  p_ejecucion bigint  default null,
  p_modelo    text    default null,
  dias        integer default 30,
  p_sentido   text    default null,   -- 'subio' | 'bajo' | null = todos
  limite      integer default 1000
)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.es_admin() then return null; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(p) order by p.fecha desc, abs(p.porcentaje) desc nulls last)
    from (
      select id, ejecucion_id, fecha, modelo, marca, nombre, precio_antes, precio_despues, diferencia, porcentaje
      from public.scraping_precios
      where (p_ejecucion is null or ejecucion_id = p_ejecucion)
        and (p_modelo is null or modelo = p_modelo)
        and (p_ejecucion is not null or p_modelo is not null
             or fecha >= now() - make_interval(days => greatest(1, least(dias, 400))))
        and (p_sentido is null or (p_sentido = 'subio' and diferencia > 0) or (p_sentido = 'bajo' and diferencia < 0))
      order by fecha desc, abs(porcentaje) desc nulls last
      limit greatest(1, least(limite, 5000))
    ) p), '[]'::jsonb);
end $$;
revoke all on function public.precios_scraping(bigint, text, integer, text, integer) from public, anon;
grant execute on function public.precios_scraping(bigint, text, integer, text, integer) to authenticated;
