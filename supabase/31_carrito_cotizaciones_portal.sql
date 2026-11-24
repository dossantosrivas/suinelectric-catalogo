-- =====================================================================
--  SUINELECTRIC · Carrito → solicitud de cotización → oferta → venta
--                 + portal "Mi cuenta" del cliente
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--
--  Solo AGREGA columnas, tablas y funciones. tienda.html y admin.html
--  siguen funcionando igual; las funciones nuevas las usan las páginas
--  -beta (tienda-beta, admin-beta, ventas-beta y mi-cuenta-beta).
--
--  · Cualquier visitante puede pedir cotización: con cuenta, o sin
--    cuenta con nombre y teléfono (máx. 5 por hora por navegador).
--  · El panel ve la solicitud, crea la oferta en Gestión y Gestión la
--    publica al cliente (sin costos). El cliente la acepta o rechaza en
--    línea; al aceptarla, Gestión crea la venta sola.
--  · Estados (pedidos.estado): enviado (Nuevo) → revision → cotizado →
--    aprobado → pagado → preparando → despachado → entregado,
--    o cancelado / vencido. Gestión mueve los de la venta solo.
--  · El cliente nunca ve costos ni la palabra "nota de entrega".
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Ampliar pedidos
-- ---------------------------------------------------------------------
alter table public.pedidos alter column cliente_email drop not null;

alter table public.pedidos
  add column if not exists numero          text,
  add column if not exists token           uuid not null default gen_random_uuid(),
  add column if not exists invitado        jsonb,          -- {nombre, telefono, email, empresa, rif}
  add column if not exists visitante       text,
  add column if not exists direccion       jsonb,
  add column if not exists items_oferta    jsonb,          -- lo cotizado, SIN costos
  add column if not exists total_oferta    numeric,
  add column if not exists vence           date,
  add column if not exists oferta_doc_id   text,           -- id del documento OF- en Gestión
  add column if not exists oferta_numero   text,
  add column if not exists venta_doc_id    text,
  add column if not exists motivo          text,           -- por qué se canceló
  add column if not exists respondido_por  text,           -- 'cliente' | 'admin'
  add column if not exists respondido_en   timestamptz,
  add column if not exists guia            text;           -- empresa y n.º de guía del envío

alter table public.pedidos drop constraint if exists pedidos_estado_check;
alter table public.pedidos add constraint pedidos_estado_check check (estado in
  ('enviado','revision','cotizado','aprobado','pagado','preparando','despachado','entregado','cancelado','vencido'));
alter table public.pedidos drop constraint if exists pedidos_quien;
alter table public.pedidos add constraint pedidos_quien
  check (cliente_email is not null or coalesce(invitado ? 'telefono', false));
alter table public.pedidos drop constraint if exists pedidos_respondido_check;
alter table public.pedidos add constraint pedidos_respondido_check check (respondido_por in ('cliente','admin'));

create unique index if not exists pedidos_numero_idx on public.pedidos(numero);
create unique index if not exists pedidos_token_idx on public.pedidos(token);
create index if not exists pedidos_invitado_email_idx on public.pedidos(lower(invitado->>'email'));
create index if not exists pedidos_oferta_doc_idx on public.pedidos(oferta_doc_id);

-- Número legible SW-AAAAMMDD-001 (día de Caracas)
create or replace function public.pedido_numerar() returns trigger
language plpgsql set search_path = public as $$
declare d text := to_char(now() at time zone 'America/Caracas', 'YYYYMMDD'); n int;
begin
  if new.numero is null then
    select coalesce(max(substring(numero from 13)::int), 0) + 1 into n
      from public.pedidos where numero like 'SW-' || d || '-%';
    new.numero := 'SW-' || d || '-' || lpad(n::text, 3, '0');
  end if;
  return new;
end $$;
drop trigger if exists pedidos_numerar on public.pedidos;
create trigger pedidos_numerar before insert on public.pedidos
  for each row execute function public.pedido_numerar();

update public.pedidos p
   set numero = 'SW-' || to_char(p.creado at time zone 'America/Caracas','YYYYMMDD') || '-' || lpad(x.n::text, 3, '0')
  from (select id, row_number() over (partition by (creado at time zone 'America/Caracas')::date order by id) n from public.pedidos) x
 where x.id = p.id and p.numero is null;

