-- =====================================================================
--  23 · AVISO DE OFERTA NUEVA (SuinBot → Telegram)
-- ---------------------------------------------------------------------
--  Cada vez que se crea una oferta en Gestión (desde el generador, la
--  lista de ofertas o el teléfono), SuinBot avisa al momento:
--
--    📝 Oferta nueva OF-20261015-003
--    Cliente: Industrias X
--    Vendedor: Ods
--    • 2 × GD20-2R2G-SS2 — $355
--    • 1 × 5SL6363-7MB — $63
--    Total: $773.00
--    Abrir en Gestión
--
--  · Le llega al mismo chat de siempre (el secreto telegram_chat_id).
--  · Para que también le llegue a otros administradores (tu papá, por
--    ejemplo), cada uno le escribe /start a SuinBot y guardas sus chat_id
--    separados por comas, UNA sola vez:
--      select vault.create_secret('111111111,222222222', 'telegram_chat_ids_ofertas');
--    (para cambiarlos: Supabase → Project Settings → Vault).
--    Otra opción: un grupo de Telegram con SuinBot y los administradores,
--    y pones el chat_id del grupo (empieza con -100…).
--  · Solo avisa al CREAR la oferta (no cada vez que se edita) y solo si
--    es de los últimos 2 días (no avisa ofertas viejas que se suban tarde).
--  · Para avisar solo las ofertas de los vendedores (no las tuyas),
--    cambia  solo_vendedores boolean := false  por  true  más abajo.
--
--  Requiere 07_notificaciones.sql (SuinBot) y 21_gestion_roles_historial.sql.
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO → Run.
--  Seguro de correr varias veces. Si Telegram falla, la oferta se guarda igual.
--
--  Prueba (manda el aviso de la última oferta guardada):
--    select public.adm_avisar_oferta_prueba();
-- =====================================================================

