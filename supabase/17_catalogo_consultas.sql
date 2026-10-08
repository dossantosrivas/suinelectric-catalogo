-- =====================================================================
--  17 · CONSULTAS DEL CATÁLOGO ÚNICO
--  a) filtrar productos por varios atributos a la vez (+ conteos por filtro)
--  b) alertas del panel: stock bajo y productos sin actualizar
-- =====================================================================

-- Productos de una categoría (y sus hijas) que cumplen TODOS los filtros.
--   p_filtros: {"potencia_kw":[5.5,7.5], "tension_entrada":["440 V 3F"]}
--              dentro de una clave = O · entre claves = Y
--   p_cubre:   {"ajuste_a": 8.5}  → productos cuyo rango ajuste_a_min..ajuste_a_max incluye 8.5
create or replace function catalogo.filtrar(
  p_categoria   text,                        -- ruta: 'control-de-motores/contactores'
  p_filtros     jsonb   default '{}',
  p_cubre       jsonb   default '{}',
  p_marcas      text[]  default null,        -- {'siemens','hyundai'}
  p_disponibles boolean default false,
  p_orden       text    default 'disponibilidad',
  p_limite      integer default 48,
  p_desde       integer default 0
) returns table (sku_id bigint, codigo text, nombre text, marca text, specs jsonb,
                 precio numeric, disponibilidad text, total bigint)
language sql stable security invoker set search_path = '' as $$
  with base as (
    select t.*
    from catalogo.v_tienda t
    join catalogo.marcas m on m.nombre = t.marca
    where (t.categoria = p_categoria or t.categoria like p_categoria || '/%')
      and (p_marcas is null or m.slug = any (p_marcas))
      and (not p_disponibles or t.disponibilidad <> 'a_pedido')
      -- cada filtro elegido: el valor del producto está entre los marcados
      and not exists (
        select 1 from jsonb_each(coalesce(p_filtros, '{}')) f(clave, valores)
        where jsonb_array_length(f.valores) > 0
          and not (f.valores @> jsonb_build_array(t.specs -> f.clave)))
      -- rangos: el valor buscado cae dentro del rango del producto
      and not exists (
        select 1 from jsonb_each_text(coalesce(p_cubre, '{}')) r(clave, valor)
        where t.specs ->> (r.clave || '_min') is null    -- sin rango: no sirve para "mi motor consume X A"
           or not (r.valor::numeric between (t.specs ->> (r.clave || '_min'))::numeric
                                        and (t.specs ->> (r.clave || '_max'))::numeric))
  )
  select b.sku_id, b.codigo, b.nombre, b.marca, b.specs, b.precio, b.disponibilidad,
         count(*) over () as total
  from base b
  order by
    case when p_orden = 'disponibilidad' then array_position(array['propio','distribuidor','a_pedido'], b.disponibilidad) end,
    case when p_orden = 'precio_asc'  then b.precio end asc nulls last,
    case when p_orden = 'precio_desc' then b.precio end desc nulls last,
    b.codigo
  limit greatest(1, least(p_limite, 200)) offset greatest(0, p_desde)
$$;

-- Conteos para cada filtro de la categoría. Cada filtro se cuenta aplicando
-- todos los DEMÁS filtros elegidos (no el suyo), así el cliente ve cuántos
-- productos tendría al marcar otra opción del mismo filtro.
create or replace function catalogo.facetas(
  p_categoria text,
  p_filtros   jsonb default '{}'
) returns jsonb
language sql stable security invoker set search_path = '' as $$
  with cat as (
    select id, ruta from catalogo.categorias where ruta = p_categoria
  ),
  attrs as (            -- filtros definidos para la categoría (o heredados de su padre)
    select distinct on (a.clave) a.clave, ac.orden
    from catalogo.atributos_categoria ac
    join catalogo.atributos a  on a.id = ac.atributo_id
    join catalogo.categorias c on c.id = ac.categoria_id
    join cat on cat.ruta = c.ruta or cat.ruta like c.ruta || '/%'
    where ac.es_filtro and a.tipo <> 'rango'          -- los rangos se filtran con p_cubre ("mi motor consume 8,5 A")
    order by a.clave, c.nivel desc
  ),
  base as (
    select t.specs from catalogo.v_tienda t
    where t.categoria = p_categoria or t.categoria like p_categoria || '/%'
  ),
  conteos as (
    select a.clave, a.orden, b.specs -> a.clave as valor, count(*) as n
    from attrs a
    join base b on b.specs ? a.clave
    where not exists (
      select 1 from jsonb_each(coalesce(p_filtros, '{}') - a.clave) f(clave, valores)
      where jsonb_array_length(f.valores) > 0
        and not (f.valores @> jsonb_build_array(b.specs -> f.clave)))
    group by a.clave, a.orden, b.specs -> a.clave
  )
  select coalesce(jsonb_object_agg(clave, opciones), '{}')
  from (
    select clave, min(orden) orden,
           jsonb_agg(jsonb_build_object('valor', valor, 'n', n) order by valor) as opciones
    from conteos group by clave
  ) x