-- El cliente con cuenta ve también lo que pidió como invitado con su mismo correo
drop policy if exists pedidos_leer on public.pedidos;
create policy pedidos_leer on public.pedidos for select to authenticated
  using (cliente_email = public.mi_email() or lower(invitado->>'email') = public.mi_email() or public.es_admin());

-- ---------------------------------------------------------------------
-- 2. Historial de cada solicitud (línea de tiempo)
-- ---------------------------------------------------------------------
create table if not exists public.pedidos_historial (
  id         bigint generated always as identity primary key,
  pedido_id  bigint not null references public.pedidos(id) on delete cascade,
  estado     text,
  detalle    text,
  por        text,                     -- 'cliente' | 'admin' | 'sistema'
  creado     timestamptz not null default now()
);
create index if not exists pedidos_historial_pedido_idx on public.pedidos_historial(pedido_id, creado);
alter table public.pedidos_historial enable row level security;
revoke all on public.pedidos_historial from anon;
grant select on public.pedidos_historial to authenticated;
drop policy if exists ph_leer on public.pedidos_historial;
create policy ph_leer on public.pedidos_historial for select to authenticated
  using (public.es_admin() or exists (select 1 from public.pedidos p where p.id = pedido_id
          and (p.cliente_email = public.mi_email() or lower(p.invitado->>'email') = public.mi_email())));

create or replace function public.pedido_registrar_cambio() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_por text := case when public.adm_es_admin() then 'admin'
                           when coalesce(auth.role(), '') in ('anon','authenticated') then 'cliente'
                           else 'sistema' end;
begin
  if tg_op = 'INSERT' then
    insert into pedidos_historial(pedido_id, estado, detalle, por) values (new.id, new.estado, 'Solicitud recibida', v_por);
  elsif new.estado is distinct from old.estado then
    insert into pedidos_historial(pedido_id, estado, detalle, por)
    values (new.id, new.estado,
            case when new.estado = 'cancelado' then new.motivo when new.estado = 'despachado' then new.guia end,
            case when new.respondido_en is distinct from old.respondido_en then coalesce(new.respondido_por, v_por) else v_por end);
  end if;
  return new;
end $$;
drop trigger if exists pedidos_historial_t on public.pedidos;
create trigger pedidos_historial_t after insert or update on public.pedidos
  for each row execute function public.pedido_registrar_cambio();

-- ---------------------------------------------------------------------
-- 3. Carrito sincronizado, listas por obra y direcciones de envío
-- ---------------------------------------------------------------------
create table if not exists public.carritos (
  cliente_email text primary key,
  items         jsonb not null default '[]',
  actualizado   timestamptz not null default now()
);
create table if not exists public.listas_cliente (
  id            bigint generated always as identity primary key,
  cliente_email text not null,
  nombre        text not null,                 -- "Tablero galpón 2", "Obra Maracay"
  descripcion   text,
  items         jsonb not null default '[]',   -- [{modelo, marca, descripcion, cantidad, nota}]
  creado        timestamptz not null default now(),
  actualizado   timestamptz not null default now()
);
create table if not exists public.clientes_direcciones (
  id             bigint generated always as identity primary key,
  cliente_email  text not null,
  alias          text not null default 'Principal',
  contacto       text,
  telefono       text,
  direccion      text not null,
  ciudad         text,
  estado_region  text,
  referencia     text,
  agencia_envio  text,
  predeterminada boolean not null default false,
  creado         timestamptz not null default now(),
  actualizado    timestamptz not null default now()
);
create index if not exists listas_cliente_email_idx on public.listas_cliente(cliente_email);
create index if not exists clientes_dir_email_idx on public.clientes_direcciones(cliente_email);

revoke all on public.carritos, public.listas_cliente, public.clientes_direcciones from anon;
grant select, insert, update, delete on public.carritos, public.listas_cliente, public.clientes_direcciones to authenticated;

