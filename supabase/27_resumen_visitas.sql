-- =====================================================================
--  27 · RESUMEN DE CADA VISITA (SuinBot → Telegram)
-- ---------------------------------------------------------------------
--  Cuando un visitante termina su visita (5 minutos sin actividad),
--  SuinBot manda un resumen de lo que hizo, como RESPUESTA al aviso de
--  "Visita nueva" de esa misma persona, para que quede en el mismo hilo:
--    · duración, de dónde vino, lugar y equipo, si es la 1ª visita o volvió
--    · lo que buscó (en orden, marcando lo que no encontró)
--    · las secciones que recorrió y cuántas tarjetas tuvo en pantalla
--    · los productos que abrió (con su link)
--    · carrito, WhatsApp y botones de la página de enlaces
--  Se manda para TODAS las visitas (también las que no hicieron nada).
--  Si la persona vuelve a moverse después del resumen, llega otro con
--  solo lo nuevo ("Siguió navegando").
--
--  Prender / apagar: panel → En vivo → "Resumen al terminar la visita"
--  (o: update avisos_eventos set activo = false where clave = 'resumen_visita';)
--
--  Pruebas:
--    select public.adm_resumen_visita('<código de visita>');   -- solo ver el texto
--    select public.enviar_resumenes_visitas();                  -- correr ya la revisión
--
--  Requiere 07, 10, 13 y 24. Seguro de correr varias veces.
-- =====================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

create index if not exists eventos_visita_creado_idx on public.eventos (visita, creado) where visita is not null;

-- ---------------------------------------------------------------------
--  Control de qué visitas ya tienen resumen (y a qué mensaje responder)
-- ---------------------------------------------------------------------
create table if not exists public.visitas_resumen (
  visita          text primary key check (char_length(visita) <= 40),
  aviso_req       bigint,          -- pedido de pg_net del aviso "Visita nueva"
  aviso_msg       bigint,          -- message_id de Telegram de ese aviso
  resumido_hasta  timestamptz,     -- último evento ya incluido en un resumen
  resumenes       integer not null default 0,
  creado          timestamptz not null default now()
);
alter table public.visitas_resumen enable row level security;
revoke all on public.visitas_resumen from anon, authenticated;

-- El interruptor aparece solo en el panel → En vivo
insert into public.avisos_eventos (clave, nombre, detalle, activo, orden)
values ('resumen_visita', 'Resumen al terminar la visita',
        'A los 5 minutos sin actividad: qué buscó, qué secciones y productos vio y qué tocó. Llega como respuesta al aviso de visita nueva.',
        true, 7)
on conflict (clave) do nothing;

-- ---------------------------------------------------------------------
--  Mandar un mensaje y devolver el número de pedido (para leer después
--  el message_id que responde Telegram). Opcional: responder a un mensaje.
-- ---------------------------------------------------------------------
create or replace function public.notificar_telegram_id(texto text, responder_a bigint default null) returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_token text;
  v_chat  text;
  v_body  jsonb;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'telegram_token';
  select decrypted_secret into v_chat  from vault.decrypted_secrets where name = 'telegram_chat_id';
  if v_token is null or v_chat is null or coalesce(texto, '') = '' then return null; end if;
  v_body := jsonb_build_object('chat_id', v_chat, 'text', left(texto, 4000),
                               'parse_mode', 'HTML', 'disable_web_page_preview', true);
  if responder_a is not null then
    v_body := v_body || jsonb_build_object('reply_parameters',
                jsonb_build_object('message_id', responder_a, 'allow_sending_without_reply', true));
  end if;
  return net.http_post(
    url     := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body    := v_body,
    timeout_milliseconds := 20000);
exception when others then
  raise warning 'notificar_telegram_id: %', sqlerrm;
  return null;
end $$;
revoke all on function public.notificar_telegram_id(text, bigint) from public, anon, authenticated;

