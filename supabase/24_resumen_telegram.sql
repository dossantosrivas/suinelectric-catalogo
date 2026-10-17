-- =====================================================================
--  24 · RESUMEN DIARIO Y MENSUAL (SuinBot → Telegram)
-- ---------------------------------------------------------------------
--  SuinBot manda al grupo de Telegram:
--    · Todos los días a las 7:00 p.m. (hora de Venezuela): el resumen
--      del día (visitas de la tienda, ofertas, ventas, cobros, compras).
--    · El día 1 de cada mes a las 7:00 a.m.: el resumen del mes anterior
--      comparado con el mes previo.
--
--  ¿A quién le llega? A los chat_id guardados en el secreto
--  telegram_chat_ids_resumen (separados por comas). Hoy es el grupo
--  "WebSuin ⚡" (-1004323945727). Para cambiarlo: Supabase → Project Settings
--  → Vault, o con SQL:
--    select vault.update_secret(id, '-1004323945727,111111111')
--      from vault.secrets where name = 'telegram_chat_ids_resumen';
--
--  Pruebas (mandan el resumen ya mismo):
--    select public.adm_enviar_resumen('dia');
--    select public.adm_enviar_resumen('mes');
--  Solo ver el texto, sin mandarlo:
--    select public.adm_resumen_dia();
--    select public.adm_resumen_mes();
--
--  Cambiar la hora: Supabase → Integrations → Cron, o
--    select cron.alter_job((select jobid from cron.job where jobname = 'suinbot_resumen_dia'), schedule := '0 23 * * *');
--  (la hora va en UTC: Venezuela = UTC−4 → 7:00 p.m. = 23:00 UTC)
--
--  Requiere 07_notificaciones.sql (SuinBot). Seguro de correr varias veces.
-- =====================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

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

-- $1.234,50 → '$1,234.50' / sin decimales si es entero grande
create or replace function public.tg_usd(n numeric) returns text
language sql immutable as $$
  select '$' || case when abs(coalesce(n, 0)) >= 1000 then to_char(round(coalesce(n, 0)), 'FM999G999G990')
                     else to_char(coalesce(n, 0), 'FM999G990D00') end
$$;

-- Variación: (+12%) / (−5%) / (nuevo)
create or replace function public.tg_var(actual numeric, antes numeric) returns text
language sql immutable as $$
  select case
    when coalesce(antes, 0) = 0 and coalesce(actual, 0) = 0 then ''
    when coalesce(antes, 0) = 0 then ' (antes 0)'
    else ' (' || case when actual >= antes then '▲ +' else '▼ ' end ||
         round((actual - antes) / antes * 100)::text || '%)'
  end
$$;

-- Documentos de Gestión con sus montos ya calculados
create or replace function public.adm_docs_montos(p_tipo text)
returns table (id text, numero text, dia date, estado text, d jsonb,
               subtotal numeric, total numeric, costo numeric, sin_costo int, pagado numeric)
language sql stable security definer set search_path = public as $$
  select r.id, r.data->>'numero',
         case when left(r.data->>'fecha', 10) ~ '^\d{4}-\d{2}-\d{2}$' then left(r.data->>'fecha', 10)::date end,
         coalesce(r.data->>'estado', ''), r.data,
         x.sub * (1 - public.tg_num(r.data->'descPct') / 100),
         x.sub * (1 - public.tg_num(r.data->'descPct') / 100) * (1 + public.tg_num(r.data->'ivaPct') / 100),
         x.costo, x.sin_costo,
         (select coalesce(sum(public.tg_num(p->'monto')), 0) from jsonb_array_elements(coalesce(r.data->'pagos', '[]')) p)
    from public.adm_registros r,
    lateral (select coalesce(sum(public.tg_num(it->'cant') * public.tg_num(it->'precio')), 0) sub,
                    coalesce(sum(public.tg_num(it->'cant') * public.tg_num(it->'costo')), 0) costo,
                    count(*) filter (where public.tg_num(it->'costo') <= 0)::int sin_costo
               from jsonb_array_elements(case when jsonb_typeof(r.data->'items') = 'array' then r.data->'items' else '[]' end) it) x
   where r.coleccion = 'docs' and not r.borrado and r.data->>'tipo' = p_tipo
