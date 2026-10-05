-- =====================================================================
--  SUINELECTRIC · En vivo (quién está en la web ahora y por dónde va)
--  y avisos a Telegram de lo que hacen los visitantes
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--  Requiere haber corrido antes 04_estadisticas.sql, 07_notificaciones.sql,
--  10_visitantes.sql y 12_enlaces.sql.
--
--  · en_linea        → una fila por navegador con la página donde está
--                      ahora y lo último que hizo. La tienda la actualiza
--                      al cambiar de página y cada ~40 s mientras está
--                      abierta (no crece: es una fila por visitante).
--  · Realtime        → el panel recibe al instante los cambios de
--                      en_linea y cada evento nuevo (panel → En vivo).
--  · avisos_eventos  → qué cosas te avisan por Telegram (SuinBot).
--                      Se prenden y apagan desde el panel → En vivo.
--  Solo los administradores pueden leer todo esto. No se guardan nombres
--  de visitantes sin cuenta ni la IP.
-- =====================================================================

-- ---------------------------------------------------------------------
--  Quién está conectado ahora
-- ---------------------------------------------------------------------
create table if not exists public.en_linea (
  visitante     text primary key check (char_length(visitante) <= 40),
  visita        text check (char_length(visita) <= 40),
  cliente_email text,
  pagina        text check (char_length(pagina) <= 200),
  titulo        text check (char_length(titulo) <= 160),
  accion        text check (char_length(accion) <= 200),     -- lo último que hizo
  accion_en     timestamptz,
  paginas       integer not null default 1,                   -- páginas vistas en esta visita
  pais          text check (char_length(pais) <= 60),
  region        text check (char_length(region) <= 80),
  ciudad        text check (char_length(ciudad) <= 80),
  proveedor     text check (char_length(proveedor) <= 100),
  dispositivo   text check (char_length(dispositivo) <= 20),
  navegador     text check (char_length(navegador) <= 40),
  sistema       text check (char_length(sistema) <= 40),
  referencia    text check (char_length(referencia) <= 120),
  activo        boolean not null default true,                -- false = cerró o dejó la pestaña en segundo plano
  entro         timestamptz not null default now(),           -- inicio de la visita actual
  visto         timestamptz not null default now()            -- última señal
);
create index if not exists en_linea_visto on public.en_linea (visto desc);

alter table public.en_linea enable row level security;
drop policy if exists en_linea_leer on public.en_linea;
create policy en_linea_leer on public.en_linea for select to authenticated using (public.es_admin());
revoke all on public.en_linea from anon;
grant select on public.en_linea to authenticated;

-- La tienda avisa dónde está (solo por esta función: nadie puede leer ni tocar filas ajenas).
-- p: {visitante, visita, pagina, titulo, accion, pais, region, ciudad, proveedor,
--     dispositivo, navegador, sistema, referencia, salir}
create or replace function public.marcar_en_linea(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_vis   text := left(nullif(trim(p->>'visitante'), ''), 40);
  v_email text := nullif(public.mi_email(), '');
  v_pag   text := left(nullif(p->>'pagina', ''), 200);
begin
  if v_vis is null then return; end if;
  -- Los administradores no cuentan (tus pruebas no salen en vivo).
  if v_email is not null and exists (select 1 from clientes where email = v_email and es_admin) then return; end if;

  insert into en_linea as e (visitante, visita, cliente_email, pagina, titulo, accion, accion_en, pais, region, ciudad,
                             proveedor, dispositivo, navegador, sistema, referencia, activo, entro, visto)
  values (v_vis, left(p->>'visita', 40), v_email, v_pag, left(nullif(p->>'titulo', ''), 160),
          left(nullif(p->>'accion', ''), 200), case when nullif(p->>'accion', '') is not null then now() end,
          left(nullif(p->>'pais', ''), 60), left(nullif(p->>'region', ''), 80), left(nullif(p->>'ciudad', ''), 80),
          left(nullif(p->>'proveedor', ''), 100), left(nullif(p->>'dispositivo', ''), 20), left(nullif(p->>'navegador', ''), 40),
          left(nullif(p->>'sistema', ''), 40), left(nullif(p->>'referencia', ''), 120),
          not coalesce((p->>'salir')::boolean, false), now(), now())
  on conflict (visitante) do update set
    -- Visita nueva: empieza de cero (entrada, origen y contador de páginas).
    entro      = case when e.visita is distinct from excluded.visita then now() else e.entro end,
    paginas    = case when e.visita is distinct from excluded.visita then 1
                      when excluded.pagina is not null and excluded.pagina is distinct from e.pagina then e.paginas + 1
                      else e.paginas end,
    referencia = case when e.visita is distinct from excluded.visita then excluded.referencia else coalesce(e.referencia, excluded.referencia) end,
    accion     = case when e.visita is distinct from excluded.visita then excluded.accion else coalesce(excluded.accion, e.accion) end,
    accion_en  = case when e.visita is distinct from excluded.visita then excluded.accion_en else coalesce(excluded.accion_en, e.accion_en) end,
    visita        = coalesce(excluded.visita, e.visita),
    cliente_email = coalesce(excluded.cliente_email, e.cliente_email),
    pagina        = coalesce(excluded.pagina, e.pagina),
    titulo        = case when excluded.pagina is not null then excluded.titulo else e.titulo end,
    pais        = coalesce(excluded.pais, e.pais),
    region      = coalesce(excluded.region, e.region),
    ciudad      = coalesce(excluded.ciudad, e.ciudad),
    proveedor   = coalesce(excluded.proveedor, e.proveedor),
    dispositivo = coalesce(excluded.dispositivo, e.dispositivo),
    navegador   = coalesce(excluded.navegador, e.navegador),
    sistema     = coalesce(excluded.sistema, e.sistema),
    activo      = excluded.activo,
    visto       = now();

  -- Limpieza de vez en cuando: quien no da señales hace más de 2 días se borra.
  if random() < 0.02 then
    delete from en_linea where visto < now() - interval '2 days';
  end if;
end $$;
revoke all on function public.marcar_en_linea(jsonb) from public;
grant execute on function public.marcar_en_linea(jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------
--  Realtime: el panel recibe al instante en_linea y los eventos nuevos
--  (respeta la seguridad: solo los administradores los reciben)
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'en_linea') then
    alter publication supabase_realtime add table public.en_linea;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'eventos') then
    alter publication supabase_realtime add table public.eventos;
  end if;
