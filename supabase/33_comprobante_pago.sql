-- =====================================================================
--  33 · COMPROBANTE DE PAGO E IDENTIFICACIÓN AL CONCRETAR OFERTA
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Seguro de volver a correr sin perder datos.
--
--  · Agrega pago_cliente (jsonb) a pedidos: referencia, identificación
--    (cédula/RIF), método, nota y archivo_ruta / archivo_nombre del recibo.
--  · Crea el bucket privado "comprobantes" en Supabase Storage para
--    recibos (JPG, PNG, WebP, PDF hasta 8 MB), con subida validada por
--    token del pedido y lectura/descarga solo para administradores.
--  · Amplía pedido_responder(..., p_pago) manteniendo compatibilidad con
--    llamadas anteriores, y agrega pedido_adjuntar_pago() para subir el
--    comprobante después de aceptar la oferta.
-- =====================================================================

-- 1. Columna en pedidos
alter table public.pedidos
  add column if not exists pago_cliente jsonb;

-- 2. Bucket privado para comprobantes
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('comprobantes', 'comprobantes', false, 8388608, '{image/jpeg,image/png,image/webp,application/pdf}')
on conflict (id) do update
  set public = false,
      file_size_limit = 8388608,
      allowed_mime_types = '{image/jpeg,image/png,image/webp,application/pdf}';

create or replace function public.puede_subir_comprobante(p_ruta text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from pedidos p
     where p.token::text = split_part(coalesce(p_ruta, ''), '/', 1)
       and p.estado in ('cotizado', 'aprobado')
  );
$$;
grant execute on function public.puede_subir_comprobante(text) to anon, authenticated;

drop policy if exists comprobantes_subir on storage.objects;
drop policy if exists comprobantes_ver_admin on storage.objects;
drop policy if exists comprobantes_borrar_admin on storage.objects;

create policy comprobantes_subir on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'comprobantes' and public.puede_subir_comprobante(name));

create policy comprobantes_ver_admin on storage.objects
  for select to authenticated
  using (bucket_id = 'comprobantes' and public.adm_es_admin());

create policy comprobantes_borrar_admin on storage.objects
  for delete to authenticated
  using (bucket_id = 'comprobantes' and public.adm_es_admin());

-- 3. Incluir pago_cliente en pedido_publico
create or replace function public.pedido_publico(r public.pedidos) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', r.id, 'numero', r.numero, 'token', r.token, 'estado', r.estado, 'guia', r.guia,
    'items', r.items, 'total', r.total,
    'items_oferta', r.items_oferta, 'total_oferta', r.total_oferta,
    'oferta_numero', r.oferta_numero, 'vence', r.vence,
    'nota_cliente', r.nota_cliente, 'nota_admin', r.nota_admin, 'motivo', r.motivo,
    'direccion', r.direccion, 'invitado', r.invitado,
    'pago_cliente', r.pago_cliente,
    'creado', r.creado, 'actualizado', r.actualizado,
    'puede_responder', r.estado = 'cotizado' and r.items_oferta is not null
                       and (r.vence is null or r.vence >= (now() at time zone 'America/Caracas')::date),
    'historial', coalesce((select jsonb_agg(jsonb_build_object('estado', h.estado, 'detalle', h.detalle, 'por', h.por, 'creado', h.creado) order by h.creado)
                             from pedidos_historial h where h.pedido_id = r.id), '[]'))
$$;