do $$
declare t text;
begin
  foreach t in array array['carritos','listas_cliente','clientes_direcciones'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_propio', t);
    execute format('create policy %I on public.%I for all to authenticated
                      using (cliente_email = public.mi_email() or public.es_admin())
                      with check (cliente_email = public.mi_email() or public.es_admin())', t || '_propio', t);
    execute format('drop trigger if exists %I on public.%I', t || '_actualizado', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.tocar_actualizado()', t || '_actualizado', t);
  end loop;
end $$;

create or replace function public.direccion_unica_pred() returns trigger
language plpgsql set search_path = public as $$
begin
  update clientes_direcciones set predeterminada = false
   where cliente_email = new.cliente_email and id <> new.id and predeterminada;
  return new;
end $$;
drop trigger if exists clientes_dir_pred on public.clientes_direcciones;
create trigger clientes_dir_pred after insert or update of predeterminada on public.clientes_direcciones
  for each row when (new.predeterminada) execute function public.direccion_unica_pred();

-- ---------------------------------------------------------------------
-- 4. Crear solicitud (con cuenta o como invitado)
-- ---------------------------------------------------------------------
create or replace function public.pedido_crear(
  p_items     jsonb,
  p_nota      text  default null,
  p_invitado  jsonb default null,    -- sin sesión: {nombre, telefono, email?, empresa?, rif?}
  p_direccion jsonb default null,
  p_visitante text  default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_email text := nullif(public.mi_email(), '');
  v_vis   text := left(nullif(trim(p_visitante), ''), 40);
  v_inv   jsonb;
  v_items jsonb;
  v_total numeric;
  v_rec   public.pedidos;
begin
  if public.acceso_bloqueado(v_vis, true) then raise exception 'No se pudo enviar la solicitud'; end if;
  if v_email is not null and not exists (select 1 from clientes where email = v_email and activo) then
    raise exception 'Tu cuenta está suspendida. Escríbenos por WhatsApp';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El carrito está vacío';
  end if;
  if jsonb_array_length(p_items) > 150 then raise exception 'Máximo 150 productos por solicitud'; end if;

  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'modelo',       left(coalesce(it->>'modelo', it->>'sku'), 80),
           'marca',        left(nullif(it->>'marca', ''), 60),
           'descripcion',  left(nullif(it->>'descripcion', ''), 400),
           'cantidad',     greatest(1, least(100000, coalesce((it->>'cantidad')::numeric, 1))),
           'precio_unit',  nullif((it->>'precio_unit')::numeric, 0),
           'precio_lista', nullif((it->>'precio_lista')::numeric, 0),
           'nota',         left(nullif(it->>'nota', ''), 300)
         )) order by ord)
    into v_items
    from jsonb_array_elements(p_items) with ordinality x(it, ord)
   where nullif(coalesce(it->>'modelo', it->>'sku'), '') is not null;
  if v_items is null then raise exception 'Los productos del carrito no tienen código'; end if;

  select sum(coalesce((i->>'precio_unit')::numeric, 0) * (i->>'cantidad')::numeric) into v_total
    from jsonb_array_elements(v_items) i;

  if v_email is null then
    v_inv := jsonb_strip_nulls(jsonb_build_object(
               'nombre',   left(btrim(p_invitado->>'nombre'), 120),
               'telefono', left(regexp_replace(coalesce(p_invitado->>'telefono',''), '[^0-9+]', '', 'g'), 20),
               'email',    lower(left(nullif(btrim(p_invitado->>'email'), ''), 160)),
               'empresa',  left(nullif(btrim(p_invitado->>'empresa'), ''), 160),
               'rif',      upper(left(nullif(btrim(p_invitado->>'rif'), ''), 20))));
    if coalesce(v_inv->>'nombre','') = '' or length(regexp_replace(coalesce(v_inv->>'telefono',''), '\D', '', 'g')) < 10 then
      raise exception 'Indica tu nombre y un teléfono válido';
    end if;
    if (select count(*) from pedidos
         where creado > now() - interval '1 hour'
           and ((v_vis is not null and visitante = v_vis) or invitado->>'telefono' = v_inv->>'telefono')) >= 5 then
      raise exception 'Has enviado varias solicitudes seguidas. Intenta de nuevo en un rato o escríbenos por WhatsApp';
    end if;
  end if;

  insert into pedidos (cliente_email, estado, items, total, nota_cliente, invitado, visitante, direccion)
  values (v_email, 'enviado', v_items, v_total, left(nullif(btrim(p_nota), ''), 2000), v_inv, v_vis, p_direccion)
  returning * into v_rec;

  if v_email is not null then delete from carritos where cliente_email = v_email; end if;
  return jsonb_build_object('id', v_rec.id, 'numero', v_rec.numero, 'token', v_rec.token);
end $$;
grant execute on function public.pedido_crear(jsonb, text, jsonb, jsonb, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Lo que ve el cliente de una solicitud (sin costos ni datos internos)
-- ---------------------------------------------------------------------
create or replace function public.pedido_publico(r public.pedidos) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', r.id, 'numero', r.numero, 'token', r.token, 'estado', r.estado, 'guia', r.guia,
    'items', r.items, 'total', r.total,
    'items_oferta', r.items_oferta, 'total_oferta', r.total_oferta,
    'oferta_numero', r.oferta_numero, 'vence', r.vence,
    'nota_cliente', r.nota_cliente, 'nota_admin', r.nota_admin, 'motivo', r.motivo,
    'direccion', r.direccion, 'invitado', r.invitado,
    'creado', r.creado, 'actualizado', r.actualizado,
    'puede_responder', r.estado = 'cotizado' and r.items_oferta is not null
                       and (r.vence is null or r.vence >= (now() at time zone 'America/Caracas')::date),
    'historial', coalesce((select jsonb_agg(jsonb_build_object('estado', h.estado, 'detalle', h.detalle, 'por', h.por, 'creado', h.creado) order by h.creado)
                             from pedidos_historial h where h.pedido_id = r.id), '[]'))
$$;

create or replace function public.pedido_por_token(p_token uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select public.pedido_publico(p) from pedidos p where p.token = p_token
$$;
grant execute on function public.pedido_por_token(uuid) to anon, authenticated;

create or replace function public.mis_pedidos() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.pedido_publico(p) order by p.creado desc), '[]')
    from pedidos p
   where public.mi_email() <> ''
     and (p.cliente_email = public.mi_email() or lower(p.invitado->>'email') = public.mi_email())