-- Link de la página del producto (igual que slugDe() de la tienda)
create or replace function public.tg_link_producto(p_modelo text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select url from productos_busqueda where modelo = p_modelo and url is not null limit 1),
    'https://suinelectric.com/p/' || coalesce(nullif(trim(both '-' from regexp_replace(
       lower(translate(p_modelo, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')), '[^a-z0-9]+', '-', 'g')), ''), 'x'))
$$;

-- "7 min", "1 h 05 min", "menos de 1 min"
create or replace function public.tg_duracion(i interval) returns text
language sql immutable as $$
  select case
    when i < interval '1 minute' then 'menos de 1 min'
    when i < interval '1 hour'   then round(extract(epoch from i) / 60) || ' min'
    else floor(extract(epoch from i) / 3600) || ' h ' ||
         lpad((round(extract(epoch from i) / 60)::int % 60)::text, 2, '0') || ' min' end
$$;

-- ---------------------------------------------------------------------
--  El texto del resumen. p_desde = solo lo ocurrido después (continuación).
-- ---------------------------------------------------------------------
create or replace function public.adm_resumen_visita(p_visita text, p_desde timestamptz default null)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini     timestamptz;
  v_fin     timestamptz;
  v_vis     text;
  v_email   text;
  c         clientes;
  v_quien   text;
  v_lugar   text;
  v_previas integer;
  v_entrada text;
  v_origen  text;
  v_busq    text;
  v_secc    text;
  v_ntarj   integer;
  v_prods   text;
  v_nprods  integer;
  v_carr    text;
  v_wa      text;
  v_links   text;
  v_txt     text;
  nl        constant text := chr(10);
begin
  select min(creado), max(creado) into v_ini, v_fin
    from eventos where visita = p_visita and creado > coalesce(p_desde, '-infinity');
  if v_ini is null then return null; end if;
  select greatest(v_fin, (select visto from en_linea where visita = p_visita)) into v_fin;

  select visitante, cliente_email, pagina, origen into v_vis, v_email, v_entrada, v_origen
    from eventos where visita = p_visita order by (tipo = 'visita') desc, creado limit 1;
  if v_email is null then
    select cliente_email into v_email from eventos where visita = p_visita and cliente_email is not null limit 1;
  end if;
  if v_email is not null then select * into c from clientes where email = v_email; end if;

  v_quien := case when c.email is not null
                  then '👤 <b>' || tg_esc(coalesce(nullif(c.nombre, ''), nullif(c.empresa, ''), c.email)) || '</b>' ||
                       coalesce(' · ' || tg_esc(nullif(c.empresa, '')), '')
                  else '🌐 Visitante ' || upper(left(replace(coalesce(v_vis, ''), '-', ''), 6)) end;
  select count(distinct visita) into v_previas from eventos
   where visitante = v_vis and visita <> p_visita and creado < v_ini;
  v_quien := v_quien || case when v_previas > 0 then ' · volvió (' || (v_previas + 1) || 'ª visita)' else ' · 1ª visita' end;
  v_lugar := tg_lugar(p_visita);

  -- Búsquedas: sin los pasos intermedios al escribir ("contac" → "contactor")
  select string_agg('  • “' || tg_esc(texto) || '”' ||
                    case when resultados = 0 then ' ❌ sin resultados'
                         when resultados is not null then ' (' || resultados || ')' else '' end, nl order by pid)
    into v_busq
    from (select texto, max(resultados) resultados, min(id) pid
            from (select id, texto, resultados, creado,
                         lead(texto)  over (order by id) sig,
                         lead(creado) over (order by id) sig_t
                    from eventos where visita = p_visita and tipo = 'busqueda'
                     and creado > coalesce(p_desde, '-infinity') and texto is not null) s
           where not (sig is not null and sig like texto || '%' and sig <> texto and sig_t - creado < interval '90 seconds')
           group by texto order by min(id) limit 12) b;

  -- Secciones recorridas (las de búsqueda ya salen arriba) y tarjetas vistas
  select string_agg(tg_esc(texto), ' › ' order by pid) into v_secc
    from (select texto, min(id) pid from eventos
           where visita = p_visita and tipo = 'ver_tarjetas' and creado > coalesce(p_desde, '-infinity')
             and texto is not null and texto not ilike 'búsqueda:%'
           group by texto order by min(id) limit 10) s;
  select count(distinct m) into v_ntarj
    from eventos, unnest(modelos) m
   where visita = p_visita and tipo = 'ver_tarjetas' and creado > coalesce(p_desde, '-infinity');

  -- Productos abiertos
  select count(*), string_agg('  • <a href="' || tg_link_producto(modelo) || '">' || tg_esc(modelo) || '</a>' ||
                              coalesce(' · ' || tg_esc(marca), ''), nl order by pid) filter (where rn <= 12)
    into v_nprods, v_prods
    from (select e.modelo, min(e.id) pid, (select marca from productos_busqueda pb where pb.modelo = e.modelo limit 1) marca,
                 row_number() over (order by min(e.id)) rn
            from eventos e where e.visita = p_visita and e.tipo = 'ver_producto'
             and e.creado > coalesce(p_desde, '-infinity') and e.modelo is not null
           group by e.modelo) p;

  select string_agg(coalesce(cantidad || ' × ', '') || tg_esc(modelo), ', ' order by pid) into v_carr
    from (select modelo, max(cantidad) cantidad, min(id) pid from eventos
           where visita = p_visita and tipo = 'agregar_carrito' and creado > coalesce(p_desde, '-infinity')
           group by modelo) x;

  select string_agg(t, ' · ' order by pid) into v_wa
    from (select case tipo when 'cotizar_whatsapp' then 'pidió precio de ' || coalesce(tg_esc(modelo), 'un producto')
                           else 'envió su pedido' end t, min(id) pid
            from eventos where visita = p_visita and tipo in ('cotizar_whatsapp', 'pedido_whatsapp')
             and creado > coalesce(p_desde, '-infinity')
           group by 1) w;

  select string_agg(tg_esc(texto), ', ' order by pid) into v_links
    from (select texto, min(id) pid from eventos
           where visita = p_visita and tipo = 'clic_enlace' and creado > coalesce(p_desde, '-infinity') and texto is not null
           group by texto) l;

  v_txt := case when p_desde is null then '🧾 <b>Resumen de la visita</b>' else '🔁 <b>Siguió navegando</b>' end ||
           ' · ' || tg_duracion(v_fin - v_ini) || nl || v_quien ||
           coalesce(nl || '📍 ' || tg_esc(v_lugar), '') ||
           case when p_desde is null and v_entrada ~ '^/p/' then nl || '🚪 Entró por la página de ' || tg_esc(substr(v_entrada, 4))
                when p_desde is null and v_origen = 'links' then nl || '🚪 Entró por la página de enlaces'
                else '' end;

  if v_busq  is not null then v_txt := v_txt || nl || nl || '🔎 <b>Buscó:</b>' || nl || v_busq; end if;
  if v_secc  is not null then v_txt := v_txt || nl || nl || '📂 <b>Recorrió:</b> ' || v_secc; end if;
  if v_ntarj > 0         then v_txt := v_txt || nl || '🗂 Tuvo en pantalla ' || v_ntarj || ' producto' || case when v_ntarj = 1 then '' else 's' end; end if;
  if v_nprods > 0        then v_txt := v_txt || nl || nl || '👁 <b>Abrió ' || v_nprods || ' producto' || case when v_nprods = 1 then '' else 's' end || ':</b>' || nl || v_prods ||
                                  case when v_nprods > 12 then nl || '  … y ' || (v_nprods - 12) || ' más' else '' end; end if;
  if v_carr  is not null then v_txt := v_txt || nl || nl || '🛒 <b>Agregó al pedido:</b> ' || v_carr; end if;
  if v_wa    is not null then v_txt := v_txt || nl || '💬 <b>WhatsApp:</b> ' || v_wa; end if;
  if v_links is not null then v_txt := v_txt || nl || '🔗 <b>Tocó:</b> ' || v_links; end if;

  if v_busq is null and v_secc is null and coalesce(v_ntarj, 0) = 0 and coalesce(v_nprods, 0) = 0
     and v_carr is null and v_wa is null and v_links is null then
    v_txt := v_txt || nl || nl || '😶 Entró y salió sin buscar ni abrir productos.';
  end if;

  return v_txt || nl || nl || '🕒 ' || to_char(v_ini at time zone 'America/Caracas', 'DD/MM HH24:MI') ||
         ' – ' || to_char(v_fin at time zone 'America/Caracas', 'HH24:MI');
end $$;
revoke all on function public.adm_resumen_visita(text, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  Revisión cada minuto: manda el resumen de las visitas que terminaron
-- ---------------------------------------------------------------------
create or replace function public.enviar_resumenes_visitas() returns integer
language plpgsql security definer set search_path = public, extensions as $$
declare
  r       record;
  vr      visitas_resumen;
  v_msg   bigint;
  v_txt   text;
  n       integer := 0;
begin
  if not aviso_activo('resumen_visita') then return 0; end if;

  for r in
    select e.visita, max(e.creado) ult
      from eventos e
      left join clientes cl on cl.email = e.cliente_email
     where e.visita is not null and e.creado > now() - interval '12 hours'
     group by e.visita
    having max(e.creado) < now() - interval '5 minutes'
       and not coalesce(bool_or(cl.es_admin), false)
     order by max(e.creado)
     limit 20
  loop
    -- ¿Sigue con la página abierta y activa? (máximo 30 min sin eventos)
    if r.ult > now() - interval '30 minutes' and exists (
         select 1 from en_linea where visita = r.visita and activo and visto > now() - interval '5 minutes') then
      continue;
    end if;

    select * into vr from visitas_resumen where visita = r.visita;
    if vr.resumido_hasta is not null and vr.resumido_hasta >= r.ult then continue; end if;

    v_msg := vr.aviso_msg;
    if v_msg is null and vr.aviso_req is not null then
      select (content::jsonb -> 'result' ->> 'message_id')::bigint into v_msg
        from net._http_response where id = vr.aviso_req and status_code = 200;
    end if;

    v_txt := adm_resumen_visita(r.visita, vr.resumido_hasta);
    if v_txt is not null then
      perform notificar_telegram_id(v_txt, v_msg);
      n := n + 1;
    end if;

    insert into visitas_resumen (visita, aviso_msg, resumido_hasta, resumenes)
    values (r.visita, v_msg, r.ult, 1)
    on conflict (visita) do update
      set aviso_msg = coalesce(visitas_resumen.aviso_msg, excluded.aviso_msg),
          resumido_hasta = excluded.resumido_hasta,
          resumenes = visitas_resumen.resumenes + 1;
  end loop;

  delete from visitas_resumen where creado < now() - interval '3 days';
  return n;
exception when others then
  raise warning 'enviar_resumenes_visitas: %', sqlerrm;
  return n;
end $$;
revoke all on function public.enviar_resumenes_visitas() from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  El aviso de "Visita nueva" guarda su número para responderle después
--  (misma función de 13_en_vivo.sql; solo cambia el envío al final)
-- ---------------------------------------------------------------------
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
    txt := txt || chr(10) || quien || coalesce(chr(10) || '📍 ' || tg_esc(lugar), '') || chr(10) ||
           '🕒 ' || tg_hora() || ' · <a href="' || url || '">Ver en vivo</a>';
    if new.tipo = 'visita' and new.visita is not null then
      insert into visitas_resumen (visita, aviso_req) values (new.visita, notificar_telegram_id(txt))
      on conflict (visita) do update set aviso_req = coalesce(visitas_resumen.aviso_req, excluded.aviso_req);
    else
      perform notificar_telegram(txt);
    end if;
  end if;
  return null;
exception when others then
  raise warning 'avisar_evento: %', sqlerrm;   -- nunca impide guardar el evento
  return null;
end $$;

-- Las visitas que ya terminaron antes de instalar esto no mandan resumen
insert into public.visitas_resumen (visita, resumido_hasta)
select visita, max(creado) from public.eventos
 where visita is not null and creado > now() - interval '12 hours'
 group by visita having max(creado) < now() - interval '30 minutes'
on conflict (visita) do nothing;

-- Cada minuto
select cron.unschedule(jobid) from cron.job where jobname = 'suinbot_resumen_visitas';
select cron.schedule('suinbot_resumen_visitas', '* * * * *', 'select public.enviar_resumenes_visitas()');
