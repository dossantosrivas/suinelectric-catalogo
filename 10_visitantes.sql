-- =====================================================================
--  SUINELECTRIC · Visitantes sin cuenta (cuántos entran, de dónde,
--  cuándo, qué buscan y qué tarjetas de producto ven)
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--  Requiere haber corrido antes 04_estadisticas.sql.
--
--  Cada navegador recibe un código aleatorio (visitante) que se guarda en
--  el propio navegador, y cada entrada a la tienda es una visita (se
--  cierra tras 30 minutos sin actividad). No se guardan nombres, correos
--  ni la dirección IP: el lugar (país, estado, ciudad y proveedor de
--  internet) lo calcula Cloudflare a partir de la conexión.
--
--  Tipos nuevos en la tabla eventos:
--    visita        → al entrar (con lugar, equipo, navegador y de dónde vino)
--    ver_tarjetas  → las tarjetas de producto que tuvo en pantalla
--                    (modelos[]), y en qué parte de la tienda (texto)
--  Solo los administradores pueden leerlo (panel → Visitantes).
-- =====================================================================

alter table public.eventos add column if not exists visitante   text check (char_length(visitante)   <= 40);
alter table public.eventos add column if not exists visita      text check (char_length(visita)      <= 40);
alter table public.eventos add column if not exists pais        text check (char_length(pais)        <= 60);
alter table public.eventos add column if not exists region      text check (char_length(region)      <= 80);
alter table public.eventos add column if not exists ciudad      text check (char_length(ciudad)      <= 80);
alter table public.eventos add column if not exists proveedor   text check (char_length(proveedor)   <= 100);
alter table public.eventos add column if not exists dispositivo text check (char_length(dispositivo) <= 20);
alter table public.eventos add column if not exists navegador   text check (char_length(navegador)   <= 40);
alter table public.eventos add column if not exists sistema     text check (char_length(sistema)     <= 40);
alter table public.eventos add column if not exists referencia  text check (char_length(referencia)  <= 120);
alter table public.eventos add column if not exists pagina      text check (char_length(pagina)      <= 200);
alter table public.eventos add column if not exists modelos     text[];

-- Tipos permitidos (se agregan visita y ver_tarjetas)
alter table public.eventos drop constraint if exists eventos_tipo_check;
alter table public.eventos add constraint eventos_tipo_check check (tipo in
  ('busqueda','ver_producto','agregar_carrito','cotizar_whatsapp','pedido_whatsapp','visita','ver_tarjetas'));

create index if not exists eventos_visitante_idx on public.eventos (visitante, creado desc) where visitante is not null;
create index if not exists eventos_visita_idx    on public.eventos (visita) where visita is not null;