$$;
revoke execute on function public.mis_pedidos() from public, anon;
grant execute on function public.mis_pedidos() to authenticated;

-- ---------------------------------------------------------------------
-- 6. El cliente acepta o rechaza la oferta en línea (con su cuenta o su enlace)
--    Aceptar deja el pedido "aprobado"; Gestión crea la venta al abrirse.
-- ---------------------------------------------------------------------
create or replace function public.pedido_responder(p_id bigint, p_token uuid, p_acepta boolean, p_motivo text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.pedidos; v_email text := public.mi_email(); v_admin boolean := public.adm_es_admin();
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

  update pedidos
     set estado = case when p_acepta then 'aprobado' else 'cancelado' end,
         motivo = case when p_acepta then null else coalesce(left(nullif(btrim(p_motivo), ''), 300), 'Rechazada por el cliente') end,
         respondido_por = case when v_admin and r.token is distinct from p_token
                                and not (v_email <> '' and (r.cliente_email = v_email or lower(r.invitado->>'email') = v_email))
                               then 'admin' else 'cliente' end,
         respondido_en = now()
   where id = r.id
  returning * into r;
  return public.pedido_publico(r);
end $$;
grant execute on function public.pedido_responder(bigint, uuid, boolean, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 7. Funciones del panel y de Gestión (administradores y vendedores)
-- ---------------------------------------------------------------------
-- Gestión publica (o actualiza) la oferta que armó para esta solicitud
create or replace function public.pedido_cotizar(
  p_id bigint, p_oferta_doc_id text, p_oferta_numero text,
  p_items jsonb,                 -- [{codigo, descripcion, cantidad, precio_unit}] sin costos
  p_total numeric, p_dias_validez int default 5
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.pedidos; v_items jsonb;
begin
  if not public.adm_es_admin() then raise exception 'Solo administradores'; end if;
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'codigo', left(i->>'codigo', 80), 'descripcion', left(i->>'descripcion', 400),
           'cantidad', (i->>'cantidad')::numeric, 'precio_unit', round((i->>'precio_unit')::numeric, 2))) order by ord)
    into v_items from jsonb_array_elements(p_items) with ordinality x(i, ord);

  update pedidos
     set estado = 'cotizado', oferta_doc_id = p_oferta_doc_id, oferta_numero = p_oferta_numero,
         items_oferta = v_items, total_oferta = round(p_total, 2),
         vence = (now() at time zone 'America/Caracas')::date + greatest(1, coalesce(p_dias_validez, 5)),
         motivo = null
   where id = p_id and estado in ('enviado','revision','cotizado','vencido')
  returning * into r;
  if not found then raise exception 'La solicitud ya fue respondida; no se puede cambiar la oferta'; end if;
  return public.pedido_publico(r);
