-- =====================================================================
--  SUINELECTRIC · Última visita y actividad en la lista de clientes
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--  Requiere 04_estadisticas.sql y 06_actividad_clientes.sql.
--
--  Una fila por cliente con cuenta que haya usado la tienda:
--    · ultima        → la última vez que hizo algo en la tienda (cualquier fecha)
--    · dias_activos  → días distintos que entró en los últimos `dias`
--    · busquedas, vistas, carrito, whatsapp → lo que hizo en esos días
--  Solo cuenta lo que hace con la sesión iniciada.
-- =====================================================================

create or replace function public.lista_clientes_actividad(dias integer default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
begin
  if not public.es_admin() then return null; end if;
  return (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select cliente_email email,
           max(creado) ultima,
           count(distinct (creado at time zone 'America/Caracas')::date) filter (where creado >= desde) dias_activos,
           count(*) filter (where creado >= desde and tipo = 'busqueda')        busquedas,
           count(*) filter (where creado >= desde and tipo = 'ver_producto')    vistas,
           count(*) filter (where creado >= desde and tipo = 'agregar_carrito') carrito,
           count(*) filter (where creado >= desde and tipo = 'cotizar_whatsapp')
             + count(distinct date_trunc('minute', creado)) filter (where creado >= desde and tipo = 'pedido_whatsapp') whatsapp
    from eventos
    where cliente_email is not null
    group by cliente_email) x);
end $$;
revoke all on function public.lista_clientes_actividad(integer) from public, anon;
grant execute on function public.lista_clientes_actividad(integer) to authenticated;