-- Igual que antes (correo y hora los pone el servidor) + limpieza de lo nuevo.
create or replace function public.eventos_completar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.cliente_email := nullif(public.mi_email(), '');
  new.creado := now();
  -- Las búsquedas se guardan en minúsculas (para agruparlas); el resto tal cual.
  new.texto := nullif(case when new.tipo = 'busqueda' then lower(trim(new.texto)) else trim(new.texto) end, '');
  if new.modelos is not null then
    new.modelos := (select array_agg(left(m, 80)) from (select distinct m from unnest(new.modelos[1:100]) m where m is not null and m <> '') x);
  end if;
  if new.tipo <> 'visita' then     -- el lugar y el equipo solo van en el evento "visita"
    new.pais := null; new.region := null; new.ciudad := null; new.proveedor := null;
    new.dispositivo := null; new.navegador := null; new.sistema := null; new.referencia := null;
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------
--  Resumen de visitantes sin cuenta para el panel
-- ---------------------------------------------------------------------
create or replace function public.resumen_visitantes(dias integer default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
begin
  if not public.es_admin() then return null; end if;
  return (
    with ev as (      -- lo que hicieron sin iniciar sesión
      select * from eventos
      where creado >= desde and cliente_email is null and visitante is not null and visita is not null
    ),
    cab as (          -- datos de entrada de cada visita
      select distinct on (visita) visita, pais, region, ciudad, proveedor, dispositivo, navegador, sistema, referencia, pagina
      from ev where tipo = 'visita' order by visita, creado
    ),
    vis as (          -- una fila por visita
      select ev.visita, min(ev.visitante) visitante, min(ev.creado) inicio, max(ev.creado) fin,
             count(*) filter (where tipo = 'busqueda')        busquedas,
             count(*) filter (where tipo = 'ver_producto')    fichas,
             coalesce(sum(cardinality(modelos)) filter (where tipo = 'ver_tarjetas'), 0) tarjetas,
             count(*) filter (where tipo = 'agregar_carrito') carrito,
             count(*) filter (where tipo in ('cotizar_whatsapp','pedido_whatsapp')) whatsapp
      from ev group by ev.visita
    ),
    primeras as (     -- primera vez que se vio a cada visitante (en todo el historial)
      select visitante, min(creado) primera from eventos
      where visitante in (select distinct visitante from vis) group by visitante
    ),
    v as (
      select vis.*, cab.pais, cab.region, cab.ciudad, cab.proveedor, cab.dispositivo, cab.navegador, cab.sistema, cab.referencia, cab.pagina,
             (p.primera >= vis.inicio - interval '1 minute') nuevo
      from vis left join cab using (visita) left join primeras p using (visitante)
    ),
    tarj as (
      select m modelo, count(*) veces, count(distinct visitante) personas
      from ev, unnest(modelos) m where tipo = 'ver_tarjetas' group by m
    ),
    fich as (
      select modelo, count(*) abiertas from ev where tipo = 'ver_producto' and modelo is not null group by modelo
    )
    select jsonb_build_object(
      'totales', (select jsonb_build_object(
          'visitas', count(*),
          'visitantes', count(distinct visitante),
          'nuevos', count(distinct visitante) filter (where nuevo),
          'busquedas', coalesce(sum(busquedas), 0),
          'fichas', coalesce(sum(fichas), 0),
          'tarjetas', coalesce(sum(tarjetas), 0),
          'carrito', coalesce(sum(carrito), 0),
          'whatsapp', coalesce(sum(whatsapp), 0),
          'con_interes', count(*) filter (where carrito > 0 or whatsapp > 0),
          'duracion_media', round(coalesce(avg(extract(epoch from fin - inicio)) filter (where fin > inicio), 0)))
        from v),
      'ahora', (select count(distinct visitante) from eventos
                where creado >= now() - interval '15 minutes' and cliente_email is null and visitante is not null),
      'por_dia', (select coalesce(jsonb_agg(x order by x.dia), '[]'::jsonb) from (
          select (inicio at time zone 'America/Caracas')::date dia, count(*) visitas, count(distinct visitante) visitantes
          from v group by 1) x),
      'por_hora', (select coalesce(jsonb_agg(x order by x.hora), '[]'::jsonb) from (
          select extract(hour from inicio at time zone 'America/Caracas')::int hora, count(*) visitas from v group by 1) x),
      'por_semana', (select coalesce(jsonb_agg(x order by x.dia), '[]'::jsonb) from (
          select extract(isodow from inicio at time zone 'America/Caracas')::int dia, count(*) visitas from v group by 1) x),
      'paises', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select pais, count(*) visitas, count(distinct visitante) visitantes from v
          group by pais order by count(*) desc limit 20) x),
      'ciudades', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select pais, region, ciudad, count(*) visitas, count(distinct visitante) visitantes from v
          where ciudad is not null or region is not null
          group by pais, region, ciudad order by count(*) desc limit 25) x),
      'proveedores', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select proveedor, count(*) visitas from v where proveedor is not null
          group by proveedor order by count(*) desc limit 15) x),
      'dispositivos', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select dispositivo, count(*) visitas from v group by dispositivo order by count(*) desc) x),
      'sistemas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select sistema, count(*) visitas from v group by sistema order by count(*) desc limit 10) x),
      'navegadores', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select navegador, count(*) visitas from v group by navegador order by count(*) desc limit 10) x),
      'origenes', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select referencia, count(*) visitas from v group by referencia order by count(*) desc limit 15) x),
      'entradas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select pagina, count(*) visitas from v where pagina is not null group by pagina order by count(*) desc limit 15) x),
      'buscado', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select texto, count(*) veces, count(distinct visitante) personas, min(resultados) resultados from ev
          where tipo = 'busqueda' and texto is not null group by texto order by count(*) desc, texto limit 30) x),
      'tarjetas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select tarj.modelo, tarj.veces, tarj.personas, coalesce(fich.abiertas, 0) abiertas
          from tarj left join fich using (modelo) order by tarj.veces desc limit 40) x),
      'visitas', (select coalesce(jsonb_agg(x order by x.inicio desc), '[]'::jsonb) from (
          select v.*, (select count(*) from vis v2 where v2.visitante = v.visitante) visitas_periodo,
                 (select string_agg(texto, ' · ') from (select distinct texto from ev e2
                    where e2.visita = v.visita and e2.tipo = 'busqueda' and e2.texto is not null limit 4) b) buscado
          from v order by inicio desc limit 150) x)
    )
  );
