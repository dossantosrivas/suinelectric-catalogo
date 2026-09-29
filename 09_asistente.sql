-- =====================================================================
--  SUINELECTRIC · Asistente con IA en el chat de la tienda (fase 2)
--  - La IA (Gemini, gratis) contesta primero y recomienda productos del
--    catálogo con su enlace. No da precios.
--  - Si el cliente pide cotizar, hablar con una persona, etc., la IA te
--    pasa la conversación y te avisa por Telegram.
--  - En cuanto TÚ respondes un chat desde Telegram, la IA se calla en ese
--    chat. Para volver a encenderla: /ia 12 en Telegram.
--
--  Requiere haber corrido antes 08_chat.sql.
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
-- =====================================================================

-- ---------- Catálogo para búsquedas (lo llena GitHub cada día) ----------
create table if not exists public.productos_busqueda (
  modelo         text primary key,
  marca          text,
  categoria      text,
  descripcion    text,
  disponible     boolean not null default true,
  disponibilidad text,           -- "+10 disponibles", "Últimas unidades", "Disponible", "Agotado"
  url            text,           -- https://suinelectric.com/p/…
  texto          text not null   -- todo junto, en minúsculas y sin acentos (para buscar)
);
alter table public.productos_busqueda enable row level security;  -- sin políticas: solo la clave secreta

-- Reemplaza todo el catálogo de búsqueda (lo usa subir-catalogo-asistente.js).
create or replace function public.cargar_productos_busqueda(datos jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if jsonb_typeof(datos) <> 'array' or jsonb_array_length(datos) < 100 then
    raise exception 'Catálogo vacío o incompleto: no se reemplaza';
  end if;
  delete from public.productos_busqueda where true;
  insert into public.productos_busqueda (modelo, marca, categoria, descripcion, disponible, disponibilidad, url, texto)
  select distinct on (x->>'modelo')
         x->>'modelo', x->>'marca', x->>'categoria', x->>'descripcion',
         coalesce((x->>'disponible')::boolean, true), x->>'disponibilidad', x->>'url', coalesce(x->>'texto', '')
    from jsonb_array_elements(datos) x
   where coalesce(x->>'modelo', '') <> '';
  get diagnostics n = row_count;
  return n;
end $$;

-- Busca por palabras o frases (normalizadas igual que 'texto'). Cada término debe
-- coincidir con el inicio de una palabra ("15 hp" no encuentra "215 hp").
-- Gana el que contiene más términos; un modelo exacto va primero.
create or replace function public.buscar_productos(p_terminos text[], p_marca text default null, p_limite int default 8)
returns jsonb
language sql stable security definer set search_path = public as $$
  with t as (
    select distinct lower(btrim(x)) as x from unnest(coalesce(p_terminos, '{}'::text[])) x
     where length(btrim(x)) >= 2 limit 10
  ), r as (
    select p.*,
           (select count(*) from t where position(' ' || t.x in p.texto) > 0)            -- palabra que empieza así
           + case when exists (select 1 from t where left(p.texto, length(t.x) + 2) = ' ' || t.x || ' ')
                  then 5 else 0 end as puntos                                            -- es el modelo exacto
      from public.productos_busqueda p
     where p_marca is null or p_marca = '' or p.marca ilike p_marca
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'modelo', modelo, 'marca', marca, 'categoria', categoria,
           'descripcion', left(descripcion, 400), 'disponibilidad', disponibilidad, 'url', url)
         order by puntos desc, disponible desc, modelo), '[]'::jsonb)
    from (select * from r where puntos > 0
           order by puntos desc, disponible desc, modelo
           limit greatest(1, least(coalesce(p_limite, 8), 15))) z
$$;

revoke all on function public.cargar_productos_busqueda(jsonb) from public, anon, authenticated;
revoke all on function public.buscar_productos(text[], text, int) from public, anon, authenticated;
grant execute on function public.cargar_productos_busqueda(jsonb) to service_role;
grant execute on function public.buscar_productos(text[], text, int) to service_role;

-- ---------- El chat ahora tiene un tercer autor: la IA ----------
alter table public.chat_mensajes drop constraint if exists chat_mensajes_autor_check;
alter table public.chat_mensajes add constraint chat_mensajes_autor_check
  check (autor in ('cliente', 'suinelectric', 'asistente'));

alter table public.chat_conversaciones add column if not exists ia_activa boolean not null default true;
alter table public.chat_conversaciones add column if not exists ia_ocupada_hasta timestamptz;