end $$;

-- Cancelar desde el panel o desde Gestión (oferta rechazada), con motivo
create or replace function public.pedido_rechazar_admin(p_id bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.adm_es_admin() then raise exception 'Solo administradores'; end if;
  update pedidos set estado = 'cancelado', motivo = left(coalesce(nullif(btrim(p_motivo), ''), 'Cancelada'), 300),
         respondido_por = 'admin', respondido_en = now()
   where id = p_id and estado in ('enviado','revision','cotizado','vencido');
end $$;

-- Gestión avisa el avance de la venta (aprobado, pagado, preparando, despachado, entregado)
create or replace function public.pedido_estado_web(p_id bigint, p_estado text, p_venta_doc_id text default null, p_guia text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.adm_es_admin() then raise exception 'Solo administradores'; end if;
  if p_estado not in ('aprobado','pagado','preparando','despachado','entregado') then raise exception 'Estado no válido'; end if;
  update pedidos
     set estado = p_estado,
         respondido_por = coalesce(respondido_por, 'admin'), respondido_en = coalesce(respondido_en, now()),
         venta_doc_id = coalesce(p_venta_doc_id, venta_doc_id),
         guia = coalesce(nullif(btrim(p_guia), ''), guia)
   where id = p_id and estado <> 'cancelado';
end $$;

-- Ofertas que el cliente aceptó en línea y Gestión aún no convirtió en venta
create or replace function public.ofertas_web_por_convertir() returns table(pedido_id bigint, numero text, oferta_doc_id text, direccion jsonb)
language sql stable security definer set search_path = public as $$
  select p.id, p.numero, p.oferta_doc_id, p.direccion from pedidos p
   where public.adm_es_admin() and p.estado = 'aprobado' and p.oferta_doc_id is not null
     and (p.venta_doc_id is null or (p.venta_doc_id like 'creando:%'
          and to_timestamp(split_part(p.venta_doc_id, ':', 3)::bigint) < now() - interval '10 minutes'))
$$;

-- Candado: si Gestión está abierta en dos equipos, solo uno crea la venta de una oferta aceptada.
-- Devuelve true si este equipo la tomó. Un candado de más de 10 minutos sin venta se puede retomar.
create or replace function public.pedido_tomar_conversion(p_id bigint, p_equipo text) returns boolean
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.adm_es_admin() then raise exception 'Solo administradores'; end if;
  update pedidos set venta_doc_id = 'creando:' || left(coalesce(p_equipo, ''), 40) || ':' || extract(epoch from now())::bigint
   where id = p_id and estado = 'aprobado'
     and (venta_doc_id is null
          or (venta_doc_id like 'creando:%' and to_timestamp(split_part(venta_doc_id, ':', 3)::bigint) < now() - interval '10 minutes'));
  get diagnostics n = row_count;
  return n > 0;
end $$;

revoke execute on function public.pedido_cotizar(bigint, text, text, jsonb, numeric, int),
  public.pedido_rechazar_admin(bigint, text), public.pedido_estado_web(bigint, text, text, text),
  public.ofertas_web_por_convertir(), public.pedido_tomar_conversion(bigint, text) from public, anon;
grant execute on function public.pedido_cotizar(bigint, text, text, jsonb, numeric, int),
  public.pedido_rechazar_admin(bigint, text), public.pedido_estado_web(bigint, text, text, text),
  public.ofertas_web_por_convertir(), public.pedido_tomar_conversion(bigint, text) to authenticated;

-- ---------------------------------------------------------------------
-- 8. Productos comprados (para recomprar rápido): solicitudes web
--    aprobadas + ventas de Gestión del cliente enlazado por tiendaEmail.
-- ---------------------------------------------------------------------
create or replace function public.mis_productos_comprados() returns jsonb
language sql stable security definer set search_path = public as $$
  with yo as (select public.mi_email() e),
  web as (
    select coalesce(i->>'codigo', i->>'modelo') modelo, i->>'marca' marca, i->>'descripcion' descripcion,
           (i->>'cantidad')::numeric cant, (i->>'precio_unit')::numeric precio, p.creado fecha
      from pedidos p, yo, jsonb_array_elements(coalesce(p.items_oferta, p.items)) i
     where yo.e <> '' and p.estado in ('aprobado','pagado','preparando','despachado','entregado')
       and (p.venta_doc_id is null or p.venta_doc_id like 'creando:%')   -- si ya hay venta, cuenta la de Gestión
       and (p.cliente_email = yo.e or lower(p.invitado->>'email') = yo.e)
  ),
  gestion as (
    select coalesce(nullif(i->>'codigo', ''), '') modelo, null::text marca,
           regexp_replace(coalesce(i->>'desc', ''), '\*[^*]*\*\s*', '', 'g') descripcion,
           (i->>'cant')::numeric cant, (i->>'precio')::numeric precio,
           case when v.data->>'fecha' ~ '^\d{4}-\d{2}-\d{2}' then left(v.data->>'fecha', 10)::date::timestamptz end fecha
      from yo
      join adm_registros c on c.coleccion = 'clientes' and not c.borrado and lower(c.data->>'tiendaEmail') = yo.e
      join adm_registros v on v.coleccion = 'docs' and not v.borrado and v.data->>'tipo' in ('venta','nota')
                          and coalesce(v.data->>'estado', '') <> 'anulada' and v.data->>'clienteId' = c.id
      cross join lateral jsonb_array_elements(v.data->'items') i
     where yo.e <> ''
  ),
  todo as (select * from web union all select * from gestion where modelo <> '')
  select coalesce(jsonb_agg(x order by x->>'ultima' desc nulls last), '[]') from (
    select jsonb_build_object(
             'modelo', modelo, 'marca', max(marca), 'descripcion', left(max(descripcion), 200),
             'veces', count(*), 'cantidad_total', sum(cant),
             'ultima', max(fecha), 'ultimo_precio', (array_agg(precio order by fecha desc nulls last))[1]) x
      from todo group by modelo) s
$$;
revoke execute on function public.mis_productos_comprados() from public, anon;
grant execute on function public.mis_productos_comprados() to authenticated;

-- ---------------------------------------------------------------------
-- 9. Avisos a Telegram: nueva solicitud (con o sin cuenta) y respuestas en línea
-- ---------------------------------------------------------------------
create or replace function public.avisar_pedido() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  c      public.clientes;
  nombre text; empresa text; contacto text; tel text;
  lineas text; n int; wa text;
begin
  select * into c from public.clientes where email = new.cliente_email;
  nombre   := coalesce(nullif(c.nombre, ''), new.invitado->>'nombre', new.cliente_email);
  empresa  := coalesce(nullif(c.empresa, ''), new.invitado->>'empresa');
  contacto := coalesce(new.cliente_email, new.invitado->>'email');
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
           then 'Total: $' || coalesce(to_char(new.total_oferta, 'FM999G999G990D00'), '—') || chr(10) || 'Gestión crea la venta al abrirse.'
           else 'Motivo: ' || coalesce(public.tg_esc(new.motivo), 'no indicado') end);
  end if;
  return new;
exception when others then
  return new;   -- un fallo de Telegram nunca impide guardar el pedido
end $$;
drop trigger if exists pedidos_avisar on public.pedidos;
create trigger pedidos_avisar after insert or update of estado on public.pedidos
  for each row execute function public.avisar_pedido();

-- ---------------------------------------------------------------------
-- 10. Ofertas sin respuesta vencen solas (6:05 a. m. de Caracas = 10:05 UTC)
-- ---------------------------------------------------------------------
create or replace function public.vencer_cotizaciones_web() returns int
language sql security definer set search_path = public as $$
  with u as (update pedidos set estado = 'vencido'
              where estado = 'cotizado' and vence < (now() at time zone 'America/Caracas')::date returning 1)
  select count(*)::int from u
$$;
revoke execute on function public.vencer_cotizaciones_web() from public, anon, authenticated;

do $$ begin
  perform cron.unschedule('vencer_cotizaciones_web') where exists (select 1 from cron.job where jobname = 'vencer_cotizaciones_web');
  perform cron.schedule('vencer_cotizaciones_web', '5 10 * * *', 'select public.vencer_cotizaciones_web()');
exception when undefined_table or invalid_schema_name or undefined_function then
  raise notice 'pg_cron no está activo: programar public.vencer_cotizaciones_web() a mano';
end $$;
