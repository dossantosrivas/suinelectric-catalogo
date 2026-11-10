-- =====================================================================
--  SUINELECTRIC · Escribirle primero a un visitante (panel → En vivo)
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--  Requiere haber corrido antes 08_chat.sql, 09_asistente.sql y
--  13_en_vivo.sql.
--
--  Hasta ahora el chat de la tienda solo lo podía empezar el visitante.
--  Con esto, desde el panel (En vivo → Escribirle) le dejas un mensaje a
--  quien está en la web y le aparece en el chat de la tienda.
--
--  · chat_conversaciones.visitante → el código de navegador del
--    visitante (el mismo de En vivo), para saber a qué chat escribirle.
--  · chat_mensajes.proactivo       → mensajes que empezaste tú.
--  · chat_iniciar()  → lo usa el panel: escribe en el chat que ya tenga
--    ese visitante o le crea uno. Apaga la IA en ese chat (lo atiendes tú)
--    y te deja un aviso "💬 Chat #…" en Telegram para seguir desde ahí.
--  · chat_aviso()    → lo pregunta la tienda cada pocos segundos: ¿un
--    asesor le escribió a este navegador? Devuelve la llave del chat.
--  La respuesta del visitante te llega por SuinBot como cualquier chat.
-- =====================================================================

alter table public.chat_conversaciones add column if not exists visitante text check (char_length(visitante) <= 40);
create index if not exists chat_conv_visitante_idx on public.chat_conversaciones (visitante, ultimo desc) where visitante is not null;
alter table public.chat_mensajes add column if not exists proactivo boolean not null default false;

-- ---------------------------------------------------------------------
--  Tú le escribes primero (panel → En vivo → Escribirle)
-- ---------------------------------------------------------------------
create or replace function public.chat_iniciar(p_visitante text, p_texto text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_vis   text := left(nullif(trim(p_visitante), ''), 40);
  v_texto text := left(btrim(coalesce(p_texto, '')), 2000);
  v_conv  public.chat_conversaciones;
  v_nuevo boolean := false;
  v_id    bigint;
begin
  if not public.es_admin() then raise exception 'Solo los administradores pueden escribirle a un visitante'; end if;
  if v_vis is null then raise exception 'Falta el código del visitante'; end if;
  if v_texto = '' then raise exception 'Mensaje vacío'; end if;

  select * into v_conv from public.chat_conversaciones where visitante = v_vis order by ultimo desc limit 1;
  if not found then
    insert into public.chat_conversaciones (token, visitante, pagina)
    values (gen_random_uuid(), v_vis, 'Le escribiste desde el panel')
    returning * into v_conv;
    v_nuevo := true;
  end if;

  insert into public.chat_mensajes (conversacion_id, autor, texto, proactivo)
  values (v_conv.id, 'suinelectric', v_texto, true)
  returning id into v_id;

  update public.chat_conversaciones
     set ultimo = now(), estado = 'abierta', ia_activa = false, ia_ocupada_hasta = null
   where id = v_conv.id;

  -- Aviso en Telegram: sirve de ancla para seguir la conversación respondiendo a ese mensaje.
  begin
    perform public.notificar_telegram(
      '💬 <b>Chat #' || v_conv.id || '</b> · ' || coalesce(public.tg_esc(v_conv.nombre), 'Visitante ' || upper(left(replace(v_vis, '-', ''), 6))) ||
      chr(10) || '<i>Le escribiste desde el panel:</i>' || chr(10) || public.tg_esc(v_texto) ||
      chr(10) || chr(10) || '<i>↩️ Responde a este mensaje para seguir escribiéndole en la tienda.</i>');
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'chat', v_conv.id, 'id', v_id, 'nuevo', v_nuevo);
end $$;
revoke all on function public.chat_iniciar(text, text) from public, anon;
grant execute on function public.chat_iniciar(text, text) to authenticated;

-- ---------------------------------------------------------------------
--  La tienda pregunta: ¿un asesor le escribió a este navegador?
--  p_token = la llave del chat que ya tenga este navegador (si tiene).
--  Devuelve {token, id}: la llave del chat y el último mensaje que
--  empezó el asesor; null si no hay nada.
-- ---------------------------------------------------------------------
create or replace function public.chat_aviso(p_visitante text, p_token uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_vis  text := left(nullif(trim(p_visitante), ''), 40);
  v_mia  bigint;
  v_conv bigint;
  v_tok  uuid;
  v_id   bigint;
begin
  if v_vis is null then return null; end if;

  if p_token is not null then
    select id into v_mia from public.chat_conversaciones where token = p_token;
  end if;

  if v_mia is not null then
    -- Su chat queda ligado a su navegador (para que el panel le escriba ahí mismo)…
    update public.chat_conversaciones set visitante = v_vis where id = v_mia and visitante is distinct from v_vis;
    -- …y si el asesor le escribió en un chat aparte antes de saberlo, esos mensajes pasan al suyo.
    if exists (select 1 from public.chat_conversaciones c where c.visitante = v_vis and c.id <> v_mia
                and not exists (select 1 from public.chat_mensajes m where m.conversacion_id = c.id and m.autor = 'cliente')) then
      update public.chat_mensajes m set conversacion_id = v_mia
       where m.conversacion_id in (select c.id from public.chat_conversaciones c where c.visitante = v_vis and c.id <> v_mia
                and not exists (select 1 from public.chat_mensajes x where x.conversacion_id = c.id and x.autor = 'cliente'));
      delete from public.chat_conversaciones c where c.visitante = v_vis and c.id <> v_mia
         and not exists (select 1 from public.chat_mensajes x where x.conversacion_id = c.id);
      update public.chat_conversaciones set ia_activa = false, ia_ocupada_hasta = null, ultimo = now() where id = v_mia;
    end if;
    v_conv := v_mia;
  else
    select c.id into v_conv from public.chat_conversaciones c
     where c.visitante = v_vis
       and exists (select 1 from public.chat_mensajes m where m.conversacion_id = c.id and m.proactivo)
     order by c.ultimo desc limit 1;
  end if;
  if v_conv is null then return null; end if;

  select max(m.id) into v_id from public.chat_mensajes m where m.conversacion_id = v_conv and m.proactivo;
  if v_id is null then return null; end if;
  select token into v_tok from public.chat_conversaciones where id = v_conv;
  return jsonb_build_object('token', v_tok, 'id', v_id);
end $$;
revoke all on function public.chat_aviso(text, uuid) from public;
grant execute on function public.chat_aviso(text, uuid) to anon, authenticated;
