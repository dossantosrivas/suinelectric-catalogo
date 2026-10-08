-- =====================================================================
--  18 · CATÁLOGO ÚNICO: carga desde archivo y exportación para la tienda
--  Va después de 16 y 17. Probado primero en el proyecto beta.
--
--  · ofertas_proveedor.disponible: listas de precios que dicen "disponible"
--    sin cantidad (Schneider, Hyundai, INVT…).
--  · v_tienda con los 4 estados que ya muestra la tienda:
--      propio (tu inventario) · distribuidor · a_pedido (tuyo, sin existencia) · agotado
--    y precio_propio = true cuando el precio es tuyo (no lleva el descuento general).
--  · alertas: los atributos obligatorios se toman de la categoría más cercana
--    (Contactores › Auxiliares no exige corriente AC3).
--  · cargar_catalogo(json): carga lo que arma scripts/migrar-catalogo-beta.js.
--  · exportar_tienda(): todo lo que necesita la tienda en un solo JSON.
-- =====================================================================

alter table catalogo.ofertas_proveedor add column if not exists disponible boolean not null default true;

-- Las columnas nuevas van al final: así la vista se reemplaza sin borrarla.
create or replace view catalogo.v_tienda with (security_invoker = on) as
select k.id            as sku_id,
       k.codigo,
       s.id            as serie_id,
       s.codigo        as serie,
       s.nombre,
       m.nombre        as marca,
       c.ruta          as categoria,
       k.specs,
       coalesce(k.precio_lista, o.precio_publico) as precio,
       case when coalesce(ex.propio, 0) > 0 then 'propio'
            when o.hay then 'distribuidor'
            when o.n = 0 then 'a_pedido'
            else 'agotado' end                     as disponibilidad,
       s.imagenes[1]   as imagen,
       k.precio_lista is not null                 as precio_propio,
       ex.propio                                   as existencia_propia
from catalogo.skus k
join catalogo.series s      on s.id = k.serie_id and s.estado = 'publicado'
join catalogo.marcas m      on m.id = s.marca_id
join catalogo.categorias c  on c.id = s.categoria_id
left join lateral (select sum(cantidad) propio from catalogo.existencias e where e.sku_id = k.id) ex on true
left join lateral (
  select count(*) n,
         coalesce(bool_or(coalesce(op.existencia, 0) > 0 or (op.existencia is null and op.disponible)), false) hay,
         (array_agg(op.precio_publico order by op.precio_publico is null, op.visto desc))[1]::numeric(12,2) precio_publico
  from catalogo.ofertas_proveedor op where op.sku_id = k.id) o on true
where k.activo;

-- (la vista se volvió a crear: filtrar y facetas de 17 la usan y siguen igual)
create or replace function catalogo.filtrar(
  p_categoria text, p_filtros jsonb default '{}', p_cubre jsonb default '{}', p_marcas text[] default null,
  p_disponibles boolean default false, p_orden text default 'disponibilidad', p_limite integer default 48, p_desde integer default 0
) returns table (sku_id bigint, codigo text, nombre text, marca text, specs jsonb, precio numeric, disponibilidad text, total bigint)
language sql stable security invoker set search_path = '' as $$
  with base as (
    select t.* from catalogo.v_tienda t join catalogo.marcas m on m.nombre = t.marca
    where (t.categoria = p_categoria or t.categoria like p_categoria || '/%')
      and (p_marcas is null or m.slug = any (p_marcas))
      and (not p_disponibles or t.disponibilidad in ('propio', 'distribuidor'))
      and not exists (select 1 from jsonb_each(coalesce(p_filtros, '{}')) f(clave, valores)
                      where jsonb_array_length(f.valores) > 0 and not (f.valores @> jsonb_build_array(t.specs -> f.clave)))
      and not exists (select 1 from jsonb_each_text(coalesce(p_cubre, '{}')) r(clave, valor)
                      where not (r.valor::numeric between (t.specs ->> (r.clave || '_min'))::numeric and (t.specs ->> (r.clave || '_max'))::numeric))
  )
  select b.sku_id, b.codigo, b.nombre, b.marca, b.specs, b.precio, b.disponibilidad, count(*) over () as total
  from base b
  order by case when p_orden = 'disponibilidad' then array_position(array['propio','distribuidor','a_pedido','agotado'], b.disponibilidad) end,
           case when p_orden = 'precio_asc'  then b.precio end asc nulls last,
           case when p_orden = 'precio_desc' then b.precio end desc nulls last,
           b.codigo
  limit greatest(1, least(p_limite, 200)) offset greatest(0, p_desde)