-- Helper para limpiar el objeto pago_cliente
create or replace function public.limpiar_pago_cliente(p_pago jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select nullif(jsonb_strip_nulls(jsonb_build_object(
    'metodo',         left(nullif(btrim(p_pago->>'metodo'), ''), 60),
    'referencia',     left(nullif(btrim(p_pago->>'referencia'), ''), 100),
    'identificacion', left(nullif(btrim(p_pago->>'identificacion'), ''), 40),
    'nota',           left(nullif(btrim(p_pago->>'nota'), ''), 300),
    'archivo_ruta',   left(nullif(btrim(p_pago->>'archivo_ruta'), ''), 300),
    'archivo_nombre', left(nullif(btrim(p_pago->>'archivo_nombre'), ''), 160),
    'fecha',          case when coalesce(nullif(btrim(p_pago->>'referencia'), ''), nullif(btrim(p_pago->>'identificacion'), ''), nullif(btrim(p_pago->>'archivo_ruta'), ''), nullif(btrim(p_pago->>'nota'), '')) is not null
                           then to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                           else null end
  )), '{}'::jsonb);
$$;

-- 4. Actualizar pedido_responder (manteniendo compatibilidad con la firma anterior de 4 argumentos)
create or replace function public.pedido_responder(
  p_id bigint, p_token uuid, p_acepta boolean, p_motivo text, p_pago jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r public.pedidos;
  v_email text := public.mi_email();
  v_admin boolean := public.adm_es_admin();
  v_pago jsonb;
begin
  select * into r from pedidos where id = p_id for update;
  if not found then raise exception 'Solicitud no encontrada'; end if;
  if not ( r.token = p_token
        or (v_email <> '' and (r.cliente_email = v_email or lower(r.invitado->>'email') = v_email))
        or v_admin) then
    raise exception 'No tienes acceso a esta solicitud';
  end if;
  if r.estado <> 'cotizado' or r.items_oferta is null then raise exception 'Esta oferta ya no espera respuesta'; end if;
  if r.vence is not null and r.vence < (now() at time zone 'America/Caracas')::date then
    update pedidos set estado = 'vencido' where id = r.id;
    return jsonb_build_object('error', 'La oferta venció. Pídenos una actualización de precios');
  end if;

  if p_acepta and p_pago is not null then
    v_pago := public.limpiar_pago_cliente(p_pago);
  end if;

  update pedidos
     set estado = case when p_acepta then 'aprobado' else 'cancelado' end,
         motivo = case when p_acepta then null else coalesce(left(nullif(btrim(p_motivo), ''), 300), 'Rechazada por el cliente') end,
         pago_cliente = case when p_acepta then coalesce(v_pago, pago_cliente) else pago_cliente end,
         respondido_por = case when v_admin and r.token is distinct from p_token
                                and not (v_email <> '' and (r.cliente_email = v_email or lower(r.invitado->>'email') = v_email))
                               then 'admin' else 'cliente' end,
         respondido_en = now()
   where id = r.id
  returning * into r;
  return public.pedido_publico(r);
end $$;
grant execute on function public.pedido_responder(bigint, uuid, boolean, text, jsonb) to anon, authenticated;

create or replace function public.pedido_responder(
  p_id bigint, p_token uuid, p_acepta boolean, p_motivo text default null
) returns jsonb
language sql security definer set search_path = public as $$
  select public.pedido_responder(p_id, p_token, p_acepta, p_motivo, null::jsonb);
$$;
grant execute on function public.pedido_responder(bigint, uuid, boolean, text) to anon, authenticated;

-- 5. Adjuntar o actualizar comprobante luego de aceptar (mientras esté aprobado / pendiente de pago)
create or replace function public.pedido_adjuntar_pago(p_id bigint, p_token uuid, p_pago jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r public.pedidos;
  v_email text := public.mi_email();
  v_admin boolean := public.adm_es_admin();
  v_pago jsonb;
begin
  select * into r from pedidos where id = p_id for update;
  if not found then raise exception 'Solicitud no encontrada'; end if;
  if not ( r.token = p_token
        or (v_email <> '' and (r.cliente_email = v_email or lower(r.invitado->>'email') = v_email))
        or v_admin) then
    raise exception 'No tienes acceso a esta solicitud';
  end if;
  if r.estado not in ('aprobado', 'pagado', 'preparando') then
    raise exception 'Este pedido no admite comprobantes en su estado actual';
  end if;

  v_pago := public.limpiar_pago_cliente(p_pago);
  if v_pago is null then raise exception 'Ingresa la referencia, identificación o adjunta el recibo'; end if;

  update pedidos set pago_cliente = v_pago where id = r.id returning * into r;

  begin
    perform public.notificar_telegram(
      '🧾 <b>Comprobante de pago adjunto</b>' || chr(10) ||
      public.tg_esc(coalesce(r.oferta_numero, '')) || ' · ' || public.tg_esc(r.numero) ||
      coalesce(chr(10) || 'Método: ' || public.tg_esc(v_pago->>'metodo'), '') ||
      coalesce(chr(10) || 'Ref.: <code>' || public.tg_esc(v_pago->>'referencia') || '</code>', '') ||
      coalesce(chr(10) || 'ID / RIF: ' || public.tg_esc(v_pago->>'identificacion'), '') ||
      case when v_pago ? 'archivo_ruta' then chr(10) || '📎 Recibo adjunto' else '' end);
  exception when others then null;
  end;

  return public.pedido_publico(r);
end $$;
grant execute on function public.pedido_adjuntar_pago(bigint, uuid, jsonb) to anon, authenticated;

-- 6. Incluir pago_cliente en ofertas_web_por_convertir_v2 para que Gestión lo muestre
create or replace function public.ofertas_web_por_convertir_v2()
returns table(pedido_id bigint, numero text, oferta_doc_id text, direccion jsonb, pago_cliente jsonb)
language sql stable security definer set search_path = public as $$
  select p.id, p.numero, p.oferta_doc_id, p.direccion, p.pago_cliente from pedidos p
   where public.adm_es_admin() and p.estado = 'aprobado' and p.oferta_doc_id is not null
     and (p.venta_doc_id is null or (p.venta_doc_id like 'creando:%'
          and to_timestamp(split_part(p.venta_doc_id, ':', 3)::bigint) < now() - interval '10 minutes'))
$$;
revoke execute on function public.ofertas_web_por_convertir_v2() from public, anon;
grant execute on function public.ofertas_web_por_convertir_v2() to authenticated;

-- 7. Actualizar aviso a Telegram al aceptar oferta para incluir datos de pago si los envió
create or replace function public.avisar_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  c record; nombre text; empresa text; contacto text; tel text; lineas text; n int; wa text;
  pg jsonb := new.pago_cliente;
begin
  select nombre, empresa, telefono, rif into c from clientes where email = new.cliente_email;
  nombre   := coalesce(nullif(c.nombre, ''), new.invitado->>'nombre');
  empresa  := coalesce(nullif(c.empresa, ''), new.invitado->>'empresa');
  contacto := coalesce(nullif(new.cliente_email, ''), new.invitado->>'email');
  tel      := coalesce(nullif(c.telefono, ''), new.invitado->>'telefono');

  if tg_op = 'INSERT' then
    n := coalesce(jsonb_array_length(new.items), 0);
    select string_agg('• ' || coalesce(it->>'cantidad','1') || ' × ' || coalesce(public.tg_esc(it->>'modelo'),'?') ||
                      coalesce(' — $' || to_char((it->>'precio_unit')::numeric, 'FM999G999G990'), ''), chr(10) order by ord)
      into lineas from jsonb_array_elements(new.items) with ordinality x(it, ord) where ord <= 12;
    if n > 12 then lineas := lineas || chr(10) || '… y ' || (n - 12) || ' más'; end if;
    wa := public.tg_wa(tel);
    perform public.notificar_telegram(
      '🛒 <b>Pedido ' || coalesce(new.numero, '#' || new.id) || '</b>' ||
      case when new.cliente_email is null then ' <i>(sin cuenta)</i>' else '' end || chr(10) ||
      '<b>' || public.tg_esc(coalesce(nombre, '—')) || '</b>' || coalesce(' · ' || public.tg_esc(empresa), '') || chr(10) ||
      coalesce(public.tg_esc(contacto) || chr(10), '') || coalesce(public.tg_esc(tel) || chr(10), '') || chr(10) ||
      coalesce(lineas, '(sin artículos)') || chr(10) || chr(10) ||
      '<b>Total: $' || coalesce(to_char(new.total, 'FM999G999G990D00'), '—') || '</b>' ||
      coalesce(chr(10) || '📝 ' || public.tg_esc(left(new.nota_cliente, 300)), '') ||
      coalesce(chr(10) || '<a href="' || wa || '">Escribirle por WhatsApp</a>', '') || chr(10) ||
      '🕒 ' || public.tg_hora(new.creado));
  elsif new.estado is distinct from old.estado and new.respondido_por = 'cliente'
        and new.respondido_en is distinct from old.respondido_en and new.estado in ('aprobado','cancelado') then
    perform public.notificar_telegram(
      case when new.estado = 'aprobado' then '✅ <b>Oferta aceptada en línea</b>' else '❌ <b>Oferta rechazada en línea</b>' end || chr(10) ||
      public.tg_esc(coalesce(new.oferta_numero, '')) || ' · ' || public.tg_esc(new.numero) || chr(10) ||
      '<b>' || public.tg_esc(coalesce(nombre, '—')) || '</b>' || coalesce(' · ' || public.tg_esc(empresa), '') || chr(10) ||
      case when new.estado = 'aprobado'
           then 'Total: $' || coalesce(to_char(new.total_oferta, 'FM999G999G990D00'), '—') ||
                coalesce(chr(10) || 'Método: ' || public.tg_esc(pg->>'metodo'), '') ||
                coalesce(chr(10) || 'Ref.: <code>' || public.tg_esc(pg->>'referencia') || '</code>', '') ||
                coalesce(chr(10) || 'ID / RIF: ' || public.tg_esc(pg->>'identificacion'), '') ||
                case when pg ? 'archivo_ruta' then chr(10) || '📎 Recibo de pago adjunto' else '' end ||
                chr(10) || 'Gestión crea la venta al abrirse.'
           else 'Motivo: ' || coalesce(public.tg_esc(new.motivo), 'no indicado') end);
  end if;
  return new;
exception when others then
  return new;
end $$;
