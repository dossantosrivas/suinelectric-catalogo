-- =====================================================================
--  SUINELECTRIC · Actividad por cliente (qué busca, mira y cotiza cada uno)
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--  Requiere haber corrido antes 04_estadisticas.sql.
--
--  La tienda ya anota el correo del cliente en cada búsqueda, ficha vista,
--  producto agregado y clic en WhatsApp cuando entra con su cuenta
--  (tabla eventos). Esto solo agrega dos resúmenes para el panel:
--    · clientes_activos(dias)          → ranking de clientes por actividad
--    · actividad_cliente(email, dias)  → el detalle de un cliente
--  Los visitantes sin cuenta siguen contando en las estadísticas generales,
--  pero no se pueden separar por persona.
-- =====================================================================

create index if not exists eventos_cliente_idx on public.eventos (cliente_email, creado desc)
  where cliente_email is not null;

-- Ranking de clientes (sin administradores)
create or replace function public.clientes_activos(dias integer default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
begin
  if not public.es_admin() then return null; end if;
  return jsonb_build_object(
    'con_cuenta', (select count(*) from eventos e where creado >= desde and cliente_email is not null
                     and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)),
    'sin_cuenta', (select count(*) from eventos where creado >= desde and cliente_email is null),
    'clientes', (select coalesce(jsonb_agg(x order by x.total desc, x.ultima desc), '[]'::jsonb) from (
        select cliente_email email,
               count(*) total,
               count(*) filter (where tipo = 'busqueda')         busquedas,
               count(*) filter (where tipo = 'ver_producto')     vistas,
               count(*) filter (where tipo = 'agregar_carrito')  carrito,
               count(*) filter (where tipo = 'cotizar_whatsapp') whatsapp,
               count(distinct date_trunc('minute', creado)) filter (where tipo = 'pedido_whatsapp') pedidos,
               count(distinct (creado at time zone 'America/Caracas')::date) dias_activos,
               max(creado) ultima
        from eventos e
        where creado >= desde and cliente_email is not null
          and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by cliente_email
        order by count(*) desc limit 100) x)
  );
end $$;
revoke all on function public.clientes_activos(integer) from public, anon;
grant execute on function public.clientes_activos(integer) to authenticated;

-- Detalle de un cliente
create or replace function public.actividad_cliente(p_email text, dias integer default 90) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
  em text := lower(trim(p_email));
begin
  if not public.es_admin() then return null; end if;
  return jsonb_build_object(
    'totales', (select coalesce(jsonb_object_agg(tipo, n), '{}'::jsonb) from (
        select tipo, count(*) n from eventos where cliente_email = em and creado >= desde group by tipo) t),
    'envios', (select count(distinct date_trunc('minute', creado)) from eventos
               where cliente_email = em and creado >= desde and tipo = 'pedido_whatsapp'),
    'dias_activos', (select count(distinct (creado at time zone 'America/Caracas')::date) from eventos
                     where cliente_email = em and creado >= desde),
    'primera', (select min(creado) from eventos where cliente_email = em),
    'ultima',  (select max(creado) from eventos where cliente_email = em),
    'buscado', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select texto, count(*) veces, min(resultados) resultados, max(creado) ultima from eventos
        where cliente_email = em and creado >= desde and tipo = 'busqueda' and texto is not null
        group by texto order by count(*) desc, max(creado) desc limit 40) x),
    'vistos', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select modelo, count(*) veces, max(creado) ultima from eventos
        where cliente_email = em and creado >= desde and tipo = 'ver_producto' and modelo is not null
        group by modelo order by count(*) desc, max(creado) desc limit 40) x),
    'cotizados', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select modelo,
               count(*) filter (where tipo = 'agregar_carrito')  carrito,
               count(*) filter (where tipo = 'cotizar_whatsapp') whatsapp,
               count(*) filter (where tipo = 'pedido_whatsapp')  pedidos,
               max(cantidad) cantidad, max(creado) ultima
        from eventos
        where cliente_email = em and creado >= desde and modelo is not null
          and tipo in ('agregar_carrito','cotizar_whatsapp','pedido_whatsapp')
        group by modelo order by count(*) desc, max(creado) desc limit 40) x),
    'recientes', (select coalesce(jsonb_agg(x order by x.creado desc), '[]'::jsonb) from (
        select tipo, texto, modelo, resultados, cantidad, origen, creado from eventos
        where cliente_email = em and creado >= desde
        order by creado desc limit 80) x)
  );
end $$;
revoke all on function public.actividad_cliente(text, integer) from public, anon;
grant execute on function public.actividad_cliente(text, integer) to authenticated;
