-- =====================================================================
--  34 · AVISOS DE TELEGRAM DE VISITANTES SOLO PARA VENEZUELA
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Seguro de volver a correr.
--
--  · avisar_evento(): los avisos de "Visita nueva" y "Entró a la página
--    de enlaces" (sin cuenta) solo se envían si pais = 'VE'.
--  · enviar_resumenes_visitas(): solo resume visitas que sean de
--    Venezuela, tengan cuenta o hayan agregado al carrito / tocado WhatsApp.
-- =====================================================================

create or replace function public.avisar_evento()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  quien text;
  lugar text;
  c     clientes;
  prod  text;
  txt   text;
  url   text := 'https://suinelectric.com/admin.html#envivo';
begin
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

  elsif new.tipo = 'visita' and new.origen = 'links' and new.pais = 'VE' and aviso_activo('links') then
    txt := '🔗 <b>Entró a la página de enlaces</b>';

  elsif new.tipo = 'visita' and new.pais = 'VE' and aviso_activo('visita') then
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
  raise warning 'avisar_evento: %', sqlerrm;
  return null;
end $function$;

create or replace function public.enviar_resumenes_visitas()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
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
       and not exists (select 1 from visitas_resumen v where v.visita = e.visita and v.resumido_hasta >= max(e.creado))
       -- Solo resumir visitas de Venezuela, con cuenta, o que agregaron al carrito / tocaron WhatsApp
       and (
             coalesce(bool_or(e.pais = 'VE'), false)
          or coalesce(bool_or(e.cliente_email is not null), false)
          or coalesce(bool_or(e.tipo in ('agregar_carrito', 'cotizar_whatsapp', 'pedido_whatsapp')), false)
       )
     order by max(e.creado)
     limit 20
  loop
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
end $function$;