$$;

create or replace function catalogo.facetas(p_categoria text, p_filtros jsonb default '{}') returns jsonb
language sql stable security invoker set search_path = '' as $$
  with cat as (select id, ruta from catalogo.categorias where ruta = p_categoria),
  attrs as (
    select distinct on (a.clave) a.clave, ac.orden, ac.es_filtro, a.tipo
    from catalogo.atributos_categoria ac
    join catalogo.atributos a  on a.id = ac.atributo_id
    join catalogo.categorias c on c.id = ac.categoria_id
    join cat on cat.ruta = c.ruta or cat.ruta like c.ruta || '/%'
    order by a.clave, c.nivel desc),
  base as (select t.specs from catalogo.v_tienda t where t.categoria = p_categoria or t.categoria like p_categoria || '/%'),
  conteos as (
    select a.clave, a.orden, b.specs -> a.clave as valor, count(*) as n
    from attrs a join base b on b.specs ? a.clave
    where a.es_filtro and a.tipo <> 'rango'
      and not exists (select 1 from jsonb_each(coalesce(p_filtros, '{}') - a.clave) f(clave, valores)
                      where jsonb_array_length(f.valores) > 0 and not (f.valores @> jsonb_build_array(b.specs -> f.clave)))
    group by a.clave, a.orden, b.specs -> a.clave)
  select coalesce(jsonb_object_agg(clave, opciones), '{}')
  from (select clave, min(orden) orden, jsonb_agg(jsonb_build_object('valor', valor, 'n', n) order by valor) as opciones
        from conteos group by clave) x
$$;

-- Alertas: obligatorios de la categoría más cercana con definición propia
create or replace function catalogo.alertas(p_dias_sin_ver integer default 3)
returns table (prioridad int, tipo text, codigo text, nombre text, detalle text, desde timestamptz)
language sql stable security invoker set search_path = '' as $$
  with propio as (
    select k.id, k.codigo, s.nombre, k.stock_minimo, coalesce(sum(e.cantidad), 0) as cant
    from catalogo.skus k join catalogo.series s on s.id = k.serie_id
    left join catalogo.existencias e on e.sku_id = k.id
    where k.activo and k.stock_minimo > 0
    group by k.id, s.nombre
  ),
  -- para cada categoría, la categoría (ella misma o un ancestro) cuyas definiciones mandan
  manda as (
    select distinct on (c.id) c.id as categoria_id, d.id as define_id
    from catalogo.categorias c
    join catalogo.categorias d on c.ruta = d.ruta or c.ruta like d.ruta || '/%'
    where exists (select 1 from catalogo.atributos_categoria ac where ac.categoria_id = d.id)
      and c.ruta not like '%/accesorios'
    order by c.id, d.nivel desc
  )
  select 1, 'stock_bajo', p.codigo, p.nombre, 'Quedan ' || p.cant || ' (mínimo ' || p.stock_minimo || ')', null::timestamptz
  from propio p where p.cant <= p.stock_minimo
  union all
  select 2, 'proveedor_no_lo_trae', k.codigo, s.nombre,
         pr.nombre || ': no aparece hace ' || extract(day from now() - o.visto)::int || ' días', o.visto
  from catalogo.ofertas_proveedor o
  join catalogo.proveedores pr on pr.id = o.proveedor_id and pr.origen = 'scraping'
  join catalogo.skus k   on k.id = o.sku_id and k.activo
  join catalogo.series s on s.id = k.serie_id and s.estado = 'publicado'
  where o.visto < now() - make_interval(days => p_dias_sin_ver)
  union all
  select 3, 'precio_viejo', k.codigo, s.nombre,
         pr.nombre || ': precio de hace ' || extract(day from now() - o.visto)::int || ' días', o.visto
  from catalogo.ofertas_proveedor o
  join catalogo.proveedores pr on pr.id = o.proveedor_id and pr.origen <> 'scraping'
  join catalogo.skus k   on k.id = o.sku_id and k.activo
  join catalogo.series s on s.id = k.serie_id and s.estado = 'publicado'
  where o.visto < now() - make_interval(days => pr.dias_vigencia)
  union all
  select 4, 'faltan_atributos', k.codigo, s.nombre, 'Falta: ' || string_agg(a.nombre, ', ' order by ac.orden), s.actualizado
  from catalogo.skus k
  join catalogo.series s on s.id = k.serie_id and s.estado = 'publicado'
  join manda md on md.categoria_id = s.categoria_id
  join catalogo.atributos_categoria ac on ac.categoria_id = md.define_id and ac.obligatorio
  join catalogo.atributos a on a.id = ac.atributo_id
  where k.activo and not (k.specs ? (case when a.tipo = 'rango' then a.clave || '_min' else a.clave end))
  group by k.codigo, s.nombre, s.actualizado
  union all
  select 5, 'sin_foto', s.codigo, s.nombre, 'La serie no tiene fotos', s.actualizado
  from catalogo.series s where s.estado = 'publicado' and cardinality(s.imagenes) = 0
  order by 1, 6 nulls first, 3
