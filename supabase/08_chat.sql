-- =====================================================================
--  SUINELECTRIC · Chat de la tienda (fase 1: chat directo contigo)
--  - El visitante escribe desde la burbuja de chat de la tienda.
--  - Cada mensaje te llega a Telegram (SuinBot) con el número del chat.
--  - Tú RESPONDES a ese mensaje en Telegram y la respuesta aparece en la
--    tienda (lo recibe la función /api/telegram de Cloudflare).
--
--  Requiere haber corrido antes 07_notificaciones.sql (usa notificar_telegram).
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
-- =====================================================================

-- ---------- Tablas ----------
create table if not exists public.chat_conversaciones (
  id        bigint generated always as identity primary key,
  token     uuid not null unique,              -- identificador secreto del visitante (vive en su navegador)
  nombre    text,
  contacto  text,                              -- WhatsApp / teléfono que dejó
  email     text,                              -- si tenía la sesión iniciada
  pagina    text,                              -- desde dónde escribió la primera vez
  estado    text not null default 'abierta' check (estado in ('abierta', 'cerrada')),
  creado    timestamptz not null default now(),
  ultimo    timestamptz not null default now()
);

create table if not exists public.chat_mensajes (
  id              bigint generated always as identity primary key,
  conversacion_id bigint not null references public.chat_conversaciones(id) on delete cascade,
  autor           text not null check (autor in ('cliente', 'suinelectric')),
  texto           text not null,
  creado          timestamptz not null default now()
);
create index if not exists chat_mensajes_conv_idx on public.chat_mensajes (conversacion_id, id);
create index if not exists chat_conv_ultimo_idx on public.chat_conversaciones (ultimo desc);

-- Nadie lee las tablas directo desde la web: solo por las funciones de abajo.
-- (Los administradores sí pueden verlas, para un futuro panel de chats.)
alter table public.chat_conversaciones enable row level security;
alter table public.chat_mensajes enable row level security;
drop policy if exists chat_conv_admin on public.chat_conversaciones;
create policy chat_conv_admin on public.chat_conversaciones for select using (public.es_admin());
drop policy if exists chat_msj_admin on public.chat_mensajes;
create policy chat_msj_admin on public.chat_mensajes for select using (public.es_admin());

-- ---------- El visitante envía un mensaje ----------
create or replace function public.chat_enviar(
  p_token uuid, p_texto text,
  p_nombre text default null, p_contacto text default null, p_pagina text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_conv  public.chat_conversaciones;
  v_texto text := left(btrim(coalesce(p_texto, '')), 1000);
  v_id    bigint;
begin
  if p_token is null or v_texto = '' then
    raise exception 'Mensaje vacío';
  end if;

  select * into v_conv from public.chat_conversaciones where token = p_token;

  if not found then
    -- Freno contra abusos: máximo 40 chats nuevos por hora en toda la tienda.
    if (select count(*) from public.chat_conversaciones where creado > now() - interval '1 hour') >= 40 then
      raise exception 'El chat está muy ocupado, escríbenos por WhatsApp';
    end if;
    insert into public.chat_conversaciones (token, nombre, contacto, email, pagina)
    values (p_token,
            nullif(left(btrim(coalesce(p_nombre, '')), 80), ''),
            nullif(left(btrim(coalesce(p_contacto, '')), 40), ''),
            nullif(public.mi_email(), ''),
            nullif(left(coalesce(p_pagina, ''), 300), ''))
    returning * into v_conv;
  else
    -- Freno por visitante: 6 mensajes por minuto y 60 por hora.
    if (select count(*) from public.chat_mensajes
         where conversacion_id = v_conv.id and autor = 'cliente' and creado > now() - interval '1 minute') >= 6
       or (select count(*) from public.chat_mensajes
         where conversacion_id = v_conv.id and autor = 'cliente' and creado > now() - interval '1 hour') >= 60 then
      raise exception 'Vas muy rápido, espera un momento';
    end if;
    update public.chat_conversaciones
       set nombre   = coalesce(nullif(left(btrim(coalesce(p_nombre, '')), 80), ''), nombre),
           contacto = coalesce(nullif(left(btrim(coalesce(p_contacto, '')), 40), ''), contacto),
           email    = coalesce(email, nullif(public.mi_email(), '')),
           estado   = 'abierta',
           ultimo   = now()
     where id = v_conv.id
     returning * into v_conv;
  end if;

  insert into public.chat_mensajes (conversacion_id, autor, texto)
  values (v_conv.id, 'cliente', v_texto)
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'chat', v_conv.id);
end $$;