end $$;
revoke all on function public.resumen_visitantes(integer) from public, anon;
grant execute on function public.resumen_visitantes(integer) to authenticated;

-- ---------------------------------------------------------------------
--  Todo lo que hizo un visitante (por su código de navegador)
-- ---------------------------------------------------------------------
create or replace function public.actividad_visitante(p_visitante text, dias integer default 90) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
begin
  if not public.es_admin() then return null; end if;
  return (
    with ev as (select * from eventos where visitante = p_visitante and creado >= desde)
    select jsonb_build_object(
      'primera', (select min(creado) from eventos where visitante = p_visitante),
      'ultima',  (select max(creado) from eventos where visitante = p_visitante),
      'correos', (select coalesce(jsonb_agg(distinct cliente_email), '[]'::jsonb) from eventos
                  where visitante = p_visitante and cliente_email is not null),
      'totales', (select coalesce(jsonb_object_agg(tipo, n), '{}'::jsonb) from (select tipo, count(*) n from ev group by tipo) t),
      'n_tarjetas', (select coalesce(sum(cardinality(modelos)), 0) from ev where tipo = 'ver_tarjetas'),
      'visitas', (select coalesce(jsonb_agg(x order by x.inicio desc), '[]'::jsonb) from (
          select ev.visita, min(creado) inicio, max(creado) fin, count(*) eventos,
                 (array_agg(pais order by creado)        filter (where tipo = 'visita'))[1] pais,
                 (array_agg(region order by creado)      filter (where tipo = 'visita'))[1] region,
                 (array_agg(ciudad order by creado)      filter (where tipo = 'visita'))[1] ciudad,
                 (array_agg(proveedor order by creado)   filter (where tipo = 'visita'))[1] proveedor,
                 (array_agg(dispositivo order by creado) filter (where tipo = 'visita'))[1] dispositivo,
                 (array_agg(navegador order by creado)   filter (where tipo = 'visita'))[1] navegador,
                 (array_agg(sistema order by creado)     filter (where tipo = 'visita'))[1] sistema,
                 (array_agg(referencia order by creado)  filter (where tipo = 'visita'))[1] referencia,
                 (array_agg(pagina order by creado)      filter (where tipo = 'visita'))[1] pagina
          from ev where ev.visita is not null group by ev.visita order by min(creado) desc limit 60) x),
      'buscado', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select texto, count(*) veces, min(resultados) resultados, max(creado) ultima from ev
          where tipo = 'busqueda' and texto is not null group by texto order by count(*) desc, max(creado) desc limit 40) x),
      'vistos', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select modelo, count(*) veces, max(creado) ultima from ev
          where tipo = 'ver_producto' and modelo is not null group by modelo order by count(*) desc, max(creado) desc limit 40) x),
      'tarjetas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select m modelo, count(*) veces, max(creado) ultima from ev, unnest(modelos) m
          where tipo = 'ver_tarjetas' group by m order by count(*) desc, max(creado) desc limit 60) x),
      'recientes', (select coalesce(jsonb_agg(x order by x.creado desc), '[]'::jsonb) from (
          select tipo, texto, modelo, modelos, resultados, cantidad, origen, pagina, visita, cliente_email, creado from ev
          order by creado desc limit 300) x)
    )
  );
end $$;
revoke all on function public.actividad_visitante(text, integer) from public, anon;
grant execute on function public.actividad_visitante(text, integer) to authenticated;
