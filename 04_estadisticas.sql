-- =====================================================================
--  SUINELECTRIC · Estadísticas: qué buscan, qué ven y qué cotizan
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--
--  La tienda anota (sin datos personales de visitantes):
--    busqueda          → lo que escriben en el buscador (y cuántos resultados hubo)
--    ver_producto      → cuando abren la ficha de un producto
--    agregar_carrito   → cuando agregan un producto al pedido
--    cotizar_whatsapp  → cuando tocan "WhatsApp" en un producto
--    pedido_whatsapp   → cuando envían el carrito por WhatsApp
--  Solo los administradores pueden leerlo (panel → Estadísticas).
-- =====================================================================

create table if not exists public.eventos (
  id            bigint generated always as identity primary key,
  tipo          text not null check (tipo in ('busqueda','ver_producto','agregar_carrito','cotizar_whatsapp','pedido_whatsapp')),
  texto         text check (char_length(texto) <= 120),   -- lo buscado
  modelo        text check (char_length(modelo) <= 80),
  resultados    integer,                                   -- solo en búsquedas
  cantidad      integer,                                   -- solo en carrito / pedidos
  cliente_email text,                                      -- solo si entró con su cuenta
  origen        text check (char_length(origen) <= 20),   -- 'tienda' o 'pagina'
  creado        timestamptz not null default now()
);
create index if not exists eventos_creado_idx on public.eventos (creado desc);
create index if not exists eventos_tipo_idx   on public.eventos (tipo, creado desc);

-- El correo se pone solo (del que está conectado); nadie puede anotar a nombre de otro.
create or replace function public.eventos_completar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.cliente_email := nullif(public.mi_email(), '');
  new.creado := now();
  new.texto := nullif(lower(trim(new.texto)), '');
  return new;
end $$;
drop trigger if exists eventos_completar on public.eventos;
create trigger eventos_completar before insert on public.eventos
  for each row execute function public.eventos_completar();

alter table public.eventos enable row level security;
drop policy if exists eventos_anotar on public.eventos;
drop policy if exists eventos_leer   on public.eventos;
drop policy if exists eventos_borrar on public.eventos;
create policy eventos_anotar on public.eventos for insert to anon, authenticated with check (true);
create policy eventos_leer   on public.eventos for select to authenticated using (public.es_admin());
create policy eventos_borrar on public.eventos for delete to authenticated using (public.es_admin());
grant insert on public.eventos to anon, authenticated;
grant select, delete on public.eventos to authenticated;

-- Resumen para el panel (se calcula en el servidor: no hay que bajar miles de filas).
create or replace function public.resumen_estadisticas(dias integer default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
begin
  if not public.es_admin() then return null; end if;
  -- No se cuenta lo que hacen los administradores (tus propias pruebas).
  return jsonb_build_object(
    'totales', (select coalesce(jsonb_object_agg(tipo, n), '{}'::jsonb) from (
        select tipo, count(*) n from eventos e
        where creado >= desde and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by tipo) t),
    'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('dia', dia, 'vistas', vistas, 'cotiza', cotiza) order by dia), '[]'::jsonb) from (
        select date_trunc('day', creado at time zone 'America/Caracas')::date dia,
               count(*) filter (where tipo = 'ver_producto') vistas,
               count(*) filter (where tipo in ('cotizar_whatsapp','pedido_whatsapp','agregar_carrito')) cotiza
        from eventos e
        where creado >= desde and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by 1) d),
    'buscado', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select texto, count(*) veces, max(resultados) resultados from eventos e
        where tipo = 'busqueda' and creado >= desde and texto is not null
          and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by texto order by count(*) desc, texto limit 30) x),
    'sin_resultados', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select texto, count(*) veces, max(creado) ultima from eventos e
        where tipo = 'busqueda' and coalesce(resultados, 0) = 0 and creado >= desde and texto is not null
          and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by texto order by count(*) desc, max(creado) desc limit 30) x),
    'vistos', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select modelo, count(*) veces from eventos e
        where tipo = 'ver_producto' and creado >= desde and modelo is not null
          and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by modelo order by count(*) desc limit 30) x),
    'cotizados', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select modelo,
               count(*) filter (where tipo = 'cotizar_whatsapp') whatsapp,
               count(*) filter (where tipo = 'agregar_carrito') carrito,
               count(*) filter (where tipo = 'pedido_whatsapp') pedidos,
               count(distinct cliente_email) filter (where cliente_email is not null) clientes
        from eventos e
        where tipo in ('cotizar_whatsapp','agregar_carrito','pedido_whatsapp') and creado >= desde and modelo is not null
          and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by modelo order by count(*) desc limit 30) x)
  );
end $$;
revoke all on function public.resumen_estadisticas(integer) from public, anon;
grant execute on function public.resumen_estadisticas(integer) to authenticated;

-- Limpieza: borra lo que tenga más de un año (lo llama el panel al abrir Estadísticas).
create or replace function public.limpiar_eventos() returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.es_admin() then return 0; end if;
  delete from public.eventos where creado < now() - interval '365 days';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.limpiar_eventos() from public, anon;
grant execute on function public.limpiar_eventos() to authenticated;