-- ---------- El visitante lee sus mensajes ----------
create or replace function public.chat_leer(p_token uuid, p_desde bigint default 0) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'autor', m.autor, 'texto', m.texto, 'creado', m.creado) order by m.id), '[]'::jsonb)
    from (select m.* from public.chat_mensajes m
            join public.chat_conversaciones c on c.id = m.conversacion_id
           where c.token = p_token and m.id > coalesce(p_desde, 0)
           order by m.id
           limit 200) m
$$;

revoke all on function public.chat_enviar(uuid, text, text, text, text) from public;
revoke all on function public.chat_leer(uuid, bigint) from public;
grant execute on function public.chat_enviar(uuid, text, text, text, text) to anon, authenticated;
grant execute on function public.chat_leer(uuid, bigint) to anon, authenticated;

-- ---------- Tú respondes (lo usa /api/telegram con la clave secreta) ----------
create or replace function public.chat_responder(p_chat bigint, p_texto text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_conv public.chat_conversaciones;
  v_texto text := left(btrim(coalesce(p_texto, '')), 2000);
begin
  select * into v_conv from public.chat_conversaciones where id = p_chat;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'No existe el chat #' || p_chat);
  end if;
  if v_texto = '' then
    return jsonb_build_object('ok', false, 'error', 'Mensaje vacío');
  end if;
  insert into public.chat_mensajes (conversacion_id, autor, texto) values (v_conv.id, 'suinelectric', v_texto);
  update public.chat_conversaciones set ultimo = now() where id = v_conv.id;
  return jsonb_build_object('ok', true, 'chat', v_conv.id, 'nombre', v_conv.nombre, 'contacto', v_conv.contacto);
end $$;

-- Lista de chats recientes (comando /chats en Telegram).
create or replace function public.chat_recientes(p_limite int default 10) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x.ultimo desc), '[]'::jsonb) from (
    select c.id, c.nombre, c.contacto, c.ultimo,
           (select m.autor from public.chat_mensajes m where m.conversacion_id = c.id order by m.id desc limit 1) as ultimo_autor,
           (select left(m.texto, 80) from public.chat_mensajes m where m.conversacion_id = c.id order by m.id desc limit 1) as ultimo_texto
      from public.chat_conversaciones c
     order by c.ultimo desc
     limit greatest(1, least(coalesce(p_limite, 10), 30))
  ) x
$$;

revoke all on function public.chat_responder(bigint, text) from public, anon, authenticated;
revoke all on function public.chat_recientes(int) from public, anon, authenticated;
grant execute on function public.chat_responder(bigint, text) to service_role;
grant execute on function public.chat_recientes(int) to service_role;

-- ---------- Aviso a Telegram por cada mensaje del visitante ----------
create or replace function public.avisar_chat() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  c        public.chat_conversaciones;
  primero  boolean;
  wa       text;
begin
  if new.autor <> 'cliente' then return new; end if;
  select * into c from public.chat_conversaciones where id = new.conversacion_id;
  primero := not exists (select 1 from public.chat_mensajes
                          where conversacion_id = new.conversacion_id and id < new.id);
  wa := public.tg_wa(c.contacto);

  perform public.notificar_telegram(
    '💬 <b>Chat #' || c.id || '</b> · ' || coalesce(public.tg_esc(c.nombre), 'Visitante') ||
    case when primero then
      coalesce(chr(10) || '📱 ' || public.tg_esc(c.contacto), '') ||
      coalesce(chr(10) || '✉️ ' || public.tg_esc(c.email), '') ||
      coalesce(chr(10) || '📄 ' || public.tg_esc(c.pagina), '')
    else '' end ||
    chr(10) || chr(10) || public.tg_esc(new.texto) ||
    case when primero then
      chr(10) || chr(10) || '<i>↩️ Responde a este mensaje para contestarle en la tienda.</i>' ||
      coalesce(chr(10) || '<a href="' || wa || '">Escribirle por WhatsApp</a>', '')
    else '' end);
  return new;
end $$;

drop trigger if exists chat_mensajes_avisar on public.chat_mensajes;
create trigger chat_mensajes_avisar after insert on public.chat_mensajes
  for each row execute function public.avisar_chat();