$$;

-- ---------- Carga desde el JSON de scripts/migrar-catalogo-beta.js ----------
-- Idempotente: se puede correr de nuevo y actualiza lo que ya existe.
create or replace function catalogo.cargar_catalogo(d jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare r record; n_series int; n_skus int; n_ofertas int;
begin
  for r in select * from jsonb_to_recordset(d -> 'categorias') as x(nombre text, padre text, nivel int, ruta text, orden int) order by nivel, ruta loop
    insert into catalogo.categorias (padre_id, nombre, slug, orden)
    values ((select id from catalogo.categorias where ruta = r.padre), r.nombre, split_part(r.ruta, '/', r.nivel), coalesce(r.orden, 0))
    on conflict (ruta) do update set nombre = excluded.nombre, orden = excluded.orden;
  end loop;

  insert into catalogo.atributos (clave, nombre, tipo, unidad)
  select x.clave, x.nombre, x.tipo, x.unidad from jsonb_to_recordset(d -> 'atributos') as x(clave text, nombre text, tipo text, unidad text)
  on conflict (clave) do update set nombre = excluded.nombre, tipo = excluded.tipo, unidad = excluded.unidad;

  insert into catalogo.atributos_categoria (categoria_id, atributo_id, orden, obligatorio, define_variante)
  select c.id, a.id, x.orden, x.obligatorio, x.define_variante
  from jsonb_to_recordset(d -> 'filtros') as x(categoria text, clave text, orden int, obligatorio boolean, define_variante boolean)
  join catalogo.categorias c on c.ruta = x.categoria
  join catalogo.atributos a  on a.clave = x.clave
  on conflict (categoria_id, atributo_id) do update set orden = excluded.orden, obligatorio = excluded.obligatorio, define_variante = excluded.define_variante;

  insert into catalogo.marcas (nombre, slug)
  select distinct s ->> 'marca', lower(regexp_replace(s ->> 'marca', '[^A-Za-z0-9]+', '-', 'g'))
  from jsonb_array_elements(d -> 'series') s
  on conflict (nombre) do nothing;

  insert into catalogo.proveedores (nombre, origen)
  select distinct o ->> 'proveedor', case when o ->> 'proveedor' = 'Grupo Eléctricos' then 'scraping' else 'lista' end
  from jsonb_array_elements(d -> 'series') s, jsonb_array_elements(s -> 'skus') k, jsonb_array_elements(k -> 'ofertas') o
  on conflict (nombre) do nothing;

  insert into catalogo.series (marca_id, categoria_id, codigo, nombre, descripcion, imagenes, estado)
  select m.id, c.id, s ->> 'codigo', s ->> 'nombre', nullif(s ->> 'descripcion', ''),
         coalesce(array(select jsonb_array_elements_text(s -> 'imagenes')), '{}'), 'publicado'
  from jsonb_array_elements(d -> 'series') s
  join catalogo.marcas m on m.nombre = s ->> 'marca'
  join catalogo.categorias c on c.ruta = s ->> 'categoria'
  on conflict (marca_id, codigo) do update set categoria_id = excluded.categoria_id, nombre = excluded.nombre,
     descripcion = excluded.descripcion, imagenes = excluded.imagenes;
  get diagnostics n_series = row_count;

  insert into catalogo.skus (serie_id, codigo, specs, precio_lista)
  select se.id, k ->> 'codigo', coalesce(k -> 'specs', '{}'), (k ->> 'precio_lista')::numeric
  from jsonb_array_elements(d -> 'series') s
  join catalogo.marcas m on m.nombre = s ->> 'marca'
  join catalogo.series se on se.marca_id = m.id and se.codigo = s ->> 'codigo'
  cross join jsonb_array_elements(s -> 'skus') k
  on conflict (codigo) do update set serie_id = excluded.serie_id, specs = excluded.specs, precio_lista = excluded.precio_lista;
  get diagnostics n_skus = row_count;

  insert into catalogo.ofertas_proveedor (sku_id, proveedor_id, precio_publico, disponible, visto)
  select distinct on (sk.id, p.id) sk.id, p.id, (o ->> 'precio_publico')::numeric, coalesce((o ->> 'disponible')::boolean, true), now()
  from jsonb_array_elements(d -> 'series') s, jsonb_array_elements(s -> 'skus') k, jsonb_array_elements(k -> 'ofertas') o
  join catalogo.skus sk on sk.codigo = k ->> 'codigo'
  join catalogo.proveedores p on p.nombre = o ->> 'proveedor'
  on conflict (sku_id, proveedor_id) do update set precio_publico = excluded.precio_publico, disponible = excluded.disponible, visto = excluded.visto;
  get diagnostics n_ofertas = row_count;

  return jsonb_build_object('series', n_series, 'skus', n_skus, 'ofertas', n_ofertas);
end $$;
revoke all on function catalogo.cargar_catalogo(jsonb) from public, anon, authenticated;

-- ---------- Todo lo que necesita la tienda, en un JSON ----------
create or replace function catalogo.exportar_tienda() returns jsonb
language sql stable security invoker set search_path = '' as $$
  with rutas as (
    select c.id, c.ruta, c.nivel, c.orden,
           array_remove(array[c3.nombre, c2.nombre, c.nombre], null) as nombres
    from catalogo.categorias c
    left join catalogo.categorias c2 on c2.id = c.padre_id
    left join catalogo.categorias c3 on c3.id = c2.padre_id
  )
  select jsonb_build_object(
    'generado', now(),
    'categorias', (select jsonb_agg(jsonb_build_object('ruta', r.ruta, 'nombres', r.nombres, 'nivel', r.nivel, 'orden', r.orden) order by r.ruta) from rutas r),
    'filtros', (select jsonb_object_agg(ruta, defs) from (
        select c.ruta, jsonb_agg(jsonb_build_object('clave', a.clave, 'nombre', a.nombre, 'unidad', a.unidad, 'tipo', a.tipo,
                                                   'variante', ac.define_variante) order by ac.orden) defs
        from catalogo.atributos_categoria ac join catalogo.atributos a on a.id = ac.atributo_id
        join catalogo.categorias c on c.id = ac.categoria_id where ac.es_filtro group by c.ruta) f),
    'productos', (select jsonb_agg(jsonb_build_object(
        'codigo', t.codigo, 'serie', t.serie, 'nombre', t.nombre, 'marca', t.marca, 'ruta', r.nombres, 'specs', t.specs,
        'precio', t.precio, 'propio', t.precio_propio, 'disp', t.disponibilidad,
        'stock', case when t.existencia_propia > 10 then '+10' when t.existencia_propia > 0 then 'pocas' end,
        'desc', s.descripcion, 'imgs', s.imagenes) order by r.ruta, t.serie, t.codigo)
      from catalogo.v_tienda t join catalogo.series s on s.id = t.serie_id join catalogo.categorias c on c.id = s.categoria_id join rutas r on r.id = c.id)
  )
$$;