-- Número seguro: '1.234,50' / '1234.5' / 12 → numeric (o 0 si no se entiende)
create or replace function public.tg_num(v jsonb) returns numeric
language plpgsql immutable as $$
declare t text;
begin
  if v is null or jsonb_typeof(v) = 'null' then return 0; end if;
  if jsonb_typeof(v) = 'number' then return (v #>> '{}')::numeric; end if;
  t := regexp_replace(v #>> '{}', '[^0-9,.\-]', '', 'g');
  if t = '' then return 0; end if;
  if t like '%,%' and t like '%.%' then
    if strpos(reverse(t), ',') < strpos(reverse(t), '.') then t := replace(replace(t, '.', ''), ',', '.'); else t := replace(t, ',', ''); end if;
  elsif t like '%,%' then t := replace(t, ',', '.');
  end if;
  return t::numeric;
exception when others then return 0;
end $$;

-- Mandar a un chat en particular (mismo bot que notificar_telegram)
create or replace function public.notificar_telegram_a(chat text, texto text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_token text;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'telegram_token';
  if v_token is null or coalesce(trim(chat), '') = '' or coalesce(texto, '') = '' then return; end if;
  perform net.http_post(
    url     := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body    := jsonb_build_object('chat_id', trim(chat), 'text', left(texto, 4000), 'parse_mode', 'HTML', 'disable_web_page_preview', true),
    timeout_milliseconds := 20000);
exception when others then
  raise warning 'notificar_telegram_a: %', sqlerrm;
end $$;
revoke all on function public.notificar_telegram_a(text, text) from public, anon, authenticated;

-- Texto del aviso de una oferta
create or replace function public.adm_texto_oferta(p_id text, d jsonb, quien uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  lineas text; n int; sub numeric; total numeric; vend text; cli text;
begin
  n := coalesce(jsonb_array_length(d->'items'), 0);
  select coalesce(sum(public.tg_num(it->'cant') * public.tg_num(it->'precio')), 0) into sub
    from jsonb_array_elements(coalesce(d->'items', '[]'::jsonb)) it;
  total := sub * (1 - public.tg_num(d->'descPct') / 100) * (1 + public.tg_num(d->'ivaPct') / 100);

  select string_agg(
           '• ' || rtrim(to_char(public.tg_num(it->'cant'), 'FM999G990D999'), '.,') || ' × ' ||
           coalesce(public.tg_esc(nullif(it->>'codigo', '')),
                    public.tg_esc(left(regexp_replace(split_part(coalesce(it->>'desc', ''), chr(10), 1), '\*|Ref / Modelo:\s*', '', 'g'), 60)), '?') ||
           ' — $' || to_char(public.tg_num(it->'precio'), 'FM999G999G990D00'),
           chr(10) order by ord)
    into lineas
    from jsonb_array_elements(coalesce(d->'items', '[]'::jsonb)) with ordinality as x(it, ord)
   where ord <= 10;
  if n > 10 then lineas := lineas || chr(10) || '… y ' || (n - 10) || ' más'; end if;

  vend := nullif(trim(coalesce(d->>'vendedor', '')), '');
  if vend is null and quien is not null then
    select coalesce(nullif(u.nombre, ''), u.email) into vend from public.adm_usuarios u
     where lower(u.email) = lower((select email from auth.users where id = quien)) limit 1;
    if vend is null then select email into vend from auth.users where id = quien; end if;
  end if;
  cli := nullif(trim(coalesce(d#>>'{cliente,nombre}', '')), '');

  return '📝 <b>Oferta nueva ' || coalesce(public.tg_esc(d->>'numero'), '') || '</b>' || chr(10) ||
         'Cliente: <b>' || coalesce(public.tg_esc(cli), 'sin nombre') || '</b>' || chr(10) ||
         'Vendedor: ' || coalesce(public.tg_esc(vend), '—') || chr(10) || chr(10) ||
         coalesce(lineas, '(sin productos)') || chr(10) || chr(10) ||
         '<b>Total: $' || to_char(total, 'FM999G999G990D00') || '</b>' ||
         case when public.tg_num(d->'descPct') > 0 then ' (con ' || rtrim(to_char(public.tg_num(d->'descPct'), 'FM990D99'), '.,') || '% desc.)' else '' end || chr(10) ||
         '<a href="https://suinelectric.com/ventas/doc/' || p_id || '">Abrir en Gestión</a> · 🕒 ' || public.tg_hora();
end $$;
revoke all on function public.adm_texto_oferta(text, jsonb, uuid) from public, anon, authenticated;

-- Trigger: oferta nueva → aviso
create or replace function public.adm_avisar_oferta() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare
  solo_vendedores boolean := false;   -- true = no avisar las ofertas que hace un administrador
  txt text; extra text; c text; quien_admin boolean;
begin
  if new.coleccion <> 'docs' or new.borrado or coalesce(new.data->>'tipo', '') <> 'oferta' then return new; end if;
  if coalesce((new.data->>'importado')::text, '') not in ('', 'false') then return new; end if;
  if left(coalesce(new.data->>'fecha', ''), 10) < to_char((now() at time zone 'America/Caracas') - interval '2 days', 'YYYY-MM-DD') then return new; end if;

  if solo_vendedores and new.actualizado_por is not null then
    select exists(select 1 from public.adm_usuarios u join auth.users a on lower(a.email) = lower(u.email)
                   where a.id = new.actualizado_por and u.rol = 'admin')
        or exists(select 1 from auth.users a where a.id = new.actualizado_por and lower(a.email) = 'manolo1496@gmail.com')
      into quien_admin;
    if quien_admin then return new; end if;
  end if;

  txt := public.adm_texto_oferta(new.id, new.data, new.actualizado_por);
  perform public.notificar_telegram(txt);
  select decrypted_secret into extra from vault.decrypted_secrets where name = 'telegram_chat_ids_ofertas';
  if extra is not null then
    foreach c in array regexp_split_to_array(extra, '\s*[,;\s]\s*') loop
      if c <> '' and c <> coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'telegram_chat_id'), '') then
        perform public.notificar_telegram_a(c, txt);
      end if;
    end loop;
  end if;
  return new;
exception when others then
  raise warning 'adm_avisar_oferta: %', sqlerrm;   -- nunca bloquea el guardado
  return new;
end $$;

drop trigger if exists adm_registros_aviso_oferta on public.adm_registros;
create trigger adm_registros_aviso_oferta after insert on public.adm_registros
  for each row execute function public.adm_avisar_oferta();

-- Prueba: manda el aviso de la última oferta guardada
create or replace function public.adm_avisar_oferta_prueba() returns text
language plpgsql security definer set search_path = public as $$
declare r public.adm_registros; txt text;
begin
  select * into r from public.adm_registros
   where coleccion = 'docs' and not borrado and data->>'tipo' = 'oferta'
   order by actualizado desc limit 1;
  if r.id is null then return 'No hay ofertas guardadas todavía'; end if;
  txt := public.adm_texto_oferta(r.id, r.data, r.actualizado_por);
  perform public.notificar_telegram('🧪 Prueba' || chr(10) || txt);
  return 'Enviado: ' || coalesce(r.data->>'numero', r.id);
end $$;
revoke all on function public.adm_avisar_oferta_prueba() from public, anon, authenticated;