end $$;

-- ---------------------------------------------------------------------
--  Avisos a Telegram de lo que hacen los visitantes
-- ---------------------------------------------------------------------
create table if not exists public.avisos_eventos (
  clave  text primary key,
  nombre text not null,
  detalle text,
  activo boolean not null default false,
  orden  integer not null default 0
);
insert into public.avisos_eventos (clave, nombre, detalle, activo, orden) values
  ('carrito',        'Agregó productos al pedido',        'La primera vez en cada visita que alguien agrega un producto al carrito.', true, 1),
  ('whatsapp',       'Tocó WhatsApp',                     'Cuando pide precio por WhatsApp, envía el carrito o toca WhatsApp en la página de enlaces (una vez por visita y producto).', true, 2),
  ('cliente_entra',  'Un cliente con cuenta entró',       'Cuando alguien con cuenta empieza una visita a la tienda.', true, 3),
  ('sin_resultados', 'Buscó algo y no lo encontró',       'Búsquedas sin resultados (una vez al día por cada texto).', true, 4),
  ('visita',         'Cualquier visita nueva',            'Cada vez que alguien entra a la web. Puede ser mucho: úsalo solo si tienes pocas visitas.', false, 5),
  ('links',          'Visita a la página de enlaces',     'Cada vez que alguien entra a suinelectric.com/links.', false, 6)
on conflict (clave) do update set nombre = excluded.nombre, detalle = excluded.detalle, orden = excluded.orden;

alter table public.avisos_eventos enable row level security;
drop policy if exists avisos_eventos_leer on public.avisos_eventos;
drop policy if exists avisos_eventos_cambiar on public.avisos_eventos;
create policy avisos_eventos_leer   on public.avisos_eventos for select to authenticated using (public.es_admin());
create policy avisos_eventos_cambiar on public.avisos_eventos for update to authenticated using (public.es_admin()) with check (public.es_admin());
revoke all on public.avisos_eventos from anon;
grant select, update (activo) on public.avisos_eventos to authenticated;

create or replace function public.aviso_activo(k text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select activo from avisos_eventos where clave = k), false)
$$;

-- Lugar y equipo de la visita (vienen en el evento "visita").
create or replace function public.tg_lugar(p_visita text) returns text
language sql stable security definer set search_path = public as $$
  select nullif(concat_ws(' · ',
           nullif(concat_ws(', ', ciudad, case when region is distinct from ciudad then region end,
                            case when pais is distinct from 'VE' then pais end), ''),
           dispositivo,
           case when referencia is not null then 'llegó por ' || referencia end), '')
  from eventos where visita = p_visita and tipo = 'visita' order by creado limit 1
$$;