-- La IA toma el turno de un chat: solo si está encendida, el último mensaje es
-- del cliente y nadie más la está atendiendo. Devuelve el historial.
create or replace function public.chat_turno_ia(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c public.chat_conversaciones;
  v_ultimo public.chat_mensajes;
  v_hist jsonb;
begin
  select * into c from public.chat_conversaciones where token = p_token for update;
  if not found or not c.ia_activa then return jsonb_build_object('ok', false, 'motivo', 'ia_apagada'); end if;
  if c.ia_ocupada_hasta is not null and c.ia_ocupada_hasta > now() then
    return jsonb_build_object('ok', false, 'motivo', 'ocupada');
  end if;
  select * into v_ultimo from public.chat_mensajes where conversacion_id = c.id order by id desc limit 1;
  if not found or v_ultimo.autor <> 'cliente' then return jsonb_build_object('ok', false, 'motivo', 'nada_pendiente'); end if;

  update public.chat_conversaciones set ia_ocupada_hasta = now() + interval '45 seconds' where id = c.id;

  select coalesce(jsonb_agg(jsonb_build_object('autor', autor, 'texto', texto) order by id), '[]'::jsonb) into v_hist
    from (select * from public.chat_mensajes where conversacion_id = c.id order by id desc limit 16) m;

  return jsonb_build_object('ok', true, 'chat', c.id, 'nombre', c.nombre, 'contacto', c.contacto,
    'email', c.email, 'pagina', c.pagina, 'hasta', v_ultimo.id,
    'primero', (select count(*) from public.chat_mensajes where conversacion_id = c.id and autor = 'cliente') = 1,
    'historial', v_hist);
end $$;

-- Guarda la respuesta de la IA (o solo libera el turno si p_texto es null).
-- p_pasar = true: la IA te pasa la conversación y se apaga en este chat.
create or replace function public.chat_guardar_ia(p_chat bigint, p_texto text, p_pasar boolean default false, p_hasta bigint default 0)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(btrim(p_texto), '') <> '' then
    insert into public.chat_mensajes (conversacion_id, autor, texto)
    values (p_chat, 'asistente', left(btrim(p_texto), 2000));
  end if;
  update public.chat_conversaciones
     set ia_ocupada_hasta = null,
         ia_activa = case when p_pasar then false else ia_activa end,
         ultimo = now()
   where id = p_chat;
  return jsonb_build_object('ok', true,
    'pendiente', exists (select 1 from public.chat_mensajes
                          where conversacion_id = p_chat and autor = 'cliente' and id > coalesce(p_hasta, 0)));
end $$;

-- Encender / apagar la IA en un chat (comando /ia en Telegram).
create or replace function public.chat_ia(p_chat bigint, p_activa boolean) returns jsonb
language sql security definer set search_path = public as $$
  update public.chat_conversaciones set ia_activa = p_activa, ia_ocupada_hasta = null where id = p_chat
  returning jsonb_build_object('ok', true, 'chat', id, 'ia', ia_activa, 'nombre', nombre)
$$;

revoke all on function public.chat_turno_ia(uuid) from public, anon, authenticated;
revoke all on function public.chat_guardar_ia(bigint, text, boolean, bigint) from public, anon, authenticated;
revoke all on function public.chat_ia(bigint, boolean) from public, anon, authenticated;
grant execute on function public.chat_turno_ia(uuid) to service_role;
grant execute on function public.chat_guardar_ia(bigint, text, boolean, bigint) to service_role;
grant execute on function public.chat_ia(bigint, boolean) to service_role;

-- Cuando tú respondes desde Telegram, la IA se apaga en ese chat.
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
  update public.chat_conversaciones set ultimo = now(), ia_activa = false, ia_ocupada_hasta = null where id = v_conv.id;
  return jsonb_build_object('ok', true, 'chat', v_conv.id, 'nombre', v_conv.nombre, 'contacto', v_conv.contacto);
end $$;

-- Aviso a Telegram: si la IA está encendida en ese chat, el aviso lo manda
-- /api/asistente junto con la respuesta de la IA (así no te llegan dos).
create or replace function public.avisar_chat() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  c        public.chat_conversaciones;
  primero  boolean;
  wa       text;
begin
  if new.autor <> 'cliente' then return new; end if;
  select * into c from public.chat_conversaciones where id = new.conversacion_id;
  if c.ia_activa then return new; end if;
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
