-- =====================================================================
--  SUINELECTRIC · Avisos a Telegram
--  Te llega un mensaje al Telegram cuando:
--    🆕 alguien crea una cuenta
--    ✍️ un cliente completa su registro (nombre, RIF, teléfono)
--    🛒 un cliente envía un pedido desde la tienda
--
--  ANTES de correr este archivo, guarda el token y tu chat_id en el
--  almacén de secretos de Supabase (Vault). En el SQL Editor corre esto
--  UNA sola vez, con tus datos reales entre las comillas:
--
--    select vault.create_secret('123456:ABC-el-token-del-bot', 'telegram_token');
--    select vault.create_secret('123456789', 'telegram_chat_id');
--
--  (Si luego cambias el token: Supabase → Project Settings → Vault, o
--   select vault.update_secret(id, 'nuevo-token') con el id del secreto.)
--
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--
--  Prueba: select public.notificar_telegram('✅ Prueba de Suinelectric');
--
--  Si Telegram no responde o faltan los secretos, NO pasa nada: el
--  registro o el pedido se guardan igual (el aviso simplemente no sale).
-- =====================================================================

create extension if not exists pg_net;

-- ---------- Enviar un mensaje ----------
create or replace function public.notificar_telegram(texto text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_token text;
  v_chat  text;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'telegram_token';
  select decrypted_secret into v_chat  from vault.decrypted_secrets where name = 'telegram_chat_id';
  if v_token is null or v_chat is null or coalesce(texto, '') = '' then
    return;
  end if;
  perform net.http_post(
    url     := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body    := jsonb_build_object(
                 'chat_id', v_chat,
                 'text', left(texto, 4000),
                 'parse_mode', 'HTML',
                 'disable_web_page_preview', true),
    timeout_milliseconds := 20000   -- la conexión a Telegram a veces tarda más de 5 s
  );
exception when others then
  raise warning 'notificar_telegram: %', sqlerrm;   -- nunca bloquea la operación
end $$;

-- Nadie desde la web puede usarla para mandarte mensajes.
revoke all on function public.notificar_telegram(text) from public, anon, authenticated;

-- Texto seguro para el formato HTML de Telegram (vacío → null).
create or replace function public.tg_esc(t text) returns text
language sql immutable as $$
  select replace(replace(replace(nullif(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
$$;

-- Hora de Venezuela, ej. 28/09 15:44
create or replace function public.tg_hora(t timestamptz default now()) returns text
language sql stable as $$
  select to_char(t at time zone 'America/Caracas', 'DD/MM HH24:MI')
$$;

-- Enlace de WhatsApp a partir de un teléfono venezolano (0412-1234567 → 584121234567).
create or replace function public.tg_wa(tel text) returns text
language sql immutable as $$
  select case
    when tel is null or regexp_replace(tel, '\D', '', 'g') = '' then null
    when regexp_replace(tel, '\D', '', 'g') ~ '^0' then 'https://wa.me/58' || substr(regexp_replace(tel, '\D', '', 'g'), 2)
    else 'https://wa.me/' || regexp_replace(tel, '\D', '', 'g')
  end
$$;

-- ---------- Clientes: cuenta nueva y registro completo ----------
create or replace function public.avisar_cliente() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  wa text;
begin
  -- Cuenta nueva: la ficha queda enlazada a un usuario que acaba de entrar.
  -- (Los clientes que tú precargas desde el panel no avisan hasta que entren.)
  if new.user_id is not null
     and (tg_op = 'INSERT' or old.user_id is null) then
    perform public.notificar_telegram(
      '🆕 <b>Cuenta nueva en la tienda</b>' || chr(10) ||
      public.tg_esc(new.email) || chr(10) ||
      coalesce(public.tg_esc(new.nombre) || chr(10), '') ||
      '🕒 ' || public.tg_hora());
  end if;

  -- Registro completo: el cliente escribió su nombre por primera vez.
  if tg_op = 'UPDATE' and coalesce(old.nombre, '') = '' and coalesce(new.nombre, '') <> '' then
    wa := public.tg_wa(new.telefono);
    perform public.notificar_telegram(
      '✍️ <b>Cliente completó su registro</b>' || chr(10) ||
      '<b>' || public.tg_esc(new.nombre) || '</b>' || chr(10) ||
      public.tg_esc(new.email) ||
      coalesce(chr(10) || 'RIF: ' || public.tg_esc(nullif(new.rif, '')), '') ||
      coalesce(chr(10) || 'Tel: ' || public.tg_esc(nullif(new.telefono, '')), '') ||
      coalesce(chr(10) || '<a href="' || wa || '">Escribirle por WhatsApp</a>', ''));
  end if;
  return new;
end $$;

drop trigger if exists clientes_avisar on public.clientes;
create trigger clientes_avisar after insert or update on public.clientes
  for each row execute function public.avisar_cliente();

-- ---------- Pedidos nuevos ----------
create or replace function public.avisar_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  c       public.clientes;
  lineas  text;
  n       int;
  wa      text;
begin
  select * into c from public.clientes where email = new.cliente_email;
  n := coalesce(jsonb_array_length(new.items), 0);

  select string_agg(
           '• ' || coalesce(it->>'cantidad', '1') || ' × ' || coalesce(public.tg_esc(it->>'modelo'), '?') ||
           coalesce(' — $' || to_char((it->>'precio_unit')::numeric, 'FM999G999G990'), ''),
           chr(10) order by ord)
    into lineas
    from jsonb_array_elements(new.items) with ordinality as x(it, ord)
   where ord <= 12;
  if n > 12 then lineas := lineas || chr(10) || '… y ' || (n - 12) || ' más'; end if;

  wa := public.tg_wa(c.telefono);
  perform public.notificar_telegram(
    '🛒 <b>Pedido #' || new.id || '</b>' || chr(10) ||
    '<b>' || public.tg_esc(coalesce(nullif(c.nombre, ''), new.cliente_email)) || '</b>' ||
    coalesce(' · ' || public.tg_esc(nullif(c.empresa, '')), '') || chr(10) ||
    public.tg_esc(new.cliente_email) || chr(10) || chr(10) ||
    coalesce(lineas, '(sin artículos)') || chr(10) || chr(10) ||
    '<b>Total: $' || coalesce(to_char(new.total, 'FM999G999G990D00'), '—') || '</b>' ||
    coalesce(chr(10) || '<a href="' || wa || '">Escribirle por WhatsApp</a>', '') || chr(10) ||
    '🕒 ' || public.tg_hora(new.creado));
  return new;
end $$;

drop trigger if exists pedidos_avisar on public.pedidos;
create trigger pedidos_avisar after insert on public.pedidos
  for each row execute function public.avisar_pedido();