$$;
revoke all on function public.adm_docs_montos(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  Resumen del día
-- ---------------------------------------------------------------------
create or replace function public.adm_resumen_dia(p_dia date default null) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_dia date := coalesce(p_dia, (now() at time zone 'America/Caracas')::date);
  ini   timestamptz; fin timestamptz;
  dias  text[] := array['lun','mar','mié','jue','vie','sáb','dom'];
  vis int; vis_ayer int; visitantes int; nuevos int; busq int; vistos int; interes int; ped int;
  of_n int; of_tot numeric; of_ab int; of_ab_tot numeric; of_venc int;
  ve_n int; ve_tot numeric; ve_gan numeric; ve_sinc int;
  cobrado numeric; xc_n int; xc_tot numeric; xe_n int;
  co_n int; co_tot numeric;
  top text;
  t text;
begin
  ini := (v_dia::timestamp) at time zone 'America/Caracas';
  fin := ini + interval '1 day';

  -- Tienda web
  select count(distinct visita), count(distinct visitante) into vis, visitantes
    from eventos where tipo = 'visita' and creado >= ini and creado < fin;
  select count(distinct visita) into vis_ayer
    from eventos where tipo = 'visita' and creado >= ini - interval '1 day' and creado < ini;
  select count(*) into nuevos from (
    select visitante from eventos where visitante is not null
     group by visitante having min(creado) >= ini and min(creado) < fin) n;
  select count(*) filter (where tipo = 'busqueda'),
         count(*) filter (where tipo = 'ver_producto'),
         count(*) filter (where tipo in ('agregar_carrito', 'cotizar_whatsapp', 'pedido_whatsapp'))
    into busq, vistos, interes
    from eventos where creado >= ini and creado < fin;
  select count(*) into ped from pedidos where creado >= ini and creado < fin;
  select string_agg(public.tg_esc(m) || ' (' || c || ')', ', ') into top from (
    select coalesce(nullif(modelo, ''), nullif(texto, '')) m, count(*) c from eventos
     where tipo in ('ver_producto', 'busqueda') and creado >= ini and creado < fin
       and coalesce(nullif(modelo, ''), nullif(texto, '')) is not null
     group by 1 order by 2 desc limit 3) x;

  -- Ofertas
  select count(*), coalesce(sum(total), 0) into of_n, of_tot from adm_docs_montos('oferta') where dia = v_dia;
  select count(*), coalesce(sum(total), 0), count(*) filter (where dia <= v_dia - 5)
    into of_ab, of_ab_tot, of_venc from adm_docs_montos('oferta') where estado = 'abierta';

  -- Ventas
  select count(*), coalesce(sum(total), 0), coalesce(sum(subtotal - costo), 0), coalesce(sum(sin_costo), 0)
    into ve_n, ve_tot, ve_gan, ve_sinc
    from adm_docs_montos('venta') where estado <> 'anulada' and dia = v_dia;
  select coalesce(sum(public.tg_num(p->'monto')), 0) into cobrado
    from adm_docs_montos('venta') v, jsonb_array_elements(coalesce(v.d->'pagos', '[]')) p
   where v.estado <> 'anulada' and left(p->>'fecha', 10) = to_char(v_dia, 'YYYY-MM-DD');
  select count(*), coalesce(sum(total - pagado), 0) into xc_n, xc_tot
    from adm_docs_montos('venta') where estado <> 'anulada' and total - pagado > 0.5;
  select count(*) into xe_n from adm_docs_montos('venta')
   where estado <> 'anulada' and jsonb_typeof(d->'entrega') = 'object'
     and coalesce(d#>>'{entrega,estado}', '') not in ('entregado', 'enviado', '');

  -- Compras
  select count(*), coalesce(sum(case when costo > 0 then costo else subtotal end), 0) into co_n, co_tot
    from adm_docs_montos('compra') where estado <> 'anulada' and dia = v_dia;

  t := '📊 <b>Resumen del ' || dias[extract(isodow from v_dia)::int] || ' ' || to_char(v_dia, 'DD/MM') || '</b>' || chr(10) || chr(10) ||
       '🌐 <b>Tienda web</b>' || chr(10) ||
       '• Visitas: <b>' || vis || '</b>' || public.tg_var(vis, vis_ayer) || chr(10) ||
       '• Visitantes: ' || visitantes || ' (' || nuevos || ' nuevos)' || chr(10) ||
       '• Búsquedas: ' || busq || ' · Productos vistos: ' || vistos || chr(10) ||
       case when interes > 0 then '• Carrito / WhatsApp: ' || interes || chr(10) else '' end ||
       case when ped > 0 then '• 🛒 Pedidos web: <b>' || ped || '</b>' || chr(10) else '' end ||
       coalesce('• Más buscado: ' || top || chr(10), '') || chr(10) ||
       '📝 <b>Ofertas</b>' || chr(10) ||
       '• Nuevas hoy: <b>' || of_n || '</b>' || case when of_n > 0 then ' — ' || public.tg_usd(of_tot) else '' end || chr(10) ||
       '• Abiertas: ' || of_ab || ' — ' || public.tg_usd(of_ab_tot) ||
       case when of_venc > 0 then chr(10) || '• ⚠️ Con 5 días o más sin respuesta: ' || of_venc else '' end || chr(10) || chr(10) ||
       '💰 <b>Ventas</b>' || chr(10) ||
       '• Ventas hoy: <b>' || ve_n || '</b>' ||
       case when ve_n > 0 then ' — <b>' || public.tg_usd(ve_tot) || '</b>' || chr(10) ||
            '• Ganancia: ' || public.tg_usd(ve_gan) ||
            case when ve_sinc > 0 then ' (' || ve_sinc || ' producto' || case when ve_sinc > 1 then 's' else '' end || ' sin costo)' else '' end
       else '' end || chr(10) ||
       '• Cobrado hoy: ' || public.tg_usd(cobrado) ||
       case when xc_n > 0 then chr(10) || '• Por cobrar: ' || xc_n || ' venta' || case when xc_n > 1 then 's' else '' end || ' — ' || public.tg_usd(xc_tot) else '' end ||
       case when xe_n > 0 then chr(10) || '• Por entregar: ' || xe_n else '' end ||
       case when co_n > 0 then chr(10) || chr(10) || '📦 <b>Compras hoy:</b> ' || co_n || ' — ' || public.tg_usd(co_tot) else '' end ||
       chr(10) || chr(10) || '<a href="https://suinelectric.com/ventas">Abrir Gestión</a>';
  return t;
end $$;
revoke all on function public.adm_resumen_dia(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  Resumen del mes (por defecto, el mes anterior)
-- ---------------------------------------------------------------------
create or replace function public.adm_resumen_mes(p_mes date default null) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  m1 date := date_trunc('month', coalesce(p_mes, ((now() at time zone 'America/Caracas')::date - interval '1 month')::date))::date;
  m2 date := (m1 + interval '1 month')::date;
  m0 date := (m1 - interval '1 month')::date;
  meses text[] := array['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
  ini timestamptz := (m1::timestamp) at time zone 'America/Caracas';
  fin timestamptz := (m2::timestamp) at time zone 'America/Caracas';
  ini0 timestamptz := (m0::timestamp) at time zone 'America/Caracas';
  vis int; vis0 int; visitantes int; mejor text; ped int;
  ve_n int; ve_tot numeric; ve_gan numeric; ve_n0 int; ve_tot0 numeric; ve_gan0 numeric; cobrado numeric;
  of_n int; of_ac int; of_re int; of_tot numeric;
  co_n int; co_tot numeric; co_prov text;
  top text;
begin
  select count(distinct visita), count(distinct visitante) into vis, visitantes
    from eventos where tipo = 'visita' and creado >= ini and creado < fin;
  select count(distinct visita) into vis0
    from eventos where tipo = 'visita' and creado >= ini0 and creado < ini;
  select to_char(d, 'DD/MM') || ' (' || c || ')' into mejor from (
    select (creado at time zone 'America/Caracas')::date d, count(distinct visita) c from eventos
     where tipo = 'visita' and creado >= ini and creado < fin group by 1 order by 2 desc, 1 limit 1) x;
  select count(*) into ped from pedidos where creado >= ini and creado < fin;

  select count(*), coalesce(sum(total), 0), coalesce(sum(subtotal - costo), 0) into ve_n, ve_tot, ve_gan
    from adm_docs_montos('venta') where estado <> 'anulada' and dia >= m1 and dia < m2;
  select count(*), coalesce(sum(total), 0), coalesce(sum(subtotal - costo), 0) into ve_n0, ve_tot0, ve_gan0
    from adm_docs_montos('venta') where estado <> 'anulada' and dia >= m0 and dia < m1;
  select coalesce(sum(public.tg_num(p->'monto')), 0) into cobrado
    from adm_docs_montos('venta') v, jsonb_array_elements(coalesce(v.d->'pagos', '[]')) p
   where v.estado <> 'anulada' and left(p->>'fecha', 10) >= to_char(m1, 'YYYY-MM-DD') and left(p->>'fecha', 10) < to_char(m2, 'YYYY-MM-DD');

  select string_agg(n || '. ' || public.tg_esc(prod) || ' — ' || rtrim(to_char(cant, 'FM999G990D99'), '.,') || ' und · ' || public.tg_usd(monto), chr(10) order by n) into top
    from (select row_number() over (order by sum(public.tg_num(it->'cant') * public.tg_num(it->'precio')) desc) n,
                 coalesce(nullif(it->>'codigo', ''),
                          left(regexp_replace(split_part(coalesce(it->>'desc', ''), chr(10), 1), '\*|Ref / Modelo:\s*', '', 'g'), 45)) prod,
                 sum(public.tg_num(it->'cant')) cant,
                 sum(public.tg_num(it->'cant') * public.tg_num(it->'precio')) monto
            from adm_docs_montos('venta') v, jsonb_array_elements(coalesce(v.d->'items', '[]')) it
           where v.estado <> 'anulada' and v.dia >= m1 and v.dia < m2
           group by 2 order by 4 desc limit 5) x;

  select count(*), count(*) filter (where estado = 'aceptada'), count(*) filter (where estado = 'rechazada'), coalesce(sum(total), 0)
    into of_n, of_ac, of_re, of_tot
    from adm_docs_montos('oferta') where dia >= m1 and dia < m2;

  select count(*), coalesce(sum(case when costo > 0 then costo else subtotal end), 0) into co_n, co_tot
    from adm_docs_montos('compra') where estado <> 'anulada' and dia >= m1 and dia < m2;
  select string_agg('• ' || public.tg_esc(p) || ' — ' || public.tg_usd(m), chr(10) order by m desc) into co_prov from (
    select coalesce(nullif(trim(d#>>'{proveedor,nombre}'), ''), 'Sin proveedor') p, sum(case when costo > 0 then costo else subtotal end) m
      from adm_docs_montos('compra') where estado <> 'anulada' and dia >= m1 and dia < m2
     group by 1 order by 2 desc limit 3) x;

  return '📅 <b>Resumen de ' || meses[extract(month from m1)::int] || ' ' || extract(year from m1) || '</b>' || chr(10) ||
         '<i>comparado con ' || meses[extract(month from m0)::int] || '</i>' || chr(10) || chr(10) ||
         '🌐 <b>Tienda web</b>' || chr(10) ||
         '• Visitas: <b>' || vis || '</b>' || public.tg_var(vis, vis0) || chr(10) ||
         '• Visitantes distintos: ' || visitantes || chr(10) ||
         coalesce('• Día con más visitas: ' || mejor || chr(10), '') ||
         '• Pedidos web: ' || ped || chr(10) || chr(10) ||
         '💰 <b>Ventas</b>' || chr(10) ||
         '• Ventas: <b>' || ve_n || '</b>' || public.tg_var(ve_n, ve_n0) || chr(10) ||
         '• Total: <b>' || public.tg_usd(ve_tot) || '</b>' || public.tg_var(ve_tot, ve_tot0) || chr(10) ||
         '• Ganancia: <b>' || public.tg_usd(ve_gan) || '</b>' || public.tg_var(ve_gan, ve_gan0) || chr(10) ||
         case when ve_n > 0 then '• Venta promedio: ' || public.tg_usd(ve_tot / ve_n) || chr(10) else '' end ||
         '• Cobrado en el mes: ' || public.tg_usd(cobrado) || chr(10) ||
         coalesce(chr(10) || '🏆 <b>Más vendidos</b>' || chr(10) || top || chr(10), '') || chr(10) ||
         '📝 <b>Ofertas</b>' || chr(10) ||
         '• Hechas: ' || of_n || ' — ' || public.tg_usd(of_tot) || chr(10) ||
         '• Aceptadas: ' || of_ac || ' · Rechazadas: ' || of_re ||
         case when of_n > 0 then ' · Cierre: ' || round(of_ac::numeric / of_n * 100) || '%' else '' end || chr(10) || chr(10) ||
         '📦 <b>Compras</b>: ' || co_n || ' — ' || public.tg_usd(co_tot) ||
         coalesce(chr(10) || co_prov, '') ||
         chr(10) || chr(10) || '<a href="https://suinelectric.com/ventas">Abrir Gestión</a>';
end $$;
revoke all on function public.adm_resumen_mes(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  Enviar a los destinatarios del resumen
-- ---------------------------------------------------------------------
create or replace function public.adm_enviar_resumen(p_tipo text default 'dia') returns text
language plpgsql security definer set search_path = public, extensions as $$
declare ids text; txt text; c text; n int := 0;
begin
  select decrypted_secret into ids from vault.decrypted_secrets where name = 'telegram_chat_ids_resumen';
  if ids is null then
    select decrypted_secret into ids from vault.decrypted_secrets where name = 'telegram_chat_id';
  end if;
  if ids is null then return 'Falta el secreto telegram_chat_ids_resumen'; end if;
  txt := case when p_tipo = 'mes' then public.adm_resumen_mes() else public.adm_resumen_dia() end;
  foreach c in array regexp_split_to_array(trim(ids), '\s*[,;\s]\s*') loop
    if c <> '' then perform public.notificar_telegram_a(c, txt); n := n + 1; end if;
  end loop;
  return 'Enviado a ' || n || ' chat(s)';
exception when others then
  raise warning 'adm_enviar_resumen: %', sqlerrm;
  return 'Error: ' || sqlerrm;
end $$;
revoke all on function public.adm_enviar_resumen(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  Programación (UTC; Venezuela = UTC−4)
-- ---------------------------------------------------------------------
select cron.unschedule(jobid) from cron.job where jobname in ('suinbot_resumen_dia', 'suinbot_resumen_mes');
select cron.schedule('suinbot_resumen_dia', '0 23 * * *', $$select public.adm_enviar_resumen('dia')$$);  -- 7:00 p.m. todos los días
select cron.schedule('suinbot_resumen_mes', '0 11 1 * *', $$select public.adm_enviar_resumen('mes')$$);  -- día 1, 7:00 a.m.