create or replace function public.avisar_evento() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  quien text;
  lugar text;
  c     clientes;
  prod  text;
  txt   text;
  url   text := 'https://suinelectric.com/admin.html#envivo';
begin
  -- Lo que hacen los administradores no avisa.
  if new.cliente_email is not null then
    select * into c from clientes where email = new.cliente_email;
    if c.es_admin then return null; end if;
  end if;
  if new.tipo = 'ver_tarjetas' or new.tipo = 'ver_producto' then return null; end if;

  quien := case when c.email is not null
                then '👤 <b>' || tg_esc(coalesce(nullif(c.nombre, ''), nullif(c.empresa, ''), c.email)) || '</b>' ||
                     coalesce(' · ' || tg_esc(nullif(c.empresa, '')), '')
                else '🌐 Visitante ' || upper(left(replace(coalesce(new.visitante, ''), '-', ''), 6)) end;
  lugar := case when new.tipo = 'visita'
                then nullif(concat_ws(' · ',
                       nullif(concat_ws(', ', new.ciudad, case when new.region is distinct from new.ciudad then new.region end,
                                        case when new.pais is distinct from 'VE' then new.pais end), ''),
                       new.dispositivo, case when new.referencia is not null then 'llegó por ' || new.referencia end), '')
                else tg_lugar(new.visita) end;
  prod := tg_esc(new.modelo);

  if new.tipo = 'agregar_carrito' and aviso_activo('carrito')
     and not exists (select 1 from eventos where visita = new.visita and tipo = 'agregar_carrito' and id <> new.id) then
    txt := '🛒 <b>Agregó al pedido</b> ' || coalesce(new.cantidad || ' × ', '') || coalesce(prod, '');

  elsif (new.tipo = 'cotizar_whatsapp' or (new.tipo = 'clic_enlace' and new.texto ilike 'whatsapp%')
         -- el carrito enviado llega como un evento por producto: un solo aviso; y si tiene cuenta ya avisa el pedido (07)
         or (new.tipo = 'pedido_whatsapp' and new.cliente_email is null
             and not exists (select 1 from eventos where visita = new.visita and tipo = 'pedido_whatsapp' and id <> new.id
                             and creado >= now() - interval '10 minutes')))
     and aviso_activo('whatsapp')
     and (new.tipo = 'pedido_whatsapp'
          or not exists (select 1 from eventos where visita = new.visita and id <> new.id and tipo = new.tipo
                         and modelo is not distinct from new.modelo and texto is not distinct from new.texto)) then
    txt := '💬 <b>' || case new.tipo
             when 'cotizar_whatsapp' then 'Pidió precio por WhatsApp</b> de ' || coalesce(prod, 'un producto')
             when 'pedido_whatsapp'  then 'Envió su pedido por WhatsApp</b>' || coalesce(' (' || prod || '…)', '')
             else 'Tocó ' || tg_esc(new.texto) || '</b> en la página de enlaces' end;

  elsif new.tipo = 'busqueda' and coalesce(new.resultados, -1) = 0 and new.texto is not null and aviso_activo('sin_resultados')
     and not exists (select 1 from eventos where tipo = 'busqueda' and resultados = 0 and texto = new.texto
                     and id <> new.id and creado >= now() - interval '1 day') then
    txt := '🔎 <b>Buscó y no encontró:</b> “' || tg_esc(new.texto) || '”';

  elsif new.tipo = 'visita' and new.cliente_email is not null and aviso_activo('cliente_entra') then
    txt := '🟢 <b>Entró a la tienda</b>' || case when new.pagina ~ '^/p/' then ' (página de ' || tg_esc(substr(new.pagina, 4)) || ')' else '' end;

  elsif new.tipo = 'visita' and new.origen = 'links' and aviso_activo('links') then
    txt := '🔗 <b>Entró a la página de enlaces</b>';

  elsif new.tipo = 'visita' and aviso_activo('visita') then
    txt := '👀 <b>Visita nueva</b>' || coalesce(' en ' || tg_esc(new.pagina), '');
  end if;

  if txt is not null then
    perform notificar_telegram(txt || chr(10) || quien || coalesce(chr(10) || '📍 ' || tg_esc(lugar), '') || chr(10) ||
      '🕒 ' || tg_hora() || ' · <a href="' || url || '">Ver en vivo</a>');
  end if;
  return null;
exception when others then
  raise warning 'avisar_evento: %', sqlerrm;   -- nunca impide guardar el evento
  return null;
end $$;

drop trigger if exists eventos_avisar on public.eventos;
create trigger eventos_avisar after insert on public.eventos
  for each row execute function public.avisar_evento();