$$;

-- b) Alertas para el panel: una fila por problema, lo más urgente primero.
create or replace function catalogo.alertas(p_dias_sin_ver integer default 3)
returns table (prioridad int, tipo text, codigo text, nombre text, detalle text, desde timestamptz)
language sql stable security invoker set search_path = '' as $$
  with propio as (
    select k.id, k.codigo, s.nombre, k.stock_minimo, coalesce(sum(e.cantidad), 0) as cant
    from catalogo.skus k
    join catalogo.series s on s.id = k.serie_id
    left join catalogo.existencias e on e.sku_id = k.id
    where k.activo and k.stock_minimo > 0
    group by k.id, s.nombre
  )
  -- 1. Tu inventario bajo el mínimo
  select 1, 'stock_bajo', p.codigo, p.nombre,
         'Quedan ' || p.cant || ' (mínimo ' || p.stock_minimo || ')', null::timestamptz
  from propio p
  where p.cant <= p.stock_minimo

  union all
  -- 2. El proveedor dejó de traerlo en el scraping o la lista (¿descontinuado?)
  select 2, 'proveedor_no_lo_trae', k.codigo, s.nombre,
         pr.nombre || ': no aparece hace ' || extract(day from now() - o.visto)::int || ' días', o.visto
  from catalogo.ofertas_proveedor o
  join catalogo.proveedores pr on pr.id = o.proveedor_id and pr.origen = 'scraping'
  join catalogo.skus k   on k.id = o.sku_id and k.activo
  join catalogo.series s on s.id = k.serie_id and s.estado = 'publicado'
  where o.visto < now() - make_interval(days => p_dias_sin_ver)

  union all
  -- 3. Precio de lista de proveedor más viejo que su vigencia
  select 3, 'precio_viejo', k.codigo, s.nombre,
         pr.nombre || ': precio de hace ' || extract(day from now() - o.visto)::int || ' días', o.visto
  from catalogo.ofertas_proveedor o
  join catalogo.proveedores pr on pr.id = o.proveedor_id and pr.origen <> 'scraping'
  join catalogo.skus k   on k.id = o.sku_id and k.activo
  join catalogo.series s on s.id = k.serie_id and s.estado = 'publicado'
  where o.visto < now() - make_interval(days => pr.dias_vigencia)

  union all
  -- 4. Publicados sin los atributos obligatorios de su categoría (no salen en los filtros)
  select 4, 'faltan_atributos', k.codigo, s.nombre,
         'Falta: ' || string_agg(a.nombre, ', ' order by ac.orden), s.actualizado
  from catalogo.skus k
  join catalogo.series s on s.id = k.serie_id and s.estado = 'publicado'
  join catalogo.atributos_categoria ac on ac.categoria_id = s.categoria_id and ac.obligatorio
  join catalogo.atributos a on a.id = ac.atributo_id
  where k.activo
    and not (k.specs ? (case when a.tipo = 'rango' then a.clave || '_min' else a.clave end))   -- un rango se guarda como _min / _max
  group by k.codigo, s.nombre, s.actualizado

  union all
  -- 5. Publicados sin foto
  select 5, 'sin_foto', s.codigo, s.nombre, 'La serie no tiene fotos', s.actualizado
  from catalogo.series s
  where s.estado = 'publicado' and cardinality(s.imagenes) = 0

  order by 1, 6 nulls first, 3
$$;

grant execute on function catalogo.filtrar(text, jsonb, jsonb, text[], boolean, text, integer, integer) to authenticated, service_role;
grant execute on function catalogo.facetas(text, jsonb) to authenticated, service_role;
grant execute on function catalogo.alertas(integer) to authenticated, service_role;
