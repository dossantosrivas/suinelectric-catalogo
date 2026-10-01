-- =====================================================================
--  SUINELECTRIC · Página de enlaces (/links): quién entra, de dónde
--  llega y qué botones toca
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--  Requiere haber corrido antes 04_estadisticas.sql y 10_visitantes.sql.
--
--  La página de enlaces usa el mismo registro que la tienda (rastreo.js):
--    visita       → al entrar (lugar, equipo, de dónde vino), con origen 'links'
--    clic_enlace  → cada botón que tocan (texto = nombre del botón)
--  Como el código del navegador es el mismo, si desde los enlaces pasan
--  a la tienda se ve como una sola visita (y se cuenta "siguió a la tienda").
--  Solo los administradores pueden leerlo (panel → Enlaces).
-- =====================================================================

-- Tipo nuevo permitido: clic_enlace
alter table public.eventos drop constraint if exists eventos_tipo_check;
alter table public.eventos add constraint eventos_tipo_check check (tipo in
  ('busqueda','ver_producto','agregar_carrito','cotizar_whatsapp','pedido_whatsapp','visita','ver_tarjetas','clic_enlace'));

create index if not exists eventos_origen_idx on public.eventos (origen, creado desc);

-- ---------------------------------------------------------------------
--  Resumen de la página de enlaces para el panel
-- ---------------------------------------------------------------------
create or replace function public.resumen_links(dias integer default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
begin
  if not public.es_admin() then return null; end if;
  return (
    with ev as (      -- todo lo del período (sin los administradores)
      select * from eventos e
      where creado >= desde and visitante is not null and visita is not null
        and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
    ),
    vl as (           -- visitas que pasaron por la página de enlaces
      select distinct visita from ev where origen = 'links'
    ),
    cab as (          -- datos de entrada de cada visita
      select distinct on (visita) visita, pais, region, ciudad, proveedor, dispositivo, navegador, sistema, referencia, pagina
      from ev where tipo = 'visita' and visita in (select visita from vl) order by visita, creado
    ),
    vis as (
      select ev.visita, min(ev.visitante) visitante,
             min(ev.creado) filter (where origen = 'links') inicio, max(ev.creado) fin,
             count(*) filter (where tipo = 'clic_enlace') clics,
             bool_or(origen in ('tienda', 'pagina')) a_tienda,
             bool_or(tipo in ('cotizar_whatsapp', 'pedido_whatsapp') or (tipo = 'clic_enlace' and texto ilike 'whatsapp%')) whatsapp,
             max(cliente_email) cliente_email
      from ev where visita in (select visita from vl) group by ev.visita
    ),
    primeras as (
      select visitante, min(creado) primera from eventos
      where visitante in (select distinct visitante from vis) group by visitante
    ),
    v as (
      select vis.*, cab.pais, cab.region, cab.ciudad, cab.proveedor, cab.dispositivo, cab.navegador, cab.sistema, cab.referencia, cab.pagina,
             (p.primera >= vis.inicio - interval '1 minute') nuevo
      from vis left join cab using (visita) left join primeras p using (visitante)
    ),
    cl as (select * from ev where tipo = 'clic_enlace' and origen = 'links')
    select jsonb_build_object(
      'totales', (select jsonb_build_object(
          'visitas', count(*),
          'visitantes', count(distinct visitante),
          'nuevos', count(distinct visitante) filter (where nuevo),
          'clics', coalesce(sum(clics), 0),
          'con_clic', count(*) filter (where clics > 0),
          'a_tienda', count(*) filter (where a_tienda),
          'whatsapp', count(*) filter (where whatsapp))
        from v),
      'ahora', (select count(distinct visitante) from eventos
                where creado >= now() - interval '15 minutes' and origen = 'links' and visitante is not null),
      'botones', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select texto, count(*) clics, count(distinct visitante) personas, max(creado) ultima
          from cl where texto is not null group by texto order by count(*) desc, texto limit 40) x),
      'por_dia', (select coalesce(jsonb_agg(x order by x.dia), '[]'::jsonb) from (
          select d dia,
                 (select count(*) from v where (v.inicio at time zone 'America/Caracas')::date = d) visitas,
                 (select count(*) from cl where (cl.creado at time zone 'America/Caracas')::date = d) clics
          from (select distinct (inicio at time zone 'America/Caracas')::date d from v
                union select distinct (creado at time zone 'America/Caracas')::date from cl) dd) x),
      'por_hora', (select coalesce(jsonb_agg(x order by x.hora), '[]'::jsonb) from (
          select extract(hour from inicio at time zone 'America/Caracas')::int hora, count(*) visitas from v group by 1) x),
      'origenes', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select referencia, count(*) visitas, count(*) filter (where clics > 0) con_clic from v
          group by referencia order by count(*) desc limit 15) x),
      'paises', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select pais, count(*) visitas, count(distinct visitante) visitantes from v
          group by pais order by count(*) desc limit 15) x),
      'ciudades', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select pais, region, ciudad, count(*) visitas, count(distinct visitante) visitantes from v
          where ciudad is not null or region is not null
          group by pais, region, ciudad order by count(*) desc limit 20) x),
      'dispositivos', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select dispositivo, count(*) visitas from v group by dispositivo order by count(*) desc) x),
      'navegadores', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select navegador, count(*) visitas from v group by navegador order by count(*) desc limit 10) x),
      'visitas', (select coalesce(jsonb_agg(x order by x.inicio desc), '[]'::jsonb) from (
          select v.*,
                 (select string_agg(texto, ' · ' order by primero) from (
                    select texto, min(creado) primero from cl where cl.visita = v.visita and texto is not null group by texto) b) botones
          from v order by inicio desc limit 150) x)
    )
  );
end $$;
revoke all on function public.resumen_links(integer) from public, anon;
grant execute on function public.resumen_links(integer) to authenticated;
